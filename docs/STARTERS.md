# New-adventure intro and starter choice

Owner request, November 5, 2026: offer Skip intro and let the player choose a
first monster instead of receiving the default Slime/Slib.

- Starter choices are restricted to ordinary first-world encounter species at
  level 1; no bosses, rare/advanced monsters, high levels or boosted stats.
  Verify each candidate against the actual first-world encounter data.
- Choices apply only when creating a new server adventure. Existing adventures
  retain their progress, monster roster, inventory and intro state.
- Skip intro enters normal gameplay after the required opening setup. The
  chosen monster must be fully usable through original battle/level/skill logic.
- The server validates allowed starter IDs and creates the selected adventure
  once. Retrying a request must not replace an existing save or grant extras.
- The intro-on path uses the original opening; at its starter award it honors
  the selected starter rather than adding a second monster.
- Monster records must be generated/validated from the original game data,
  with correct base stats, EXP growth, skills, name, roster indexes and checksums.
- Starter selection and initial progress persist on the account before the
  first frame is playable. It uses the same automatic-save path as other play.

The published 0.2.3 host already starts new adventures at the farm after the
boat, but does not yet provide this expanded skip-intro/starter-choice flow.
No starter-choice feature should be advertised as working until original-game
battle and reload checks pass.
