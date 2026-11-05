# Party behavior — agreed requirements

Status: planned/in development; not included in the published 0.2.2 gameplay.

- Players can form a party and invite other online players.
- When the leader enters another world, members follow into that same world
  even if they do not own its key. Access does not permanently grant the key.
- Members explore the same world but fight separate battles.
- Earned EXP is split evenly among eligible party members in the same world.
- Loot, gold, items and monster recruitment remain individual.
- A generated world needs its actual key/instance identity; matching a map ID
  or room number is insufficient.
- Travel must preserve each member's own monsters, inventory and campaign
  progress. A leader's complete save must never replace a member's save.
- Shared EXP must reach the original game's level/stat/skill progression,
  survive autosaves and reconnects, and avoid duplicate reward application.

ROM travel and EXP integration must be verified before advertising the feature
as playable. A party roster or server reward calculation alone is insufficient.

Optional region entry also requires each member to have that region’s local ROM.
A leader’s key grants party access but does not supply copyrighted content.
See [EXPANSIONS.md](EXPANSIONS.md).
