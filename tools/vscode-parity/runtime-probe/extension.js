const fs = require('node:fs');
const path = require('node:path');
const vscode = require('vscode');

async function activate() {
	const outputPath = process.env.ALULA_RUNTIME_REGISTRY_OUT;
	if (!outputPath) {
		throw new Error('ALULA_RUNTIME_REGISTRY_OUT must point to the runtime registry output file.');
	}

	const [commandIds, languageIds] = await Promise.all([
		vscode.commands.getCommands(false),
		vscode.languages.getLanguages()
	]);
	const configurationInput = process.env.ALULA_RUNTIME_CONFIG_KEYS;
	const configurationCandidates = configurationInput
		? JSON.parse(await fs.promises.readFile(configurationInput, 'utf8'))
		: [];
	const configuration = vscode.workspace.getConfiguration();
	const registeredConfigurationKeys = configurationCandidates
		.filter(key => configuration.inspect(key) !== undefined)
		.sort();
	const extensions = vscode.extensions.all.map(extension => ({
		id: extension.id,
		name: extension.packageJSON.name,
		publisher: extension.packageJSON.publisher,
		version: extension.packageJSON.version,
		isActive: extension.isActive,
		contributionPoints: Object.keys(extension.packageJSON.contributes ?? {}).sort()
	})).sort((a, b) => a.id.localeCompare(b.id));

	const output = {
		capturedAt: new Date().toISOString(),
		reference: {
			version: vscode.version,
			appName: vscode.env.appName,
			uiKind: vscode.env.uiKind,
			language: vscode.env.language
		},
		instrumentation: {
			extensionId: 'alula-internal.alula-vscode-runtime-registry-probe',
			productFeature: false
		},
		commands: commandIds.filter(id => id !== 'alulaRegistryProbe.export').sort(),
		languages: languageIds.sort(),
		configurationCandidates: configurationCandidates.length,
		configurationKeys: registeredConfigurationKeys,
		extensions
	};

	await fs.promises.mkdir(path.dirname(outputPath), { recursive: true });
	await fs.promises.writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
}

function deactivate() { }

module.exports = { activate, deactivate };
