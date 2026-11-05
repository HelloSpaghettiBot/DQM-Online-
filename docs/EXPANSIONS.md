# One MMO, optional ROM expansions

Owner requirements, November 5, 2026: one account, character and shared online
world, inspired by PokeMMO. Optional locally supplied ROMs unlock additional
regions/content. Separate emulator games presented as an expansion do not meet
this requirement.

| Local source | Platform | Verified identity | Integration |
| --- | --- | --- | --- |
| Cobi’s Journey USA | GBC | `8e38a7420ef5239c7196aa4fd4b1499e65db2823e875bbf8241bb2199e766d4e` | Base campaign alpha |
| Iru no Bouken Japan | GBC | `1916208828ce85763d7ca03821eb17cec1a51d55cd80a36bd30a3ea653396a39` | Optional expansion integration pending |
| Caravan Heart Japan | GBA | `fb388539b95fdaf6009bad879e9bbb25955daf8d4d438486a9213d407b2b48ce` | Optional expansion integration pending |

All three supplied ROMs have valid platform header checksums. This confirms
identity only. It does not prove world, save, monster or multiplayer compatibility.
ROMs stay local and remain excluded from the repository and every public package.

Local import is now implemented in the working source: Menu → Optional ROMs
validates these exact revisions, retains private local copies, and reports the
regions as not yet playable. Import/remove/wrong-slot and unchanged-base-progress
checks pass with both supplied archives. This is not yet a published expansion.

## Required behavior

- Cobi alone remains sufficient for the base game. Missing expansions do not
  block login, base progress, chat or parties.
- An optional-ROM screen reports imported, missing and not-yet-playable states
  honestly. Import must never replace the active Cobi ROM or checkpoint.
- A server-owned region/instance identity separates actual worlds and revisions.
  Japanese and USA RAM addresses are not assumed interchangeable.
- Region entry checks local content availability; members cannot enter a region
  whose required ROM is absent. Party key access is a separate entitlement from
  having the required local source ROM.
- Parties follow the leader into the same world without permanently granting
  its key. Battles remain separate; EXP splits evenly among eligible members
  in that world, while loot/recruitment remains personal.
- Cross-region character/monster/inventory representations require explicit
  tested mappings and transactional server persistence. Loading another player’s
  full checkpoint is prohibited.

## Engine work

Iru uses GBC hardware but a different game revision, text and address layout.
Its ROM can supply optional content only after a tested regional adapter exists.
Caravan Heart is a separate GBA game and needs a GBA engine/content adapter;
Gambatte cannot execute it. Their content is not unlocked by merely accepting
the file extension or copying a map ID.

The hosted 0.2.3 release does not yet enable either expansion or the requested
party gameplay. Publish playable claims only after actual region travel, retained
individual progress and original-game reward progression have passed verification.
