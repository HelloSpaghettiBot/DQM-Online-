# Protocol 2

Shared RPC node path: `/root/Main/Net`; source `shared/net.gd`.
Transport: production WSS at `wss://403world.com/DQM/ws`; local test ENet at
127.0.0.1:24778. Production WebSocket server binds loopback behind nginx TLS.

All client RPCs derive identity from `get_remote_sender_id()`. A submitted peer
ID selects a target for an invitation only, never an acting account. Server
event methods require authority. Clients have no administrative/reward methods.

| Request | Fields / checks |
| --- | --- |
| login | username, 64-hex one-use ticket, protocol=2; 10-second deadline |
| chat | plain text, 1–240 characters, no control characters, burst/rate limit |
| presence | increasing sequence; byte map/room/x/y/state; facing 0–3; 10 Hz |
| invite | target peer; kind Challenge/Trade/Breed; no self/busy targets |
| answer | pending random invitation ID; only invitee; expires after 30 sec |
| serial | current link ID; consecutive sequence; even-length byte/mode pairs |
| end_link | ends caller's current pair; disconnect also tears it down |
| heartbeat | increasing client sequence echoed by server; 1 Hz client, 5-second client / 8-second server deadlines |
| list_games | caller's slot, revision, UTC timestamp metadata only |
| load_game | slot 1–3, account derived from authenticated peer; issues a new per-load save token |
| save_game | active slot, token, current revision, exactly 32768 bytes SRAM, 1024–262144 bytes emulator checkpoint; no active link |
| backup / restore_backup | legacy RPCs rejected; no local-to-server backup overwrite route |

Serial modes: 0=normal request, 1=fast request, 128=response. Maximum 2048 bytes
per RPC, bounded queues and aggregate rates. The server forwards only within a
consented pair. The emulator serial wait times out after 2 seconds and can be
woken during teardown. Unexpected sequences end the link instead of guessing.

Chat is currently server-wide. Presence snapshots include only the same map and
room, exclude the caller and expire after 3 seconds. Instance/key-world identity
is incomplete; this is a known shared-world limitation.

HTTP: POST `/DQM/api/register` and `/DQM/api/login`; JSON username/password,
4096-byte body maximum. Passwords 12–128 chars; usernames 3–24 ASCII letters,
digits or underscores. Registration/login are rate limited; hashing concurrency
is bounded. Tickets are stored as SHA256 of cryptographically random tokens,
never as plaintext. Replay/expired tickets are rejected. GET `/DQM/api/status`
exposes counts, uptime and downloadable release metadata only.


Server adventure writes use a SQLite transaction and compare the prior revision.
An acknowledgement returns the new revision, load token, slot and SHA256 of
SRAM followed by state. Clients wait for that acknowledgement before logout,
quit or switching adventures. There is at most one in-flight client save.
WebSocket buffers accommodate checkpoints (512 KiB inbound, 2 MiB server output).
Checkpoint payloads are bounded opaque client data, not validated game actions.
Protocol 1 clients require an update. Existing server SRAM backups migrate into
slot 1; no old local save is imported automatically.
