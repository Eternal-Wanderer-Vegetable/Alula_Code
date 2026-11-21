'use strict';
// Windows-only diagnostic validation; does not compile or execute the native Swift helper.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { pathToFileURL } = require('node:url');
const { createRequire } = require('node:module');
const { spawnSync } = require('node:child_process');

const repo = path.resolve(process.argv[2] || 'E:/temp/alula-pr3-20261117');
const prefix = path.resolve(process.argv[3] || 'E:/Temp/alula-p0582-validation');
const script = path.resolve(__filename);
for (const output of [script, prefix + '.json', prefix + '.log']) {
  const relative = path.relative(repo, output);
  if (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative)) {
    throw new Error('Script and output paths must be outside the repository');
  }
}
const packageRoot = 'C:/Users/Vegetable/AppData/Roaming/npm/node_modules/gitnexus';
const localRequire = createRequire(packageRoot + '/package.json');
const bash = 'C:/Program Files/Git/bin/bash.exe';
const lines = [];
const result = {
  timestamp: new Date().toISOString(), repo, script, outputPrefix: prefix,
  limitations: [
    'Swift tree-sitter validates syntax structure only; no Swift compilation or native execution.',
    'Workflow fixtures mock helper/process APIs; they do not test AppKit identity, AX, System Events, actual OS PID lifecycle or macOS Bash 3.2.',
    'No native runtime evidence or product acceptance is established by these checks.'
  ],
  files: {}, checks: [], fixtures: [],
};
function log(text) { lines.push(text); process.stdout.write(text + '\n'); }
function check(name, action) {
  try { const details = action(); result.checks.push({ name, passed: true, details }); log('PASS ' + name); return details; }
  catch (error) { result.checks.push({ name, passed: false, error: String(error.stack || error) }); log('FAIL ' + name + ': ' + error.message); return undefined; }
}
function runShell(input, timeout = 10000) {
  return spawnSync(bash, ['--noprofile', '--norc', '-s'], { input, encoding: 'utf8', timeout, maxBuffer: 8 * 1024 * 1024 });
}
(async () => {
  try {
    const workflowPath = path.join(repo, '.github/workflows/platform-availability.yml');
    const swiftPath = path.join(repo, 'tools/vscode-parity/macos-native-dnd-input.swift');
    for (const file of [workflowPath, swiftPath]) {
      result.files[file] = { sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') };
    }
    const workflow = check('workflow-yaml', () => localRequire('js-yaml').load(fs.readFileSync(workflowPath, 'utf8')));
    if (workflow) {
      check('all-bash-run-blocks-syntax', () => {
        const blocks = [];
        for (const [job, data] of Object.entries(workflow.jobs)) for (const step of data.steps) {
          if (typeof step.run !== 'string' || ['powershell', 'pwsh'].includes(step.shell) || (job === 'windows' && !step.shell)) continue;
          const parsed = spawnSync(bash, ['--noprofile', '--norc', '-n'], { input: step.run, encoding: 'utf8' });
          blocks.push({ job, name: step.name || step.id || '<unnamed>', status: parsed.status, stderr: parsed.stderr });
          if (parsed.status !== 0) throw new Error(JSON.stringify(blocks[blocks.length - 1]));
        }
        return { count: blocks.length, blocks };
      });
      const body = workflow.jobs.macos.steps.find(step => step.name === 'Launch macOS native-titlebar mode and verify native Quit menu').run;
      const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'alula-quit-fixture-'));
      const temp = directory.split(path.sep).join('/');
      const cases = [
        ['both-gone-wrapper-zero', 0], ['bind-zero', 1], ['bind-multiple', 1],
        ['invalid-pid', 1], ['identity-unknown', 1], ['app-alive-wrapper-gone', 1],
        ['app-gone-wrapper-alive', 1], ['both-alive', 1], ['wrapper-nonzero', 7],
        ['wrapper-exit-before-quit', 1],
      ];
      try {
        for (const [fixture, expected] of cases) {
          const prelude = `set -e
export RUNNER_TEMP='${temp}'
fixture='${fixture}'
function /usr/libexec/PlistBuddy() { printf '%s' dev.alula.test; }
function ${temp}/alula-native-dnd-input() {
 case "$1" in
 --snapshot-native-apps) return 0;;
 --bind-native-app)
   case "$fixture" in bind-zero|bind-multiple) return 1;; invalid-pid) printf '%s' unknown;; *) printf '%s' 424242;; esac;;
 --quit-native-menu) [[ "$4" == "$RUNNER_TEMP/alula-macos-native-target.json" ]] || return 9;;
 --observe-native-app)
   if [[ "$3" == --windows ]]; then return 0; fi
   case "$fixture" in identity-unknown|app-alive-wrapper-gone|app-gone-wrapper-alive|both-alive) return 1;; *) return 0;; esac;;
 --validate-native-app) return 1;;
 *) return 9;; esac
}
function open() { return 0; }
function sleep() { return 0; }
function kill() {
 if [[ "$1" == -0 ]]; then
   if [[ "$fixture" == wrapper-exit-before-quit ]]; then return 1; fi
   if [[ "\${observer_status:-}" != '' && "$2" == "$open_pid" ]]; then
     case "$fixture" in identity-unknown|app-alive-wrapper-gone) return 1;; esac
   fi
 fi
 return 0
}
function wait() {
 if [[ "$fixture" == wrapper-nonzero && "$1" == "$open_pid" ]]; then return 7; fi
 builtin wait "$@"
}
function ps() { return 0; }
`;
          const execution = runShell(prelude + body);
          const entry = { name: fixture, expectedStatus: expected, actualStatus: execution.status,
            signal: execution.signal, stdout: execution.stdout, stderr: execution.stderr,
            error: execution.error ? String(execution.error) : null,
            passed: execution.status === expected && !execution.error };
          result.fixtures.push(entry);
          log((entry.passed ? 'PASS ' : 'FAIL ') + fixture + ': expected=' + expected + ' actual=' + execution.status);
        }
      } finally { fs.rmSync(directory, { recursive: true, force: true }); }
    }
    const grammarModule = await import(pathToFileURL(packageRoot + '/dist/core/tree-sitter/vendored-grammars.js').href);
    check('swift-tree-sitter-structure', () => {
      const Parser = localRequire('tree-sitter');
      const parser = new Parser();
      parser.setLanguage(grammarModule.requireVendoredGrammar('tree-sitter-swift'));
      const tree = parser.parse(fs.readFileSync(swiftPath, 'utf8'), undefined, { bufferSize: 1024 * 1024 });
      const errors = [];
      function walk(node) {
        if (node.type === 'ERROR' || node.isMissing) errors.push({ type: node.type, at: node.startPosition, text: node.text.slice(0, 150) });
        for (const child of node.namedChildren) walk(child);
      }
      walk(tree.rootNode);
      if (errors.length) throw new Error(JSON.stringify(errors));
      return { errors: 0, nativeCompilation: 'not run' };
    });
    check('scoped-git-diff-check', () => {
      const execution = spawnSync('git', ['-C', repo, 'diff', '--check', '--', 'tools/vscode-parity/macos-native-dnd-input.swift', '.github/workflows/platform-availability.yml'], { encoding: 'utf8' });
      if (execution.status !== 0) throw new Error(execution.stdout + execution.stderr);
      return { status: execution.status, stdout: execution.stdout, stderr: execution.stderr };
    });
  } catch (error) {
    result.fatalError = String(error.stack || error);
    log('FATAL ' + error.message);
  } finally {
    result.passed = !result.fatalError && result.checks.every(item => item.passed) && result.fixtures.length === 10 && result.fixtures.every(item => item.passed);
    // The full parsed workflow is not needed in evidence: retain only validation metadata.
    const yamlCheck = result.checks.find(item => item.name === 'workflow-yaml');
    if (yamlCheck && yamlCheck.passed) yamlCheck.details = { parsed: true };
    log('RESULT ' + (result.passed ? 'PASS' : 'FAIL') + '; native compile/execution not run');
    fs.mkdirSync(path.dirname(prefix), { recursive: true });
    fs.writeFileSync(prefix + '.json', JSON.stringify(result, null, 2) + '\n');
    fs.writeFileSync(prefix + '.log', lines.join('\n') + '\n\n' + JSON.stringify({ checks: result.checks, fixtures: result.fixtures, limitations: result.limitations }, null, 2) + '\n');
    process.stdout.write('JSON: ' + prefix + '.json\nLOG: ' + prefix + '.log\n');
    process.exitCode = result.passed ? 0 : 1;
  }
})();
