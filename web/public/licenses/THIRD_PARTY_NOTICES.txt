# Third-party software

- **Gambatte / libretro Gambatte** — GPL version 2.
  https://github.com/libretro/gambatte-libretro
  Commit `77f2567d718b8973d02caa2daa8dce4953faf811`.
  Local changes add a bounded serial bridge, C++17 compilation and correct
  consumption of incoming serial bits during intermediate register reads.
  The complete license is `LICENSE`; original notices remain in upstream source.
  Modified files carry DQM Online change notices dated November 5, 2026.
- **Godot** — MIT license, https://godotengine.org/license/.
  Engine `4.6.3.stable.official.7d41c59c4`. Engine source:
  https://github.com/godotengine/godot/tree/4.6.3-stable.
  Godot includes third-party components; see its copyright/license notices at
  https://github.com/godotengine/godot/blob/4.6.3-stable/COPYRIGHT.txt.
- **godot-cpp** — MIT license,
  https://github.com/godotengine/godot-cpp/tree/27d9dd23c83871e0619fca5dc2cddfbfd69e926a.
  Local build adds an explicit `<cstdlib>` include for current LLVM-MinGW.
- **godot-sqlite** — MIT license, release v4.8.
  https://github.com/2shady4u/godot-sqlite/releases/tag/v4.8.
  Used on the server; its license accompanies the downloaded extension.
- **SQLite** — public domain, https://www.sqlite.org/copyright.html.
- **LLVM-MinGW** — build tool only, release 20261104. LLVM, mingw-w64 and
  runtime notices are retained with the toolchain; the client includes its
  statically linked C++ runtime. https://github.com/mstorsjo/llvm-mingw.
- **VT323** — Peter Hull, SIL Open Font License 1.1.
  https://github.com/google/fonts/tree/main/ofl/vt323.
  Font and complete OFL notice are in `client/assets/fonts/`.

- **Press Start 2P** — CodeMan38, SIL Open Font License 1.1.
  https://github.com/google/fonts/tree/main/ofl/pressstart2p.
  Website font and complete OFL notice are in `web/public/assets/`.

Gameplay screenshots on the website depict the original game and are not
covered by this project’s GPL license.

Commercial ROMs, game graphics, maps, music and scripts are not part of this
project or its license. The client reads the player's own local ROM and no ROM
or ROM hash is sent to the server.
