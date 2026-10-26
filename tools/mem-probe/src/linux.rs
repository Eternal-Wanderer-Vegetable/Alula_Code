//! Linux 实现：/proc 遍历 + smaps_rollup（PSS / Private）。

use super::ProcInfo;
use std::path::PathBuf;

fn proc_dir() -> PathBuf {
    PathBuf::from("/proc")
}

fn read_u64_field(line: &str) -> Option<u64> {
    line.split_whitespace().nth(1)?.parse().ok()
}

/// 解析 /proc/<pid>/stat 的 comm 与 ppid。
/// comm 可含空格与括号：取最后一个 ')' 之后的部分再解析。
fn parse_stat(pid: u64) -> Option<(String, u64)> {
    let raw = std::fs::read_to_string(proc_dir().join(pid.to_string()).join("stat")).ok()?;
    let close = raw.rfind(')')?;
    let comm = raw[raw.find('(')? + 1..close].to_string();
    let rest = raw[close + 1..].trim();
    // rest[0] = state；ppid 是第 2 个字段
    let mut it = rest.split_whitespace();
    let _state = it.next()?;
    let ppid: u64 = it.next()?.parse().ok()?;
    Some((comm, ppid))
}

fn parse_smaps_rollup(pid: u64) -> (u64, u64, u64) {
    // 返回 (pss, private, peak)。无权限/文件缺失时为 0。
    let Ok(text) = std::fs::read_to_string(proc_dir().join(pid.to_string()).join("smaps_rollup"))
    else {
        return (0, 0, 0);
    };
    let mut pss = 0u64;
    let mut private = 0u64;
    for line in text.lines() {
        if line.starts_with("Pss:") {
            pss = read_u64_field(line).unwrap_or(0) * 1024;
        } else if line.starts_with("Private_Clean:") {
            private += read_u64_field(line).unwrap_or(0) * 1024;
        } else if line.starts_with("Private_Dirty:") {
            private += read_u64_field(line).unwrap_or(0) * 1024;
        }
    }
    (pss, private, 0)
}

fn working_set(pid: u64) -> u64 {
    // statm 第 2 个字段 × 页大小
    let Ok(statm) = std::fs::read_to_string(proc_dir().join(pid.to_string()).join("statm")) else {
        return 0;
    };
    let rss_pages: u64 = statm.split_whitespace().nth(1)?.parse().ok()?;
    rss_pages * 4096
}

pub fn snapshot() -> Result<Vec<ProcInfo>, String> {
    let dir = proc_dir();
    let entries = std::fs::read_dir(&dir).map_err(|e| format!("读取 /proc 失败: {e}"))?;
    let mut procs = Vec::new();
    for entry in entries.flatten() {
        let fname = entry.file_name();
        let Ok(pid) = fname.to_string_lossy().parse::<u64>() else {
            continue;
        };
        let Some((name, ppid)) = parse_stat(pid) else {
            continue;
        };
        let (pss, private, _peak) = parse_smaps_rollup(pid);
        procs.push(ProcInfo {
            pid,
            ppid,
            name,
            working_set: working_set(pid),
            private,
            peak_private: 0,
            pss,
        });
    }
    Ok(procs)
}

pub fn kill_tree(root_pid: u64) -> Result<(), String> {
    let all = super::snapshot()?;
    let Some(tree) = super::tree(&all, root_pid) else {
        return Err(format!("进程 {root_pid} 不存在"));
    };
    // 先杀子后杀父（避免父退出后孤儿重生问题此处不存在，但顺序更稳）
    for p in tree.iter().rev() {
        unsafe {
            libc::kill(p.pid as i32, libc::SIGKILL);
        }
    }
    Ok(())
}

/// lib.rs 统一通过 `platform::` 前缀调用。
pub mod platform {
    pub use super::{kill_tree, snapshot};
}
