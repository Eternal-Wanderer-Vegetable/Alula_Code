//! 原子保存（docs/02 §6.3）：同目录临时文件 → 写入 → fsync → 原子改名。
//! 任意时刻被杀不会留下半写文件；目标要么是旧内容要么是新内容。

use encoding_rs::GBK;
use std::borrow::Cow;
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextEncoding {
    Utf8,
    Utf16Le,
    Utf16Be,
    Gbk,
}

impl TextEncoding {
    pub fn id(self) -> &'static str {
        match self {
            Self::Utf8 => "utf-8",
            Self::Utf16Le => "utf-16le",
            Self::Utf16Be => "utf-16be",
            Self::Gbk => "gbk",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        match id.to_ascii_lowercase().as_str() {
            "utf-8" | "utf8" => Some(Self::Utf8),
            "utf-16le" | "utf16le" => Some(Self::Utf16Le),
            "utf-16be" | "utf16be" => Some(Self::Utf16Be),
            "gbk" | "gb2312" => Some(Self::Gbk),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineEnding {
    Lf,
    CrLf,
}

impl LineEnding {
    pub fn id(self) -> &'static str {
        match self {
            Self::Lf => "lf",
            Self::CrLf => "crlf",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        match id.to_ascii_lowercase().as_str() {
            "lf" => Some(Self::Lf),
            "crlf" => Some(Self::CrLf),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TextFileOptions {
    pub encoding: TextEncoding,
    pub bom: bool,
    pub line_ending: LineEnding,
}

impl Default for TextFileOptions {
    fn default() -> Self {
        Self {
            encoding: TextEncoding::Utf8,
            bom: false,
            line_ending: LineEnding::Lf,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodedTextFile {
    /// Editor buffers use LF consistently; `options` carries the on-disk EOL.
    pub text: String,
    pub options: TextFileOptions,
}

#[derive(Debug)]
pub enum DecodeError {
    UnsupportedEncoding(String),
    InvalidData(String),
    BinaryContent,
}

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedEncoding(detail) => write!(f, "不支持或无法识别文件编码: {detail}"),
            Self::InvalidData(detail) => write!(f, "文件编码数据无效: {detail}"),
            Self::BinaryContent => write!(f, "文本包含 NUL 字符，按二进制文件处理"),
        }
    }
}

#[derive(Debug)]
pub enum EncodeError {
    InvalidOptions(String),
    UnrepresentableCharacters(String),
}

impl std::fmt::Display for EncodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidOptions(detail) => write!(f, "无效的文本文件选项: {detail}"),
            Self::UnrepresentableCharacters(encoding) => {
                write!(f, "当前文本包含无法用 {encoding} 表示的字符")
            }
        }
    }
}

fn decode_utf16(bytes: &[u8], little_endian: bool) -> Result<String, DecodeError> {
    let (pairs, remainder) = bytes.as_chunks::<2>();
    if !remainder.is_empty() {
        return Err(DecodeError::InvalidData("UTF-16 字节数为奇数".to_string()));
    }
    let units = pairs
        .iter()
        .map(|pair| {
            if little_endian {
                u16::from_le_bytes(*pair)
            } else {
                u16::from_be_bytes(*pair)
            }
        })
        .collect::<Vec<_>>();
    String::from_utf16(&units)
        .map_err(|_| DecodeError::InvalidData("UTF-16 代理项序列无效".to_string()))
}

fn decode_bytes(bytes: &[u8], encoding: TextEncoding, bom: bool) -> Result<String, DecodeError> {
    match encoding {
        TextEncoding::Utf8 => std::str::from_utf8(bytes)
            .map(str::to_string)
            .map_err(|e| DecodeError::InvalidData(e.to_string())),
        TextEncoding::Utf16Le => decode_utf16(bytes, true),
        TextEncoding::Utf16Be => decode_utf16(bytes, false),
        TextEncoding::Gbk => {
            if bom {
                return Err(DecodeError::InvalidData("GBK 不支持 BOM".to_string()));
            }
            let (decoded, had_errors) = GBK.decode_without_bom_handling(bytes);
            if had_errors {
                Err(DecodeError::InvalidData("GBK 字节序列无效".to_string()))
            } else {
                Ok(decoded.into_owned())
            }
        }
    }
}

fn strip_matching_bom(bytes: &[u8], encoding: TextEncoding) -> (bool, &[u8]) {
    let prefix_len = match encoding {
        TextEncoding::Utf8 if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) => 3,
        TextEncoding::Utf16Le if bytes.starts_with(&[0xFF, 0xFE]) => 2,
        TextEncoding::Utf16Be if bytes.starts_with(&[0xFE, 0xFF]) => 2,
        _ => 0,
    };
    (prefix_len > 0, &bytes[prefix_len..])
}

fn detect_line_ending(text: &str) -> LineEnding {
    let bytes = text.as_bytes();
    for (index, byte) in bytes.iter().enumerate() {
        match byte {
            b'\r' if bytes.get(index + 1) == Some(&b'\n') => return LineEnding::CrLf,
            b'\n' => return LineEnding::Lf,
            b'\r' => return LineEnding::Lf,
            _ => {}
        }
    }
    LineEnding::Lf
}

fn normalize_line_endings(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\r', "\n")
}

/// Decode a text file, optionally forcing an encoding for an explicit reopen action.
/// Without an override, BOM wins, then valid UTF-8, then strict GBK fallback.
pub fn decode_file(
    bytes: &[u8],
    encoding_override: Option<TextEncoding>,
) -> Result<DecodedTextFile, DecodeError> {
    let (encoding, bom, payload) = if let Some(encoding) = encoding_override {
        let (bom, payload) = strip_matching_bom(bytes, encoding);
        (encoding, bom, payload)
    } else if bytes.starts_with(&[0x00, 0x00, 0xFE, 0xFF])
        || bytes.starts_with(&[0xFF, 0xFE, 0x00, 0x00])
    {
        return Err(DecodeError::UnsupportedEncoding("UTF-32".to_string()));
    } else if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        (TextEncoding::Utf8, true, &bytes[3..])
    } else if bytes.starts_with(&[0xFF, 0xFE]) {
        (TextEncoding::Utf16Le, true, &bytes[2..])
    } else if bytes.starts_with(&[0xFE, 0xFF]) {
        (TextEncoding::Utf16Be, true, &bytes[2..])
    } else if std::str::from_utf8(bytes).is_ok() {
        (TextEncoding::Utf8, false, bytes)
    } else {
        (TextEncoding::Gbk, false, bytes)
    };

    let decoded = decode_bytes(payload, encoding, bom)?;
    if decoded.contains('\0') {
        return Err(DecodeError::BinaryContent);
    }
    let line_ending = detect_line_ending(&decoded);
    Ok(DecodedTextFile {
        text: normalize_line_endings(&decoded),
        options: TextFileOptions {
            encoding,
            bom,
            line_ending,
        },
    })
}

/// Encode canonical-LF editor text to the selected on-disk charset and EOL.
pub fn encode_file(text: &str, options: TextFileOptions) -> Result<Vec<u8>, EncodeError> {
    if options.encoding == TextEncoding::Gbk && options.bom {
        return Err(EncodeError::InvalidOptions("GBK 不支持 BOM".to_string()));
    }
    let normalized = normalize_line_endings(text);
    let eol_text = match options.line_ending {
        LineEnding::Lf => Cow::Borrowed(normalized.as_str()),
        LineEnding::CrLf => Cow::Owned(normalized.replace('\n', "\r\n")),
    };

    let mut bytes = match options.encoding {
        TextEncoding::Utf8 => eol_text.as_bytes().to_vec(),
        TextEncoding::Utf16Le => eol_text.encode_utf16().flat_map(u16::to_le_bytes).collect(),
        TextEncoding::Utf16Be => eol_text.encode_utf16().flat_map(u16::to_be_bytes).collect(),
        TextEncoding::Gbk => {
            let (encoded, _, had_errors) = GBK.encode(&eol_text);
            if had_errors {
                return Err(EncodeError::UnrepresentableCharacters(
                    options.encoding.id().to_string(),
                ));
            }
            encoded.into_owned()
        }
    };

    if options.bom {
        let mut with_bom = match options.encoding {
            TextEncoding::Utf8 => vec![0xEF, 0xBB, 0xBF],
            TextEncoding::Utf16Le => vec![0xFF, 0xFE],
            TextEncoding::Utf16Be => vec![0xFE, 0xFF],
            TextEncoding::Gbk => unreachable!("GBK BOM rejected above"),
        };
        with_bom.append(&mut bytes);
        bytes = with_bom;
    }
    Ok(bytes)
}

#[derive(Debug)]
pub enum SaveError {
    NoParentDir(String),
    ReadOnlyTarget(String),
    CreateTempFailed(String, std::io::Error),
    WriteFailed(String, std::io::Error),
    SyncFailed(String, std::io::Error),
    RenameFailed(String, std::io::Error),
    InvalidOptions(String),
    UnrepresentableCharacters(String),
}

impl std::fmt::Display for SaveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SaveError::NoParentDir(p) => write!(f, "目标没有父目录: {p}"),
            SaveError::ReadOnlyTarget(p) => write!(f, "目标文件是只读文件: {p}"),
            SaveError::CreateTempFailed(p, e) => write!(f, "创建临时文件失败 ({p}): {e}"),
            SaveError::WriteFailed(p, e) => write!(f, "写入失败 ({p}): {e}"),
            SaveError::SyncFailed(p, e) => write!(f, "fsync 失败 ({p}): {e}"),
            SaveError::RenameFailed(p, e) => write!(f, "原子改名失败 ({p}): {e}"),
            SaveError::InvalidOptions(detail) => write!(f, "无效的文本文件选项: {detail}"),
            SaveError::UnrepresentableCharacters(encoding) => {
                write!(f, "当前文本包含无法用 {encoding} 表示的字符")
            }
        }
    }
}

fn temp_path(parent: &Path, target: &Path) -> PathBuf {
    let pid = std::process::id();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    let name = target
        .file_name()
        .map(|n| format!(".{}.tmp{pid}{nanos}", n.to_string_lossy()))
        .unwrap_or_else(|| format!(".alula-tmp{pid}{nanos}"));
    parent.join(name)
}

/// 原子保存：写同目录临时文件并 fsync 后 rename 覆盖目标。
pub fn atomic_save(path: &str, content: &str) -> Result<(), SaveError> {
    atomic_save_bytes(path, content.as_bytes())
}

/// 原子保存并按指定编码、BOM 与 EOL 生成文件字节。
pub fn atomic_save_with_options(
    path: &str,
    content: &str,
    options: TextFileOptions,
) -> Result<(), SaveError> {
    let bytes = encode_file(content, options).map_err(|e| match e {
        EncodeError::InvalidOptions(detail) => SaveError::InvalidOptions(detail),
        EncodeError::UnrepresentableCharacters(encoding) => {
            SaveError::UnrepresentableCharacters(encoding)
        }
    })?;
    atomic_save_bytes(path, &bytes)
}

fn atomic_save_bytes(path: &str, bytes: &[u8]) -> Result<(), SaveError> {
    let target = Path::new(path);
    if target
        .metadata()
        .is_ok_and(|metadata| metadata.permissions().readonly())
    {
        return Err(SaveError::ReadOnlyTarget(path.to_string()));
    }
    let parent = match target.parent().filter(|p| !p.as_os_str().is_empty()) {
        Some(p) => p.to_path_buf(),
        None => return Err(SaveError::NoParentDir(path.to_string())),
    };
    let tmp = temp_path(&parent, target);
    let cleanup = |mut p: PathBuf| {
        let _ = std::fs::remove_file(&mut p);
    };

    let mut file = std::fs::File::create(&tmp)
        .map_err(|e| SaveError::CreateTempFailed(tmp.display().to_string(), e))?;
    file.write_all(bytes)
        .map_err(|e| SaveError::WriteFailed(tmp.display().to_string(), e))?;
    file.sync_all()
        .map_err(|e| SaveError::SyncFailed(tmp.display().to_string(), e))?;
    drop(file);

    if let Err(e) = std::fs::rename(&tmp, target) {
        cleanup(tmp.clone());
        return Err(SaveError::RenameFailed(
            format!("{} -> {}", tmp.display(), path),
            e,
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmpdir(_name: &str) -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }

    #[test]
    fn save_creates_and_overwrites() {
        let td = tmpdir("doc-save");
        let target = td.path().join("out.txt");

        atomic_save(target.to_str().unwrap(), "第一版").unwrap();
        assert_eq!(std::fs::read_to_string(&target).unwrap(), "第一版");

        atomic_save(target.to_str().unwrap(), "第二版内容更长的内容").unwrap();
        assert_eq!(
            std::fs::read_to_string(&target).unwrap(),
            "第二版内容更长的内容"
        );

        // 目录内不应残留临时文件
        let leftovers: Vec<_> = std::fs::read_dir(td.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "残留临时文件: {leftovers:?}");
    }

    #[test]
    fn unicode_and_crlf_preserved() {
        let td = tmpdir("doc-uni");
        let target = td.path().join("u.txt");
        let content = "中文🦊emoji\r\n行二\r\n";
        atomic_save(target.to_str().unwrap(), content).unwrap();
        assert_eq!(std::fs::read_to_string(&target).unwrap(), content);
    }

    #[test]
    fn encoded_roundtrip_preserves_bom_eol_and_missing_final_newline() {
        let text = "你好 🦊\n第二行";
        let cases = [
            (
                TextFileOptions {
                    encoding: TextEncoding::Utf8,
                    bom: false,
                    line_ending: LineEnding::CrLf,
                },
                None,
            ),
            (
                TextFileOptions {
                    encoding: TextEncoding::Utf8,
                    bom: true,
                    line_ending: LineEnding::Lf,
                },
                None,
            ),
            (
                TextFileOptions {
                    encoding: TextEncoding::Utf16Le,
                    bom: true,
                    line_ending: LineEnding::CrLf,
                },
                None,
            ),
            (
                TextFileOptions {
                    encoding: TextEncoding::Utf16Be,
                    bom: true,
                    line_ending: LineEnding::Lf,
                },
                None,
            ),
            (
                TextFileOptions {
                    encoding: TextEncoding::Utf16Le,
                    bom: false,
                    line_ending: LineEnding::Lf,
                },
                Some(TextEncoding::Utf16Le),
            ),
            (
                TextFileOptions {
                    encoding: TextEncoding::Utf16Be,
                    bom: false,
                    line_ending: LineEnding::CrLf,
                },
                Some(TextEncoding::Utf16Be),
            ),
        ];

        for (options, override_encoding) in cases {
            let bytes = encode_file(text, options).unwrap();
            let decoded = decode_file(&bytes, override_encoding).unwrap();
            assert_eq!(decoded.text, text);
            assert_eq!(decoded.options, options);
            assert!(!decoded.text.ends_with('\n'));
        }
    }

    #[test]
    fn mixed_endings_use_the_first_style_and_normalize_all_lines() {
        let decoded = decode_file(b"a\r\nb\nc\r", None).unwrap();
        assert_eq!(decoded.text, "a\nb\nc\n");
        assert_eq!(decoded.options.line_ending, LineEnding::CrLf);
        let saved = encode_file(&decoded.text, decoded.options).unwrap();
        assert_eq!(saved, b"a\r\nb\r\nc\r\n");
    }

    #[test]
    fn gbk_roundtrip_and_unrepresentable_text_are_explicit() {
        let options = TextFileOptions {
            encoding: TextEncoding::Gbk,
            bom: false,
            line_ending: LineEnding::CrLf,
        };
        let bytes = encode_file("你好\n世界", options).unwrap();
        let decoded = decode_file(&bytes, None).unwrap();
        assert_eq!(decoded.text, "你好\n世界");
        assert_eq!(decoded.options, options);

        let error = encode_file("你好🦊", options).unwrap_err();
        assert!(matches!(error, EncodeError::UnrepresentableCharacters(_)));
    }

    #[test]
    fn unsupported_or_malformed_encodings_fail_without_replacement() {
        assert!(matches!(
            decode_file(&[0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41], None),
            Err(DecodeError::UnsupportedEncoding(_))
        ));
        assert!(matches!(
            decode_file(&[0xFF, 0xFE, 0x41], None),
            Err(DecodeError::InvalidData(_))
        ));
    }

    #[test]
    fn no_parent_dir_rejected() {
        assert!(matches!(
            atomic_save("just-a-name.txt", "x"),
            Err(SaveError::NoParentDir(_))
        ));
    }

    #[test]
    fn read_only_target_is_rejected_before_replacement() {
        let td = tmpdir("doc-readonly");
        let target = td.path().join("readonly.txt");
        std::fs::write(&target, b"disk version").unwrap();

        #[cfg(unix)]
        let original_mode = {
            use std::os::unix::fs::PermissionsExt;
            std::fs::metadata(&target).unwrap().permissions().mode()
        };
        let mut permissions = std::fs::metadata(&target).unwrap().permissions();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            permissions.set_mode(original_mode & !0o222);
        }
        #[cfg(windows)]
        permissions.set_readonly(true);
        std::fs::set_permissions(&target, permissions).unwrap();

        assert!(matches!(
            atomic_save(target.to_str().unwrap(), "replacement"),
            Err(SaveError::ReadOnlyTarget(_))
        ));
        assert_eq!(std::fs::read(&target).unwrap(), b"disk version");

        #[cfg(unix)]
        let permissions = {
            use std::os::unix::fs::PermissionsExt;
            let mut permissions = std::fs::metadata(&target).unwrap().permissions();
            permissions.set_mode(original_mode);
            permissions
        };
        #[cfg(windows)]
        let mut permissions = std::fs::metadata(&target).unwrap().permissions();
        #[cfg(windows)]
        permissions.set_readonly(false);
        std::fs::set_permissions(&target, permissions).unwrap();
    }
}
