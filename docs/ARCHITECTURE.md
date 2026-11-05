# Current architecture

The owner's revised target is an original-campaign multiplayer client, not the
blueprint's placeholder town. Godot renders the desktop/Android shell, HUD,
nearby avatars and audio. Gambatte runs the original local Cobi ROM on a paced
worker thread. Audio/video buffers and serial queues cross bounded interfaces;
blocking cable waits never run on Godot's main thread.

The client adapter reads game state, map/room identifiers, pixel coordinates and
the player's OAM/VRAM sprite. Nearby-player drawing overlays ROM-derived local
sprites; the server does not supply commercial assets. Rendering is conservative
and suppresses avatars for unrecognized states/layouts. It currently lacks
complete campaign/camera/occlusion validation and movement interpolation.

Public login: HTTPS JSON username/password -> scrypt verification -> random
one-use 60-second ticket -> WSS game login. Passwords are never in game RPCs or
client settings. Game sessions are bound to the authenticated account. The
website and Godot share a private SQLite file on the VPS, using WAL and prepared
statements. Game ticket consumption is transactional. Loopback-only ENet exists
for reproducible development tests.

The server owns session identity, roster, invitation consent, link pairing and
server-adventure account isolation. It currently validates payload bounds/rates, not
gameplay semantics. Presence and checkpoint contents are client-reported. The
original battle/monster engine remains local. This is not yet an authoritative
MMO and must not be advertised as cheat-resistant or as a safe public economy.

SQLite v4.8 has been exercised on Linux headless for migration, account lookup,
ticket transactions and isolated backup persistence. No storage fallback is
silently enabled. Missing SQLite stops startup with a clear error.

No new hand-built world substitutes for the ROM campaign. Co-op dungeon/boss
work from the initial blueprint is deferred behind the owner's shared-world,
challenges, trading and breeding priorities.


The campaign starts only after authenticated adventure selection and server
loading. SRAM and exact resume state live in SQLite games records keyed by
account and slot, with transactional revision checking and per-load tokens.
The client retains only its ROM and preferences on disk; legacy local saves
remain untouched and are ignored. Five-second server autosaves and acknowledged
save-and-quit replace local suspend/optional-backup workflows. Lost connections
stop the worker, clear gameplay rendering, and require another server load.
See UX_REFERENCE.md for the reference flow and authority limitations.
