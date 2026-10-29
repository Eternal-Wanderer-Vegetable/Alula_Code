#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const DEFAULT_DIAGNOSTICS = 'docs/diagnostics/2026-10-27-p00';
const EXPECTED_SOURCE = '4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e';
const FIELD_NAMES = new Set([
	'id', 'command', 'commandId', 'title', 'category', 'when', 'precondition', 'menu', 'menus',
	'primary', 'secondary', 'mac', 'linux', 'win', 'key', 'weight', 'group', 'order', 'alt',
	'language', 'languageId', 'scopeName', 'viewId', 'viewContainerId', 'name', 'type', 'filename',
	'extension', 'default', 'defaultValue', 'description', 'scope', 'enum', 'deprecated', 'tags',
	'editor', 'notebookType', 'viewType', 'debuggerType', 'provider', 'location'
]);

function argumentsFrom(argv) {
	const values = new Map();
	for (const arg of argv) {
		if (!arg.startsWith('--')) {
			continue;
		}
		const separator = arg.indexOf('=');
		if (separator < 0) {
			values.set(arg.slice(2), 'true');
		} else {
			values.set(arg.slice(2, separator), arg.slice(separator + 1));
		}
	}
	return values;
}

const args = argumentsFrom(process.argv.slice(2));
if (args.has('help')) {
	console.log('Usage: node tools/vscode-parity/export-atomic-contributions.mjs --source=<pinned-vscode-checkout> [--runtime=<runtime-registry.json>]');
	process.exit(0);
}

const repoRoot = process.cwd();
const resolveArg = (name, fallback) => path.resolve(args.get(name) ?? fallback);
const sourceRoot = path.resolve(args.get('source') ?? process.env.VSCODE_SOURCE_ROOT ?? '');
if (!args.has('source') && !process.env.VSCODE_SOURCE_ROOT) {
	throw new Error('Pass --source=<pinned-vscode-checkout> or set VSCODE_SOURCE_ROOT.');
}

const coveragePath = resolveArg('coverage', 'docs/plans/vscode-source-coverage.json');
const matrixPath = resolveArg('matrix', 'docs/plans/vscode-parity-matrix.json');
const builtinIndexPath = resolveArg('manifests', 'docs/plans/vscode-builtin-manifests.json');
const runtimePath = resolveArg('runtime', path.join(DEFAULT_DIAGNOSTICS, 'runtime-registry.json'));
const outputPath = resolveArg('output', path.join(DEFAULT_DIAGNOSTICS, 'atomic-contributions.json'));
const summaryPath = resolveArg('summary', path.join(DEFAULT_DIAGNOSTICS, 'atomic-contributions-summary.json'));
const configKeysPath = resolveArg('configuration-keys-output', path.join(DEFAULT_DIAGNOSTICS, 'runtime-configuration-candidates.json'));

const readJson = async file => JSON.parse(await fs.readFile(file, 'utf8'));
const sha256 = contents => createHash('sha256').update(contents).digest('hex');
const sha1Blob = contents => createHash('sha1').update(`blob ${contents.length}\0`).update(contents).digest('hex');
const sourceCoverage = await readJson(coveragePath);
const matrix = await readJson(matrixPath);
const builtinIndex = await readJson(builtinIndexPath);
const runtime = await readJson(runtimePath);
const packageJson = await readJson(path.join(sourceRoot, 'package.json'));
const product = await readJson(path.join(sourceRoot, 'product.json'));

const execGit = (...gitArgs) => execFileSync('git', ['-C', sourceRoot, ...gitArgs], { encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 }).trim();
const sourceCommit = execGit('rev-parse', 'HEAD');
const sourceTree = execGit('rev-parse', 'HEAD^{tree}');
if (sourceCommit !== EXPECTED_SOURCE || sourceCoverage.reference?.vscode !== EXPECTED_SOURCE || matrix.reference?.vscode !== EXPECTED_SOURCE) {
	throw new Error(`Pinned source mismatch: expected ${EXPECTED_SOURCE}, got source=${sourceCommit}, coverage=${sourceCoverage.reference?.vscode}, matrix=${matrix.reference?.vscode}`);
}

const requireFromHere = createRequire(import.meta.url);
const ts = requireFromHere(path.join(sourceRoot, 'node_modules', 'typescript', 'lib', 'typescript.js'));
const normalized = value => value.split(path.sep).join('/');
const sourceCoverageEntries = sourceCoverage.entries.filter(entry => entry.repository === 'vscode' && entry.entry_type === 'dir');
const unresolvedDiscoverySet = new Set(sourceCoverage.unresolved_discovery_ids ?? []);
const groupsByPrefix = new Map(matrix.groups.map(group => [group.prefix, group]));
const externalBuiltinsById = new Map((builtinIndex.externalBuiltInExtensions ?? []).map(item => [item.name, item]));
const runtimeCommands = new Set(runtime.commands ?? []);
const runtimeLanguages = new Set(runtime.languages ?? []);
const runtimeConfigurations = new Set(runtime.configurationKeys ?? []);
const runtimeExtensionById = new Map((runtime.extensions ?? []).map(extension => [extension.id.toLowerCase(), extension]));
const probeExtensionId = runtime.instrumentation?.extensionId?.toLowerCase() ?? '';
const staticItems = [];
const configurationKeys = new Set();
const registrationIdentityCounts = new Map();
const astCounters = { trackedSourceFiles: 0, parsedSourceFiles: 0, registrationCalls: 0, unresolvedCalls: 0 };

function nearestCoverage(relativePath) {
	let result;
	for (const entry of sourceCoverageEntries) {
		const candidate = normalized(entry.path);
		if ((relativePath === candidate || relativePath.startsWith(`${candidate}/`)) && (!result || candidate.length > normalized(result.path).length)) {
			result = entry;
		}
	}
	return result;
}

function candidateFeatures(coverageEntry) {
	const prefixes = [...new Set(coverageEntry?.requirement_prefixes ?? [])].sort();
	const rows = prefixes.flatMap(prefix => groupsByPrefix.get(prefix)?.rows ?? []);
	return {
		candidateRequirementPrefixes: prefixes,
		candidateFeatureIds: [...new Set(rows.map(row => row.id))].sort(),
		candidateCaseIds: [...new Set(rows.map(row => row.case_id).filter(Boolean))].sort(),
		status: prefixes.length ? 'candidate-family-route' : 'unmapped'
	};
}

function runtimeReachability(kind, id) {
	if (!runtime || !id) {
		return { status: 'unknown', evidence: null };
	}
	if (kind === 'command') {
		return { status: runtimeCommands.has(id) ? 'observed' : 'not-observed', evidence: 'runtime.commands' };
	}
	if (kind === 'language') {
		return { status: runtimeLanguages.has(id) ? 'observed' : 'not-observed', evidence: 'runtime.languages' };
	}
	if (kind === 'configuration') {
		return { status: runtimeConfigurations.has(id) ? 'observed' : (runtime.configurationCandidates ? 'not-observed' : 'not-probed'), evidence: runtime.configurationCandidates ? 'runtime.configurationKeys' : null };
	}
	if (kind === 'extension') {
		const extension = runtimeExtensionById.get(id.toLowerCase());
		return { status: extension ? 'discoverable' : 'not-observed', evidence: extension ? 'runtime.extensions' : null, isActive: extension?.isActive ?? null };
	}
	return { status: 'static-only', evidence: null };
}

function sourceInfo(relativePath, line, coverageEntry, blobSha, sourceKind) {
	const features = candidateFeatures(coverageEntry);
	return {
		repository: 'microsoft/vscode',
		commit: sourceCommit,
		path: relativePath,
		line: line ?? null,
		url: `https://github.com/microsoft/vscode/blob/${sourceCommit}/${relativePath}${line ? `#L${line}` : ''}`,
		blobSha: blobSha ?? null,
		discoveryIds: coverageEntry ? [coverageEntry.discovery_id] : [],
		candidateScopeClasses: [...new Set(coverageEntry?.scope_classes ?? [])].sort(),
		scopeDecision: coverageEntry?.scope_decision ?? null,
		scopeReason: coverageEntry?.reason ?? null,
		...features,
		kind: sourceKind
	};
}

function makeItem({ kind, id, source, rawFields = {}, registration = null, owner = null, fixedScope = null }) {
	const identityBase = `${kind}:${id ?? 'unknown'}:${sha256(JSON.stringify({ path: source.path, line: source.line ?? 0, registration, rawFields })).slice(0, 16)}`;
	const occurrence = (registrationIdentityCounts.get(identityBase) ?? 0) + 1;
	registrationIdentityCounts.set(identityBase, occurrence);
	const identity = occurrence === 1 ? identityBase : `${identityBase}:${occurrence}`;
	return {
		upstream_id: id ? `${kind}:${id}` : null,
		registration_id: identity,
		kind,
		id: id ?? null,
		owner,
		source,
		raw_fields: rawFields,
		registration,
		scope: {
			candidate_classes: fixedScope ?? source.candidateScopeClasses,
			adjudicated_class: null,
			decision_status: fixedScope ? 'source-kind-candidate' : (source.candidateScopeClasses.length ? 'path-candidate' : 'unclassified'),
			unresolved_reason: fixedScope || source.candidateScopeClasses.length ? null : 'No source coverage directory matched this item; A–G routing needs review.'
		},
		feature_mapping: {
			candidate_requirement_prefixes: source.candidateRequirementPrefixes,
			candidate_feature_ids: source.candidateFeatureIds,
			candidate_case_ids: source.candidateCaseIds,
			mapped_feature_ids: [],
			case_ids: [],
			status: source.candidateFeatureIds.length ? 'candidate-only' : 'unmapped',
			unresolved_reason: source.candidateFeatureIds.length ? 'Directory route is a candidate only; exact feature mapping needs review.' : 'No requirement-family route matched this item; feature mapping needs review.'
		},
		local_implementation: { symbols: [], case_ids: [], evidence: [], status: 'unmapped' },
		reachability: runtimeReachability(kind, id)
	};
}

function lineForToken(text, token) {
	if (!token) {
		return null;
	}
	const index = text.indexOf(JSON.stringify(token));
	return index < 0 ? null : text.slice(0, index).split('\n').length;
}

function staticValue(node, depth = 0) {
	if (!node || depth > 5) {
		return undefined;
	}
	if (ts.isStringLiteralLike(node)) {
		return node.text;
	}
	if (ts.isNumericLiteral(node)) {
		return Number(node.text);
	}
	if (node.kind === ts.SyntaxKind.TrueKeyword) {
		return true;
	}
	if (node.kind === ts.SyntaxKind.FalseKeyword) {
		return false;
	}
	if (node.kind === ts.SyntaxKind.NullKeyword) {
		return null;
	}
	if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isTypeAssertionExpression(node) || ts.isSatisfiesExpression(node)) {
		return staticValue(node.expression, depth + 1);
	}
	if (ts.isPrefixUnaryExpression(node) && ts.isNumericLiteral(node.operand)) {
		return node.operator === ts.SyntaxKind.MinusToken ? -Number(node.operand.text) : Number(node.operand.text);
	}
	if (ts.isArrayLiteralExpression(node)) {
		return node.elements.slice(0, 100).map(element => staticValue(element, depth + 1) ?? { expression: element.getText().slice(0, 160) });
	}
	if (ts.isObjectLiteralExpression(node)) {
		const output = {};
		for (const property of node.properties.slice(0, 100)) {
			if (!ts.isPropertyAssignment(property)) {
				continue;
			}
			const key = propertyName(property.name);
			if (!key) {
				continue;
			}
			const value = staticValue(property.initializer, depth + 1);
			output[key] = value === undefined ? { expression: property.initializer.getText().slice(0, 160) } : value;
		}
		return output;
	}
	if (ts.isIdentifier(node) || ts.isPropertyAccessExpression(node) || ts.isCallExpression(node) || ts.isElementAccessExpression(node)) {
		return { expression: node.getText().slice(0, 200) };
	}
	return { expression: node.getText().slice(0, 200) };
}

function propertyName(name) {
	if (ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)) {
		return name.text;
	}
	return undefined;
}

function property(object, name) {
	if (!object || !ts.isObjectLiteralExpression(object)) {
		return undefined;
	}
	const found = object.properties.find(entry => ts.isPropertyAssignment(entry) && propertyName(entry.name) === name);
	return found?.initializer;
}

function objectFields(object) {
	if (!object || !ts.isObjectLiteralExpression(object)) {
		return {};
	}
	const output = {};
	for (const entry of object.properties) {
		if (!ts.isPropertyAssignment(entry)) {
			continue;
		}
		const name = propertyName(entry.name);
		if (!name || !FIELD_NAMES.has(name)) {
			continue;
		}
		const value = staticValue(entry.initializer);
		if (value !== undefined) {
			output[name] = value;
		}
	}
	return output;
}

function callName(expression) {
	if (ts.isIdentifier(expression)) {
		return expression.text;
	}
	if (ts.isPropertyAccessExpression(expression)) {
		return expression.name.text;
	}
	if (ts.isElementAccessExpression(expression) && expression.argumentExpression && ts.isStringLiteralLike(expression.argumentExpression)) {
		return expression.argumentExpression.text;
	}
	return '';
}

function callKind(name) {
	if (/^(?:registerAction2|registerEditorAction|registerCommand|registerCommandAlias|registerQuickAccessCommand)$/.test(name)) return 'command';
	if (/^(?:appendMenuItem|appendMenuItems|registerMenuItem|registerSubmenu)$/.test(name)) return 'menu';
	if (/^(?:registerKeybindingRule|registerKeybinding|registerKeybindingRules)$/.test(name)) return 'keybinding';
	if (/^(?:registerConfiguration|registerConfigurations|registerDefaultConfigurations|registerConfigurationDefaults)$/.test(name)) return 'configuration';
	if (/^(?:registerLanguage|registerLanguageAssociation|registerLanguageConfiguration|registerGrammarDefinition|registerTextModelContentProvider)$/.test(name)) return 'language';
	if (/^(?:registerView|registerViewContainer|registerViews|registerViewDescriptor|registerViewWelcomeContent)$/.test(name)) return 'view';
	if (/^(?:registerColor|registerIcon|registerProductIcon|registerThemingParticipant|registerTheme)$/.test(name)) return 'theme';
	if (/^(?:registerExtensionPoint|registerWorkbenchContribution|registerWorkbenchContribution2|registerWorkbenchContribution3|registerEditorContribution)$/.test(name)) return 'contribution';
	if (/^(?:registerSingleton|registerService|registerAuthenticationProvider)$/.test(name)) return 'service';
	if (/^(?:registerTaskProvider|registerDebugConfigurationProvider|registerDebugger|registerNotebookSerializer|registerNotebookRenderer|registerCustomEditorProvider|registerFileSystemProvider|registerTerminalProfileProvider|registerStatusBarItem|registerQuickAccessProvider)$/.test(name)) return 'provider';
	if (/^register(?:Completion|Hover|Definition|Declaration|Implementation|TypeDefinition|Reference|Rename|CodeAction|DocumentFormatting|DocumentRangeFormatting|OnTypeFormatting|SignatureHelp|DocumentSymbol|WorkspaceSymbol|DocumentLink|FoldingRange|SelectionRange|SemanticTokens|InlineCompletion|CallHierarchy|TypeHierarchy|Color|InlayHint|LinkedEditing|Moniker|DocumentHighlight|EvaluatableExpression|InlineValues|CodeLens|DocumentPasteEdit|DocumentDropEdit|TreeData|Timeline|TerminalLink|TerminalCompletion).*Provider$/.test(name)) return 'provider';
	if (/^(?:registerEditorPane|registerEditorSerializer|registerDiffEditor|registerNotebookEditor|registerCustomEditor)$/.test(name)) return 'editor-contribution';
	return null;
}

function lineOf(sourceFile, node) {
	return sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1;
}

function addSourceItem({ kind, id, relativePath, line, blobSha, fields, registration, coverageEntry, owner = null, fixedScope = null }) {
	staticItems.push(makeItem({
		kind,
		id,
		owner,
		source: sourceInfo(relativePath, line, coverageEntry ?? nearestCoverage(relativePath), blobSha, 'typescript-ast'),
		rawFields: fields,
		registration,
		fixedScope
	}));
	if (kind === 'configuration' && id) configurationKeys.add(id);
}

function findActionConfiguration(call) {
	let result;
	function walk(node) {
		if (result) return;
		if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.SuperKeyword && node.arguments[0] && ts.isObjectLiteralExpression(node.arguments[0])) {
			result = node.arguments[0];
			return;
		}
		ts.forEachChild(node, walk);
	}
	walk(call);
	return result;
}

function firstString(node) {
	let found;
	function walk(current) {
		if (found) return;
		if (ts.isStringLiteralLike(current)) {
			found = current.text;
			return;
		}
		ts.forEachChild(current, walk);
	}
	if (node) walk(node);
	return found;
}

function emitConfigurationCall(call, callMethod, sourceFile, relativePath, blobSha, coverageEntry) {
	const first = call.arguments[0];
	const configObjects = first && ts.isArrayLiteralExpression(first) ? first.elements.filter(ts.isObjectLiteralExpression) : (first && ts.isObjectLiteralExpression(first) ? [first] : []);
	let emitted = 0;
	for (const configObject of configObjects) {
		const sectionId = staticValue(property(configObject, 'id'));
		if (typeof sectionId === 'string') {
			addSourceItem({ kind: 'configuration-section', id: sectionId, relativePath, line: lineOf(sourceFile, configObject), blobSha, fields: objectFields(configObject), registration: callMethod, coverageEntry });
			emitted++;
		}
		const properties = property(configObject, 'properties');
		if (properties && ts.isObjectLiteralExpression(properties)) {
			for (const setting of properties.properties) {
				if (!ts.isPropertyAssignment(setting)) continue;
				const key = propertyName(setting.name);
				if (!key) continue;
				addSourceItem({ kind: 'configuration', id: key, relativePath, line: lineOf(sourceFile, setting), blobSha, fields: objectFields(setting.initializer), registration: callMethod, coverageEntry, owner: typeof sectionId === 'string' ? sectionId : null });
				emitted++;
			}
		}
		if (callMethod === 'registerDefaultConfigurations' || callMethod === 'registerConfigurationDefaults') {
			for (const setting of configObject.properties) {
				if (!ts.isPropertyAssignment(setting)) continue;
				const key = propertyName(setting.name);
				if (!key) continue;
				addSourceItem({ kind: 'configuration-default', id: key, relativePath, line: lineOf(sourceFile, setting), blobSha, fields: { default: staticValue(setting.initializer) }, registration: callMethod, coverageEntry });
				emitted++;
			}
		}
	}
	return emitted;
}

function emitAction2(call, sourceFile, relativePath, blobSha, coverageEntry) {
	const config = findActionConfiguration(call);
	const actionId = typeof staticValue(property(config, 'id')) === 'string' ? staticValue(property(config, 'id')) : firstString(call.arguments[0]);
	const title = staticValue(property(config, 'title'));
	const fields = objectFields(config);
	addSourceItem({ kind: 'command', id: actionId ?? null, relativePath, line: lineOf(sourceFile, call), blobSha, fields, registration: 'registerAction2', coverageEntry });
	let emitted = 1;
	const menus = property(config, 'menu');
	if (menus && ts.isArrayLiteralExpression(menus)) {
		for (const menu of menus.elements) {
			if (!ts.isObjectLiteralExpression(menu)) continue;
			const menuId = staticValue(property(menu, 'id'));
			const menuKey = typeof menuId === 'string' ? menuId : menuId?.expression ?? null;
			addSourceItem({ kind: 'menu', id: actionId ? `${actionId}@${menuKey ?? 'unknown-menu'}` : null, relativePath, line: lineOf(sourceFile, menu), blobSha, fields: { command: actionId ?? null, title, menu: menuKey, ...objectFields(menu) }, registration: 'registerAction2.menu', coverageEntry });
			emitted++;
		}
	}
	const keybinding = property(config, 'keybinding');
	if (keybinding && (ts.isObjectLiteralExpression(keybinding) || ts.isArrayLiteralExpression(keybinding))) {
		const bindings = ts.isArrayLiteralExpression(keybinding) ? keybinding.elements : [keybinding];
		for (const binding of bindings) {
			if (!ts.isObjectLiteralExpression(binding)) continue;
			addSourceItem({ kind: 'keybinding', id: actionId ?? null, relativePath, line: lineOf(sourceFile, binding), blobSha, fields: objectFields(binding), registration: 'registerAction2.keybinding', coverageEntry });
			emitted++;
		}
	}
	return emitted;
}

function emitCall(call, callMethod, sourceFile, relativePath, blobSha, coverageEntry) {
	if (callMethod === 'registerAction2') {
		return emitAction2(call, sourceFile, relativePath, blobSha, coverageEntry);
	}
	if (callMethod.startsWith('registerConfiguration')) {
		return emitConfigurationCall(call, callMethod, sourceFile, relativePath, blobSha, coverageEntry);
	}
	if (callMethod === 'registerDefaultConfigurations' || callMethod === 'registerConfigurationDefaults') {
		return emitConfigurationCall(call, callMethod, sourceFile, relativePath, blobSha, coverageEntry);
	}
	let object;
	if (callMethod === 'appendMenuItem' || callMethod === 'appendMenuItems') {
		object = call.arguments[1];
	} else {
		object = call.arguments.find(ts.isObjectLiteralExpression);
	}
	const fields = objectFields(object);
	let id = fields.id;
	if (callMethod === 'registerCommand' && call.arguments[0]) {
		const first = staticValue(call.arguments[0]);
		if (typeof first === 'string') id = first;
	}
	if (callMethod === 'appendMenuItem' || callMethod === 'appendMenuItems') {
		const command = object && ts.isObjectLiteralExpression(object) ? property(object, 'command') : undefined;
		const commandObject = command && ts.isObjectLiteralExpression(command) ? command : undefined;
		const commandId = typeof staticValue(command) === 'string' ? staticValue(command) : staticValue(property(commandObject, 'id'));
		const menuId = call.arguments[0]?.getText(sourceFile) ?? null;
		id = typeof commandId === 'string' ? `${menuId}:${commandId}` : null;
		fields.command = commandId ?? null;
		fields.menu = menuId;
	}
	if (callMethod === 'registerKeybindingRule' || callMethod === 'registerKeybindingRules') {
		id = fields.command ?? fields.id;
	}
	if (typeof id !== 'string') {
		id = firstString(call.arguments[0]);
	}
	addSourceItem({ kind: callKind(callMethod), id: typeof id === 'string' ? id : null, relativePath, line: lineOf(sourceFile, call), blobSha, fields, registration: callMethod, coverageEntry });
	return 1;
}

const sourceFileNames = execGit('ls-files', '-z', '--', 'src/vs', 'extensions').split('\0').filter(Boolean).map(normalized);
const astPaths = sourceFileNames.filter(file => /\.(?:ts|tsx|js|jsx)$/.test(file) && !/\.d\.ts$/.test(file) && !/(?:^|\/)(?:node_modules|out|test|tests|fixtures)(?:\/|$)/.test(file) && !/\.(?:test|spec)\.(?:ts|tsx|js|jsx)$/.test(file));
astCounters.trackedSourceFiles = sourceFileNames.filter(file => /\.(?:ts|tsx|js|jsx)$/.test(file)).length;
const candidatePattern = /\b(?:register|append)(?:Action|Command|Keybinding|Menu|Configuration|View|Language|LanguageAssociation|LanguageConfiguration|Grammar|Theme|Icon|ProductIcon|Color|ThemingParticipant|WorkbenchContribution|EditorContribution|ExtensionPoint|Singleton|Service|Completion|Hover|Definition|Declaration|Implementation|TypeDefinition|Reference|Rename|CodeAction|DocumentFormatting|DocumentRangeFormatting|OnTypeFormatting|SignatureHelp|DocumentSymbol|WorkspaceSymbol|DocumentLink|FoldingRange|SelectionRange|SemanticTokens|InlineCompletion|CallHierarchy|TypeHierarchy|InlayHint|LinkedEditing|Moniker|DocumentHighlight|EvaluatableExpression|InlineValues|CodeLens|TaskProvider|DebugConfigurationProvider|Debugger|Notebook|CustomEditor|FileSystemProvider|TerminalProfileProvider|StatusBarItem|QuickAccessProvider|EditorPane|EditorSerializer|DiffEditor|ViewDescriptor)\w*\s*\(/;

for (const relativePath of astPaths) {
	const absolutePath = path.join(sourceRoot, ...relativePath.split('/'));
	let text;
	try {
		text = await fs.readFile(absolutePath, 'utf8');
	} catch {
		continue;
	}
	if (!candidatePattern.test(text)) continue;
	candidatePattern.lastIndex = 0;
	const sourceFile = ts.createSourceFile(relativePath, text, ts.ScriptTarget.Latest, true, relativePath.endsWith('x') ? ts.ScriptKind.TSX : (relativePath.endsWith('.js') || relativePath.endsWith('.jsx') ? ts.ScriptKind.JS : ts.ScriptKind.TS));
	const blobSha = sha1Blob(Buffer.from(text));
	const coverageEntry = nearestCoverage(relativePath);
	astCounters.parsedSourceFiles++;
	function walk(node) {
		if (ts.isCallExpression(node)) {
			const name = callName(node.expression);
			const kind = callKind(name);
			if (kind) {
				astCounters.registrationCalls++;
				const emitted = emitCall(node, name, sourceFile, relativePath, blobSha, coverageEntry);
				if (!emitted) astCounters.unresolvedCalls++;
			}
		}
		ts.forEachChild(node, walk);
	}
	walk(sourceFile);
}

function manifestLine(raw, id) {
	return lineForToken(raw, id);
}

function manifestId(kind, item, extensionId, point, index) {
	if (typeof item === 'string') return item;
	if (!item || typeof item !== 'object') return null;
	const fields = ['command', 'id', 'viewType', 'type', 'language', 'scopeName', 'name', 'filename', 'key'];
	for (const field of fields) {
		if (typeof item[field] === 'string') return item[field];
	}
	return `${extensionId}:${point}:${index}`;
}

function addManifestItem({ kind, id, extensionId, manifest, relativePath, raw, item, point, menuId = null, owner = null, fixedScope = null }) {
	const coverageEntry = nearestCoverage(relativePath);
	const line = manifestLine(raw, id);
	const itemFields = item && typeof item === 'object' ? item : { value: item };
	staticItems.push(makeItem({
		kind,
		id,
		source: sourceInfo(relativePath, line, coverageEntry, sha1Blob(Buffer.from(raw)), 'extension-manifest'),
		rawFields: { contributionPoint: point, menu: menuId, ...itemFields },
		registration: `manifest:${point}`,
		owner: owner ?? extensionId,
		fixedScope
	}));
	if (kind === 'configuration' && id) configurationKeys.add(id);
}

function contributionItems(extensionId, manifest, relativePath, raw) {
	const contributes = manifest.contributes ?? {};
	for (const [point, value] of Object.entries(contributes)) {
		if (point === 'configuration' || point === 'configurationDefaults') {
			const sections = Array.isArray(value) ? value : [value];
			for (const section of sections) {
				if (!section || typeof section !== 'object') continue;
				if (point === 'configurationDefaults') {
					for (const [key, defaultValue] of Object.entries(section)) {
						addManifestItem({ kind: 'configuration-default', id: key, extensionId, manifest, relativePath, raw, item: { default: defaultValue }, point });
						configurationKeys.add(key);
					}
					continue;
				}
				const sectionId = section.id;
				if (typeof sectionId === 'string') addManifestItem({ kind: 'configuration-section', id: sectionId, extensionId, manifest, relativePath, raw, item: section, point });
				for (const [key, definition] of Object.entries(section.properties ?? {})) {
					addManifestItem({ kind: 'configuration', id: key, extensionId, manifest, relativePath, raw, item: definition, point, owner: sectionId ?? extensionId });
					configurationKeys.add(key);
				}
			}
			continue;
		}
		if (point === 'menus') {
			for (const [menuId, entries] of Object.entries(value ?? {})) {
				for (const [index, item] of (Array.isArray(entries) ? entries : []).entries()) {
					const commandId = typeof item?.command === 'string' ? item.command : item?.command?.id;
					const id = `${menuId}:${commandId ?? item?.id ?? index}`;
					addManifestItem({ kind: 'menu', id, extensionId, manifest, relativePath, raw, item: { ...item, command: commandId ?? null }, point, menuId });
				}
			}
			continue;
		}
		if (point === 'commands') {
			for (const [index, item] of (Array.isArray(value) ? value : []).entries()) addManifestItem({ kind: 'command', id: manifestId('command', item, extensionId, point, index), extensionId, manifest, relativePath, raw, item, point });
			continue;
		}
		if (point === 'keybindings') {
			for (const [index, item] of (Array.isArray(value) ? value : []).entries()) addManifestItem({ kind: 'keybinding', id: item?.command ?? `${extensionId}:${point}:${index}`, extensionId, manifest, relativePath, raw, item, point });
			continue;
		}
		if (point === 'languages') {
			for (const [index, item] of (Array.isArray(value) ? value : []).entries()) addManifestItem({ kind: 'language', id: item?.id ?? `${extensionId}:${point}:${index}`, extensionId, manifest, relativePath, raw, item, point });
			continue;
		}
		if (point === 'grammars') {
			for (const [index, item] of (Array.isArray(value) ? value : []).entries()) addManifestItem({ kind: 'grammar', id: item?.scopeName ?? `${extensionId}:${point}:${index}`, extensionId, manifest, relativePath, raw, item, point });
			continue;
		}
		const elements = Array.isArray(value) ? value : (value && typeof value === 'object' ? Object.entries(value).map(([key, item]) => ({ key, value: item })) : [value]);
		for (const [index, item] of elements.entries()) {
			const id = manifestId(`manifest:${point}`, item, extensionId, point, index);
			addManifestItem({ kind: `manifest:${point}`, id, extensionId, manifest, relativePath, raw, item, point });
		}
	}
	for (const [index, event] of (manifest.activationEvents ?? []).entries()) {
		addManifestItem({ kind: 'activation-event', id: event, extensionId, manifest, relativePath, raw, item: { event, index }, point: 'activationEvents' });
	}
	for (const [index, dependency] of (manifest.extensionDependencies ?? []).entries()) {
		addManifestItem({ kind: 'extension-dependency', id: dependency, extensionId, manifest, relativePath, raw, item: { dependency, index }, point: 'extensionDependencies' });
	}
}

const manifestPaths = sourceFileNames.filter(file => /^extensions\/[^/]+\/package\.json$/.test(file));
const manifestNames = new Set();
for (const relativePath of manifestPaths) {
	const absolutePath = path.join(sourceRoot, ...relativePath.split('/'));
	const raw = await fs.readFile(absolutePath, 'utf8');
	const manifest = JSON.parse(raw);
	const extensionId = `${manifest.publisher ?? 'vscode'}.${manifest.name}`;
	manifestNames.add(extensionId.toLowerCase());
	const manifestCoverage = nearestCoverage(relativePath);
	staticItems.push(makeItem({
		kind: 'extension',
		id: extensionId,
		source: sourceInfo(relativePath, 1, manifestCoverage, sha1Blob(Buffer.from(raw)), 'extension-manifest'),
		rawFields: {
			name: manifest.name,
			publisher: manifest.publisher ?? 'vscode',
			version: manifest.version,
			main: manifest.main ?? null,
			browser: manifest.browser ?? null,
			activationEvents: manifest.activationEvents ?? [],
			dependencies: manifest.extensionDependencies ?? [],
			contributionPoints: Object.keys(manifest.contributes ?? {}).sort()
		},
		registration: 'manifest:package',
		fixedScope: externalBuiltinsById.has(extensionId) ? ['B'] : null
	}));
	contributionItems(extensionId, manifest, relativePath, raw);
}

function addProductItem(kind, id, value, key) {
	const raw = JSON.stringify(product);
	const fixedScope = key === 'builtInExtensions' ? ['B'] : (key === 'defaultChatAgent' ? ['F'] : null);
	staticItems.push(makeItem({
		kind,
		id,
		source: sourceInfo('product.json', lineForToken(raw, key), nearestCoverage('product.json'), sha1Blob(Buffer.from(raw)), 'product-json'),
		rawFields: value,
		registration: `product:${key}`,
		fixedScope
	}));
}

for (const [key, value] of Object.entries(product)) {
	if (key === 'builtInExtensions') {
		for (const entry of value ?? []) {
			const normalizedId = entry.name;
			addProductItem('external-built-in-extension', normalizedId, entry, key);
		}
	} else if (/(?:Gallery|Sync|Tunnel|Port|Authentication|Entitlement|Telemetry|ChatAgent|ApiProposal|apiProposals|ExtensionKind|Mcp)/i.test(key) || key === 'quality' || key === 'nameShort' || key === 'applicationName' || key === 'urlProtocol') {
		addProductItem('product-feature-flag', key, value, key);
	}
}

function addRuntimeOnly(kind, id, evidence) {
	const relativePath = path.relative(repoRoot, runtimePath).split(path.sep).join('/');
	staticItems.push(makeItem({
		kind,
		id,
		source: {
			repository: 'microsoft/vscode', commit: sourceCommit, path: relativePath, line: null,
			url: null, blobSha: null, discoveryIds: [], candidateScopeClasses: [], scopeDecision: null,
			scopeReason: null, candidateRequirementPrefixes: [], candidateFeatureIds: [], candidateCaseIds: [],
			status: 'runtime-only', kind: 'runtime-registry'
		},
		rawFields: { evidence },
		registration: 'runtime-registry-only'
	}));
}

const sourceIdsByKind = new Map();
for (const item of staticItems) {
	if (!item.id) continue;
	if (!sourceIdsByKind.has(item.kind)) sourceIdsByKind.set(item.kind, new Set());
	sourceIdsByKind.get(item.kind).add(item.id);
}
const sourceAtomicItemCount = staticItems.length;
for (const commandId of runtimeCommands) if (!sourceIdsByKind.get('command')?.has(commandId)) addRuntimeOnly('command', commandId, 'runtime.commands');
for (const languageId of runtimeLanguages) if (!sourceIdsByKind.get('language')?.has(languageId)) addRuntimeOnly('language', languageId, 'runtime.languages');
for (const configurationId of runtimeConfigurations) if (!sourceIdsByKind.get('configuration')?.has(configurationId)) addRuntimeOnly('configuration', configurationId, 'runtime.configurationKeys');
for (const [extensionId, extension] of runtimeExtensionById) {
	if (extensionId === probeExtensionId || manifestNames.has(extensionId)) continue;
	addRuntimeOnly('extension', extensionId, 'runtime.extensions');
}

const reconciliationKinds = ['command', 'configuration', 'language', 'extension'];
const reconciliation = {};
for (const kind of reconciliationKinds) {
	const source = sourceIdsByKind.get(kind) ?? new Set();
	const runtimeIds = kind === 'command' ? runtimeCommands
		: kind === 'configuration' ? runtimeConfigurations
			: kind === 'language' ? runtimeLanguages
				: new Set([...runtimeExtensionById.keys()].filter(id => id !== probeExtensionId));
	const matched = [...source].filter(id => runtimeIds.has(kind === 'extension' ? id.toLowerCase() : id)).sort();
	const sourceOnly = [...source].filter(id => !runtimeIds.has(kind === 'extension' ? id.toLowerCase() : id)).sort();
	const runtimeOnly = [...runtimeIds].filter(id => !source.has(id)).sort();
	reconciliation[kind] = {
		staticUniqueIds: source.size,
		runtimeUniqueIds: runtimeIds.size,
		matchedIds: matched.length,
		sourceOnlyIds: sourceOnly.length,
		runtimeOnlyIds: runtimeOnly.length,
		matched,
		sourceOnly,
		runtimeOnly
	};
}

const unresolvedDiscoveries = sourceCoverage.entries
	.filter(entry => unresolvedDiscoverySet.has(entry.discovery_id))
	.map(entry => ({ discovery_id: entry.discovery_id, path: entry.path, discovery_bucket: entry.discovery_bucket, requirement_prefixes: entry.requirement_prefixes, scope_classes: entry.scope_classes, reason: entry.reason }));
const unresolvedRegistrations = staticItems.filter(item => !item.id || item.feature_mapping.status === 'unmapped' || item.scope.decision_status === 'unclassified').map(item => item.registration_id);
const countsByKind = Object.fromEntries([...new Set(staticItems.map(item => item.kind))].sort().map(kind => [kind, staticItems.filter(item => item.kind === kind).length]));
const countsByScopeCandidate = Object.fromEntries('ABCDEFG'.split('').map(letter => [letter, staticItems.filter(item => item.scope.candidate_classes.includes(letter)).length]));
const countsByReachability = Object.fromEntries([...new Set(staticItems.map(item => item.reachability.status))].sort().map(status => [status, staticItems.filter(item => item.reachability.status === status).length]));
const registrationIdCount = new Set(staticItems.map(item => item.registration_id)).size;
const inputHashes = {};
for (const file of [coveragePath, matrixPath, builtinIndexPath, runtimePath]) inputHashes[path.relative(repoRoot, file).split(path.sep).join('/')] = sha256(await fs.readFile(file));

const output = {
	schema_version: 1,
	kind: 'atomic-source-runtime-manifest-registration-ledger',
	claim_limits: [
		'抽取到注册调用不等于产品可达或行为已实现；所有映射、范围和可达性仍保留候选/实测状态。',
		'运行时命令/语言/配置来自隔离 Code-OSS 开发宿主；运行时 probe 扩展不属于产品。',
	'菜单、键位、provider、feature flag 与主题当前为静态来源；公开扩展 API 不提供完整运行时枚举接口。',
		'目录路由只提供候选需求族；local implementation、case 和 evidence 需后续逐项签收。'
	],
	reference: { repository: 'microsoft/vscode', commit: sourceCommit, tree: sourceTree, version: packageJson.version, productName: product.nameShort },
	inputs: { ...inputHashes, runtimeCapturedAt: runtime.capturedAt ?? null },
	statistics: {
		trackedSourceFiles: astCounters.trackedSourceFiles,
		parsedSourceFiles: astCounters.parsedSourceFiles,
		astRegistrationCalls: astCounters.registrationCalls,
		unresolvedAstCalls: astCounters.unresolvedCalls,
		extensionManifestCount: manifestPaths.length,
		priorDiscoveryEntryCount: sourceCoverage.entries.length,
		priorUnresolvedDiscoveryCount: unresolvedDiscoveries.length,
		sourceAtomicItemCount,
		runtimeOnlyLedgerItemCount: staticItems.length - sourceAtomicItemCount,
		runtimeCommandCount: runtimeCommands.size,
		runtimeLanguageCount: runtimeLanguages.size,
		runtimeConfigurationCount: runtimeConfigurations.size,
		runtimeExtensionCount: runtimeExtensionById.size - (probeExtensionId ? 1 : 0),
		atomicItemCount: staticItems.length,
		uniqueRegistrationIdCount: registrationIdCount,
		duplicateRegistrationIdCount: staticItems.length - registrationIdCount,
		unclassifiedScopeCount: staticItems.filter(item => item.scope.decision_status === 'unclassified').length,
		unclassifiedSourceScopeCount: staticItems.filter(item => item.source.kind !== 'runtime-registry' && item.scope.decision_status === 'unclassified').length,
		unmappedFeatureCount: staticItems.filter(item => item.feature_mapping.status === 'unmapped').length,
		unmappedSourceFeatureCount: staticItems.filter(item => item.source.kind !== 'runtime-registry' && item.feature_mapping.status === 'unmapped').length,
		unresolvedRegistrationCount: unresolvedRegistrations.length,
		countsByKind,
		countsByScopeCandidate,
		countsByReachability
	},
	reconciliation,
	unresolved: {
		discoveryEntries: unresolvedDiscoveries,
		registrationIds: unresolvedRegistrations
	},
	items: staticItems
};

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
await fs.writeFile(summaryPath, `${JSON.stringify({ reference: output.reference, inputs: output.inputs, statistics: output.statistics, reconciliation: Object.fromEntries(Object.entries(reconciliation).map(([kind, value]) => [kind, { staticUniqueIds: value.staticUniqueIds, runtimeUniqueIds: value.runtimeUniqueIds, matchedIds: value.matchedIds, sourceOnlyIds: value.sourceOnlyIds, runtimeOnlyIds: value.runtimeOnlyIds }])) }, null, 2)}\n`, 'utf8');
await fs.writeFile(configKeysPath, `${JSON.stringify([...configurationKeys].sort(), null, 2)}\n`, 'utf8');
console.log(JSON.stringify({ output: path.relative(repoRoot, outputPath), summary: path.relative(repoRoot, summaryPath), configurationKeys: path.relative(repoRoot, configKeysPath), reference: output.reference, statistics: output.statistics }, null, 2));
