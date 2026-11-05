# Cobi USA adapter research

Recognized local identity:
SHA256 `8e38a7420ef5239c7196aa4fd4b1499e65db2823e875bbf8241bb2199e766d4e`.
4194304 bytes, internal title DWM2-C, game code BQLE, CGB flag 0x80,
MBC5+RAM+battery type 0x1b, 32768-byte battery save. Header checksum validated.
The importer rejects unknown/modified variants; recognition is not proof of all
online functions. Iru Japanese and Caravan Heart are not compatible substitutes.

Primary research by TAS authors:
https://tasvideos.org/Forum/Topics/8157?CurrentPage=1&Highlight=506734

Read-only fields used:

| Address | Meaning |
| --- | --- |
| FF8E | player X in pixels |
| FF8F | map section X |
| FF90 | map ID |
| FF91 | player Y in pixels |
| FF92 | map section Y |
| C5DB | game mode; observed 1 in opening ship, 5 in title/name entry |

Verified in a local opening-ship state: first four 8x8 OAM entries form Cobi's
16x16 avatar; tiles 0–11, VRAM bank 0. OAM X-8/Y-16 yields screen position.
Left movement changed ROM position and the first actor's screen location by
matching pixel distances. No ROM patch or writes were used. Neighbor positions
are projected relative to the local avatar in the same map/section. Avatar
pixels and transparency are recovered from local OAM/VRAM/frame data only.

Not verified: all maps, scrolling boundaries, scene-script hiding, sprite slot
changes, alternate avatar forms, battle/menu transitions, procedural-key-world
identity, other regional ROMs, and foreground occlusion. Do not claim universal
shared-world compatibility from the opening-scene result.

Serial research found a bug in the pinned upstream network serial path: repeated
SC/SB register reads shifted the high bits of a received byte more than once.
The patch shifts from the remaining-bit position, preserving original timing.
A tiny independently authored ROM exchanges 42/43 through two real emulator
processes and the authenticated relay. Full original link-mode transactions
remain a separate verification requirement.
