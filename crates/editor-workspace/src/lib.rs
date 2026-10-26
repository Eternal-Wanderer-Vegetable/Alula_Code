//! 工作区文件系统操作：目录枚举、文件读取。
//!
//! MVP 边界（docs/03 Phase 1）：UTF-8 文本文件；二进制/非 UTF-8 文件返回
//! BinaryFile 错误（编码处理是 Phase 1 后续任务）。文件监视（notify）下一增量接入。

use serde::Serialize;
use std::path::Path;

#[derive(Debug, Clone, Serialize)]
pub struct DirEntry {
    pub name: String,
    /// 完整路径（UI 直接用于下一层枚举/打开）
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
}

#[derive(Debug)]
pub enum WorkspaceError {
    NotFound(String),
    NotADirectory(String),
    BinaryFile(String),
    Io(String),
}

impl std::fmt::Display for WorkspaceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WorkspaceError::NotFound(p) => write!(f, "路径不存在: {p}"),
            WorkspaceError::NotADirectory(p) => write!(f, "不是目录: {p}"),
            WorkspaceError::BinaryFile(p) => write!(f, "二进制文件（MVP 暂不支持）: {p}"),
            WorkspaceError::Io(e) => write!(f, "IO 错误: {e}"),
        }
    }
}

fn entry_path(dir: &Path, name: &std::ffi::OsStr) -> Option<String> {
    dir.join(name).to_str().map(|s| s.to_string())
}

/// 枚举目录（目录在前，其余按名称不区分大小写排序）。
pub fn list_dir(path: &str) -> Result<Vec<DirEntry>, WorkspaceError> {
    let dir = Path::new(path);
    if !dir.exists() {
        return Err(WorkspaceError::NotFound(path.to_string()));
    }
    if !dir.is_dir() {
        return Err(WorkspaceError::NotADirectory(path.to_string()));
    }
    let read = std::fs::read_dir(dir).map_err(|e| WorkspaceError::Io(e.to_string()))?;
    let mut entries = Vec::new();
    for e in read {
        let e = e.map_err(|err| WorkspaceError::Io(err.to_string()))?;
        let name_os = e.file_name();
        let meta = e
            .metadata()
            .map_err(|err| WorkspaceError::Io(err.to_string()))?;
        let Some(path_str) = entry_path(dir, &name_os) else {
            continue;
        };
        let name = name_os.to_string_lossy().to_string();
        entries.push(DirEntry {
            name,
            path: path_str,
            is_dir: meta.is_dir(),
            size: meta.len(),
        });
    }
    entries.sort_by(|a, b| {
        b.is_dir
            .cmp(&a.is_dir)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(entries)
}

/// 读取 UTF-8 文本文件。含 NUL 或非法 UTF-8 视为二进制文件。
pub fn read_file(path: &str) -> Result<String, WorkspaceError> {
    let p = Path::new(path);
    if !p.exists() {
        return Err(WorkspaceError::NotFound(path.to_string()));
    }
    let bytes = std::fs::read(p).map_err(|e| WorkspaceError::Io(e.to_string()))?;
    if bytes.contains(&0) {
        return Err(WorkspaceError::BinaryFile(path.to_string()));
    }
    String::from_utf8(bytes).map_err(|_| WorkspaceError::BinaryFile(path.to_string()))
}

pub fn exists(path: &str) -> bool {
    Path::new(path).exists()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmpdir(name: &str) -> tempfile::TempDir {
        tempdir_named(name)
    }

    fn tempdir_named(_name: &str) -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }

    #[test]
    fn list_dir_sorted_dirs_first_and_metadata() {
        let td = tmpdir("ws-list");
        let root = td.path();
        std::fs::create_dir(root.join("zdir")).unwrap();
        std::fs::create_dir(root.join("adir")).unwrap();
        std::fs::write(root.join("m.txt"), "hello").unwrap();

        let entries = list_dir(root.to_str().unwrap()).unwrap();
        assert_eq!(entries.len(), 3);
        // 目录在前
        assert!(entries[0].is_dir && entries[1].is_dir);
        assert_eq!(entries[0].name, "adir");
        assert_eq!(entries[1].name, "zdir");
        let file = entries.iter().find(|e| e.name == "m.txt").unwrap();
        assert!(!file.is_dir);
        assert_eq!(file.size, 5);
        assert!(file.path.contains("m.txt"));
    }

    #[test]
    fn list_dir_errors() {
        assert!(matches!(
            list_dir("Z:/definitely/not/here"),
            Err(WorkspaceError::NotFound(_)) | Err(WorkspaceError::Io(_))
        ));
    }

    #[test]
    fn read_file_utf8_and_binary() {
        let td = tmpdir("ws-read");
        let f = td.path().join("a.txt");
        std::fs::write(&f, "中文内容\nok").unwrap();
        assert_eq!(read_file(f.to_str().unwrap()).unwrap(), "中文内容\nok");

        let b = td.path().join("b.bin");
        std::fs::write(&b, [0x68, 0x00, 0x69]).unwrap();
        assert!(matches!(
            read_file(b.to_str().unwrap()),
            Err(WorkspaceError::BinaryFile(_))
        ));
    }
}
