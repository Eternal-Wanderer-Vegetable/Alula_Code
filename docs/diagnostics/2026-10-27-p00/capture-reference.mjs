#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

function flag(name, fallback) {
	const prefix = `--${name}=`;
	const value = process.argv.find(arg => arg.startsWith(prefix));
	return value ? value.slice(prefix.length) : fallback;
}

const port = Number(flag('port', '9222'));
const outputDir = path.resolve(flag('output', 'docs/diagnostics/2026-10-27-p00'));
const productPath = flag('product', '');

const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then(response => {
	if (!response.ok) {
		throw new Error(`CDP target list returned HTTP ${response.status}`);
	}
	return response.json();
});
const target = targets.find(candidate => candidate.type === 'page' && candidate.url.includes('/workbench/'));
if (!target) {
	throw new Error('No VS Code workbench page found in the CDP target list.');
}

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
	const timeout = setTimeout(() => reject(new Error('Timed out connecting to the VS Code renderer.')), 10000);
	socket.addEventListener('open', () => {
		clearTimeout(timeout);
		resolve();
	}, { once: true });
	socket.addEventListener('error', event => {
		clearTimeout(timeout);
		reject(event.error ?? new Error('CDP WebSocket connection failed.'));
	}, { once: true });
});

let nextId = 1;
const pending = new Map();
socket.addEventListener('message', event => {
	const message = JSON.parse(String(event.data));
	if (message.id === undefined) {
		return;
	}
	const request = pending.get(message.id);
	if (!request) {
		return;
	}
	pending.delete(message.id);
	clearTimeout(request.timeout);
	if (message.error) {
		request.reject(new Error(message.error.message));
	} else {
		request.resolve(message.result);
	}
});

function send(method, params = {}) {
	const id = nextId++;
	return new Promise((resolve, reject) => {
		const timeout = setTimeout(() => {
			pending.delete(id);
			reject(new Error(`Timed out waiting for CDP ${method}.`));
		}, 15000);
		pending.set(id, { resolve, reject, timeout });
		socket.send(JSON.stringify({ id, method, params }));
	});
}

const expression = `(() => {
	const root = document.documentElement;
	const body = document.body;
	const workbench = document.querySelector('.monaco-workbench');
	const workbenchStyle = getComputedStyle(workbench || body);
	const rootStyle = getComputedStyle(root);
	return {
		url: location.href,
		title: document.title,
		readyState: document.readyState,
		viewport: { innerWidth, innerHeight, outerWidth, outerHeight },
		screen: { width: screen.width, height: screen.height, availWidth: screen.availWidth, availHeight: screen.availHeight },
		devicePixelRatio: window.devicePixelRatio,
		locale: navigator.language,
		languages: navigator.languages,
		timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
		userAgent: navigator.userAgent,
		theme: {
			rootClass: root.className,
			rootDataTheme: root.getAttribute('data-vscode-theme-kind'),
			bodyClass: body.className,
			workbenchClass: workbench?.className ?? null,
			backgroundColor: workbenchStyle.backgroundColor,
			foregroundColor: workbenchStyle.color,
			fontFamily: workbenchStyle.fontFamily,
			editorBackground: rootStyle.getPropertyValue('--vscode-editor-background').trim()
		}
	};
})()`;

try {
	let continuedWithoutSignIn = false;
	if (process.argv.includes('--continue-without-sign-in')) {
		const dismissal = await send('Runtime.evaluate', {
			expression: `(() => {
				const candidate = [...document.querySelectorAll('button, a, [role="button"]')]
					.find(element => /continue without signing in/i.test(element.innerText || element.textContent || ''));
				if (!candidate) {
					return false;
				}
				candidate.click();
				return true;
			})()`,
			returnByValue: true
		});
		continuedWithoutSignIn = dismissal.result.value;
		if (continuedWithoutSignIn) {
			await new Promise(resolve => setTimeout(resolve, 2500));
		}
	}
	let gotStarted = false;
	if (process.argv.includes('--get-started')) {
		const dismissal = await send('Runtime.evaluate', {
			expression: `(() => {
				const candidate = [...document.querySelectorAll('button, a, [role="button"]')]
					.find(element => /^get started$/i.test((element.innerText || element.textContent || '').trim()));
				if (!candidate) {
					return false;
				}
				candidate.click();
				return true;
			})()`,
			returnByValue: true
		});
		gotStarted = dismissal.result.value;
		if (gotStarted) {
			await new Promise(resolve => setTimeout(resolve, 2500));
		}
	}
	const evaluation = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
	if (evaluation.exceptionDetails) {
		throw new Error(evaluation.exceptionDetails.text);
	}
	const runtime = evaluation.result.value;
	const screenshot = await send('Page.captureScreenshot', { format: 'png', fromSurface: true, captureBeyondViewport: false });
	const report = {
		capturedAt: new Date().toISOString(),
		cdp: { port, targetId: target.id, targetUrl: target.url },
		continuedWithoutSignIn,
		gotStarted,
		collector: { node: process.version, platform: process.platform, arch: process.arch },
		runtime
	};
	if (productPath) {
		const product = JSON.parse(await fs.readFile(productPath, 'utf8'));
		const packageJson = JSON.parse(await fs.readFile(path.join(path.dirname(productPath), 'package.json'), 'utf8'));
		const npmrc = await fs.readFile(path.join(path.dirname(productPath), '.npmrc'), 'utf8');
		report.product = {
			nameShort: product.nameShort,
			applicationName: product.applicationName,
			version: packageJson.version,
			electronVersion: /^target="?([^"\r\n]+)"?$/m.exec(npmrc)?.[1] ?? null,
			builtInExtensions: product.builtInExtensions ?? []
		};
	}
	await fs.mkdir(outputDir, { recursive: true });
	await fs.writeFile(path.join(outputDir, 'runtime-evidence.json'), `${JSON.stringify(report, null, 2)}\n`);
	await fs.writeFile(path.join(outputDir, 'reference-workbench.png'), Buffer.from(screenshot.data, 'base64'));
	console.log(JSON.stringify(report, null, 2));
} finally {
	socket.close();
}
