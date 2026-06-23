# coleleavitt-overlay

My personal [Gentoo](https://www.gentoo.org/) overlay (`repo_name = local`).
It mirrors a handful of upstream Gentoo packages, carries some binary and
live ebuilds, and keeps them current automatically via GitHub Actions CI/CD.

`masters = gentoo`, so it layers on top of the main `::gentoo` tree.

## Enabling the overlay

### With eselect-repository (recommended)

```sh
eselect repository add coleleavitt git https://github.com/coleleavitt/coleleavitt-overlay.git
emaint sync -r coleleavitt
```

### Manually (`/etc/portage/repos.conf/coleleavitt.conf`)

```ini
[coleleavitt]
location = /var/db/repos/local
sync-type = git
sync-uri = https://github.com/coleleavitt/coleleavitt-overlay.git
masters = gentoo
auto-sync = yes
```

Then `emerge --sync` (or `emaint sync -r coleleavitt`).

## Installing a package

Most packages are masked behind `~amd64`/`**`. Accept keywords as needed, e.g.
for Cursor:

```sh
echo "app-editors/cursor ~amd64" >> /etc/portage/package.accept_keywords/cursor
emerge -av app-editors/cursor
```

## Packages

| Package | Notes |
| --- | --- |
| `app-editors/cursor` | Cursor — AI-first code editor (prebuilt `.deb`). Mirrored from `::gentoo`. |
| `app-emulation/looking-glass` | Looking Glass (live `9999`). |
| `app-emulation/qemu-stealth` | QEMU with anti-detection patches. |
| `app-misc/screamingfrogseospider` | Screaming Frog SEO Spider (bin). |
| `app-office/logseq` | Logseq knowledge base. |
| `dev-build/cmake` | CMake (auto-updated). |
| `dev-db/surrealdb-bin` | SurrealDB (bin). |
| `dev-lang/spidermonkey` | SpiderMonkey (auto-updated, LLVM-tracking). |
| `dev-lang/swift-bin` | Swift toolchain (bin). |
| `dev-qt/qttools` | Qt tools (auto-updated). |
| `dev-util/bpf-linker` | bpf-linker (auto-updated, LLVM-tracking). |
| `dev-util/mesa_clc` | Mesa standalone CLC (auto-updated). |
| `dev-util/spirv-llvm-translator` | SPIRV-LLVM-Translator (per-LLVM-slot auto-update). |
| `gui-apps/waybar` | Waybar. |
| `gui-libs/egl-wayland` | NVIDIA EGLStream-based Wayland external platform. |
| `gui-wm/niri` | niri scrollable-tiling Wayland compositor. |
| `media-libs/mesa` | Mesa (auto-updated, LLVM-tracking). |
| `net-im/vesktop-bin` | Vesktop (auto-updated). |
| `net-p2p/biglybt-extreme-mod` | BiglyBT Extreme Mod. |
| `net-proxy/mitmproxy-linux` | mitmproxy Linux redirector. |
| `net-wireless/linssid` | LinSSID Wi-Fi scanner. |
| `sci-libs/gsl` | GNU Scientific Library. |
| `sci-ml/ollama` | Ollama LLM runner. |
| `sys-apps/uutils-coreutils` | Rust coreutils (auto-updated, LLVM-tracking). |
| `sys-apps/xdg-desktop-portal` | xdg-desktop-portal. |
| `sys-firmware/edk2` | EDK II UEFI firmware. |
| `sys-firmware/uefitool` | UEFITool (auto-updated). |
| `www-client/torbrowser` | Tor Browser (auto-updated from the Tor Project AUS API). |
| `www-client/zen-browser-bin` | Zen Browser (auto-updated). |
| `x11-drivers/nvidia-drivers` | NVIDIA drivers. |

## CI/CD

Two workflows live under `.github/workflows/`:

### `ci.yml` — Gentoo Overlay QA

Runs [`pkgcheck`](https://github.com/pkgcore/pkgcheck-action) on every push to
`master` and on pull requests. It fails on real QA errors only and excludes a
set of expected overlay-only warnings (live `9999` ebuilds, overlay-specific
licenses/USE flags, `**` keywords, etc.).

### `auto-update.yml` — Auto-update packages

Runs daily (`cron: 0 7 * * *`) and on manual `workflow_dispatch`. It detects
new upstream releases and bumps the corresponding ebuild + `Manifest`, then
commits and pushes to `master` (serialized, one package at a time).

Each package is a matrix entry describing how to detect its latest version
(`check_type`) and how to construct its distfiles. Supported `check_type`s:

| `check_type` | How it detects |
| --- | --- |
| `archive` | scrape a directory index with a regex |
| `github` | latest GitHub release tag |
| `github_tag` | latest matching GitHub tag |
| `mozilla_esr` | Mozilla ESR product-details |
| `spirv_per_slot` | newest SPIRV tag per LLVM slot |
| `torbrowser_torproject` | Tor Project AUS download API |
| `cursor_api` | Cursor official download API (version **and** build commit) |

Most packages are bumped by the generic `.github/scripts/bump-package.sh`.
Packages whose distfile URLs need more than a version string use a dedicated
script:

- `bump-torbrowser.sh` — templates `www-client/torbrowser` from Tor Project release data.
- `bump-cursor.sh` — bumps `app-editors/cursor`, rewriting both the version and the upstream build commit (`BUILD_ID`).

To trigger an update by hand: **Actions → Auto-update packages → Run workflow**,
then pick a package (or `all`).

#### Adding a new auto-updated package

1. Add the package directory (ebuild + `metadata.xml` + `Manifest`).
2. Add the package name to the `workflow_dispatch` `package` choice list.
3. Add a matrix entry under `jobs.update.strategy.matrix.include` with the
   appropriate `check_type` and `downloads`.
4. If the distfile URL needs more than `{VERSION}`, add a `check_type` branch
   in the *Detect latest version* step and a dedicated bump step/script.

##### Example: Cursor (`app-editors/cursor`)

Cursor's `.deb` URL is keyed on both the version *and* a build commit
(`commitSha`), so it can't use the generic bump path:

- `check_type: cursor_api` queries
  `https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=latest`
  and emits `version` + `build_id`.
- `bump-cursor.sh` clones the latest ebuild, rewrites `BUILD_ID`, renames it to
  the new version, downloads the amd64/arm64 debs, and regenerates the
  `Manifest`.

## Licenses

Overlay-specific license texts (e.g. the Cursor EULA) live under `licenses/`
so the overlay is self-contained.

## Disclaimer

This is a personal overlay provided as-is, with no warranty. Binary packages
(Cursor, Zen, Swift, SurrealDB, …) are redistributed under their respective
upstream licenses — review them before use.
