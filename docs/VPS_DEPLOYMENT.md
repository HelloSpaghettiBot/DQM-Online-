# VPS deployment

The public site is scoped to `/DQM` on 403world.com. Other site routes and game
services must remain untouched. This alpha uses HTTPS/WSS instead of opening a
new UDP port or requiring Tailscale. The initial blueprint's VPN-only plan was
superseded by the owner's public registration/download request.

- Code releases: `/opt/dqmonline/releases/<release>`; atomic symlink `current`.
- Pinned engine: `/opt/dqmonline/runtime/Godot_v4.6.3-stable_linux.x86_64`.
- Private data: `/var/lib/dqmonline/dqmonline.db`, owner dqmonline, mode 0600.
- Services: `dqmonline-web`, `dqmonline-game`, `dqmonline-backup.timer`.
- Local listeners: website 127.0.0.1:9045; game WebSocket 127.0.0.1:24778.
- nginx: `/etc/nginx/snippets/dqmonline.conf`, included only in the main
  403world.com TLS virtual host. DQM public routes bypass that host's legacy
  network filter and use their own account authentication. No global filter is
  disabled. The firewall remains unchanged: ports 80/443 serve DQM traffic.

## Install

Create the low-privilege `dqmonline` system account, private data directory and
read-only release directories. Install the pinned standard Godot engine. Copy
the server, shared protocol, Linux SQLite extension and website. The server's
SQLite GDExtension list must be imported by the pinned engine before startup.
Initialize the account database with `web/service.py` before the game service
starts; the systemd dependency orders these services. Never copy local
development accounts, databases or ROMs to the VPS.

Install the service files under `/etc/systemd/system`, insert the isolated
nginx include, run `nginx -t`, then enable the services and timer. The deployment
tool creates a timestamped backup of pre-existing configuration and rolls back
its modifications on a failed health check.

## Operational checks

```sh
systemctl status dqmonline-web dqmonline-game
journalctl -u dqmonline-web -u dqmonline-game --since '15 minutes ago'
curl -fsS http://127.0.0.1:9045/DQM/api/status
systemctl list-timers dqmonline-backup.timer
```

Logs contain service events, HTTP method/status, peer/session counts and errors;
they must not contain passwords, tickets, request bodies or ROM contents. Public
status includes only online state, player count, uptime and release metadata.

## Backups

The daily timer uses SQLite's backup API, stores consistent databases under
`/var/backups/dqmonline/` with mode 0600 and retains 14 copies. Manual backup:
`python3 /opt/dqmonline/current/deployment/backup.py`. Backups contain private
password hashes and cartridge saves; never put them in source/download paths.

For restore, stop both services, preserve the current database, copy a known
backup to the private data directory, remove obsolete WAL/SHM files while
services are stopped, set owner/mode and restart. Confirm `PRAGMA integrity_check`
on the restored database before accepting logins.

## Upgrade and rollback

Create and verify a new release directory; back up SQLite through its backup
API, then atomically replace `current` and restart both services. Test the local
HTTP status and an authenticated WSS connection, then the public URLs. Schema
changes must remain backward compatible or carry a migration-specific restore
plan. To roll back code, restore the prior `current` symlink and restart. Restore
nginx from the deployment backup only if routing was changed; validate before
reload. Keep user data separate from releases throughout.

## Capacity

The first local demonstration used two clients. No large-scale concurrency or
public economy claim is made. Measure service memory, CPU, login hash load and
latency under real two-player sessions on the VPS before increasing capacity.

## Farm starter and protocol 2

The production unit reads a private validated `farm-start.state` and
`farm-start.srm` from `/var/lib/dqmonline/`. They are generated from the owner's
local ROM after the original intro has completed and the player can walk on
the family farm (map 0, room 1/2). They are save data, not a ROM. Keep them out
of the source/client downloads, mode 0600, owned by dqmonline. The server copies
the template only into an empty adventure at revision 0. Existing account saves
and migrated server cartridge backups are not replaced.

To prepare your own starter from an explicitly supplied farm checkpoint, run
`tests/emulator_probe.gd` with your local ROM and checkpoint and a neutral frame
plan, then validate the resulting `.state/.srm` with `tests/starter_probe.gd`.
Never use another player's developed character. The first-party intro scripts
must have completed, and normal walking/story interaction must work. The hosted
template was obtained through the original intro, without arbitrary RAM writes.
These private fixtures are deliberately not included in the public source.

The 0.2 server/client protocol is incompatible with 0.1 clients. Back up SQLite,
export/package all clients and deploy the server and complete public downloads
together. Account databases and prior saves remain in the private data folder.
