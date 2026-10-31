# P03.7 Windows 11 Release artifact validation

Date: 2026-10-31. Validation ran on Windows 11 Pro for Workstations build `10.0.26200`, x64. WMI reported `Win32_Processor.Architecture=9`, CPU `AMD Ryzen 7 9700X`, and `PROCESSOR_ARCHITECTURE=AMD64`. The display was `2048×1152`; Alula's tested client area was `1267×712` at 120 DPI (125% scaling). Windows system/app theme settings were dark, and the workbench rendered its dark palette. This is one DPI/theme configuration, not a matrix.

Two packages were tested on the same host. The historical package is the exact Windows artifact requested from run [41109679662](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41109679662), source `d5319369c5b5d569954e0d816daf325f3bc12a51`. The current branch package is from run [41177214462](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41177214462), source `d3a7a56e8ebe48ae47c384618f3955b0516e3f57`. Artifact and executable hashes are recorded in [`artifact-provenance.json`](evidence/artifact-provenance.json).

## Current branch package: tested interactions pass

The `d3a7a56` Release artifact created a visible, nonuniform client window and passed the automated desktop interaction flow:

- The editor exposed 44 MSAA nodes, including all required strings: `打开文件夹`, `UTF-8. UTF-8`, `LF. 行尾格式`, and the saved editor text.
- The supplied Rust sample `fn main() { println!("linux-save-ok"); }` was saved and read back byte-for-byte.
- Microsoft Pinyin showed the `ni'hao` composition with the `你好` candidate. Space committed `你好`; Escape canceled a subsequent `zhong'guo` composition without removing the committed text. The committed text was saved and read back.
- Both editor views showed the same Rust document. Editing the second view appended `// view-2`; both views then showed the same result and the file read back with that edit.
- `WM_CLOSE` exited within the timeout with code `0`. A second launch used as a no-accessibility close control also exited with code `0`.

The final client screenshot and raw run record are [`client.png`](evidence/current-d3a7/client.png) and [`raw-validator-metadata.json`](evidence/current-d3a7/raw-validator-metadata.json). IME composition, committed text, and cancellation screenshots are in the same directory. The final interaction capture places the editor in the right-hand pane and leaves a large unused area on the left. MSAA and saved values confirm the two editor views, but this image does not pass visual layout/usability review; determine whether this is a workbench layout issue or a capture/window-state artifact before closing the Windows usability gate. The separate initial Narrator probe image shows the welcome editor occupying the client area.

Two raw metadata fields are incorrect because the reused validator hardcodes them: `artifactSourceCommit` reports `d531...` for both packages, and `artifactArchitecture` reports Windows 11 ARM emulation for interaction runs. WMI confirms the test host is x64 as recorded above. Run SHA, artifact ID/name, ZIP digest, and tested executable hash identify `d3a7a56` in [`artifact-provenance.json`](evidence/artifact-provenance.json).

## Exact historical package: close failure reproduced

The exact `d5319369` artifact passed the same visible rendering, sample save/read-back, Pinyin composition/commit/cancel, and dual-view synchronization/edit/save checks. Its process did **not** close cleanly: `WM_CLOSE` ended with `0xC000041D` (`-1073740771`) without timing out. A second launch with no UI Automation or MSAA queries produced the same exit code. Windows Application Error events report `flutter_windows.dll`, exception `0xC0000005`, offset `0x000000000001e220`; see [`close-crash-diagnostics.json`](evidence/historical-d531/close-crash-diagnostics.json) and [`no-accessibility-close-control.json`](evidence/historical-d531/no-accessibility-close-control.json).

This is a result for the older binary. The later `d3a7a56` package closed cleanly on the same host and must not be conflated with it.

## Narrator and remaining validation

Windows Narrator was launched for the current package. A UI Automation query returned only `Alula Code` and `FLUTTERVIEW` (two descendants, zero `LegacyIAccessible` patterns); 14 Tab probes resolved to the same `Alula Code` window node, and the expected control/editor names were absent from that UIA tree. The separate MSAA query did expose the 44-node semantic tree, but speech audio was not captured. Narrator output and useful focus traversal are therefore **not verified**. Raw probe: [`result.json`](evidence/narrator-current/result.json), [`transcript.txt`](evidence/narrator-current/transcript.txt), and [`window.png`](evidence/narrator-current/window.png).

The 125% dark-theme run confirms rendering at that one setting. Light/dark switching and 150% scaling remain untested. Native DRM Linux and native macOS remain unavailable. Therefore the project-level platform status stays pending; these results do not authorize a macOS package for users or complete P15 sign-off.

The test used a temporary Windows `USERPROFILE`, the validation script backed up and restored `tests/fixtures/rust-mini/src/main.rs`, and its SHA-256 returned to `6689b6c06534079c1a006631f54d180f642d169f7a15455c50a2a7eeb2b02684`. The temporary app and Narrator processes were stopped and the prior foreground window restored. Reproduction scripts and the validator variant are under [`scripts/`](scripts/).
