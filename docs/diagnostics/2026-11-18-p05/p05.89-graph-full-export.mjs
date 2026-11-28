import { LocalBackend, buildDetectChangesDiffArgs } from 'file:///C:/Users/Vegetable/AppData/Roaming/npm/node_modules/gitnexus/dist/mcp/local/local-backend.js';
import { readFileSync, writeFileSync, writeSync, readdirSync, statSync, openSync, closeSync, readSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { Session } from 'node:inspector';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Observe the installed, unmodified handler's actual pre-listing state with the
// debugger. No evaluation assigns to handler locals or changes its return value.
const [repoArg = 'E:/Temp/alula-pr3-20261117', prefixArg = 'E:/Temp/alula-p0589-graph-full', baseRef = 'main'] = process.argv.slice(2);
const repo = path.resolve(repoArg);
const prefix = path.resolve(prefixArg);
if (prefix.toLowerCase() === repo.toLowerCase() || prefix.toLowerCase().startsWith(repo.toLowerCase() + path.sep)) throw new Error('Outputs must be outside repository');
process.env.GIT_OPTIONAL_LOCKS = '0';
const backendFile = fileURLToPath('file:///C:/Users/Vegetable/AppData/Roaming/npm/node_modules/gitnexus/dist/mcp/local/local-backend.js');
const source = readFileSync(backendFile, 'utf8');
const sliceStatement = 'const listedSymbols = Array.from(changedSymbols.values()).slice(0, DETECT_CHANGES_MAX_LISTED_SYMBOLS);';
if (source.split(sliceStatement).length !== 2) throw new Error('Expected unique installed handler cap statement');
const breakpointLine = source.slice(0, source.indexOf(sliceStatement)).split('\n').length - 1;
const hash = value => createHash('sha256').update(value).digest('hex');
function fileHash(file) {
  const fd = openSync(file, 'r');
  const digest = createHash('sha256');
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try { let count; while ((count = readSync(fd, buffer, 0, buffer.length, null)) > 0) digest.update(buffer.subarray(0, count)); }
  finally { closeSync(fd); }
  return digest.digest('hex');
}
const git = (...args) => execFileSync('git', ['--no-optional-locks', '-C', repo, ...args], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
const gitDir = git('rev-parse', '--absolute-git-dir').trim();
function snapshot() {
  const status = git('status', '--porcelain=v1', '-z', '--untracked-files=all');
  const untracked = git('ls-files', '--others', '--exclude-standard', '-z').split('\0').filter(Boolean);
  const graphDir = path.join(repo, '.gitnexus');
  const graphFiles = readdirSync(graphDir).sort().filter(name => statSync(path.join(graphDir, name)).isFile()).map(name => ({ name, bytes: statSync(path.join(graphDir, name)).size, sha256: fileHash(path.join(graphDir, name)) }));
  return {
    head: git('rev-parse', 'HEAD').trim(), base: git('rev-parse', baseRef).trim(),
    gitIndexSha256: fileHash(path.join(gitDir, 'index')),
    graphMetaSha256: fileHash(path.join(graphDir, 'meta.json')),
    graphFiles,
    trackedDiffSha256: hash(git('diff', 'HEAD', '--binary', '--no-ext-diff', '--color=never')),
    compareDiffSha256: hash(git(...buildDetectChangesDiffArgs('compare', baseRef))),
    allDiffSha256: hash(git(...buildDetectChangesDiffArgs('all'))),
    statusSha256: hash(status),
    untracked: untracked.map(file => ({ file, sha256: fileHash(path.join(repo, file)) })),
  };
}
const before = snapshot();
const meta = JSON.parse(readFileSync(path.join(repo, '.gitnexus/meta.json'), 'utf8'));
const packageVersion = JSON.parse(readFileSync(path.resolve(path.dirname(backendFile), '../../../package.json'), 'utf8')).version;
const sourceBefore = fileHash(backendFile);
const logFile = `${prefix}-export.log`;
const log = entry => { const text = JSON.stringify(entry) + '\n'; writeSync(1, text); writeFileSync(logFile, text, { flag: 'a' }); };
writeFileSync(logFile, '');
log({ repo, before, indexedAt: meta.indexedAt, lastCommit: meta.lastCommit, stats: meta.stats, indexCoverage: meta.indexCoverage });
const inspector = new Session();
inspector.connect();
const post = (method, params = {}) => new Promise((resolve, reject) => inspector.post(method, params, (error, result) => error ? reject(error) : resolve(result)));
let currentLabel;
let capture;
let captureError;
inspector.on('Debugger.paused', ({ params }) => {
  const frame = params.callFrames.find(frame => frame.functionName === 'detectChanges');
  if (!frame) { inspector.post('Debugger.resume'); return; }
  const expression = `JSON.stringify({ changed_symbols: Array.from(changedSymbols.values()), affected_processes: Array.from(affectedProcesses.values()), queryDegraded, processCount, risk, changedFiles: new Set(fileDiffs.map(f => f.filePath)).size, cap: DETECT_CHANGES_MAX_LISTED_SYMBOLS, scope, base_ref: params.base_ref ?? null })`;
  inspector.post('Debugger.evaluateOnCallFrame', { callFrameId: frame.callFrameId, expression, returnByValue: true, silent: true, throwOnSideEffect: true }, (error, result) => {
    try {
      if (error) throw error;
      if (result.exceptionDetails || typeof result.result?.value !== 'string') throw new Error(JSON.stringify(result));
      if (capture) throw new Error('Unexpected duplicate handler capture');
      capture = JSON.parse(result.result.value);
    } catch (error) { captureError = error; }
    inspector.post('Debugger.resume');
  });
});
const backend = new LocalBackend();
let failed = false;
const evidence = [];
try {
  await post('Debugger.enable');
  const breakpoint = await post('Debugger.setBreakpointByUrl', { url: new URL('file:///C:/Users/Vegetable/AppData/Roaming/npm/node_modules/gitnexus/dist/mcp/local/local-backend.js').href, lineNumber: breakpointLine });
  if (!breakpoint.locations?.length) throw new Error('Breakpoint did not bind to installed handler');
  log({ packageVersion, backendFile, backendSha256: sourceBefore, breakpointLine: breakpointLine + 1, breakpointLocations: breakpoint.locations, method: 'Read-only debugger capture of original handler maps before fixed listing cap; original response retained unchanged' });
  if (!await backend.init()) throw new Error('No indexed repository available');
  for (const [label, args] of [['all', { scope: 'all' }], ['main', { scope: 'compare', base_ref: baseRef }]]) {
    currentLabel = label; capture = undefined; captureError = undefined;
    const originalResponse = await backend.callTool('detect_changes', { ...args, repo, worktree: repo });
    if (captureError) throw captureError;
    if (!capture) throw new Error(`No internal-state capture for ${currentLabel}: ${JSON.stringify(originalResponse)}`);
    const originalFile = `${prefix}-${label}-original-response.json`;
    writeFileSync(originalFile, JSON.stringify(originalResponse, null, 2) + '\n');
    const countsMatch = capture.changed_symbols.length === originalResponse.summary?.changed_count && capture.affected_processes.length === originalResponse.summary?.affected_count;
    const originalPrefixMatches = JSON.stringify(originalResponse.changed_symbols) === JSON.stringify(capture.changed_symbols.slice(0, capture.cap));
    const affectedProcessesMatch = JSON.stringify(originalResponse.affected_processes) === JSON.stringify(capture.affected_processes);
    const changedFilesMatch = capture.changedFiles === originalResponse.summary?.changed_files;
    const riskMatches = capture.risk === originalResponse.summary?.risk_level;
    const uniqueIds = new Set(capture.changed_symbols.map(symbol => symbol.id)).size === capture.changed_symbols.length && new Set(capture.affected_processes.map(process => process.id)).size === capture.affected_processes.length;
    if (!countsMatch || !originalPrefixMatches || !affectedProcessesMatch || !changedFilesMatch || !riskMatches || !uniqueIds || capture.queryDegraded || originalResponse.error || originalResponse.partial === true) throw new Error(`Handler completeness verification failed for ${label}`);
    const file = `${prefix}-${label}.json`;
    const result = {
      provenance: { method: 'original-handler-pre-listing-debugger-capture', installedVersion: packageVersion, backendFile, backendSha256: sourceBefore, breakpointLine: breakpointLine + 1, snapshotBefore: before, args: { ...args, repo, worktree: repo }, diffArgs: buildDetectChangesDiffArgs(args.scope, args.base_ref), originalResponseFile: originalFile, originalResponseSha256: fileHash(originalFile), originalResponseTruncated: originalResponse.truncated ?? false, cap: capture.cap, note: 'The native API response remains unchanged in originalResponseFile. This full export uses the actual complete pre-cap maps from that same invocation. Its truncated:false describes these exported full arrays; it does not claim the native response was untruncated.' },
      summary: originalResponse.summary,
      changed_symbols: capture.changed_symbols,
      affected_processes: capture.affected_processes,
      partial: capture.queryDegraded,
      truncated: false,
      completeness: { countsMatch, originalPrefixMatches, affectedProcessesMatch, changedFilesMatch, riskMatches, uniqueIds, queryDegraded: capture.queryDegraded, observedSymbolCount: capture.changed_symbols.length, observedProcessCount: capture.processCount },
      arrayDigests: { changedSymbolsSha256: hash(JSON.stringify(capture.changed_symbols)), affectedProcessesSha256: hash(JSON.stringify(capture.affected_processes)), changedSymbolIdsSortedSha256: hash(JSON.stringify(capture.changed_symbols.map(s => s.id).sort())), affectedProcessIdsSortedSha256: hash(JSON.stringify(capture.affected_processes.map(p => p.id).sort())) },
    };
    writeFileSync(file, JSON.stringify(result, null, 2) + '\n');
    const saved = JSON.parse(readFileSync(file, 'utf8'));
    if (saved.changed_symbols.length !== saved.summary.changed_count || saved.affected_processes.length !== saved.summary.affected_count) throw new Error('Serialized export count mismatch');
    const entry = { label, file, bytes: statSync(file).size, sha256: fileHash(file), summary: saved.summary, partial: saved.partial, truncated: saved.truncated, symbols: saved.changed_symbols.length, processes: saved.affected_processes.length, completeness: saved.completeness, arrayDigests: saved.arrayDigests, originalFile, originalSha256: fileHash(originalFile), originalTruncated: originalResponse.truncated ?? false };
    evidence.push(entry); log(entry);
  }
} catch (error) {
  failed = true; log({ error: error.stack ?? String(error), currentLabel });
} finally {
  await backend.dispose();
  await post('Debugger.disable');
  inspector.disconnect();
  const after = snapshot();
  const repositorySnapshotUnchanged = JSON.stringify(before) === JSON.stringify(after);
  const installedBackendUnchanged = sourceBefore === fileHash(backendFile);
  const receipt = { repo, baseRef, packageVersion, before, after, repositorySnapshotUnchanged, installedBackendUnchanged, evidence, success: !failed && repositorySnapshotUnchanged && installedBackendUnchanged && evidence.length === 2 };
  writeFileSync(`${prefix}-receipt.json`, JSON.stringify(receipt, null, 2) + '\n');
  log({ repositorySnapshotUnchanged, installedBackendUnchanged, after, receiptFile: `${prefix}-receipt.json`, success: receipt.success });
  if (!receipt.success) failed = true;
}
process.exitCode = failed ? 1 : 0;
