# Verification — November 4, 2026

## Passed

- Linux emulator core and Godot GDExtension compile.
- Linux native libraries also compile on the Ubuntu 24.04 hosting VPS.
- Godot client and server import/start without parser errors.
- Supplied USA Cobi ROM identity/header validation and original opening campaign
  playback, graphics and generated audio.
- Read-only coordinate and avatar validation in the original opening ship.
- Two visible desktop clients: original map, both named characters, bidirectional
  chat, DW3-inspired floating HUD and no virtual emulator controls on desktop.
- Two real ENet clients: authenticated login, roster, chat, consented invitation,
  serial relay, isolated SQLite cartridge backups and restore.
- Tiny original hardware-test ROM: bidirectional emulated serial exchange through
  two native core processes and the server, received values 42 and 43.
- HTTPS-account-compatible local API + two WebSocket clients: registration,
  scrypt password login, one-use tickets consumed transactionally, chat,
  invitation, relay and account-isolated backup/restore.
- Seven Python tests: malformed/unknown/ambiguous ROM inputs, password and ticket
  flow, duplicate name, wrong password, cross-origin rejection, invalid account
  name and private-field-free status.
- Windows x64 cross-compilation, dependency inspection and Godot export.
- Android arm64 compilation and APK export/signature verification. APK includes
  the native bridge and core and requests internet/network access without broad
  external-storage access. Native touchscreen overlay implements per-finger
  simultaneous input; hardware testing is pending.
- Public VPS installation: website and game run as the low-privilege dqmonline
  account, nginx configuration validates, and public status reports online.
- Live HTTPS registration and password login through the actual Godot client,
  followed by an authenticated WSS connection to 403world.com.
- Public main/source/server pages, CSS and JavaScript return HTTP 200. All three
  hosted client downloads match their published size and SHA256. The public
  source download matches the sanitized local source archive.
- Exported Linux application starts with the Ubuntu-built native libraries.

- Updated desktop gameplay capture: roster hidden, Menu opens Players, and
  two named characters and global chat remain visible.
- Actual in-client registration over public HTTPS, automatic password login,
  and authenticated WSS session; password field cleared and no password saved.
  The temporary verification account was removed afterward.

- Rendered Android layout preview: native ROM prompt, in-client signup, touch
  controls, and full-screen stretch setting. This is a desktop layout preview,
  not a real-device verification.
- ROM onboarding, private retained ROM import, extensionless ZIP detection,
  in-app form validation, and stretch/aspect toggle with saved configuration.
- Chromium desktop (1440 px) and mobile (390 and 320 px) website screenshots;
  all images load, no horizontal overflow or JavaScript errors. Actual browser
  registration/login passed against an isolated local database.

## Online-only server adventures — 0.2.0

- Actual client plus original ROM: retained ROM and conflicting legacy local
  saves cannot start the campaign offline; login waits for adventure selection.
- Account progress persisted, server process restarted, and a fresh client
  profile resumed the byte-identical server SRAM/checkpoint on another device
  profile. Old local .state/.srm files remained unchanged and were ignored.
- Adventure switching waits for save confirmation; a new slot starts separately.
- A UDP blackhole dropped packets without closing the connection. The heartbeat
  deadline stopped the emulator, hid the game, and returned to login.
- Two actual WebSocket clients exchanged 160 KiB save payloads, reloaded their
  own data, and rejected stale save tokens/revisions. No cross-account state.
- Generic emulated cable relay still exchanged bytes 42 and 43 under protocol 2.
- New desktop captures show authenticated adventure selection, server-save menu,
  and two visible players/chat from an isolated development server.

## Controls and updater — 0.2.0

- Large Android D-pad regions, movement + A multitouch, analog deadzone and
  direction changes, and clearing held input when a menu opens.
- Desktop-rendered Android screenshots: large D-pad, analog, size slider,
  stretch setting and luls.lol branding. Real-device ergonomics remain untested.
- Updater rejects wrong origin/path, oversized metadata, bad hashes, ZIP path
  traversal, ROM entries and oversized ZIP content before installing.
- Actual updater worker runs from an exported Linux client.
- Actual updater worker replaces executable/PCK/native files in a disposable
  folder. A deliberately failed later replacement restored prior files.

## Farm start

- Original ROM intro completed through normal inputs, including arrival on
  GreatLog. The resulting private starter is the family farm, map 0 room 1/2,
  x=80,y=80, state 1. Loading it and walking left changes x while preserving map.
- Two real client captures show both named players and chat at the farm.
- Empty server adventure slots receive the starter once; existing progress is
  preserved. Private starter files are excluded from all public artifacts.

## Live 0.2 deployment

- Updated website, protocol 2 server, Windows/Linux exports and signed Android
  APK published at 403world.com/DQM. New database schema and private farm
  starter installed; pre-deployment SQLite backup retained.
- Actual public HTTPS in-client registration, automatic WSS login, new adventure
  farm start, acknowledged server save, logout, login and resumed revision passed.
  Temporary verification account and adventure were removed afterward.
- Live home/server/source pages, all screenshots, release links, online status,
  and desktop/phone browser layouts verified.

## Limits / pending

- Windows and Android exports have not been run on real devices.
- Original Cobi PvP, monster/key trades and multiplayer breeding have not passed
  end-to-end game tests; a working generic cable test does not prove them.
- Whole-campaign completion and universal shared-world presence are unverified.
- Sprite/camera edge cases, key-world instance identity, foreground occlusion and
  transition handling need broader research and integration.
- Movement and cartridge saves are client-reported, not server-authoritative;
  no cheat-resistant economy is provided.
- Some forced headless exit probes reported ObjectDB cleanup warnings. Normal
  game quit waits for the server save acknowledgement; lifecycle stress testing remains.


No test result is inferred solely from compilation or a screenshot. Test output
is private development data and is intentionally excluded from public artifacts.

## App name correction — 0.2.1

The Android app label, desktop window title and interface identify the game as
DQM Online. luls.lol is confined to the custom startup splash. The existing
Android package ID, signing key and local data location are preserved. The
release build and Android version code increase to 4 so installed clients
detect the correction through the updater.

0.2.1 removes the manual Save to server button. Quit game, logout and adventure
selection automatically preserve progress; periodic autosaving remains active.

Confirmed periodic autosaving advances the server revision without a manual
action; logout, restart, fresh-profile resume and connection-loss checks pass.
The updated menu capture shows Quit game and no manual save button.

## Chat and nameplates — 0.2.2

- Two actual connected clients running the supplied ROM: keyboard movement with
  chat open, followed by direction changes, preserves the visible chat panel.
- Android layout preview: a focused chat field releases focus when the D-pad is
  pressed; movement and A work simultaneously without closing chat. Keyboard
  dismissal is requested only on platforms that support a virtual keyboard.
- Local nameplates follow the OAM avatar position every display frame. Local and
  remote label instances remain constant while walking and turning, and remain
  visible throughout the movement checks. Nearby actors interpolate between
  network positions; their label and sprite share the same position calculation.
- Plain outlined text replaces the nameplate background boxes. Updated desktop
  and Android layout captures show the current labels, chat and controls.
- These Android checks run in the desktop layout preview. Physical-device
  keyboard dismissal and ergonomics still need device testing.

## Project notice and source documentation — 0.2.3

- Original fan-project notice added to ROM onboarding, a scrollable in-client
  Project notice & licenses panel, README, packaged disclaimer and website.
- Android layout preview shows the notice and opens the complete project notice
  without starting gameplay. Bundled GPL and component license text files are
  readable through the client panel.
- Website home/source/legal links and legal text checked in Chromium at desktop,
  390 px and 320 px widths; no horizontal overflow.
- Existing website registration/login, client image loading and connected-client
  menu captures continue to pass.
- A disclaimer is not legal clearance. See docs/LEGAL_REVIEW.md for its scope.

## Optional-ROM import foundation — working source

- Both owner-supplied Iru GBC and Caravan Heart GBA ZIPs validate exact identities
  and platform header checksums. Raw and extensionless Android ZIP paths work.
- Private retained imports, remove/reimport, and rejecting the wrong ROM for a
  slot passed. Importing optional content leaves the Cobi ROM, location, SRAM and
  monster/inventory memory unchanged.
- Optional ROMs are shown as imported/missing with region integration pending.
  This does not establish playable regions or cross-game monster compatibility.

## Optional import release — 0.2.4

- Base Cobi autosave, server restart, fresh-device resume, slot isolation and
  heartbeat disconnection checks pass after adding optional import support.
- Existing player progress and the online-only campaign gate remain in use.
- Both optional sources can be imported and removed locally. Regions, party
  gameplay and starter selection remain explicitly unfinished.
