// バックグラウンド検証用のWebSocketサーバー。依存パッケージなしで動く。
// 5秒ごとに連番を全端末へ送り、6回に1回（30秒ごと）は通知の合図を付ける。
// 標準入力で n を押すとすぐに通知の合図を送り、q で終了する。

import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { networkInterfaces } from 'node:os';
import { createInterface } from 'node:readline';

const PORT = Number(process.env.PORT ?? 8080);
const INTERVAL_MS = 5000;
const NOTIFY_EVERY = 6;
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

const clients = new Set();
let seq = 0;

function textFrame(text) {
  const payload = Buffer.from(text);
  let header;
  if (payload.length < 126) {
    header = Buffer.from([0x81, payload.length]);
  } else {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(payload.length, 2);
  }
  return Buffer.concat([header, payload]);
}

function controlFrame(opcode, payload = Buffer.alloc(0)) {
  return Buffer.concat([Buffer.from([0x80 | opcode, payload.length]), payload]);
}

// 端末から届くのはpingとcloseだけなので、1チャンクに1フレームとみなして読む
function readControlFrame(chunk) {
  const opcode = chunk[0] & 0x0f;
  const length = chunk[1] & 0x7f;
  const masked = (chunk[1] & 0x80) !== 0;
  if (!masked || length >= 126) return { opcode, payload: Buffer.alloc(0) };
  const mask = chunk.subarray(2, 6);
  const payload = Buffer.from(chunk.subarray(6, 6 + length));
  for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
  return { opcode, payload };
}

function log(message) {
  const time = new Date().toLocaleTimeString('ja-JP', { hour12: false });
  console.log(`${time} ${message}`);
}

function broadcast(notify) {
  seq += 1;
  const message = {
    seq,
    server_time: new Date().toISOString(),
    notify,
    ...(notify ? { text: `#${seq} の合図です` } : {}),
  };
  const frame = textFrame(JSON.stringify(message));
  for (const socket of clients) socket.write(frame);
  log(`送信 #${seq}${notify ? '（通知の合図）' : ''} → ${clients.size}台`);
}

const server = createServer((_req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('WebSocketで接続してください\n');
});

server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) {
    socket.destroy();
    return;
  }
  const accept = createHash('sha1').update(key + WS_GUID).digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
  );
  const peer = `${socket.remoteAddress}:${socket.remotePort}`;
  clients.add(socket);
  log(`接続 ${peer}（${clients.size}台）`);

  socket.on('data', (chunk) => {
    const { opcode, payload } = readControlFrame(chunk);
    if (opcode === 0x9) socket.write(controlFrame(0xa, payload));
    if (opcode === 0x8) socket.end(controlFrame(0x8));
  });
  const remove = () => {
    if (clients.delete(socket)) log(`切断 ${peer}（${clients.size}台）`);
  };
  socket.on('close', remove);
  socket.on('error', remove);
});

server.listen(PORT, () => {
  log(`ポート ${PORT} で待ち受けています。アプリには次のどれかを入力してください`);
  for (const addresses of Object.values(networkInterfaces())) {
    for (const address of addresses ?? []) {
      if (address.family === 'IPv4' && !address.internal) console.log(`  ws://${address.address}:${PORT}`);
    }
  }
  console.log('n + Enter: すぐに通知の合図を送る / q + Enter: 終了');
});

setInterval(() => broadcast(seq % NOTIFY_EVERY === NOTIFY_EVERY - 1), INTERVAL_MS);

createInterface({ input: process.stdin }).on('line', (line) => {
  const command = line.trim();
  if (command === 'n') broadcast(true);
  if (command === 'q') process.exit(0);
});
