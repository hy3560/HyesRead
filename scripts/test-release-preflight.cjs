const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { validateVersions, requireSuccessfulQuality } = require('./release-preflight.cjs');
const success = { id: 1, head_sha: 'release', head_branch: 'main', event: 'push', status: 'completed', conclusion: 'success' };
assert.equal(requireSuccessfulQuality([success], 'release'), success);
for (const changes of [{ head_sha: 'old' }, { head_branch: 'feature' }, { event: 'pull_request' }, { status: 'in_progress' }, { conclusion: 'failure' }, { conclusion: 'cancelled' }]) {
  assert.throws(() => requireSuccessfulQuality([{ ...success, ...changes }], 'release'));
}
assert.throws(() => requireSuccessfulQuality([], 'release'));
assert.throws(() => requireSuccessfulQuality([success, { ...success, id: 2, status: 'queued', conclusion: null }], 'release'));
const directory = mkdtempSync(join(tmpdir(), 'hyesread-release-gate-'));
try {
  mkdirSync(join(directory, 'src-tauri'));
  writeFileSync(join(directory, 'package.json'), JSON.stringify({ version: '0.1.27' }));
  writeFileSync(join(directory, 'src-tauri/tauri.conf.json'), JSON.stringify({ version: '0.1.27' }));
  writeFileSync(join(directory, 'src-tauri/Cargo.toml'), '[package]\nname = "hyes-read"\nversion = "0.1.27"\n');
  writeFileSync(join(directory, 'src-tauri/Cargo.lock'), '[[package]]\nname = "hyes-read"\nversion = "0.1.27"\n');
  assert.equal(validateVersions(directory, 'v0.1.27'), '0.1.27');
  assert.throws(() => validateVersions(directory, 'v0.1.26'));
  writeFileSync(join(directory, 'src-tauri/tauri.conf.json'), JSON.stringify({ version: '0.1.26' }));
  assert.throws(() => validateVersions(directory, 'v0.1.27'));
} finally {
  rmSync(directory, { recursive: true, force: true });
}
console.log('Release preflight: exact commit, latest run and version consistency checks passed');
