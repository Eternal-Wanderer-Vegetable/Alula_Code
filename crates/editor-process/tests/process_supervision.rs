use std::process::{Command, Stdio};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use editor_process::{ProcessKind, ProcessMetadata, ProcessSupervisor};

#[test]
fn supervised_root_fixture() {
    if std::env::var_os("ALULA_SUPERVISED_ROOT_FIXTURE").is_none() {
        return;
    }

    let executable = std::env::current_exe().expect("test executable path");
    let mut descendant = Command::new(executable)
        .args(["--exact", "supervised_descendant_fixture", "--nocapture"])
        .env("ALULA_SUPERVISED_DESCENDANT_FIXTURE", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn descendant fixture");
    thread::sleep(Duration::from_secs(30));
    let _ = descendant.wait();
}

#[test]
fn supervised_descendant_fixture() {
    if std::env::var_os("ALULA_SUPERVISED_DESCENDANT_FIXTURE").is_some() {
        thread::sleep(Duration::from_secs(30));
    }
}

#[test]
fn tracks_a_process_tree_and_terminates_descendants_before_the_root() {
    let supervisor = Arc::new(ProcessSupervisor::default());
    let executable = std::env::current_exe().expect("test executable path");
    let mut command = Command::new(executable);
    command
        .args(["--exact", "supervised_root_fixture", "--nocapture"])
        .env("ALULA_SUPERVISED_ROOT_FIXTURE", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    let mut child = supervisor
        .spawn(
            &mut command,
            ProcessMetadata::new(
                "test process tree",
                ProcessKind::Task,
                Some("fixture".to_string()),
            ),
        )
        .expect("spawn supervised process");
    let root_pid = child.id();

    let deadline = Instant::now() + Duration::from_secs(5);
    let processes = loop {
        let processes = supervisor.snapshot().expect("snapshot process tree");
        if processes.iter().any(|process| process.pid != root_pid) {
            break processes;
        }
        assert!(Instant::now() < deadline, "descendant did not appear");
        thread::sleep(Duration::from_millis(25));
    };
    assert!(processes.iter().any(|process| {
        process.pid == root_pid
            && process.root_pid == root_pid
            && process.kind == ProcessKind::Task
            && process.label == "test process tree"
            && process.workspace.as_deref() == Some("fixture")
    }));
    assert!(processes.iter().any(|process| process.pid != root_pid));

    child.kill_tree_and_wait().expect("terminate process tree");
    assert!(supervisor.snapshot().expect("empty snapshot").is_empty());
}

#[test]
fn critical_reclaim_stops_search_but_leaves_other_process_kinds_running() {
    let supervisor = Arc::new(ProcessSupervisor::default());
    let executable = std::env::current_exe().expect("test executable path");
    let mut search_command = Command::new(&executable);
    search_command
        .args(["--exact", "supervised_root_fixture", "--nocapture"])
        .env("ALULA_SUPERVISED_ROOT_FIXTURE", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut search = supervisor
        .spawn(
            &mut search_command,
            ProcessMetadata::new("search fixture", ProcessKind::Search, None),
        )
        .expect("spawn search fixture");
    let search_pid = search.id();

    let mut other_command = Command::new(executable);
    other_command
        .args(["--exact", "supervised_descendant_fixture", "--nocapture"])
        .env("ALULA_SUPERVISED_DESCENDANT_FIXTURE", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut other = supervisor
        .spawn(
            &mut other_command,
            ProcessMetadata::new("task fixture", ProcessKind::Task, None),
        )
        .expect("spawn non-search fixture");
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let processes = supervisor.snapshot().expect("snapshot process tree");
        if processes
            .iter()
            .any(|process| process.label == "search fixture" && process.pid != search_pid)
        {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "search descendant did not appear"
        );
        thread::sleep(Duration::from_millis(25));
    }

    assert_eq!(
        supervisor
            .stop_registered_kind(ProcessKind::Search)
            .expect("stop registered search tree"),
        1
    );
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if search
            .try_wait()
            .expect("wait for reclaimed search")
            .is_some()
        {
            break;
        }
        assert!(Instant::now() < deadline, "search process did not exit");
        thread::sleep(Duration::from_millis(25));
    }
    assert!(other.try_wait().expect("check task process").is_none());

    other
        .kill_tree_and_wait()
        .expect("clean up non-search fixture");
}
