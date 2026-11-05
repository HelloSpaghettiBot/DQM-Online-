# Build details

Godot 4.6.3 stable, godot-sqlite v4.8, SCons 4.11.1; exact upstream revisions
and SHA256 values are in `tools/bootstrap.py`. Standard GDScript engine only.

## Linux

Run `python3 tools/bootstrap.py --downloads /path/to/downloads`, then
`python3 tools/run.py client --rom /path/to/cobi.gbc`.

For an exported alpha, obtain the official 4.6.3 export templates and put
`linux_debug.x86_64` into `.tools/templates/`. Run:

```sh
mkdir -p builds/linux
.tools/Godot_v4.6.3-stable_linux.x86_64 --headless --path client --export-debug Linux
```

Public Linux native libraries were built on Ubuntu 24.04 (glibc 2.39), using
the VPS's GCC 13. The godot-cpp binding links the C++ runtime statically;
Gambatte uses Ubuntu's shared C++ runtime. The OS must provide its standard C++ runtime libraries. Older glibc
distributions are not verified.

## Android arm64

Install OpenJDK 17, Android command-line tools, platform tools, build-tools
35.0.1, platform 35 and NDK 28.1.13356709. Configure Godot's editor Android SDK
and Java SDK paths. Android 10+ is recommended for the native ROM file picker.
The exported engine manifest targets API 36; real-device installation is untested.

After bootstrap, patch `libgambatte/libretro/jni/Android.mk` to add
`-std=c++17` to `LOCAL_CXXFLAGS` (the serial bridge uses mutex/condition_variable).

```sh
/path/to/ndk/ndk-build -C .vendor/gambatte/libgambatte/libretro/jni \
  APP_ABI=arm64-v8a APP_PLATFORM=android-24 -j4
mkdir -p client/bin/android/arm64
cp .vendor/gambatte/libgambatte/libretro/libs/arm64-v8a/libretro.so client/bin/android/arm64/
ANDROID_HOME=/path/to/android-sdk .tools/venv/bin/scons -C native \
  platform=android arch=arm64 target=template_debug build_profile=build_profile.json -j4
```

Put the official `android_debug.apk` export template into `.tools/templates/`,
then export with `godot --headless --path client --export-debug Android`.
This alpha uses debug signing; production releases require a private release
keystore, which must remain outside source/public artifacts. No broad filesystem
permission is requested: use the Android document picker to grant one file.

## Windows x86_64 from Linux

The alpha was cross-compiled with LLVM-MinGW 20261104 UCRT Ubuntu-22.04 x86_64.
Upstream download and published SHA256:
`919380403de87dca3c581c2053230cd298af5e891286628ba0613b7fed370926`.

Use a separate copy of Gambatte for Windows to avoid reusing Linux `.o` files.
Remove the ELF-only `-Wl,-version-script=$(version_script)` link flag in that
copy's Makefile. Build `platform=windows` with the toolchain's
`x86_64-w64-mingw32-clang` and `clang++`. Retain the C++17 and serial patches.
Put `gambatte_libretro.dll` in `client/bin/windows/`.

Generate an import archive using LLVM dlltool: create a `.def` with
`LIBRARY gambatte_libretro.dll`, `EXPORTS`, then its `retro_*` exports, including
the four `retro_dqm_*` functions. `llvm-readobj --coff-exports` lists them.
Run `x86_64-w64-mingw32-dlltool -d gambatte.def -l libgambatte_libretro.dll.a`.

```sh
.tools/venv/bin/scons -C native platform=windows arch=x86_64 \
  use_mingw=yes use_llvm=yes mingw_prefix=/path/to/llvm-mingw \
  target=template_debug build_profile=build_profile.json -j4
mkdir -p builds/windows
godot --headless --path client --export-debug Windows
```

The Windows export template is `windows_debug_x86_64.exe`, placed in
`.tools/templates/`. No code signing is configured. The exported Windows binary
has not been run on a Windows device. All needed custom DLLs must stay beside
the EXE/PCK; do not publish only the EXE.

## Public packaging

`python3 tools/package.py` writes client ZIPs and a sanitized source ZIP into
`web/public/downloads/` and updates its manifest. It uses explicit allowlists,
rejects forbidden extensions/private paths, and never packages `.local` or
arbitrary workspace files. Dependency source accompanies the GPL bridge.
Source archives exclude commercial ROMs and playable extracted assets. Website
presentation assets include the gameplay and menu screenshots shown publicly.
