// Forwards a TCP port to the Firestore emulator and stops passing bytes while
// a followed log file says so: the integration test prints "HOST stall-on" and
// "HOST stall-off" (R2 of the Codex re-review: a commit left waiting on a
// connection that has gone quiet). Usage, in Git Bash on Windows:
//   node firebase/tests/stall-proxy.js <log> <listen port> <target port>
const fs = require('node:fs');
const net = require('node:net');

const [log, listen, target] = process.argv.slice(2);
let stalled = false;
const sockets = new Set();

function apply(socket) {
  if (stalled) socket.pause();
  else socket.resume();
}

net
  .createServer((client) => {
    const server = net.connect(Number(target), '127.0.0.1');
    for (const [from, to] of [
      [client, server],
      [server, client],
    ]) {
      sockets.add(from);
      from.on('close', () => {
        sockets.delete(from);
        to.destroy();
      });
      from.on('error', () => to.destroy());
      from.pipe(to);
      apply(from);
    }
  })
  .listen(Number(listen), '0.0.0.0');

let read = 0;
setInterval(() => {
  if (!fs.existsSync(log)) return;
  const size = fs.statSync(log).size;
  if (size <= read) return;
  const text = fs.readFileSync(log, 'utf8').slice(read);
  read = size;
  for (const line of text.split('\n')) {
    if (line.includes('HOST stall-on')) stalled = true;
    else if (line.includes('HOST stall-off')) stalled = false;
    else if (line.includes('All tests passed') || line.includes('Some tests failed')) process.exit(0);
    else continue;
    console.log(`proxy: stalled ${stalled}`);
    sockets.forEach(apply);
  }
}, 100);
