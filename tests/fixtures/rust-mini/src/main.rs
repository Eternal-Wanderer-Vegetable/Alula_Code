// 基准测试用的最小 Rust 工程：足够让编辑器/LSP 打开并索引，
// 又小到不会让语言服务器成为内存主因。

/// 计算第 n 个斐波那契数（朴素递归，供跳转/重命名测试）。
fn fib(n: u64) -> u64 {
    if n < 2 {
        return n;
    }
    fib(n - 1) + fib(n - 2)
}

/// 带前缀打印一行结果。
fn report(prefix: &str, value: u64) {
    println!("{prefix}: {value}");
}

fn main() {
    let n = std::env::args()
        .nth(1)
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(10);
    report("fib", fib(n));
}
