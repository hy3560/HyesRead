const { readFileSync } = require('node:fs');
const { join } = require('node:path');

function validateVersions(root, tag) {
  const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
  const tauriVersion = JSON.parse(readFileSync(join(root, 'src-tauri/tauri.conf.json'), 'utf8')).version;
  const cargo = readFileSync(join(root, 'src-tauri/Cargo.toml'), 'utf8');
  const cargoVersion = cargo.match(/\[package\][\s\S]*?\bversion\s*=\s*"([^"]+)"/)?.[1];
  const lock = readFileSync(join(root, 'src-tauri/Cargo.lock'), 'utf8');
  const lockVersion = lock.match(/\[\[package\]\]\s+name = "hyes-read"\s+version = "([^"]+)"/)?.[1];
  if (!/^\d+\.\d+\.\d+$/.test(version) || tag !== `v${version}`
    || [tauriVersion, cargoVersion, lockVersion].some(value => value !== version)) {
    throw new Error('Release tag and frontend/Tauri/Cargo versions must match');
  }
  return version;
}

function requireSuccessfulQuality(runs, sha) {
  const matching = runs.filter(run => run.head_sha === sha && run.head_branch === 'main' && run.event === 'push');
  matching.sort((a, b) => b.id - a.id || (b.run_attempt || 1) - (a.run_attempt || 1));
  const latest = matching[0];
  if (!latest || latest.status !== 'completed' || latest.conclusion !== 'success') {
    throw new Error('The latest main quality run for this exact commit has not passed');
  }
  return latest;
}

module.exports = { validateVersions, requireSuccessfulQuality };
