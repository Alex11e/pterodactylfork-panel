// Real nginx + mock Wings transport checks. Usage: node gateway-proxy.mjs <php> <nginx>
// Run from a scratch directory; the temporary nginx config and logs stay there.
import assert from 'node:assert/strict';
import http from 'node:http';
import { createHash, randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const [php, nginx] = process.argv.slice(2).map(p => resolve(p));
const here = dirname(fileURLToPath(import.meta.url));
const scratch = mkdtempSync(join(process.cwd(), 'gateway-test-'));
mkdirSync(join(scratch, 'logs'));
mkdirSync(join(scratch, 'temp'));
const sockets = new Set();
const observed = [];
const origin = 'https://panel.example.com';
const uuid = '12345678-1234-1234-1234-123456789abc';
const download = randomBytes(256 * 1024);
let checks = 0;
const check = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };

function frame(text, masked = false, opcode = 1) {
    const data = Buffer.from(text);
    const large = data.length >= 126;
    const header = Buffer.alloc(large ? 4 : 2);
    header[0] = 0x80 | opcode;
    header[1] = (masked ? 0x80 : 0) | (large ? 126 : data.length);
    if (large) header.writeUInt16BE(data.length, 2);
    if (!masked) return Buffer.concat([header, data]);
    const mask = randomBytes(4);
    for (let i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
    return Buffer.concat([header, mask, data]);
}
function readFrames(socket, callback) {
    let pending = Buffer.alloc(0);
    socket.on('data', chunk => {
        pending = Buffer.concat([pending, chunk]);
        while (pending.length >= 2) {
            let length = pending[1] & 127;
            let offset = 2;
            if (length === 126) {
                if (pending.length < 4) return;
                length = pending.readUInt16BE(2); offset = 4;
            }
            const masked = Boolean(pending[1] & 128);
            if (pending.length < offset + (masked ? 4 : 0) + length) return;
            const opcode = pending[0] & 15;
            const mask = masked ? pending.subarray(offset, offset + 4) : null;
            if (masked) offset += 4;
            const data = Buffer.from(pending.subarray(offset, offset + length));
            pending = pending.subarray(offset + length);
            if (mask) for (let i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
            callback(data, opcode);
        }
    });
}
function mockWings(id) {
    const server = http.createServer(async (req, res) => {
        observed.push({ id, url: req.url, headers: req.headers });
        res.setHeader('Access-Control-Allow-Origin', origin);
        res.setHeader('Set-Cookie', 'must-not-reach-panel=1');
        if (req.method === 'OPTIONS') { res.writeHead(204).end(); return; }
        if (!req.url.includes('token=valid')) { res.writeHead(401).end(); return; }
        if (req.url.startsWith('/upload/file')) {
            const chunks = []; for await (const chunk of req) chunks.push(chunk);
            res.end(createHash('sha256').update(Buffer.concat(chunks)).digest('hex'));
        } else {
            res.setHeader('Content-Disposition', 'attachment; filename="test.bin"');
            res.end(download);
        }
    });
    server.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });
    server.on('upgrade', (req, socket) => {
        observed.push({ id, url: req.url, headers: req.headers });
        if (req.headers.origin !== origin) { socket.end('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n'); return; }
        const accept = createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
        socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
        let authenticated = false;
        readFrames(socket, (data, opcode) => {
            if (opcode === 8) { socket.end(frame(data, false, 8)); return; }
            const message = JSON.parse(data.toString());
            if (message.event === 'auth') {
                authenticated = message.args[0] === 'valid' || message.args[0] === 'renewed';
                socket.write(frame(JSON.stringify({ event: authenticated ? 'auth success' : 'jwt error', args: [] })));
            } else if (authenticated) {
                socket.write(frame(JSON.stringify({ event: 'console output', args: message.args })));
            }
        });
    });
    return server;
}
const wings1 = mockWings(1), wings2 = mockWings(2);
let child;
const watchdog = setTimeout(() => { throw new Error('Gateway tests timed out'); }, 30000);
try {
    wings1.listen(0, '127.0.0.1'); wings2.listen(0, '127.0.0.1');
    await Promise.all([once(wings1, 'listening'), once(wings2, 'listening')]);
    const portReservation = http.createServer(); portReservation.listen(0, '127.0.0.1'); await once(portReservation, 'listening');
    const port = portReservation.address().port; await new Promise(r => portReservation.close(r));
    const rendered = spawnSync(php, [join(here, 'render-gateway-fixture.php'), String(wings1.address().port), String(wings2.address().port)], { encoding: 'utf8', windowsHide: true });
    assert.equal(rendered.status, 0, rendered.error?.message || rendered.stderr);
    writeFileSync(join(scratch, 'nginx.conf'), `daemon off;\nworker_processes 1;\nerror_log logs/error.log;\npid logs/nginx.pid;\nevents { worker_connections 128; }\nhttp { access_log off; client_body_temp_path temp/body; proxy_temp_path temp/proxy; fastcgi_temp_path temp/fastcgi; uwsgi_temp_path temp/uwsgi; scgi_temp_path temp/scgi; server { listen 127.0.0.1:${port};\n${rendered.stdout}\nlocation / { return 404; } } }`);
    const prefix = scratch.replaceAll('\\', '/') + '/';
    const args = ['-p', prefix, '-c', 'nginx.conf'];
    const syntax = spawnSync(nginx, [...args, '-t'], { cwd: scratch, encoding: 'utf8', windowsHide: true });
    assert.equal(syntax.status, 0, syntax.stderr); checks++;
    child = spawn(nginx, args, { cwd: scratch, windowsHide: true, stdio: 'ignore' });
    const base = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let i = 0; i < 50; i++) {
        try { await fetch(base); ready = true; break; } catch { await new Promise(r => setTimeout(r, 50)); }
    }
    assert.ok(ready, 'nginx startup failed');
    for (const path of ['/_wings/99/download/file', '/_wings/1/api/system', '/_wings/1/api/servers', '/_wings/1/api/update', '/_wings/1/download/file/extra']) {
        const before = observed.length;
        check((await fetch(base + path)).status, 404); check(observed.length, before);
    }
    check((await fetch(base + '/_wings/1/download/file', { method: 'DELETE' })).status, 405);
    check((await fetch(base + '/_wings/1/download/file')).status, 401);
    check((await fetch(base + '/_wings/1/download/file', { method: 'OPTIONS' })).status, 204);
    const response = await fetch(base + '/_wings/2/download/file?token=valid&name=a%2Fb', { headers: { Cookie: 'panel-session=secret', Authorization: 'Bearer secret', 'X-CSRF-TOKEN': 'secret', Origin: origin } });
    check(response.status, 200);
    check(Buffer.from(await response.arrayBuffer()), download);
    check(response.headers.get('set-cookie'), null);
    check(response.headers.get('content-disposition'), 'attachment; filename="test.bin"');
    check(response.headers.get('content-security-policy'), "sandbox; default-src 'none'");
    const received = observed.at(-1);
    check(received.id, 2); check(received.url, '/download/file?token=valid&name=a%2Fb');
    check(received.headers.cookie, undefined); check(received.headers.authorization, undefined);
    check(received.headers['x-csrf-token'], undefined); check(received.headers.origin, origin);
    const upload = randomBytes(2 * 1024 * 1024);
    const uploadResponse = await fetch(base + '/_wings/1/upload/file?token=valid&directory=%2F', { method: 'POST', body: upload });
    check(await uploadResponse.text(), createHash('sha256').update(upload).digest('hex'));
    check(observed.at(-1).url, '/upload/file?token=valid&directory=%2F');
    check((await fetch(base + '/_wings/1/download/backup?token=valid')).status, 200);
    const openWs = originValue => new Promise((resolveWs, reject) => {
        const req = http.request(base + `/_wings/1/api/servers/${uuid}/ws`, { headers: { Connection: 'Upgrade', Upgrade: 'websocket', Origin: originValue, 'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': randomBytes(16).toString('base64') } });
        req.on('upgrade', (res, socket) => resolveWs({ status: res.statusCode, socket }));
        req.on('response', res => { res.resume(); resolveWs({ status: res.statusCode }); });
        req.on('error', reject); req.end();
    });
    check((await openWs('https://untrusted.example.com')).status, 403);
    const { status, socket } = await openWs(origin); check(status, 101);
    const messages = [], waiters = [];
    readFrames(socket, data => { const message = JSON.parse(data.toString()); if (waiters.length) waiters.shift()(message); else messages.push(message); });
    const next = () => messages.length ? Promise.resolve(messages.shift()) : new Promise(r => waiters.push(r));
    const send = (event, arg) => socket.write(frame(JSON.stringify({ event, args: [arg] }), true));
    send('auth', 'invalid'); check((await next()).event, 'jwt error');
    send('auth', 'valid'); check((await next()).event, 'auth success');
    send('send command', 'status'); check(await next(), { event: 'console output', args: ['status'] });
    send('auth', 'renewed'); check((await next()).event, 'auth success');
    send('send command', 'x'.repeat(7000)); check((await next()).args[0], 'x'.repeat(7000));
    socket.destroy();
    const reconnect = await openWs(origin); check(reconnect.status, 101); reconnect.socket.destroy();
    console.log(`PASS: ${checks} real nginx HTTP/WebSocket transport checks (mock Wings)`);
} finally {
    clearTimeout(watchdog);
    if (child) spawnSync(nginx, ['-p', scratch.replaceAll('\\', '/') + '/', '-c', 'nginx.conf', '-s', 'stop'], { cwd: scratch, windowsHide: true });
    for (const socket of sockets) socket.destroy();
    wings1.close(); wings2.close();
}
