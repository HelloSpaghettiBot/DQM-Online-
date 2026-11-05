# Client updates

Exported clients check the HTTPS release manifest at startup and every five
minutes, with an explicit Settings → Check for updates action. Development
editor runs do not replace the editor. Release identity is shared/release.gd;
packaging writes platform, monotonically increasing build, version, byte count
and SHA256 into web/public/downloads/manifest.json. Each platform is fetched
only from its fixed HTTPS path on 403world.com; redirects are disabled.

Downloads go into a private staging area. Byte count and SHA256 are checked
before installation. Desktop ZIPs also enforce bounded entry/file/total sizes,
reject path traversal, duplicate paths and ROM/save/database payloads. A private
copy of the old executable/PCK/native libraries runs the updater while the
installed game exits. It backs up affected files, replaces them, rolls back on
failure and restarts the client. Install folders must be writable. Credentials,
ROMs, preferences and server saves are outside the replaced files. Interrupted
process/power-loss recovery during replacement still needs broader testing.

During gameplay the client waits for a confirmed server save before exiting
for an update. Link sessions postpone installation until they end. Android
opens the verified APK using Godot's FileProvider integration. Android requires
the user to allow this app to install packages and approve the OS installation;
no silent package installation is claimed. Keep the same package ID, signing
key and increasing Android version code for subsequent APK updates.

Publishing: increment shared/release.gd and Android version/code and name,
export all clients, restore target-compatible Linux libraries, package, verify,
then publish pages plus complete downloads as one release. Clients without this
updater (0.1.x) need one manual installation. HTTPS and the site's manifest are
the current update trust boundary; no independent release signature is claimed.

Verified: malformed archive/origin/hash rejection and actual file replacement
and rollback in disposable folders. Real Windows/Android installation remains
pending hardware verification. Do not infer those results from Linux checks.
