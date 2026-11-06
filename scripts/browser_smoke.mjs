// Run only against an already started local synthetic-data app.
// Uses an installed Node with global WebSocket and an installed Chrome. No npm packages.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, readdir, mkdir, writeFile, rm, lstat, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { saveCapture } from './browser_capture.mjs';

const target = new URL(process.env.DASHBOARD_URL ?? 'http://127.0.0.1:7431/');
if (target.protocol !== 'http:' || target.hostname !== '127.0.0.1' || !target.port || target.username || target.password) {
  throw new Error('Browser smoke accepts only the owned loopback HTTP app.');
}
if (typeof WebSocket !== 'function') throw new Error('Use a qualified Node version with global WebSocket.');
const evidence = resolve(process.env.DASHBOARD_EVIDENCE_DIR ?? '.runtime/browser-smoke');
const images = resolve('docs/screenshots');
const updateImages = process.env.DASHBOARD_UPDATE_SCREENSHOTS === '1';
await mkdir(evidence, { recursive: true });
const profile = await mkdtemp(join(tmpdir(), 'bicycle-browser-'));
const profileIdentity = await lstat(profile);
const chrome = spawn(process.env.CHROME_BIN ?? '/usr/bin/google-chrome', [
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--disable-extensions', '--disable-sync', '--disable-background-networking',
  '--metrics-recording-only', '--remote-debugging-address=127.0.0.1',
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--window-size=1440,1080', 'about:blank',
], { detached: true, stdio: ['ignore', 'ignore', 'pipe'] });
let spawnError;
let childCreated = false;
const launched = new Promise((resolve, reject) => {
  chrome.once('spawn', () => { childCreated = true; resolve(); });
  chrome.once('error', error => { spawnError = error; reject(error); });
});
const exited = new Promise(resolve => chrome.once('exit', resolve));
const alive = () => chrome.exitCode === null && chrome.signalCode === null && !spawnError;
let stderr = '';
chrome.stderr.on('data', chunk => { stderr += chunk.toString(); });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const records = [];
const blocked = [];
const exceptions = [];
const protocolErrors = [];
const contrast = (foreground, background) => {
  const luminance = color => {
    const rgb = color.match(/[0-9.]+/g).slice(0, 3).map(value => Number(value) / 255);
    const linear = rgb.map(value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4);
    return .2126 * linear[0] + .7152 * linear[1] + .0722 * linear[2];
  };
  const a = luminance(foreground), b = luminance(background);
  return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
};
let socket;
let primary;
const cleanupErrors = [];
let ownership;
const processState = async pid => {
  try {
    const text = await readFile('/proc/' + pid + '/stat', 'utf8');
    const fields = text.slice(text.lastIndexOf(')') + 1).trim().split(/\s+/);
    return { pid: Number(pid), state: fields[0], pgid: Number(fields[2]), sid: Number(fields[3]), startTicks: fields[19] };
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
};
const ownedGroup = async () => {
  const states = await Promise.all((await readdir('/proc')).filter(name => /^\d+$/.test(name)).map(processState));
  const members = states.filter(state => state?.pgid === chrome.pid);
  if (members.some(state => state.sid !== chrome.pid)) throw new Error('Owned Chrome session changed.');
  const leader = members.find(state => state.pid === chrome.pid);
  if (leader && leader.startTicks !== ownership.startTicks) throw new Error('Chrome PID was reused.');
  return members;
};
const signalGroup = async signal => {
  if (!(await ownedGroup()).length) return;
  try { process.kill(-chrome.pid, signal); } catch (error) { if (error.code !== 'ESRCH') throw error; }
};
let sequence = 0;
const pending = new Map();
const command = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++sequence;
  const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 10000);
  pending.set(id, { resolve, reject, timer });
  socket.send(JSON.stringify({ id, method, params }));
});
const evaluate = async expression => {
  const result = await command('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
};
const waitFor = async (expression, label, timeout = 60000) => {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (await evaluate(expression)) return;
    await delay(100);
  }
  throw new Error(`Timed out: ${label}. ${await evaluate('document.body.innerText')}`);
};
const capture = async name => {
  await delay(300);
  const shot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  const bytes = Buffer.from(shot.data, 'base64');
  await saveCapture({ evidence, images, name, bytes, updateImages });
  records.push({ screenshot: name, publicImageUpdated: updateImages, viewport: await evaluate('({ width: innerWidth, height: innerHeight })') });
};
const scrollTo = async heading => evaluate(`(() => {
  const element = [...document.querySelectorAll('.chart-title')].find(node => node.textContent.trim() === ${JSON.stringify(heading)});
  if (!element) throw new Error('Heading not found');
  element.scrollIntoView({ block: 'start' });
  return true;
})()`);
try {
  await launched;
  ownership = await processState(chrome.pid);
  assert.ok(ownership && ownership.pgid === chrome.pid && ownership.sid === chrome.pid);
  await writeFile(join(evidence, 'OWNED-CHROME.json'), JSON.stringify({ ...ownership, profile, target: target.href, argv: chrome.spawnargs }, null, 2) + '\n', { flag: 'wx' });
  let port;
  const debugDeadline = Date.now() + 15000;
  while (Date.now() < debugDeadline) {
    try { port = Number((await readFile(join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]); if (port) break; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (spawnError) throw spawnError;
    if (!alive()) throw new Error('Chrome exited before its local debug endpoint.');
    await delay(100);
  }
  if (!port) throw new Error('No Chrome debugging port.');
  await writeFile(join(evidence, 'CDP-PORT.json'), JSON.stringify({ port, host: '127.0.0.1' }) + '\n', { flag: 'wx' });
  const tabs = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = tabs.find(tab => tab.type === 'page');
  assert.ok(page?.webSocketDebuggerUrl);
  const endpoint = new URL(page.webSocketDebuggerUrl);
  assert.equal(endpoint.hostname, '127.0.0.1');
  assert.equal(Number(endpoint.port), port);
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id) {
      const item = pending.get(message.id);
      if (!item) return;
      clearTimeout(item.timer); pending.delete(message.id);
      if (message.error) item.reject(new Error(JSON.stringify(message.error))); else item.resolve(message.result);
    } else if (message.method === 'Fetch.requestPaused') {
      const url = new URL(message.params.request.url);
      if (url.origin === target.origin || ['data:', 'blob:', 'about:'].includes(url.protocol)) {
        void command('Fetch.continueRequest', { requestId: message.params.requestId }).catch(error => protocolErrors.push(error.message));
      } else {
        blocked.push(url.origin + url.pathname);
        void command('Fetch.failRequest', { requestId: message.params.requestId, errorReason: 'BlockedByClient' }).catch(error => protocolErrors.push(error.message));
      }
    } else if (message.method === 'Runtime.exceptionThrown') exceptions.push(message.params.exceptionDetails.text);
  });
  await command('Page.enable');
  await command('Runtime.enable');
  await command('Fetch.enable', { patterns: [{ urlPattern: '*' }] });
  await command('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1080, deviceScaleFactor: 1, mobile: false });
  await command('Page.navigate', { url: target.href });
  await waitFor(`document.querySelector('.kpi-group') && [...document.querySelectorAll('.js-plotly-plot')].filter(plot => plot.querySelector('svg.main-svg')).length >= 2 && !document.documentElement.classList.contains('shiny-busy')`, 'initial synthetic overview');
  const initial = await evaluate(`({ scope: document.querySelector('.scope-text').innerText, metrics: document.querySelector('.kpi-group').innerText })`);
  assert.match(initial.scope, /All 8 fictional stores/);
  const light = await evaluate(`({ background: getComputedStyle(document.body).backgroundColor, color: getComputedStyle(document.body).color })`);
  assert.ok(contrast(light.color, light.background) >= 4.5, 'Light body text must have readable contrast.');
  records.push({ lightContrast: { ...light, ratio: contrast(light.color, light.background) } });
  await evaluate("document.documentElement.dataset.smokeDocument = 'applied-selection-document'");
  assert.match(await evaluate('document.body.innerText'), /Synthetic USD revenue/);
  const mapLabels = await evaluate(`(() => {
    const plot = [...document.querySelectorAll('.js-plotly-plot')].find(plot => plot._fullData?.some(trace => trace.fill === 'toself'));
    const traces = plot._fullData.filter(trace => trace.fill === 'toself');
    const index = plot._fullData.findIndex(trace => trace.name === 'DC');
    const dc = plot._fullData[index];
    const path = index >= 0 ? plot.querySelector('.scatterlayer').children[index].querySelector('.js-fill') : null;
    const box = path?.getBoundingClientRect();
    return { names: traces.map(trace => trace.name), dc: dc ? { name: dc.name, text: dc.text, fillcolor: dc.fillcolor, hoveron: dc.hoveron } : null,
      hoverPoint: box ? { x: box.left + box.width / 2, y: box.top + box.height / 2 } : null };
  })()`);
  records.push({ renderedMap: mapLabels });
  assert.ok(mapLabels.names.every(name => typeof name === 'string' && /^[A-Z]{2}$/.test(name)), 'Every rendered polygon must have a state or DC label.');
  assert.equal(mapLabels.dc?.name, 'DC');
  assert.ok([mapLabels.dc.text].flat().every(text => text === 'DC: $0.00'));
  assert.equal(mapLabels.dc.fillcolor, '#e7ebef');
  assert.ok(mapLabels.hoverPoint);
  await command('Input.dispatchMouseEvent', { type: 'mouseMoved', ...mapLabels.hoverPoint });
  await waitFor(`[...document.querySelectorAll('.hoverlayer')].some(node => node.textContent.includes('DC: $0.00'))`, 'actual DC polygon hover', 15000);
  records.push({ actualDCHover: await evaluate(`[...document.querySelectorAll('.hoverlayer')].map(node => node.textContent).filter(text => text.includes('DC: $0.00'))`) });
  await evaluate(`[...document.querySelectorAll('.js-plotly-plot')].filter(plot => plot._fullData?.some(trace => trace.fill === 'toself')).forEach(plot => Plotly.Fx.unhover(plot))`);
  await command('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 10, y: 10 });
  await capture('overview-desktop.png');
  // Use actual input widgets. Changes must not affect the applied scope until Apply.
  await evaluate(`document.querySelector('#filters-shops').selectize.setValue(['Canal Bicycle']);
    document.querySelector('#filters-horizon').value = '6';
    document.querySelector('#filters-horizon').dispatchEvent(new Event('change', { bubbles: true }));
    document.querySelector('#filters-forecast_mode').click();`);
  assert.equal(await evaluate(`document.querySelector('.scope-text').innerText`), initial.scope);
  await evaluate(`document.querySelector('#filters-apply').click()`);
  await waitFor(`document.querySelector('.scope-text')?.innerText.includes('Canal Bicycle') && document.querySelector('#forecast_metrics table')?.innerText.includes('Seasonal naive') && document.body.innerText.includes('Future horizon: 6 months') && !document.documentElement.classList.contains('shiny-busy')`, 'coherent applied forecast selection');
  assert.notEqual(await evaluate(`document.querySelector('.kpi-group').innerText`), initial.metrics);
  assert.match(await evaluate('document.body.innerText'), /Synthetic data accuracy says nothing about real retail performance/);
  const appliedCopy = await evaluate(`[...document.querySelectorAll('p')].map(node => node.innerText).filter(text => text.includes('Applied stores:'))`);
  records.push({ appliedFilterCopy: appliedCopy });
  assert.equal(appliedCopy.length, 2);
  assert.ok(appliedCopy.every(text => text.includes('Canal Bicycle. Bike types: Mountain, Road. Families:') && !/ \./.test(text)));
  assert.doesNotMatch(await evaluate('document.body.innerText'), /this PR/i);
  assert.match(await evaluate(`document.querySelector('#forecast_metrics').innerText`), /MAE \(USD\/month\)|MAE/);
  await command('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1440, deviceScaleFactor: 1, mobile: false });
  await waitFor(`document.querySelector('#validation_plot svg.main-svg') && document.querySelector('#future_plot svg.main-svg') && !document.documentElement.classList.contains('shiny-busy')`, 'rendered forecast plots after desktop resize');
  assert.equal(await evaluate('document.documentElement.dataset.smokeDocument'), 'applied-selection-document', 'Resize must retain the applied session.');
  assert.match(await evaluate('document.body.innerText'), /Future horizon: 6 months/);
  await scrollTo('Monthly forecast and validation');
  const forecastFits = await evaluate(`(() => {
    const headings = [...document.querySelectorAll('.chart-title')];
    const forecast = headings.find(node => node.textContent.trim() === 'Monthly forecast and validation').parentElement.getBoundingClientRect();
    const comparison = headings.find(node => node.textContent.trim() === 'Period comparison').parentElement.getBoundingClientRect();
    const future = document.querySelector('#future_plot').getBoundingClientRect();
    return { futureBottom: future.bottom, forecastBottom: forecast.bottom, comparisonTop: comparison.top };
  })()`);
  records.push({ forecastLayout: forecastFits });
  assert.ok(forecastFits.futureBottom <= forecastFits.forecastBottom && forecastFits.forecastBottom <= forecastFits.comparisonTop + 1, 'Forecast plots must fit above the period comparison.');
  await capture('forecast-validation-desktop.png');
  // Invalid Apply preserves the known applied state and gives an actionable message.
  await evaluate(`document.querySelector('#filters-horizon').value = '25'; document.querySelector('#filters-horizon').dispatchEvent(new Event('change', { bubbles: true })); document.querySelector('#filters-apply').click();`);
  await waitFor(`document.querySelector('#filters-error')?.innerText.includes('Changes not applied')`, 'invalid horizon refusal');
  assert.match(await evaluate(`document.querySelector('.scope-text').innerText`), /Canal Bicycle/);
  assert.match(await evaluate('document.body.innerText'), /Future horizon: 6 months/);
  await evaluate(`document.querySelector('#filters-horizon').value = '6'; document.querySelector('#filters-horizon').dispatchEvent(new Event('change', { bubbles: true })); document.querySelector('#filters-apply').click();`);
  await waitFor(`!document.querySelector('#filters-error')?.innerText`, 'valid selection restores feedback');
  await evaluate(`document.querySelector('#view_mode').selectize.setValue('dark')`);
  await waitFor(`document.documentElement.dataset.theme === 'dark'`, 'dark appearance');
  await command('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await waitFor(`document.documentElement.dataset.theme === 'dark' && document.querySelector('.scope-text')?.innerText.includes('Canal Bicycle') && !document.documentElement.classList.contains('shiny-busy')`, 'phone retains applied filters and appearance');
  assert.equal(await evaluate('document.documentElement.dataset.smokeDocument'), 'applied-selection-document', 'Phone resize must retain the applied session.');
  await scrollTo('Period comparison');
  await waitFor(`document.querySelector('.driver-table')?.innerText.includes('Total observed change')`, 'phone comparison');
  const phone = await evaluate(`({ viewport: innerWidth, width: document.documentElement.scrollWidth, body: document.body.innerText, background: getComputedStyle(document.body).backgroundColor, color: getComputedStyle(document.body).color })`);
  records.push({ phoneLayout: phone });
  assert.ok(phone.width <= phone.viewport + 1, 'Phone page must not overflow horizontally.');
  assert.match(phone.body, /Category mix/);
  assert.match(phone.body, /Weighted price/);
  assert.match(phone.body, /Each period has/);
  const tableHeading = await evaluate(`(() => { const style = getComputedStyle(document.querySelector('.driver-table thead th')); return { color: style.color, background: style.backgroundColor }; })()`);
  records.push({ darkContrast: { body: contrast(phone.color, phone.background), heading: contrast(tableHeading.color, tableHeading.background), tableHeading } });
  assert.ok(contrast(phone.color, phone.background) >= 4.5 && contrast(tableHeading.color, tableHeading.background) >= 4.5, 'Dark body and table heading text must have readable contrast.');
  const drivers = await evaluate(`[...document.querySelectorAll('.driver-table tbody tr')].map(row => ({ name: row.cells[0].innerText, value: row.cells[1].innerText, visible: row.getBoundingClientRect().height > 0 && getComputedStyle(row).display !== 'none' }))`);
  records.push({ visibleAccounting: drivers });
  assert.deepEqual(drivers.map(row => row.name), ['Volume', 'Category mix', 'Weighted price', 'Total observed change']);
  assert.ok(drivers.every(row => row.visible), 'All accounting components must remain visible.');
  const amount = value => Number(value.replace(/[^0-9.-]/g, ''));
  assert.ok(Math.abs(drivers.slice(0, 3).reduce((sum, row) => sum + amount(row.value), 0) - amount(drivers[3].value)) <= .02, 'Displayed accounting components must reconcile within cent rounding.');
  await capture('comparison-phone-dark.png');
  // Reset applies every default immediately, with no delayed JavaScript click.
  await evaluate(`document.querySelector('#filters-reset').click()`);
  await waitFor(`document.querySelector('.scope-text')?.innerText === ${JSON.stringify(initial.scope)} && document.querySelector('#filters-horizon')?.value === '12' && !document.querySelector('#filters-forecast_mode')?.checked && !document.documentElement.classList.contains('shiny-busy')`, 'Reset defaults');
  assert.equal(await evaluate(`document.querySelector('.kpi-group').innerText`), initial.metrics);
  // Empty selections must be refused without changing the applied view.
  await evaluate(`document.querySelector('#filters-shops').selectize.clear(); document.querySelector('#filters-apply').click()`);
  await waitFor(`document.querySelector('#filters-error')?.innerText.includes('Select at least one')`, 'empty store refusal');
  assert.equal(await evaluate(`document.querySelector('.scope-text').innerText`), initial.scope);
  assert.deepEqual(exceptions, []);
  assert.deepEqual(protocolErrors, []);
  assert.deepEqual(blocked, [], 'The app must not require external browser assets.');
  records.push({ behavior: 'Apply/invalid horizon/Reset/empty selection', passed: true, phone, exceptions, blocked });
} catch (error) {
  primary = error;
  records.push({ failure: error.stack ?? String(error), exceptions, blocked });
  if (socket?.readyState === WebSocket.OPEN) {
    try {
      await writeFile(join(evidence, 'failure-body.txt'), await evaluate('document.body.innerText'), { flag: 'wx' });
      await writeFile(join(evidence, 'failure-layout.json'), JSON.stringify(await evaluate(`({ viewport: innerWidth, width: document.documentElement.scrollWidth, overflow: [...document.querySelectorAll('body *')].map(node => ({ tag: node.tagName, id: node.id, class: node.className?.baseVal ?? node.className, rect: node.getBoundingClientRect().toJSON() })).filter(node => node.rect.right > innerWidth + 1 || node.rect.left < -1) })`), null, 2), { flag: 'wx' });
      const shot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
      await writeFile(join(evidence, 'failure-view.png'), Buffer.from(shot.data, 'base64'), { flag: 'wx' });
    } catch (error) { records.push({ failureBodyError: error.message }); }
  }
} finally {
  if (socket?.readyState === WebSocket.OPEN) {
    try { await command('Browser.close'); } catch (error) { cleanupErrors.push(error); }
    socket.close();
  }
  let terminal;
  let profileRemoved = false;
  try {
    if (ownership) {
      await signalGroup('SIGTERM');
      for (let attempt = 0; attempt < 50 && (await ownedGroup()).length; attempt++) await delay(100);
      if ((await ownedGroup()).length) await signalGroup('SIGKILL');
      await Promise.race([exited, delay(5000)]);
      for (let attempt = 0; attempt < 50 && (await ownedGroup()).length; attempt++) await delay(100);
      const remaining = await ownedGroup();
      terminal = { created: true, pid: chrome.pid, pgid: chrome.pid, startTicks: ownership.startTicks, reaped: !alive(), exitCode: chrome.exitCode, signal: chrome.signalCode, remaining };
      if (remaining.length || alive()) throw new Error('Chrome group cleanup is not proved.');
      const actual = await lstat(profile);
      assert.ok(actual.isDirectory() && !actual.isSymbolicLink() && actual.dev === profileIdentity.dev && actual.ino === profileIdentity.ino && actual.uid === profileIdentity.uid);
      await rm(profile, { recursive: true, force: true });
      profileRemoved = true;
    } else if (spawnError && !childCreated && chrome.pid === undefined) {
      terminal = { created: false, pid: null, pgid: null, startTicks: null, reaped: false, exitCode: null, signal: null, remaining: [] };
      const actual = await lstat(profile);
      assert.ok(actual.isDirectory() && !actual.isSymbolicLink() && actual.dev === profileIdentity.dev && actual.ino === profileIdentity.ino && actual.uid === process.getuid() && (actual.mode & 0o777) === 0o700);
      assert.deepEqual(await readdir(profile), [], 'An unused profile must be empty.');
      await rmdir(profile);
      profileRemoved = true;
    } else throw new Error('Chrome ownership was not acquired. Profile retained.');
  } catch (error) {
    cleanupErrors.push(error);
  }
  for (const value of pending.values()) clearTimeout(value.timer);
  await writeFile(join(evidence, 'CHROME-TERMINAL.json'), JSON.stringify(terminal ?? { created: childCreated, pid: chrome.pid ?? null, reaped: false, cleanupProved: false }, null, 2) + '\n');
  await writeFile(join(evidence, 'PROFILE-TERMINAL.json'), JSON.stringify({ path: profile, dev: profileIdentity.dev, ino: profileIdentity.ino, exclusivelyCreated: true, noChildCreated: !childCreated, removed: profileRemoved }, null, 2) + '\n');
  await writeFile(join(evidence, 'browser-results.json'), JSON.stringify(records, null, 2) + '\n');
  await writeFile(join(evidence, 'chrome.stderr'), stderr);
  await writeFile(join(evidence, 'ERRORS.json'), JSON.stringify({ primary: primary?.stack ?? null, primaryDetails: primary ? { name: primary.name, message: primary.message, code: primary.code ?? null, errno: primary.errno ?? null, syscall: primary.syscall ?? null, path: primary.path ?? null, spawnargs: primary.spawnargs ?? null } : null, cleanup: cleanupErrors.map(error => error.stack ?? String(error)) }, null, 2) + '\n');
}
if (primary && cleanupErrors.length) throw new AggregateError([primary, ...cleanupErrors], 'Browser check failed and cleanup has errors.', { cause: primary });
if (primary) throw primary;
if (cleanupErrors.length) throw new AggregateError(cleanupErrors, 'Browser cleanup failed.');
console.log('Browser smoke passed. Three actual app captures saved in run evidence.' + (updateImages ? ' Public screenshots updated by explicit opt-in.' : ' Public screenshots unchanged.'));
