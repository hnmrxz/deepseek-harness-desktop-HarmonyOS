# hostkit build report (subagent deliverable)

Branch state: **working tree only, nothing committed** (`git status` → `?? hostkit/`, plus
`M .gitignore` and the single allowed row in `docs/README.md`).

## 1. Deliverables and line counts

All paths relative to the repository root.

| file | lines |
|---|---|
| `hostkit/package.json` | 27 |
| `hostkit/README.md` | 383 |
| `hostkit/bin/hostkit.mjs` | 389 |
| `hostkit/src/config.mjs` | 322 |
| `hostkit/src/discovery.mjs` | 326 |
| `hostkit/src/qr.mjs` | 727 |
| `hostkit/src/server.mjs` | 655 |
| `hostkit/src/core/audit.mjs` | 111 |
| `hostkit/src/core/crypto.mjs` | 324 |
| `hostkit/src/core/frames.mjs` | 228 |
| `hostkit/src/core/hostproc.mjs` | 343 |
| `hostkit/src/core/pairing.mjs` | 229 |
| `hostkit/src/core/proxy.mjs` | 237 |
| `hostkit/src/core/tunnel.mjs` | 567 |
| `hostkit/src/core/whitelist.mjs` | 180 |
| `hostkit/src/core/ws.mjs` | 549 |
| `hostkit/src/platform/common.mjs` | 95 |
| `hostkit/src/platform/darwin.mjs` | 65 |
| `hostkit/src/platform/index.mjs` | 30 |
| `hostkit/src/platform/linux.mjs` | 64 |
| `hostkit/src/platform/win32.mjs` | 72 |
| `hostkit/test/audit.test.mjs` | 95 |
| `hostkit/test/cli.test.mjs` | 214 |
| `hostkit/test/config.test.mjs` | 239 |
| `hostkit/test/crypto.test.mjs` | 190 |
| `hostkit/test/discovery.test.mjs` | 199 |
| `hostkit/test/frames.test.mjs` | 135 |
| `hostkit/test/hostproc.test.mjs` | 249 |
| `hostkit/test/index.mjs` | 25 |
| `hostkit/test/pairing.test.mjs` | 170 |
| `hostkit/test/proxy.test.mjs` | 254 |
| `hostkit/test/qr.test.mjs` | 251 |
| `hostkit/test/tunnel.e2e.test.mjs` | 503 |
| `hostkit/test/whitelist.test.mjs` | 148 |
| `hostkit/test/ws.test.mjs` | 326 |
| `hostkit/test/helpers/util.helper.mjs` | 94 |
| `hostkit/test/helpers/qr-decode.helper.mjs` | 462 |
| `hostkit/test/helpers/qr-tables.helper.mjs` | 70 |

Totals: **5548 lines of code** (`src/` + `bin/`), **3624 lines of tests**, **383 lines of README**,
**9582 lines** including `package.json`. 38 files, zero runtime dependencies.

Outside `hostkit/`:

* `.gitignore` — four added lines for hostkit state (`hostkit/node_modules/`, `hostkit/.hostkit/`,
  `hostkit/**/*.pem`, `*.key`, `*.crt`, `*.jsonl`, `*.tmp`).
* `docs/README.md` — exactly one row added to the document table (H1 → `../hostkit/README.md`).

Nothing else was touched. The other `M` entries in `git status` (`appstate/`, `dshcompat/`, `entry/`)
belong to a **parallel agent working in the same checkout** — not this task.

## 2. Test command and observed output

```
cd hostkit
node --test                 # auto-discovery, all 13 suites
node --test test/index.mjs  # same, explicit entry point
npm test                    # -> node --test test/index.mjs
```

Latest run:

```
# tests 295
# suites 0
# pass 295
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 44479.8862
```

`npm test` runs the 13 suites through `test/index.mjs` and reports **146** tests (the entry point loads
each suite once); `node --test` additionally discovers the mixed `*.test.mjs` files individually and
reports **295**. Both are green.

**Platform caveat, verified:** the task book's literal command `node --test test/` fails on
**Node 22.20.0 / Windows** with `Cannot find module '…\hostkit\test'` — that build treats a non-glob
path argument as a module specifier rather than a directory to search (verified for `test`, `./test/`,
and with `--test-name-pattern`). `test/index.mjs` exists so the directory form can be emulated, and the
README documents the working commands. On Node builds that do scan directories, `node --test test/`
loads `test/index.mjs` and runs the whole suite.

### Required coverage, item by item

| Requirement | Where |
|---|---|
| crypto round-trip | `crypto.test.mjs` — seal/open in both directions, nonce uniqueness |
| tamper detection | ciphertext, tag, counter, direction byte and nonce prefix each rejected |
| replay rejection | byte-identical replay **and** out-of-order delivery rejected; cross-session frame fails to authenticate |
| ws handshake/frame round trip incl. >125 B and >64 KiB | `ws.test.mjs` — 2 B, 200 B, 70 000 B; 7/16/64-bit lengths |
| masking verification | server rejects an unmasked client frame; server frames carry no mask bit (raw bytes); `connect()` masks on the wire (raw net server) |
| pairing expiry + token reuse rejection | `pairing.test.mjs` — fake clock expiry, one-time burn, second-device refusal, wrong-token non-DoS |
| whitelist revoke | `whitelist.test.mjs` — sticky across reload, live-session teardown asserted in e2e |
| audit append+query | `audit.test.mjs` — tail, filters, torn-last-line tolerance, disabled mode |
| full end-to-end tunnel | `tunnel.e2e.test.mjs` — fake dsh host on loopback (`POST /api/ping` + `/api/remote.mux` WS echo), device paired in-test, one HTTP call and one WS round trip driven through the tunnel, plus too-large, 404 passthrough, heartbeat survival, unpaired refusal, revoke-while-live |
| discovery | `discovery.test.mjs` — real UDP announce→listen round trip, junk rejection, target list |

Extra suites beyond the required list: `config.test.mjs` (platform layer + loopback guard),
`hostproc.test.mjs` (announce parsing, backoff ladder, give-up cap with injected spawn),
`proxy.test.mjs` (loopback exit semantics), `cli.test.mjs` (real child-process CLI runs, QR raster,
pairing URI, exit codes), `qr.test.mjs` (independent decoder + closed-form table checks).

## 3. Task-book items — satisfied

1. **§6.5 保活与代持** — `src/core/hostproc.mjs` spawns only the official CLI and parses its stdout.
   The announce format is read from the upstream source (`dsh-web-app/lib/index.js`:
   `console.log(\`dsh web: \${authenticatedUrl}\${lanUrl …}\`)`), not guessed, and the token is parsed for
   diagnostics only — hostkit never stores it. Backoff 500 ms → 1 s → 2 s → 4 s → 8 s → 10 s, cap 5
   restarts/minute then give up. SIGINT/SIGTERM stop the child by pid (and process group on POSIX).
2. **§6.5 发现** — `src/discovery.mjs`, UDP broadcast on port 8799, announce every 3 s, directed
   broadcasts per interface, `hostkit discover`.
3. **§6.5 配对** — 120 s window, one-time `pairId` burned on success, 32-byte `pairToken`
   constant-time compare, whitelist write (temp + fsync + rename, mode 0600), audit on success **and**
   rejection, plus `devices` / `revoke` / `audit` / `status`.
4. **§6.5 隧道** — `/tunnel`, E2E-sealed frames, 2 s heartbeat mirroring the dsh mux, exit always
   `127.0.0.1:<dshPort>`, TLS optional and additive.
5. **§6.4 L1 security** — explicit pairing with a one-time key; unpaired devices always refused;
   per-device revocation with immediate session teardown; the Host is never exposed; no `Host`/`Origin`
   forgery anywhere (the client's headers pass through untouched).
6. **Zero dependencies** — `dependencies: {}`; RFC 6455 server **and** client implemented in
   `src/core/ws.mjs` (client frames masked, verified on the wire); QR encoder implemented in
   `src/qr.mjs` (byte mode, EC level M, version auto) and verified by an independent decoder.
7. **Never binds the dsh Host past loopback** — `assertLoopbackHost` runs in the `HostkitServer`
   constructor, before any socket, discovery or supervision exists.
8. **Zero upstream patches / optional component / no name-based process killing** — enforced in code
   and asserted in tests.
9. **Cross-platform** — `src/platform/{index,win32,darwin,linux,common}.mjs` isolate spawn flags, state
   directory, cert directory, LAN enumeration and the pid-scoped kill command.
10. **Audit** — append-only JSONL with `hostkit.start/stop`, `pair.window.*`, `pair.success/reject`,
    `tunnel.open/close/reject`, `device.revoke`, `host.spawn/exit/restart/giveup`.
11. **README** — purpose, quick start, the full wire-protocol tables, the L1/L2 threat model, and an
    explicit Limitations section (below).

## 4. Deviations (also listed in `hostkit/README.md` §Limitations)

| # | Deviation | Reason |
|---|---|---|
| 1 | **UDP broadcast instead of mDNS** | No zero-dependency mDNS for Node; ArkTS would need `@ohos.net.mdns` or a hand-written DNS-SD parser; discovery is a convenience and pairing works from a typed URI/6-digit code |
| 2 | **Self-signed TLS optional, not mandatory** | The payload is E2E-sealed before the transport, so TLS only protects the plaintext hello and the pairing token. `--tls-selfsigned` shells out to `openssl` and fails loudly rather than silently downgrading |
| 3 | **TLS and plaintext cannot share one port** | Would need SNI-style protocol sniffing on the raw socket; with `--cert`/`--key` the listener serves `https`/`wss` only |
| 4 | **6-digit manual code is a display convenience** | Derived from the pairing token for typing; the server still requires the full `pairId` + `pairToken` |
| 5 | **CLI `revoke` does not reach a running server's live sessions** | It updates the whitelist (device cannot reconnect) and audits; immediate teardown of a live session goes through `HostkitServer.revoke`. Cross-process revocation would need an admin route that was out of scope |
| 6 | **`/state` + `/audit` authenticate with the pairing token or a per-run admin token** | No dedicated device-key-authenticated status API yet |
| 7 | **`--pair` is a flag on `start`** | A window opened this way closes on first success or expiry |
| 8 | **One pairing window at a time** | A new window supersedes the previous one |
| 9 | **Upstream stdout is parsed for diagnostics, not its state** | Health is "any HTTP status from `GET /` on loopback" |
| 10 | **Windows child reclaim is `taskkill /PID <pid> /T /F`** | Pid-scoped; a SIGKILL-resistant child may survive hostkit's exit, and hostkit never falls back to name matching |
| 11 | **`ws-data` gained an optional `t` field (`"b"`/`"t"`)** | The documented envelope has no text/binary flag, but the dsh mux frames are JSON *text*; absent `t` means binary, so the documented shape still interoperates |
| 12 | **`node --test test/` does not work on Node 22.20/Windows** | Runner platform quirk (see §2); `test/index.mjs` + documented commands replace it |

## 5. Not verified / what I could not check

* **No real phone or ArkTS client has connected.** The e2e test uses a fake dsh host (plain `node:http`)
  and a device paired through the real `POST /pair` endpoint.
* **The real `dsh` CLI is no longer installed in this checkout.** Early in the session I ran
  `node …/@deepseek-ai/dsh/lib/bin.js web --no-open --port 3122` with a scratch `DSH_HOME` and got the
  real announce line (`dsh web: http://127.0.0.1:3122/?token=WMk1FI0pPbEEIMVD72sgalTE6DtU96ezrLzE5s8wLIY`),
  and later ran `hostkit start --dsh-cmd "<node> <bin.js> web --no-open --host 127.0.0.1 --port 3123"`,
  which spawned the child and reported its exit. **However**, partway through the session the desktop
  app appears to have replaced `@deepseek-ai/dsh` (its `lib/` directory is now empty), so the real-CLI
  launch path could not be re-verified at the end and the supervised child now exits 1. What *was*
  observed end to end in that run: the listener came up on 8877, `/health` answered, the supervisor
  spawned the child with exactly the argv from `--dsh-cmd`, detected the unexpected exit, walked the
  500/1000/2000/4000/8000 ms ladder, wrote `host.spawn`/`host.exit`/`host.restart`/`host.giveup` to the
  audit log, and terminated the child on SIGINT. The announce-line parser is tested against the exact
  upstream format string taken from the upstream source.
* **The QR code has never been scanned by a camera.** It is verified by
  `test/helpers/qr-decode.helper.mjs`, an independent decoder (its own un-masking, de-interleaving,
  Berlekamp–Massey and Forney, its own duplicated ISO/IEC 18004 tables), plus closed-form checks that
  both table copies reproduce `(16v+128)v+64 − …` for all 40 versions × 4 levels and that the
  implemented function-module geometry leaves exactly the formula's data-module count.
* **TLS is untested.** `resolveTls` and `mintSelfSigned` exist and fail loudly, but no test starts a
  `wss` listener; `--tls-selfsigned` depends on an `openssl` binary and is untested.
* **Discovery only exercised on loopback and one LAN interface.** Directed-broadcast behaviour across
  multiple interfaces and Wi-Fi client isolation are not covered.
* **No load/soak testing**, and the audit log is not fsync'd per record.

## 6. Notable bugs found and fixed while building (for reviewers)

These were caught by the tests and are worth knowing about because each would have been a silent
failure in production:

1. **`SealedChannel` rejected its own first frame** — `lastRecvSeq` started at `0n`, so counter `0`
   failed the strictly-increasing check. Now `-1n`.
2. **QR interleave allocated one codeword too many** — `numBlocks * (short + ec) + numShortBlocks`
   instead of `+ (numBlocks - numShortBlocks)`, which shifted every version's codeword stream.
3. **QR function modules were tracked with a `0xff` sentinel** — a function module legitimately written
   as `0` looked like free data space, so the zig-zag placement shifted by one bit. Now a parallel
   `reserved` bitmap.
4. **QR alignment patterns were drawn with swapped axes** — a symbol that still "looked like" a QR code
   but would not scan.
5. **`WsConnection.finish()` called `socket.destroy(clean)`** — `destroy(error)` only *records* the
   error and does not tear the socket down, leaking the descriptor and hanging `server.close()`
   (and therefore hostkit shutdown) indefinitely.
6. **`send(data, {binary:false})` could not send a text frame from a `Buffer`** — the dsh mux frames are
   JSON text; now an explicit `binary` option always wins.
7. **`hostkit stop()` hung on upgraded sockets** — the HTTP server does not account for sockets handed to
   an `upgrade` listener, so `server.close()` waited forever; now sessions are destroyed explicitly and
   `closeAllConnections()` is used.
8. **`valueFlag.number` was declared for the numeric flags but not for `--port`/`--discovery-port`/`--dsh-port`**,
   so ports were parsed as strings and silently fell back to defaults.
9. **`parseArgv` reported unknown flags but `loadConfig` did not** surface them to the CLI (fixed).
10. **`AuditLog.append` threw when its directory was removed while running** — now re-creates the
    directory so a shutdown record is never lost.

## 7. Housekeeping note (encoding)

A `Set-Content` round-trip I used to bulk-update import paths re-encoded six test files through the
system ANSI code page, mangling non-ASCII characters. All six were repaired programmatically and are
now plain ASCII (`qr.test.mjs` was rewritten from scratch). All assertions are ASCII-only, all 295
tests pass, and no file in `hostkit/` contains non-ASCII or control characters any more. A few comments
that previously used an em dash or an arrow now use `-`/`->`.
