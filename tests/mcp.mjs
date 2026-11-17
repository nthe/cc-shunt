import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, symlinkSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const work = mkdtempSync(join(tmpdir(), 'shunt-mcp-check.'));
const root = join(work, 'project\n'), record = join(work, 'record');
mkdirSync(root); mkdirSync(record);
const file = 'a \'quoted\nfile\n';
writeFileSync(join(root, file), 'value = 42\n');
writeFileSync(join(root, file.slice(0, -1)), 'wrong file\n');
writeFileSync(join(work, 'outside'), 'outside');
symlinkSync(join(work, 'outside'), join(root, 'escape'));
symlinkSync(work, join(root, 'outside-folder'));
symlinkSync(file, join(root, 'inside-link'));
const pause = ms => new Promise(r => setTimeout(r, ms));
const quote = s => `'${s.replaceAll("'", "'\\''")}'`;
const clients = [];
function client(env = {}) {
  const child = spawn('bash', ['scripts/mcp-reader', '--root', root, '--backend', 'command'], {
    env: { ...process.env, SHUNT_ACTIVE: '', RECORD: record,
      SHUNT_COMMAND: quote(resolve('tests/stub-worker')), ...env }, stdio: ['pipe', 'pipe', 'pipe'],
  });
  const waiting = new Map(), messages = [];
  let buffer = '', stderr = '';
  child.stderr.on('data', b => { stderr += b; });
  child.stdout.on('data', b => {
    buffer += b;
    while (buffer.includes('\n')) {
      const at = buffer.indexOf('\n'), line = buffer.slice(0, at); buffer = buffer.slice(at + 1);
      const message = JSON.parse(line); messages.push(message);
      const pending = waiting.get(message.id);
      if (pending) { waiting.delete(message.id); clearTimeout(pending.timer); pending.resolve(message); }
    }
  });
  const closed = new Promise(resolve => child.on('close', (code, signal) => {
    for (const p of waiting.values()) { clearTimeout(p.timer); p.reject(Error(`Server closed: ${code}/${signal}: ${stderr}`)); }
    waiting.clear(); resolve(code);
  }));
  function request(id, method, params = {}) {
    const promise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => { waiting.delete(id); reject(Error(`No reply for ${id}: ${stderr}`)); }, 7000);
      waiting.set(id, { resolve, reject, timer });
    });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    return promise;
  }
  const api = { child, messages, request, closed,
    initialize: () => request('init', 'initialize', { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'check', version: '1' } }),
    call: (id, paths = [file]) => request(id, 'tools/call', { name: 'bulk_read', arguments: { question: 'What value?', paths } }),
    close: async () => { child.stdin.end(); const code = await closed; assert.equal(code, 0, stderr); },
    cancel: id => {
      const p = waiting.get(id); waiting.delete(id); clearTimeout(p.timer); p.resolve(null);
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/cancelled', params: { requestId: id } }) + '\n');
    },
  };
  clients.push(api); return api;
}
async function until(fn) { for (let i = 0; i < 100; i++) { if (fn()) return; await pause(25); } throw Error('Condition timed out'); }
function stopped(pid) { try { process.kill(pid, 0); return false; } catch (e) { if (e.code === 'ESRCH') return true; throw e; } }
let checks = 0;
try {
  const c = client();
  assert.equal((await c.initialize()).result.protocolVersion, '2025-03-26');
  assert.equal((await c.request('list', 'tools/list')).result.tools[0].name, 'bulk_read');
  const answer = await c.call(0);
  assert.equal(answer.result.isError, false);
  assert.equal(answer.result.content[0].text.trim(), 'short answer');
  assert.match(readFileSync(join(record, 'prompt'), 'utf8'), /1\tvalue = 42/);
  const scout = await c.request('scout', 'tools/call', { name: 'scout', arguments: { task: 'Trace the value', paths: ['.'] } });
  assert.equal(scout.result.isError, false, JSON.stringify(scout));
  const scoutPrompt = readFileSync(join(record, 'prompt'), 'utf8');
  assert.match(scoutPrompt, /Trace the value/);
  assert.match(scoutPrompt, /starting paths/);
  assert.ok(!scoutPrompt.includes('value = 42'), 'Scout must discover content in its own context');
  assert.equal(readFileSync(join(record, 'cwd'), 'utf8'), realpathSync(root) + '\n');
  assert.equal((await c.request('scout-escape', 'tools/call', { name: 'scout', arguments: { task: 'Trace', paths: ['outside-folder'] } })).error.code, -32602);
  assert.equal((await c.request('scout-empty', 'tools/call', { name: 'scout', arguments: { task: ' ', paths: ['.'] } })).error.code, -32602);
  assert.equal((await c.call('inside-link', ['inside-link'])).result.isError, false);
  assert.match(readFileSync(join(record, 'prompt'), 'utf8'), /1\tvalue = 42/);
  checks++;
  for (const path of ['../outside', 'escape', 'outside-folder/outside']) assert.equal((await c.call(path, [path])).error.code, -32602);
  assert.equal((await c.request('bad', 'tools/call', { name: 'bulk_read', arguments: { question: 'x', paths: [file], extra: true } })).error.code, -32602);
  assert.equal((await c.request(null, 'ping')).error.code, -32600);
  checks++;
  const fragment = JSON.stringify({ jsonrpc: '2.0', id: 'fragment', method: 'ping' });
  c.child.stdin.write(fragment.slice(0, 12));
  await pause(1100);
  c.child.stdin.write(fragment.slice(12) + '\n');
  await until(() => c.messages.some(m => m.id === 'fragment'));
  assert.deepEqual(c.messages.find(m => m.id === 'fragment').result, {});
  checks++;
  rmSync(join(record, 'prompt'));
  writeFileSync(join(root, 'binary'), Buffer.from([0]));
  assert.equal((await c.call('binary', ['binary'])).result.isError, true);
  assert.equal(existsSync(join(record, 'prompt')), false);
  await c.close(); checks++;

  const slow = join(work, 'slow');
  writeFileSync(slow, '#!/usr/bin/env bash\ncat >/dev/null\nsleep 2\nprintf "done\\n"\n', { mode: 0o755 });
  const d = client({ SHUNT_COMMAND: quote(slow) }); await d.initialize();
  const start = Date.now(), done = d.call('slow');
  assert.equal((await d.request('ping', 'ping')).result.constructor, Object);
  assert.equal((await d.call('busy')).error.code, -32000);
  assert.equal((await done).result.content[0].text.trim(), 'done');
  assert.ok(Date.now() - start >= 2000);
  assert.equal(d.messages.filter(m => m.id === 'slow').length, 1);
  await d.close(); checks++;

  rmSync(join(record, 'child'), { force: true });
  const cancel = client({ WAIT: '1' }); await cancel.initialize();
  const cancelled = cancel.call('cancel');
  await until(() => existsSync(join(record, 'child')));
  const cancelledPid = Number(readFileSync(join(record, 'child'), 'utf8'));
  cancel.cancel('cancel'); await cancelled;
  await cancel.request('after-cancel', 'ping');
  await until(() => stopped(cancelledPid));
  assert.equal(cancel.messages.some(m => m.id === 'cancel'), false);
  await cancel.close(); checks++;

  rmSync(join(record, 'child'), { force: true });
  const timeout = client({ WAIT: '1', SHUNT_TIMEOUT_SECONDS: '1' }); await timeout.initialize();
  const timed = await timeout.call('timeout');
  assert.equal(timed.result.isError, true); assert.match(timed.result.content[0].text, /time limit/);
  await until(() => stopped(Number(readFileSync(join(record, 'child'), 'utf8'))));
  await timeout.close(); checks++;

  rmSync(join(record, 'child'), { force: true });
  const eof = client({ WAIT: '1' }); await eof.initialize();
  const interrupted = eof.call('eof').catch(() => null);
  await until(() => existsSync(join(record, 'child')));
  const eofPid = Number(readFileSync(join(record, 'child'), 'utf8'));
  await eof.close(); await interrupted;
  await until(() => stopped(eofPid)); checks++;

  const large = join(work, 'large');
  writeFileSync(large, '#!/usr/bin/env bash\ncat >/dev/null\nhead -c 200000 /dev/zero | tr "\\000" x\n', { mode: 0o755 });
  const l = client({ SHUNT_COMMAND: quote(large) }); await l.initialize();
  assert.equal((await l.call('large')).result.content[0].text.length, 200000);
  await l.close(); checks++;
} finally {
  for (const c of clients) if (c.child.exitCode === null) { c.child.kill('SIGTERM'); await c.closed; }
  rmSync(work, { recursive: true, force: true });
}
console.log(`MCP reader: ${checks} checks passed`);
