const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const { spawnSync } = require('node:child_process');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

// Exercise the actual instances used by Tailwind, not an unused direct dependency.
const tailwindRequire = createRequire(require.resolve('tailwindcss'));
const instances = [
  tailwindRequire('braces'),
  createRequire(tailwindRequire.resolve('chokidar'))('braces'),
  createRequire(tailwindRequire.resolve('micromatch'))('braces'),
];
for (const braces of new Set(instances)) {
  assert.deepEqual(braces.expand('src/{app,lib}/**/*.{ts,tsx}'), [
    'src/app/**/*.ts', 'src/app/**/*.tsx', 'src/lib/**/*.ts', 'src/lib/**/*.tsx',
  ]);
  for (const size of [100, 1000, 10000]) {
    for (const pattern of ['{'.repeat(size) + 'a,b' + '}'.repeat(size), '('.repeat(size) + 'a' + ')'.repeat(size), '{'.repeat(size)]) {
      for (const method of ['parse', 'compile', 'expand', 'stringify']) {
        assert.throws(() => braces[method](pattern), error => error instanceof SyntaxError && /safe nesting depth|exceeds max characters/.test(error.message));
      }
    }
  }
  let ast = { type: 'text', value: 'a' };
  for (let i = 0; i < 1000; i++) ast = { type: 'root', nodes: [ast] };
  for (const method of ['compile', 'expand', 'stringify']) {
    assert.throws(() => braces[method](ast), /safe nesting depth/);
    const cyclic = { type: 'root', nodes: [] };
    cyclic.nodes.push(cyclic);
    assert.throws(() => braces[method](cyclic), /repeated nodes/);
  }
}
console.log('braces depth mitigation: regression checks passed for Tailwind dependencies');
if (process.argv.includes('--verify-only')) process.exit(0);

const audit = spawnSync('pnpm audit --registry=https://registry.npmjs.org --json', { shell: true, encoding: 'utf8', timeout: 120000 });
if (audit.error) throw audit.error;
let report;
try { report = JSON.parse(audit.stdout); } catch { throw new Error(`Dependency audit returned invalid JSON: ${audit.stderr}`); }
if (!report.metadata?.vulnerabilities || report.error) throw new Error('Dependency audit failed to obtain a valid registry report');
const advisories = Object.values(report.advisories || {});
const packageJson = JSON.parse(readFileSync(resolve(__dirname, '../package.json'), 'utf8'));
const tailwindIsDevOnly = !!packageJson.devDependencies?.tailwindcss && !packageJson.dependencies?.tailwindcss;
const accepted = advisories.filter(item => item.github_advisory_id === 'GHSA-vfj7-8cjw-p6xm'
  && item.module_name === 'braces'
  && tailwindIsDevOnly
  && item.findings?.length > 0
  && item.findings.every(finding => finding.version === '3.0.3'
    && finding.dev !== false
    && finding.paths?.length > 0
    && finding.paths.every(path => /^\.>tailwindcss>(?:chokidar|micromatch|fast-glob>micromatch)>braces$/.test(path))));
const remaining = advisories.filter(item => !accepted.includes(item));
for (const item of accepted) console.log(`Locally mitigated (upstream still reported): ${item.github_advisory_id}`);
for (const item of remaining) console.error(`${item.severity}: ${item.module_name} ${item.github_advisory_id}`);
const count = Object.values(report.metadata.vulnerabilities).reduce((sum, value) => sum + Number(value), 0);
if (remaining.length || (count > 0 && !advisories.length) || (audit.status !== 0 && count === 0)) process.exit(1);
console.log('Dependency audit: no unmitigated advisories');
