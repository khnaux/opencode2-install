# Install OpenCode 2.x (Linux, macOS, Termux)

A tiny, dependency-light installer that always lands on the **latest OpenCode 2.x** — and refuses to install 1.x by accident.

Verified against **OpenCode 2.1.4** (October 2026). The version is resolved at run time, so this guide does not go stale with every release.

```bash
curl -fsSL https://opencode.ai/v2/install | bash   # official upstream installer
```

That one-liner is all most people need. The script in this repo wraps it with version pinning, platform detection, Termux support, and a post-install check that the binary really is 2.x.

---

## TL;DR

```bash
git clone https://github.com/khnaux/opencode2-install.git
cd opencode2-install

bash install-opencode2.sh --dry-run   # see the plan
bash install-opencode2.sh             # install latest 2.x
bash install-opencode2.sh -v 2.1.4    # or pin an exact build
```

On Android/Termux, always invoke it with `bash`, not `./script` (Android has no `/usr/bin/env`).

---

## What the script does

| Platform | Method | Notes |
| --- | --- | --- |
| Linux (glibc/musl, x64/arm64) | official installer | musl and non-AVX2 "baseline" builds auto-detected |
| macOS (Intel/Apple silicon) | official installer | Rosetta-translated shells are mapped to arm64 |
| Termux on Android (arm64) | npm `@bash0816/opencode-termux` | runs the official Linux binary through the Termux glibc runtime |

Steps it performs:

1. Resolves the current release from `https://opencode.ai/update/api/latest/cli/npm`.
2. Fails hard if that version is not `2.x` (or if you pin a `1.x` version).
3. Installs via the official installer, or the Termux wrapper on Android.
4. Repairs the npm launcher shebang on Termux — npm rewrites it to `#!/usr/bin/env node`, which does not exist on Android.
5. Runs `opencode --version` and confirms the result starts with `2.`.

Options:

```
-v, --version <ver>   pin a build, e.g. 2.1.4 (must be 2.x)
    --dry-run         print the plan, change nothing
    --no-deps         Termux: don't auto-install glibc-runner/patchelf
    --no-verify       skip the final version check
    --prefix <dir>    npm global prefix (Termux only)
-h, --help            usage
```

---

## Manual installs (no script)

Pick one:

```bash
# official installer
curl -fsSL https://opencode.ai/v2/install | bash

# Homebrew
brew install anomalyco/tap/opencode-v2

# npm / bun / pnpm / yarn / Vite+
npm install -g @opencode/cli
bun install -g --trust @opencode/cli
pnpm add -g --allow-build=@opencode/cli @opencode/cli
yarn global add @opencode/cli
vp install -g @opencode/cli

# Arch (AUR)
paru -S opencode-beta

# mise (requires mise 2026.10.9 or newer — older versions install V1)
mise use -g opencode

# Docker
docker run --rm -it ghcr.io/anomalyco/opencode:2.1.4
```

Standalone binaries are published per platform under
`https://opencode.ai/update/api/latest/cli/opencode/`, e.g. `opencode-linux-x64.tar.gz`,
`opencode-linux-arm64-musl.tar.gz`, `opencode-darwin-arm64.zip`, `opencode-windows-x64.zip`.

Desktop builds (`.dmg`, `.exe`, `.deb`, `.rpm`, `.AppImage`) live under
`https://opencode.ai/update/api/latest/desktop/opencode/`.

> Windows package managers are not supported upstream. On Windows, use the standalone
> binary or the desktop app.

---

## Termux / Android

OpenCode has no official Android build. The official Linux binary is linked against
glibc, while Android uses bionic, so it cannot run as-is. The community wrapper
[`@bash0816/opencode-termux`](https://www.npmjs.com/package/@bash0816/opencode-termux)
downloads the official `@opencode/cli-linux-arm64` binary and points its ELF
interpreter at the Termux glibc runtime.

```bash
pkg update
pkg install nodejs-lts glibc-runner patchelf

npm install -g @bash0816/opencode-termux@latest
termux-fix-shebang "$PREFIX/lib/node_modules/@bash0816/opencode-termux/bin/opencode-termux"

opencode --version    # -> opencode v2.1.4
```

Or let the script handle all of it:

```bash
bash install-opencode2.sh
```

Caveats:

- **arm64 only.** 32-bit and x86 Android are not covered.
- **Third-party.** The wrapper is community-maintained and not affiliated with the OpenCode project.
- **First launch is slow.** The wrapper downloads and patches a ~200 MB binary on first run; later launches are fast.
- **Don't export `LD_LIBRARY_PATH`.** Loading Termux's glibc libs globally makes `node`, `bash`, and MCP servers fail with `bad ELF magic`. The wrapper scopes the loader per process for this reason.
- Keep `patchelf` installed, or updates fail with `patchelf not found. Run "pkg install patchelf"`.

---

## Verify, update, run

```bash
opencode --version        # must print 2.x
opencode                  # start the TUI
```

First run: use `/connect` to add a provider. Configuration lives in
`~/.config/opencode/opencode.json(c)`; terminal-only preferences (theme, keybinds) live in
`~/.config/opencode/cli.json`.

Update later:

```bash
opencode update                                   # built-in updater (fixed in 2.0.22)
npm install -g @opencode/cli@latest               # npm install
npm install -g @bash0816/opencode-termux@latest   # Termux
bash install-opencode2.sh                         # this script
```

OpenCode runs a background service. If it looks stuck:

```bash
opencode service status
opencode service restart
opencode api get /api/info
opencode --standalone    # isolate shared-service problems
```

Logs: `~/.local/share/opencode/log/opencode.log` (filter `role=cli` for the client,
`role=server` for sessions/providers/tools). Add `OPENCODE_LOG_LEVEL=DEBUG` for one
reproduction run when normal logs are not enough.

---

## Troubleshooting

**`opencode: command not found`**
The native installer puts the binary in `~/.opencode/bin` and edits your shell rc.
Open a new shell, or:

```bash
export PATH="$HOME/.opencode/bin:$PATH"
```

**`Unsupported OS/Arch`**
Only `linux`/`darwin` with `x64`/`arm64` are published. On Alpine or another musl distro the
official installer selects the musl build automatically; make sure `curl` and `tar` exist
(`apk add curl tar`).

**`Illegal instruction` on an old x64 CPU**
The installer installs a `-baseline` (no AVX2) build automatically when `/proc/cpuinfo`
lacks `avx2`. If you copied a binary from another machine, grab the `-baseline` archive instead.

**Termux: `bad interpreter: No such file or directory`**
A shebang points at `/usr/bin/env`, which Android does not have. Run the script with `bash`
and repair installed npm launchers with `termux-fix-shebang <path>`.

**Termux: `patchelf not found`**
`pkg install patchelf`, then re-run the install.

**Version is 1.x after installing**
Something pinned V1 (an old `mise`, an old tap, a stale `@opencode-ai/*` package). Install
explicitly: `bash install-opencode2.sh -v 2.1.4`, or `npm install -g @opencode/cli@latest`.

---

## Uninstall

```bash
# native installer
rm -rf ~/.opencode        # then delete the PATH line from your shell rc

# npm
npm uninstall -g @opencode/cli

# Termux wrapper
npm uninstall -g @bash0816/opencode-termux
rm -rf ~/.opencode-termux ~/.opencode
```

Configuration (`~/.config/opencode`) and data (`~/.local/share/opencode`) are separate —
back them up before deleting anything.

---

## Files

```
install-opencode2.sh   installer (bash 3.2+, macOS default bash is fine)
README.md              this guide
PUBLISH.md             how to push this to GitHub / publish as a gist
```

## Sources

- OpenCode V2 docs — <https://opencode.ai/v2/docs/>
- Install page / download matrix — <https://opencode.ai/v2/docs/>
- Release channel metadata — `https://opencode.ai/update/api/latest/cli/npm`
- Termux wrapper — <https://www.npmjs.com/package/@bash0816/opencode-termux>

## License

MIT for the script and this guide. OpenCode itself is MIT; the Termux wrapper is GPL-3.0.
