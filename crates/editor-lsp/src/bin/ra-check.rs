//! 对真实 rust-analyzer 的无头验证：
//! 在 rust-mini fixture 上跑 didOpen → 轮询诊断 → 补全请求，打印结果。
//! 用法：cargo run -p editor-lsp --bin ra-check

use std::time::{Duration, Instant};

fn main() {
    let workspace = r"E:\Alula_Code\tests\fixtures\rust-mini";
    let main_rs = format!("{workspace}\\src\\main.rs");
    let text = std::fs::read_to_string(&main_rs).expect("读取 main.rs");

    println!("[1] 启动 rust-analyzer …");
    let started = Instant::now();
    let server =
        editor_lsp::LspServer::spawn(workspace, &["rust-analyzer".to_string()]).expect("spawn");
    println!("    握手完成，耗时 {:.1}s", started.elapsed().as_secs_f64());

    let uri = editor_lsp::path_to_uri(&main_rs);
    // 内存内容带一个语法错误（磁盘文件保持正确）——语法错误会即时推送
    let opened = text.replace("fn fib(", "fn fib(^^");
    println!("[2] didOpen {uri}（内存版含类型错误）");
    std::thread::sleep(Duration::from_secs(3));
    server.did_open(&uri, "rust", 1, &opened).expect("didOpen");
    std::thread::sleep(Duration::from_secs(2));

    // didSave 触发 flycheck（cargo check → 推送诊断）
    server.did_save(&uri).expect("didSave");
    // pull diagnostics（LSP 3.17）
    let pull = server.request(
        "textDocument/diagnostic",
        serde_json::json!({
            "textDocument": {"uri": uri},
            "identifier": "rust-analyzer",
            "previousResultId": null,
        }),
        30000,
    );
    match &pull {
        Ok(v) => {
            let items = v
                .get("items")
                .and_then(|i| i.as_array())
                .map(|a| a.len())
                .unwrap_or(0);
            println!(
                "[2.5] pull diagnostics: kind={:?} items={}",
                v.get("kind").and_then(|k| k.as_str()),
                items
            );
        }
        Err(e) => println!("[2.5] pull diagnostics 失败: {e}"),
    }
    if let Ok(v) = &pull {
        println!(
            "[2.6] pull 原始响应: {}",
            serde_json::to_string_pretty(v)
                .unwrap_or_default()
                .chars()
                .take(600)
                .collect::<String>()
        );
    }
    // didChange 触发重分析（VS Code 即时红线走的路径）
    server.did_change_full(&uri, 2, &opened).expect("didChange");

    println!("[3] 轮询诊断（最长 45s）…");
    let deadline = Instant::now() + Duration::from_secs(45);
    let mut last_count = -1i64;
    loop {
        let diags = server.diagnostics(&uri);
        if diags.len() as i64 != last_count {
            last_count = diags.len() as i64;
            println!(
                "    诊断 {} 条 @ {:.1}s",
                diags.len(),
                started.elapsed().as_secs_f64()
            );
            for d in &diags {
                println!(
                    "      [sev{}] L{} C{}: {}",
                    d.severity,
                    d.line,
                    d.character,
                    d.message.lines().next().unwrap_or("")
                );
            }
        }
        if !diags.is_empty() && Instant::now() > deadline {
            break;
        }
        // 等 RA 首批诊断 + 稳定 5s
        if !diags.is_empty() {
            std::thread::sleep(Duration::from_secs(5));
            if server.diagnostics(&uri).len() == diags.len() {
                break;
            }
        } else if Instant::now() > deadline {
            println!("    超时未收到诊断");
            break;
        }
        std::thread::sleep(Duration::from_millis(500));
    }

    println!("[4] 补全请求（在 main 内 offset=30，超时 8s）…");
    let items = server.completion(&uri, 5, 20, 8000).unwrap_or_else(|e| {
        println!("    补全失败: {e}");
        Vec::new()
    });
    println!(
        "    补全 {} 项，前 8 项: {:?}",
        items.len(),
        &items[..items.len().min(8)]
    );

    println!("[5] shutdown");
    server.shutdown().unwrap();
    println!("完成");
}
