//! Windows 实现：Toolhelp 快照 + GetProcessMemoryInfo。

use super::ProcInfo;
use windows_sys::Win32::{
    Foundation::{CloseHandle, INVALID_HANDLE_VALUE},
    System::{
        Diagnostics::ToolHelp::{
            CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W,
            TH32CS_SNAPPROCESS,
        },
        ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS_EX},
        Threading::{OpenProcess, TerminateProcess, PROCESS_TERMINATE},
    },
};

const PROCESS_QUERY_LIMITED_INFORMATION: u32 = 0x1000;

fn u16z(buf: &[u16]) -> String {
    let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    String::from_utf16_lossy(&buf[..end])
}

pub fn snapshot() -> Result<Vec<ProcInfo>, String> {
    unsafe {
        let h = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if h == INVALID_HANDLE_VALUE {
            return Err("CreateToolhelp32Snapshot 失败".into());
        }
        let mut entry = PROCESSENTRY32W {
            dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32,
            ..std::mem::zeroed()
        };
        if Process32FirstW(h, &mut entry) == 0 {
            CloseHandle(h);
            return Err("Process32FirstW 失败".into());
        }
        let mut procs = Vec::new();
        loop {
            let pid = entry.th32ProcessID as u64;
            let (ws, priv_b, peak) = memory_of(pid);
            procs.push(ProcInfo {
                pid,
                ppid: entry.th32ParentProcessID as u64,
                name: u16z(&entry.szExeFile),
                working_set: ws,
                private: priv_b,
                peak_private: peak,
                pss: priv_b, // Windows 无 PSS 概念；与 private 保持一致便于统一求和
            });
            if Process32NextW(h, &mut entry) == 0 {
                break;
            }
        }
        CloseHandle(h);
        Ok(procs)
    }
}

/// 返回 (working_set, private, peak_private)；打不开的进程返回 (0,0,0)。
fn memory_of(pid: u64) -> (u64, u64, u64) {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid as u32);
        if h.is_null() {
            return (0, 0, 0);
        }
        let mut pmc = PROCESS_MEMORY_COUNTERS_EX {
            cb: std::mem::size_of::<PROCESS_MEMORY_COUNTERS_EX>() as u32,
            ..std::mem::zeroed()
        };
        let ok = GetProcessMemoryInfo(
            h,
            &mut pmc as *mut PROCESS_MEMORY_COUNTERS_EX as *mut windows_sys::Win32::System::ProcessStatus::PROCESS_MEMORY_COUNTERS,
            pmc.cb,
        );
        CloseHandle(h);
        if ok == 0 {
            return (0, 0, 0);
        }
        (
            pmc.WorkingSetSize as u64,
            pmc.PrivateUsage.max(0) as u64,
            pmc.PeakPagefileUsage as u64,
        )
    }
}

pub fn kill_tree(root_pid: u64) -> Result<(), String> {
    let all = super::snapshot()?;
    let Some(tree) = super::tree(&all, root_pid) else {
        return Err(format!("进程 {root_pid} 不存在"));
    };
    unsafe {
        for p in &tree {
            let h = OpenProcess(PROCESS_TERMINATE, 0, p.pid as u32);
            if !h.is_null() {
                TerminateProcess(h, 1);
                CloseHandle(h);
            }
        }
    }
    Ok(())
}

/// lib.rs 统一通过 `platform::` 前缀调用。
pub mod platform {
    pub use super::{kill_tree, snapshot};
}
