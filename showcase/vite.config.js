import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';
import { cpSync } from 'node:fs';
import { relative, sep } from 'node:path';

export default defineConfig(({ command, mode }) => {
  const websiteBuild = command === 'build' && mode === 'website';
  const publicPath = fileURLToPath(new URL('./public', import.meta.url));
  const websiteOutput = fileURLToPath(new URL('./dist-website', import.meta.url));
  return {
    plugins: [react(), websiteBuild && {
      name: 'website-public-assets',
      writeBundle() {
        cpSync(publicPath, websiteOutput, {
          recursive: true,
          filter: source => relative(publicPath, source).split(sep)[0] !== 'downloads',
        });
      },
    }],
    // Website-only output excludes local APKs even after a guarded build.
    build: {
      outDir: mode === 'website' ? 'dist-website' : 'dist',
      copyPublicDir: !websiteBuild,
    },
    resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
    assetsInclude: ['**/*.glb'],
  };
});
