# Kesor showcase

React/Vite product website with English/Khmer copy, light/dark themes and local
fonts/screenshots. This is a separate static website; it does not run the banking
backend. Node 24/npm 11 are the locally verified toolchain.

## Preview without APKs

From the repository root:

```powershell
npm --prefix showcase ci
npm --prefix showcase run dev:website
npm --prefix showcase run build:website
npm --prefix showcase run preview:website
```

Run the dev and preview servers separately. These explicit website commands do
not require `.local/` release records or canonical APKs. `build:website` writes
`dist-website/`, excluding `public/downloads/` even if local APKs already exist.
It keeps the regular `dist/` artifact separate. Download buttons remain in the
page, but no APK availability is established by a website-only build.

## Prepare verified downloads locally

The existing `npm run dev` and `npm run build` commands first run
`scripts/sync-apks.mjs`. They require both canonical APKs, the active release
record and matching verification evidence under the ignored repository/app
`.local/` directories. The script verifies size/hash, Railway origin, signature,
ZIP CRC and absence of `.env` entries before copying into `public/downloads/`.
It does not rebuild an app. `npm run sync:apks` refreshes an already-running
development server; `npm run build` produces `dist/` with verified downloads.

Do not invent verification records or bypass this guard to distribute APKs.
See [DEPLOYMENT.md](../docs/DEPLOYMENT.md) for current canonical paths and release
verification. Both output directories, dependencies and generated downloads stay
ignored; commit source assets and the npm lockfile.

## Files and hosting

- `src/App.jsx`, `Hero.jsx`, `Splash.jsx`: page composition and entrances.
- `src/data.js`, `i18n.js`, `Preferences.jsx`: product links/content, Khmer copy and preferences.
- `src/components/`: interactive visual components.
- `public/`: licensed fonts, branding, screenshots and team art.
- `hosting/`: Nginx Dockerfile/configuration for an isolated deployment payload.

The hosting Dockerfile expects a prepared `site/` directory beside it; it is not
a source-build Dockerfile. Read the deployment runbook before packaging. The last
recorded live deployment is website-only, and hosted APK delivery is deferred.
Local build success does not establish live download availability. Deployment
requires explicit user authorization and the specific showcase service IDs.
