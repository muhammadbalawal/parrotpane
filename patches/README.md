# terminal-browser Widevine patches

`terminal-browser-widevine.patch` makes zenbu-labs/terminal-browser play DRM video
(Netflix, and anything else using Widevine) so parrotpane can share it.

Applies to upstream commit `b16b8574a026ba0ef451e7e377e12b5747c47706`.

## What it changes

- `browser/src/main.tsx` loads the Widevine CDM through Electron's `components` API.
  castLabs builds ship no CDM until `components.whenReady()` is awaited.
- `browser/src/page/offscreen.ts` uses plain bitmap offscreen rendering on macOS instead of
  the shared-texture mode. Shared textures need zenbu's patched Electron; bitmap works on a
  stock build, which is what lets castLabs' Electron be dropped in.
- `browser/src/page/frame-rate.ts` defaults bitmap mode to 30fps. At the display's native
  60Hz the CPU cannot copy retina frames fast enough and audio drifts out of sync.
- `scripts/release.sh` allows a deliberately swapped Electron via
  `TERMINAL_BROWSER_ALLOW_FOREIGN_ELECTRON=1`.

## Rebuilding

```
git clone https://github.com/zenbu-labs/terminal-browser
cd terminal-browser && git checkout b16b857
git apply /path/to/terminal-browser-widevine.patch
pnpm install
```

Then replace `browser/node_modules/electron/dist` with a castLabs build
(`castlabs/electron-releases`, tag matching the pinned Electron major, e.g. `v43.5.0+wvcus`),
VMP sign it, and build:

```
python3 -m pip install --upgrade castlabs-evs
python3 -m castlabs_evs.account signup
python3 -m castlabs_evs.vmp sign-pkg <dir containing Electron.app>
TERMINAL_BROWSER_ALLOW_FOREIGN_ELECTRON=1 pnpm build:dist && pnpm install:dist
```

Without VMP signing Netflix returns error E100. Without the CDM entirely it returns M7701-1003.
