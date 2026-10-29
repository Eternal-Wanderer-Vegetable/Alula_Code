use std::collections::HashMap;
use std::io;
use std::process::{Child, ChildStdin, ChildStdout, Command, ExitStatus};
use std::sync::{Arc, Mutex, OnceLock};
use sysinfo::{MemoryRefreshKind, ProcessRefreshKind, ProcessesToUpdate, System};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProcessKind {
    LanguageServer,
    Git,
    Search,
    Task,
    Terminal,
    DebugAdapter,
    WebView,
    Other,
}

impl ProcessKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::LanguageServer => "languageServer",
            Self::Git => "git",
            Self::Search => "search",
            Self::Task => "task",
            Self::Terminal => "terminal",
            Self::DebugAdapter => "debugAdapter",
            Self::WebView => "webView",
            Self::Other => "other",
        }
    }

    pub fn from_tag(kind: &str) -> Self {
        match kind {
            "languageServer" => Self::LanguageServer,
            "git" => Self::Git,
            "search" => Self::Search,
            "task" => Self::Task,
            "terminal" => Self::Terminal,
            "debugAdapter" => Self::DebugAdapter,
            "webView" => Self::WebView,
            _ => Self::Other,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProcessMetadata {
    pub label: String,
    pub kind: ProcessKind,
    pub workspace: Option<String>,
}

impl ProcessMetadata {
    pub fn new(label: impl Into<String>, kind: ProcessKind, workspace: Option<String>) -> Self {
        Self {
            label: label.into(),
            kind,
            workspace,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProcessInfo {
    pub root_pid: u32,
    pub pid: u32,
    pub parent_pid: Option<u32>,
    pub name: String,
    pub label: String,
    pub kind: ProcessKind,
    pub workspace: Option<String>,
    pub resident_bytes: u64,
}

/// Owns the metadata for child processes and provides an on-demand process-tree snapshot.
/// It does not run a background watcher; callers choose when to sample the tree.
#[derive(Default)]
pub struct ProcessSupervisor {
    roots: Mutex<HashMap<u32, ProcessMetadata>>,
}

impl ProcessSupervisor {
    pub fn global() -> Arc<Self> {
        static INSTANCE: OnceLock<Arc<ProcessSupervisor>> = OnceLock::new();
        Arc::clone(INSTANCE.get_or_init(|| Arc::new(Self::default())))
    }

    pub fn spawn(
        self: &Arc<Self>,
        command: &mut Command,
        metadata: ProcessMetadata,
    ) -> io::Result<SupervisedChild> {
        let child = command.spawn()?;
        let pid = child.id();
        match self.roots.lock() {
            Ok(mut roots) => {
                roots.insert(pid, metadata.clone());
            }
            Err(_) => {
                let mut child = child;
                let _ = child.kill();
                let _ = child.wait();
                return Err(io::Error::other("process supervisor lock poisoned"));
            }
        }
        Ok(SupervisedChild {
            child,
            supervisor: Arc::clone(self),
            metadata,
            registered: true,
        })
    }

    /// Register a process started by another host layer (for example Dart `Process.start`).
    pub fn register_external(&self, pid: u32, metadata: ProcessMetadata) -> io::Result<()> {
        self.roots
            .lock()
            .map_err(|_| io::Error::other("process supervisor lock poisoned"))?
            .insert(pid, metadata);
        Ok(())
    }

    pub fn unregister_external(&self, pid: u32) -> io::Result<()> {
        self.roots
            .lock()
            .map_err(|_| io::Error::other("process supervisor lock poisoned"))?
            .remove(&pid);
        Ok(())
    }

    pub fn snapshot(&self) -> io::Result<Vec<ProcessInfo>> {
        let roots = self
            .roots
            .lock()
            .map_err(|_| io::Error::other("process supervisor lock poisoned"))?
            .clone();
        if roots.is_empty() {
            return Ok(Vec::new());
        }

        let mut system = System::new().map_err(io::Error::other)?;
        system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().with_memory().without_tasks(),
        );

        let mut parents = HashMap::new();
        for (pid, process) in system.processes() {
            if let (Some(pid), Some(parent)) =
                (pid_as_u32(*pid), process.parent().and_then(pid_as_u32))
            {
                parents.insert(pid, parent);
            }
        }

        let mut result = Vec::new();
        for (root_pid, metadata) in roots {
            for (pid, process) in system.processes() {
                let Some(pid) = pid_as_u32(*pid) else {
                    continue;
                };
                let mut parent = process.parent().and_then(pid_as_u32);
                let mut cursor = pid;
                let mut depth = 0;
                while cursor != root_pid && depth < 128 {
                    let Some(parent_pid) = parent else {
                        break;
                    };
                    cursor = parent_pid;
                    parent = parents.get(&cursor).copied();
                    depth += 1;
                }
                if cursor != root_pid {
                    continue;
                }
                result.push(ProcessInfo {
                    root_pid,
                    pid,
                    parent_pid: process.parent().and_then(pid_as_u32),
                    name: process.name().to_string_lossy().into_owned(),
                    label: metadata.label.clone(),
                    kind: metadata.kind,
                    workspace: metadata.workspace.clone(),
                    resident_bytes: process.memory(),
                });
            }
        }
        result.sort_by_key(|entry| (entry.root_pid, entry.pid));
        Ok(result)
    }

    /// Stop reclaimable searches on critical pressure, preserving Git mutations, editing and save.
    pub fn stop_registered_kind(&self, kind: ProcessKind) -> io::Result<usize> {
        let roots: Vec<u32> = self
            .roots
            .lock()
            .map_err(|_| io::Error::other("process supervisor lock poisoned"))?
            .iter()
            .filter_map(|(pid, metadata)| (metadata.kind == kind).then_some(*pid))
            .collect();
        if roots.is_empty() {
            return Ok(0);
        }

        let mut system = System::new().map_err(io::Error::other)?;
        system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().without_tasks(),
        );
        let mut children: HashMap<u32, Vec<u32>> = HashMap::new();
        for (pid, process) in system.processes() {
            if let Some(parent) = process.parent().and_then(pid_as_u32) {
                if let Some(pid) = pid_as_u32(*pid) {
                    children.entry(parent).or_default().push(pid);
                }
            }
        }

        let mut stopped = 0;
        for root_pid in roots {
            let mut descendants = Vec::new();
            collect_descendants(root_pid, &children, &mut descendants, 0);
            for pid in descendants {
                if let Some(process) = system.process(sysinfo::Pid::from(pid as usize)) {
                    let _ = process.kill();
                }
            }
            if let Some(process) = system.process(sysinfo::Pid::from(root_pid as usize)) {
                if process.kill() {
                    stopped += 1;
                }
            }
        }
        Ok(stopped)
    }

    fn unregister(&self, pid: u32) {
        if let Ok(mut roots) = self.roots.lock() {
            roots.remove(&pid);
        }
    }

    fn kill_descendants(&self, root_pid: u32) -> io::Result<()> {
        let mut system = System::new().map_err(io::Error::other)?;
        system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().without_tasks(),
        );
        let mut children: HashMap<u32, Vec<u32>> = HashMap::new();
        let mut processes = HashMap::new();
        for (pid, process) in system.processes() {
            let Some(pid) = pid_as_u32(*pid) else {
                continue;
            };
            processes.insert(pid, process);
            if let Some(parent) = process.parent().and_then(pid_as_u32) {
                children.entry(parent).or_default().push(pid);
            }
        }

        let mut descendants = Vec::new();
        collect_descendants(root_pid, &children, &mut descendants, 0);
        for pid in descendants {
            if let Some(process) = processes.get(&pid) {
                let _ = process.kill();
            }
        }
        Ok(())
    }
}

fn pid_as_u32(pid: sysinfo::Pid) -> Option<u32> {
    pid.to_string().parse().ok()
}

fn collect_descendants(
    root: u32,
    children: &HashMap<u32, Vec<u32>>,
    output: &mut Vec<u32>,
    depth: usize,
) {
    if depth >= 128 {
        return;
    }
    if let Some(direct) = children.get(&root) {
        for child in direct {
            collect_descendants(*child, children, output, depth + 1);
            output.push(*child);
        }
    }
}

pub struct SupervisedChild {
    child: Child,
    supervisor: Arc<ProcessSupervisor>,
    metadata: ProcessMetadata,
    registered: bool,
}

impl SupervisedChild {
    pub fn id(&self) -> u32 {
        self.child.id()
    }

    pub fn metadata(&self) -> &ProcessMetadata {
        &self.metadata
    }

    pub fn take_stdin(&mut self) -> Option<ChildStdin> {
        self.child.stdin.take()
    }

    pub fn take_stdout(&mut self) -> Option<ChildStdout> {
        self.child.stdout.take()
    }

    pub fn try_wait(&mut self) -> io::Result<Option<ExitStatus>> {
        let status = self.child.try_wait()?;
        if status.is_some() {
            self.unregister();
        }
        Ok(status)
    }

    /// Force-stop descendants from leaves upward, then wait for the owned root process.
    pub fn kill_tree_and_wait(&mut self) -> io::Result<ExitStatus> {
        let descendants_result = self.supervisor.kill_descendants(self.child.id());
        if self.child.try_wait()?.is_none() {
            if let Err(error) = self.child.kill() {
                if self.child.try_wait()?.is_none() {
                    return Err(error);
                }
            }
        }
        let status = self.child.wait()?;
        self.unregister();
        descendants_result?;
        Ok(status)
    }

    fn unregister(&mut self) {
        if self.registered {
            self.supervisor.unregister(self.child.id());
            self.registered = false;
        }
    }
}

impl Drop for SupervisedChild {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.kill_tree_and_wait();
        } else {
            self.unregister();
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MemoryPressure {
    Normal,
    Warn,
    Critical,
}

impl MemoryPressure {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Warn => "warn",
            Self::Critical => "critical",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MemorySource {
    System,
    Cgroup,
}

impl MemorySource {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Cgroup => "cgroup",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MemorySnapshot {
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub pressure: MemoryPressure,
    pub source: MemorySource,
    pub transitioned_to_critical: bool,
}

/// Samples memory only when requested and applies hysteresis to avoid UI state flapping.
pub struct ResourcePressureMonitor {
    system: System,
    pressure: MemoryPressure,
}

impl ResourcePressureMonitor {
    pub fn new() -> io::Result<Self> {
        Ok(Self {
            system: System::new().map_err(io::Error::other)?,
            pressure: MemoryPressure::Normal,
        })
    }

    pub fn sample(&mut self) -> io::Result<MemorySnapshot> {
        self.system
            .refresh_memory_specifics(MemoryRefreshKind::nothing().with_ram());
        let cgroup = self.system.cgroup_limits();
        let (total_bytes, available_bytes, source) = match cgroup {
            Some(limits) if limits.total_memory > 0 => (
                limits.total_memory,
                limits.free_memory.min(limits.total_memory),
                MemorySource::Cgroup,
            ),
            _ => (
                self.system.total_memory(),
                self.system
                    .available_memory()
                    .min(self.system.total_memory()),
                MemorySource::System,
            ),
        };
        if total_bytes == 0 {
            return Err(io::Error::other("system reported zero total memory"));
        }
        let previous = self.pressure;
        self.pressure = classify_memory_pressure(total_bytes, available_bytes, previous);
        Ok(MemorySnapshot {
            total_bytes,
            available_bytes,
            pressure: self.pressure,
            source,
            transitioned_to_critical: previous != MemoryPressure::Critical
                && self.pressure == MemoryPressure::Critical,
        })
    }
}

/// Warning at 15% available, critical at 7%; recovery uses 20%/10% hysteresis.
pub fn classify_memory_pressure(
    total_bytes: u64,
    available_bytes: u64,
    previous: MemoryPressure,
) -> MemoryPressure {
    if total_bytes == 0 {
        return previous;
    }
    let available = u128::from(available_bytes.min(total_bytes));
    let total = u128::from(total_bytes);
    let below = |percent: u128| available * 100 <= total * percent;
    let above = |percent: u128| available * 100 >= total * percent;

    match previous {
        MemoryPressure::Normal if below(7) => MemoryPressure::Critical,
        MemoryPressure::Normal if below(15) => MemoryPressure::Warn,
        MemoryPressure::Normal => MemoryPressure::Normal,
        MemoryPressure::Warn if below(7) => MemoryPressure::Critical,
        MemoryPressure::Warn if above(20) => MemoryPressure::Normal,
        MemoryPressure::Warn => MemoryPressure::Warn,
        MemoryPressure::Critical if above(10) => MemoryPressure::Warn,
        MemoryPressure::Critical => MemoryPressure::Critical,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pressure_thresholds_and_hysteresis() {
        assert_eq!(
            classify_memory_pressure(100, 30, MemoryPressure::Normal),
            MemoryPressure::Normal
        );
        assert_eq!(
            classify_memory_pressure(100, 15, MemoryPressure::Normal),
            MemoryPressure::Warn
        );
        assert_eq!(
            classify_memory_pressure(100, 7, MemoryPressure::Normal),
            MemoryPressure::Critical
        );
        assert_eq!(
            classify_memory_pressure(100, 9, MemoryPressure::Critical),
            MemoryPressure::Critical
        );
        assert_eq!(
            classify_memory_pressure(100, 10, MemoryPressure::Critical),
            MemoryPressure::Warn
        );
        assert_eq!(
            classify_memory_pressure(100, 19, MemoryPressure::Warn),
            MemoryPressure::Warn
        );
        assert_eq!(
            classify_memory_pressure(100, 20, MemoryPressure::Warn),
            MemoryPressure::Normal
        );
    }

    #[test]
    fn process_tree_orders_descendants_before_parents() {
        let children = HashMap::from([(10, vec![11, 13]), (11, vec![12])]);
        let mut descendants = Vec::new();
        collect_descendants(10, &children, &mut descendants, 0);
        assert_eq!(descendants, [12, 11, 13]);
    }

    #[test]
    fn pressure_with_zero_total_keeps_prior_state() {
        assert_eq!(
            classify_memory_pressure(0, 0, MemoryPressure::Warn),
            MemoryPressure::Warn
        );
    }
}
