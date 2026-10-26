//! mem-probe CLI
//!
//! 用法：
//!   mem-probe tree --pid <N>                       一次性输出进程树内存 JSON
//!   mem-probe watch --exe <路径> [--arg 参数]...    启动并周期采样进程树，输出 WatchReport
//!                    [--duration 45] [--interval 1] [--label L] [--out 报告.json]
//!                    [--root-name Code.exe] [--no-kill] [--md 报告.md]
//!   mem-probe sleepy --ms <N>                      睡眠 N 毫秒后退出（测试用替身应用）

use mem_probe::{report_markdown, watch, WatchReport};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = run(&args);
    std::process::exit(code);
}

fn run(args: &[String]) -> i32 {
    match args.first().map(|s| s.as_str()) {
        Some("sleepy") => {
            let ms: u64 = args
                .iter()
                .position(|a| a == "--ms")
                .and_then(|i| args.get(i + 1))
                .and_then(|v| v.parse().ok())
                .unwrap_or(1000);
            std::thread::sleep(std::time::Duration::from_millis(ms));
            0
        }
        Some("tree") => cmd_tree(args),
        Some("watch") => cmd_watch(args),
        Some("--help") | Some("-h") | Some("help") | None => {
            print_help();
            0
        }
        Some(other) => {
            eprintln!("未知子命令: {other}");
            print_help();
            2
        }
    }
}

fn print_help() {
    eprintln!(
        "用法:\n  mem-probe tree --pid <N>\n  mem-probe watch --exe <路径> [--arg 参数]... [--duration 45] [--interval 1]\n                    [--label L] [--out f.json] [--md f.md] [--root-name N] [--no-kill]\n  mem-probe sleepy --ms <N>"
    );
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn has_flag(args: &[String], name: &str) -> bool {
    args.iter().any(|a| a == name)
}

fn collect_values(args: &[String], name: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == name {
            if let Some(v) = args.get(i + 1) {
                out.push(v.clone());
                i += 2;
                continue;
            }
        }
        i += 1;
    }
    out
}

fn emit_report(report: &WatchReport, out: Option<&String>, md: Option<&String>) {
    let json = serde_json::to_string_pretty(report).expect("序列化报告");
    match out {
        Some(path) => {
            std::fs::write(path, &json)
                .map_err(|e| format!("写出 {path} 失败: {e}"))
                .unwrap();
            eprintln!("JSON 报告: {path}");
        }
        None => println!("{json}"),
    }
    if let Some(path) = md {
        std::fs::write(path, report_markdown(report))
            .map_err(|e| format!("写出 {path} 失败: {e}"))
            .unwrap();
        eprintln!("Markdown 报告: {path}");
    }
}

fn cmd_tree(args: &[String]) -> i32 {
    let Some(pid) = flag(args, "--pid").and_then(|v| v.parse().ok()) else {
        eprintln!("tree 需要 --pid <N>");
        return 2;
    };
    match mem_probe::snapshot() {
        Ok(all) => match mem_probe::tree(&all, pid) {
            Some(tree) => {
                let total_private: u64 = tree.iter().map(|p| p.private).sum();
                let total_ws: u64 = tree.iter().map(|p| p.working_set).sum();
                println!(
                    "{}",
                    serde_json::json!({
                        "root_pid": pid,
                        "n_processes": tree.len(),
                        "total_private_bytes": total_private,
                        "total_private_mib": (total_private as f64 / 1048576.0 * 10.0).round() / 10.0,
                        "total_working_set_bytes": total_ws,
                        "processes": tree,
                    })
                );
                0
            }
            None => {
                eprintln!("进程 {pid} 不存在");
                1
            }
        },
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

fn cmd_watch(args: &[String]) -> i32 {
    let Some(exe) = flag(args, "--exe") else {
        eprintln!("watch 需要 --exe <路径>");
        return 2;
    };
    let exe_args = collect_values(args, "--arg");
    let duration: f64 = flag(args, "--duration")
        .and_then(|v| v.parse().ok())
        .unwrap_or(45.0);
    let interval: f64 = flag(args, "--interval")
        .and_then(|v| v.parse().ok())
        .unwrap_or(1.0);
    let label = flag(args, "--label").unwrap_or_else(|| {
        std::path::Path::new(&exe)
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "app".into())
    });
    let out = flag(args, "--out");
    let md = flag(args, "--md");
    let root_name = flag(args, "--root-name");
    let kill = !has_flag(args, "--no-kill");

    match watch(
        &exe,
        &exe_args,
        duration,
        interval,
        root_name.as_deref(),
        &label,
        kill,
    ) {
        Ok(report) => {
            emit_report(&report, out.as_ref(), md.as_ref());
            // 摘要打到 stderr 供控制台速览
            eprintln!(
                "摘要 [{label}]: 峰值 {:.1} MiB / 稳态 {:.1} MiB / 结束 {:.1} MiB（{} 进程）",
                report.summary.peak_private as f64 / 1048576.0,
                report.summary.stable_private as f64 / 1048576.0,
                report.summary.final_private as f64 / 1048576.0,
                report.final_processes.len(),
            );
            0
        }
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}
