//! 原子保存（docs/02 §6.3）：同目录临时文件 → 写入 → fsync → 原子改名。
//! 任意时刻被杀不会留下半写文件；目标要么是旧内容要么是新内容。

use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub enum SaveError {
    NoParentDir(String),
    CreateTempFailed(String, std::io::Error),
    WriteFailed(String, std::io::Error),
    SyncFailed(String, std::io::Error),
    RenameFailed(String, std::io::Error),
}

impl std::fmt::Display for SaveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SaveError::NoParentDir(p) => write!(f, "目标没有父目录: {p}"),
            SaveError::CreateTempFailed(p, e) => write!(f, "创建临时文件失败 ({p}): {e}"),
            SaveError::WriteFailed(p, e) => write!(f, "写入失败 ({p}): {e}"),
            SaveError::SyncFailed(p, e) => write!(f, "fsync 失败 ({p}): {e}"),
            SaveError::RenameFailed(p, e) => write!(f, "原子改名失败 ({p}): {e}"),
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
    let target = Path::new(path);
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
    file.write_all(content.as_bytes())
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
    fn no_parent_dir_rejected() {
        assert!(matches!(
            atomic_save("just-a-name.txt", "x"),
            Err(SaveError::NoParentDir(_))
        ));
    }
}
