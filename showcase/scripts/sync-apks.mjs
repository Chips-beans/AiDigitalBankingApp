// Package the latest locally verified Railway APKs, without rebuilding either app.
// Run automatically before dev/build; APKs and generated metadata stay out of Git.
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { copyFile, mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repo = resolve(site, '..');
const destination = join(site, 'public', 'downloads');
const apiBase = 'https://backend-production-18646.up.railway.app/api/v1';
const files = [
  { app: 'customer_app', source: 'Kesor Bank.apk', file: 'kesor-bank.apk' },
  { app: 'merchant_app', source: 'KesorMerchant.apk', file: 'kesor-merchant.apk' },
];
const json = async path => JSON.parse(await readFile(path, 'utf8'));
const sha256 = async path => {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
};

try {
  const active = await json(join(repo, '.local', 'apk-refresh-active.json'));
  if (!/^\d{8}-\d{6}$/.test(active.stamp) || active.apiBase !== apiBase) throw new Error('The current APK record is not a verified Railway release.');
  const verified = await json(join(repo, '.local', `apk-refresh-${active.stamp}`, 'verification.json'));
  if (verified.stamp !== active.stamp || verified.apiBase !== apiBase) throw new Error('APK release records disagree.');
  const releases = [];
  for (const entry of files) {
    const source = join(repo, 'frontend', entry.app, '.local', 'apk', entry.source);
    const record = verified.apps.find(app => app.app === entry.app);
    if (!record?.railwayUrlPresent || record.envEntryCount !== 0 || !record.zipCrcValid || !record.signatureVerified) throw new Error(`${entry.app} is not verified for distribution.`);
    if ((await stat(source)).size !== record.bytes || await sha256(source) !== record.sha256.toLowerCase()) throw new Error(`${entry.app} differs from the latest verified APK. Refresh its verification before packaging.`);
    releases.push({ ...entry, sourcePath: source, bytes: record.bytes, sha256: record.sha256.toLowerCase() });
  }
  await mkdir(destination, { recursive: true });
  for (const release of releases) {
    const target = join(destination, release.file);
    const unchanged = await stat(target).then(info => info.size === release.bytes).catch(() => false);
    if (!unchanged || await sha256(target) !== release.sha256) {
      const temporary = `${target}.part`;
      await copyFile(release.sourcePath, temporary);
      if (await sha256(temporary) !== release.sha256) throw new Error(`${release.app} changed while being copied.`);
      await rename(temporary, target);
    }
    console.log(`Verified ${release.file}: ${release.bytes} bytes, SHA-256 ${release.sha256}`);
  }
  await writeFile(join(destination, 'manifest.json'), `${JSON.stringify({
    buildStamp: active.stamp,
    apiBase,
    apps: releases.map(({ app, file, bytes, sha256 }) => ({ app, file, bytes, sha256 })),
  }, null, 2)}\n`);
} catch (error) {
  console.error(`APK download preparation failed: ${error.message}`);
  console.error('This checkout needs both canonical APKs and the latest .local/apk-refresh verification records. See docs/DEPLOYMENT.md.');
  process.exitCode = 1;
}
