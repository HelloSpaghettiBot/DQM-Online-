# Account appearance

Menu → Appearance offers 85 complete walking sprite records from the supplied
USA Cobi ROM, 59 ROM palettes and front/back/left/right preview. Default is Cobi
with palette index 18. Selection is stored per account, across adventure slots
and devices. Apply waits for server confirmation; a failed save leaves the
previous appearance active. Login retrieves the saved selection.

The verified local ROM contains 98 graphics records at bank 0x7D / 0x7E.
The client decodes their length/escape/back-reference stream in memory; shorter
actor records are normalized to Cobi's tile arrangement. Thirteen records with
large structures, effects or fewer than three facing poses are excluded from
player selection. Optional Iru / Caravan appearances are not integrated yet.
No extracted sprites, palettes, ROM bytes or checkpoints are in the source tree.
Screenshots are examples of the running client, not GPL game assets.

The render hook replaces OBJ tile and palette sampling only for the first four
OAM entries, validated tile slots, world state 1 and 8x8 mode. Background and
other actors retain the original PPU priority rules. Link sessions disable it.
It never writes the ROM, emulated RAM or save payload; appearance is not part of
the emulator checkpoint. Cobi remains the character in campaign dialogue.

Protocol 2 gains optional welcome/presence fields and the reliable `/look ID
PALETTE` command (also used by the GUI). No RPC declaration changed. The server
validates IDs against a shared whitelist, saves to SQLite before acknowledging,
and injects the session's saved appearance into presence. Clients cannot upload
artwork or choose another account's appearance. Old protocol-2 clients continue
using their previous appearance renderer; update them to see custom sprites.

Current remote sprites use facing poses; continuous remote walk-frame animation
is not yet synchronized. Physical Android/Windows device testing is pending.
