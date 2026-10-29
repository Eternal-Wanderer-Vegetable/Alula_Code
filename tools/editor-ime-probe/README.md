# P00.4 Editor / IME Probe

Standalone Windows Flutter app for the first P00.4 risk experiment. It uses the
cached code_forge 11.3.0 package and does not depend on the Alula workbench.

From Windows Git Bash:

1. cd /e/alula_code/tools/editor-ime-probe
2. /e/_alula_tools/flutter-win-wrapper.sh pub get --offline
3. /e/_alula_tools/flutter-win-wrapper.sh analyze
4. /e/_alula_tools/flutter-win-wrapper.sh test
5. /e/_alula_tools/flutter-win-wrapper.sh run -d windows

For a real Microsoft Pinyin replay, keep the Windows app open and run this
from a second Windows Git Bash:

1. powershell.exe -NoProfile -ExecutionPolicy Bypass -File
   /e/Alula_Code/tools/editor-ime-probe/scripts/run-ime-smoke.ps1
   -OutputDirectory /e/Alula_Code/docs/diagnostics/2026-10-27-p00

The script captures the active composition, first-candidate commit, Escape
cancellation and Latin typing states as PNG files. It temporarily raises the
probe window, then restores its normal z-order.

The page starts with 10,000 lines. Use it to inspect:

1. Ordinary keyboard input and frame timing in the visible editor.
2. Microsoft Pinyin composition (nihao), candidate selection, commit and
   cancellation. The IME state panel reports the composing overlay separately
   from committed document text.
3. The Seed 3 cursors button, typing, and Ctrl+Z behavior.
4. Scroll middle to verify navigation within the long document.
5. Capture metrics to print a JSON record prefixed with P00.4_EDITOR in the
   Flutter run log.

Automated tests drive a composing TextEditingValue through Flutter's test
text-input channel and exercise the 10k-line viewport and cursor API. This
complements, but does not replace, the real Windows IME run.
