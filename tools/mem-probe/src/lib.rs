//! mem-probe：进程树内存采集（docs/04-性能预算与测试基准 §1）。
//!
//! 口径（与 docs/04 §1.1 一致）：
//! - Windows：Private Bytes（私有提交，`PROCESS_MEMORY_COUNTERS_EX::PrivateUsage`）+
//!   Working Set，禁止只看/累加 RSS；
//! - Linux：PSS（smaps_rollup）与 Private（Private_Clean+Private_Dirty）；
//! - 所有求和限定在「根进程 + 全部后代」的进程树内。

use serde::{Deserialize, Serialize};

#[cfg(windows)]
pub mod win;
#[cfg(windows)]
pub use win::platform;

#[cfg(unix)]
pub mod linux;
#[cfg(unix)]
pub use linux::platform;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcInfo {
    pub pid: u64,
    pub ppid: u64,
    pub name: String,
    /// Working Set / RSS（字节）
    pub working_set: u64,
    /// Private Bytes（Windows）/ Private_Clean+Private_Dirty（Linux）（字节）
    pub private: u64,
    pub peak_private: u64,
    /// Linux 专用：PSS（Windows 上与 private 相同值，便于统一求和口径）
    pub pss: u64,
}

/// 一次性枚举当前全部进程（字段尽力而为；无法打开的进程被跳过）。
pub fn snapshot() -> Result<Vec<ProcInfo>, String> {
    platform::snapshot()
}

/// 从根进程开始的整棵进程树（含根本身）；根不存在返回 None。
/// 父进程已退出但仍存活的进程会被并入根为 pid 的树（按当前快照的父子关系）。
pub fn tree(all: &[ProcInfo], root_pid: u64) -> Option<Vec<ProcInfo>> {
    let mut children: std::collections::HashMap<u64, Vec<usize>> = std::collections::HashMap::new();
    for (i, p) in all.iter().enumerate() {
        children.entry(p.ppid).or_default().push(i);
    }
    let root_idx = all.iter().position(|p| p.pid == root_pid)?;
    let mut seen = vec![false; all.len()];
    let mut out = Vec::new();
    let mut stack = vec![root_idx];
    while let Some(i) = stack.pop() {
        if seen[i] {
            continue;
        }
        seen[i] = true;
        out.push(all[i].clone());
        if let Some(kids) = children.get(&all[i].pid) {
            for &k in kids {
                if !seen[k] {
                    stack.push(k);
                }
            }
        }
    }
    Some(out)
}

/// 按进程名查找 PID（大小写不敏感的完整文件名匹配，如 "code.exe"）。
pub fn find_pid_by_name(all: &[ProcInfo], name: &str) -> Option<u64> {
    let name = name.to_ascii_lowercase();
    all.iter()
        .find(|p| p.name.to_ascii_lowercase() == name)
        .map(|p| p.pid)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Sample {
    /// 距启动的秒数
    pub t: f64,
    pub total_private: u64,
    pub total_working_set: u64,
    pub n_processes: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Summary {
    /// 采样期内进程树私有内存峰值（字节）
    pub peak_private: u64,
    /// 稳定态：采样尾部 40% 样本的中位数（字节）
    pub stable_private: u64,
    pub final_private: u64,
    pub final_working_set: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatchReport {
    pub label: String,
    pub exe: String,
    pub args: Vec<String>,
    pub duration_s: f64,
    pub interval_s: f64,
    pub root_pid: u64,
    pub platform: String,
    pub captured_at: String,
    pub samples: Vec<Sample>,
    /// 最后一次采样的进程明细（归因分解用）
    pub final_processes: Vec<ProcInfo>,
    pub summary: Summary,
}

pub fn summarize(samples: &[Sample]) -> Option<Summary> {
    let last = samples.last()?;
    let peak = samples.iter().map(|s| s.total_private).max()?;
    let tail = (samples.len() * 2).div_ceil(5); // 尾部 40%
    let mut tail_vals: Vec<u64> = samples[samples.len() - tail.max(1)..]
        .iter()
        .map(|s| s.total_private)
        .collect();
    tail_vals.sort_unstable();
    let stable = tail_vals[tail_vals.len() / 2];
    Some(Summary {
        peak_private: peak,
        stable_private: stable,
        final_private: last.total_private,
        final_working_set: last.total_working_set,
    })
}

pub fn report_markdown(r: &WatchReport) -> String {
    let mib = |b: u64| format!("{:.1}", b as f64 / 1048576.0);
    let mut s = String::new();
    s.push_str(&format!("# 内存基线：{}\n\n", r.label));
    s.push_str(&format!(
        "- 可执行文件：`{} {}`\n- 平台/口径：{} / 进程树 Private Bytes{}\n",
        r.exe,
        r.args.join(" "),
        r.platform,
        if r.platform == "linux" {
            "（含 PSS）"
        } else {
            ""
        }
    ));
    s.push_str(&format!(
        "- 采样：{:.0}s，间隔 {:.1}s，共 {} 个样本\n- 采集时间：{}\n\n",
        r.duration_s,
        r.interval_s,
        r.samples.len(),
        r.captured_at
    ));
    s.push_str(&format!(
        "| 指标 | Private (MiB) | Working Set (MiB) |\n|---|---|---|\n\
         | 启动峰值 | {} | — |\n\
         | 稳定态（尾部 40% 中位） | {} | — |\n\
         | 结束时 | {} | {} |\n\n",
        mib(r.summary.peak_private),
        mib(r.summary.stable_private),
        mib(r.summary.final_private),
        mib(r.summary.final_working_set)
    ));
    s.push_str(
        "## 进程明细（结束时）\n\n| PID | 进程 | Private MiB | WS MiB |\n|---|---|---|---|\n",
    );
    let mut procs: Vec<&ProcInfo> = r.final_processes.iter().collect();
    procs.sort_by_key(|p| std::cmp::Reverse(p.private));
    for p in procs.iter().take(20) {
        s.push_str(&format!(
            "| {} | {} | {} | {} |\n",
            p.pid,
            p.name,
            mib(p.private),
            mib(p.working_set)
        ));
    }
    s
}

/// 采样 `exe` 启动后的进程树。root_name 用于启动器先退出的场景
/// （如 `cmd /c code ...`：以 "Code.exe" 重新定位根）。
pub fn watch(
    exe: &str,
    args: &[String],
    duration_s: f64,
    interval_s: f64,
    root_name: Option<&str>,
    label: &str,
    kill_on_exit: bool,
) -> Result<WatchReport, String> {
    use std::time::Instant;

    if duration_s <= 0.0 || interval_s <= 0.0 {
        return Err("duration/interval 必须为正".into());
    }
    let started_at = Instant::now();
    let mut child = std::process::Command::new(exe)
        .args(args)
        .spawn()
        .map_err(|e| format!("启动 {exe} 失败: {e}"))?;
    let child_pid = child.id() as u64;

    // 定位根：优先 root_name（等待其出现），否则用直接子进程 pid
    let root_pid = match root_name {
        Some(name) => {
            let deadline = started_at + std::time::Duration::from_secs(30);
            loop {
                if let Ok(all) = snapshot() {
                    if let Some(pid) = find_pid_by_name(&all, name) {
                        break pid;
                    }
                }
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    return Err(format!("等待进程 {name} 出现超时（30s）"));
                }
                std::thread::sleep(std::time::Duration::from_millis(200));
            }
        }
        None => child_pid,
    };

    let mut samples = Vec::new();
    let launch = Instant::now();
    while launch.elapsed().as_secs_f64() < duration_s {
        let t = launch.elapsed().as_secs_f64();
        let total = {
            let all = snapshot()?;
            match tree(&all, root_pid) {
                Some(procs) => Sample {
                    t,
                    total_private: procs.iter().map(|p| p.private).sum(),
                    total_working_set: procs.iter().map(|p| p.working_set).sum(),
                    n_processes: procs.len(),
                },
                None => {
                    // 根已退出：停止采样
                    break;
                }
            }
        };
        samples.push(total);
        let next = launch
            + std::time::Duration::from_secs_f64(((t + interval_s) * 1000.0).ceil() / 1000.0);
        let wait = next.saturating_duration_since(Instant::now());
        std::thread::sleep(wait);
    }

    // 结束时对进程明细做一次最终快照（可能根已退出）
    let final_processes = snapshot()
        .ok()
        .and_then(|all| tree(&all, root_pid))
        .unwrap_or_default();

    if kill_on_exit {
        let _ = platform::kill_tree(root_pid);
        let _ = child.kill();
        let _ = child.wait();
    }

    let summary = summarize(&samples).ok_or("未采集到任何样本")?;
    Ok(WatchReport {
        label: label.to_string(),
        exe: exe.to_string(),
        args: args.to_vec(),
        duration_s,
        interval_s,
        root_pid,
        platform: std::env::consts::OS.to_string(),
        captured_at: chrono_now(),
        samples,
        final_processes,
        summary,
    })
}

fn chrono_now() -> String {
    // 不引入 chrono：用 std time 拼 UTC 时间（精度到秒，报告用途足够）
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let days = secs / 86400;
    let tod = secs % 86400;
    let (h, mi, s) = (tod / 3600, (tod % 3600) / 60, tod % 60);
    // 民用日期算法（Howard Hinnant civil_from_days）
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02} {h:02}:{mi:02}:{s:02} UTC")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_contains_self() {
        let all = snapshot().unwrap();
        let me = std::process::id() as u64;
        assert!(all.iter().any(|p| p.pid == me), "快照缺少当前进程");
        let me_info = all.iter().find(|p| p.pid == me).unwrap();
        assert!(me_info.private > 0 || cfg!(unix), "private 应大于 0");
    }

    #[test]
    fn tree_of_self_includes_self() {
        let all = snapshot().unwrap();
        let me = std::process::id() as u64;
        let t = tree(&all, me).unwrap();
        assert!(t.iter().any(|p| p.pid == me));
    }

    #[test]
    fn tree_missing_root_returns_none() {
        let all = snapshot().unwrap();
        assert!(tree(&all, u64::MAX).is_none());
    }

    #[test]
    fn summarize_reports_peak_and_stable() {
        let mk = |t: f64, p: u64| Sample {
            t,
            total_private: p,
            total_working_set: p,
            n_processes: 1,
        };
        let s = summarize(&[
            mk(0.0, 100),
            mk(1.0, 200),
            mk(2.0, 150),
            mk(3.0, 140),
            mk(4.0, 130),
        ])
        .unwrap();
        assert_eq!(s.peak_private, 200);
        assert!(s.final_private == 130);
    }
}
