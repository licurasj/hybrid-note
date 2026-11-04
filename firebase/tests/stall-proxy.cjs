// Forwards a TCP port to the Firestore emulator and holds back all bytes while
// a followed log file says so: the integration test prints "HOST stall-on" and
// "HOST stall-off" (R2 of the Codex re-review: a commit left waiting on a
// connection that has gone quiet). Usage, in Git Bash on Windows:
//   node firebase/tests/stall-proxy.cjs <log> <listen port> <target port>
const fs = require('node:fs');
const net = require('node:net');

const [log, listen, target] = process.argv.slice(2);
let stalled = false;
// What arrived during a stall, in order, as [socket to write to, bytes].
let held = [];

function forward(from, to) {
  from.on('data', (bytes) => {
    if (stalled) held.push([to, bytes]);
    else to.write(bytes);
  });
  from.on('close', () => to.destroy());
  from.on('error', () => to.destroy());
}

net
  .createServer((client) => {
    const server = net.connect(Number(target), '127.0.0.1');
    forward(client, server);
    forward(server, client);
  })
  .listen(Number(listen), '0.0.0.0');

function handle(line) {
  if (line.includes('HOST stall-on')) {
    stalled = true;
  } else if (line.includes('HOST stall-off')) {
    stalled = false;
    for (const [to, bytes] of held) {
      if (!to.destroyed) to.write(bytes);
    }
    held = [];
  } else if (line.includes('All tests passed') || line.includes('Some tests failed')) {
    process.exit(0);
  } else {
    return;
  }
  console.log(`proxy: stalled ${stalled}`);
}

let read = 0;
let partial = '';
setInterval(() => {
  if (!fs.existsSync(log)) return;
  const bytes = fs.readFileSync(log);
  if (bytes.length <= read) return;
  const lines = (partial + bytes.subarray(read).toString('utf8')).split('\n');
  read = bytes.length;
  partial = lines.pop();
  lines.forEach(handle);
}, 50);
