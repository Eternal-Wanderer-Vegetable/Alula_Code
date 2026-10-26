// watch 模式端到端测试：用 mem-probe 自己的 sleepy 子命令充当替身应用。
use mem_probe::watch;

#[test]
fn watch_tracks_and_kills_child() {
    let bin = env!("CARGO_BIN_EXE_mem-probe");
    let r = watch(
        bin,
        &["sleepy".to_string(), "--ms".to_string(), "5000".to_string()],
        1.5,
        0.25,
        None,
        "sleepy-test",
        true,
    )
    .expect("watch 应成功");
    assert!(r.samples.len() >= 3, "1.5s/0.25s 应采到至少 3 个样本");
    assert!(r.summary.peak_private > 0, "私有内存应大于 0");
    // 进程是长眠型的：采样期内存活
    assert!(r.samples.iter().all(|s| s.n_processes >= 1));
}
