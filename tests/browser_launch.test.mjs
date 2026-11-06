import assert from 'node:assert/strict';
import test from 'node:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, access, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

test('a missing Chrome keeps ENOENT and removes only its unused profile without claiming a child', async () => {
  const root = await mkdtemp(join(tmpdir(), 'launch-test-'));
  let groupAbsent = false;
  try {
    const evidence = join(root, 'evidence'), missing = join(root, 'missing-chrome');
    const result = spawnSync(process.execPath, ['scripts/browser_smoke.mjs'], {
      cwd: resolve('.'), detached: true, timeout: 10000, encoding: 'utf8',
      env: { ...process.env, TMPDIR: root, CHROME_BIN: missing, DASHBOARD_EVIDENCE_DIR: evidence },
    });
    assert.throws(() => process.kill(-result.pid, 0), { code: 'ESRCH' });
    groupAbsent = true;
    assert.equal(result.error, undefined);
    assert.equal(result.status, 1);
    const errors = JSON.parse(await readFile(join(evidence, 'ERRORS.json'), 'utf8'));
    assert.equal(errors.primaryDetails.code, 'ENOENT');
    assert.equal(errors.primaryDetails.path, missing);
    assert.equal(errors.primaryDetails.syscall, 'spawn ' + missing);
    assert.match(errors.primary, /ENOENT/);
    assert.deepEqual(errors.cleanup, []);
    const terminal = JSON.parse(await readFile(join(evidence, 'CHROME-TERMINAL.json'), 'utf8'));
    assert.equal(terminal.created, false);
    assert.equal(terminal.pid, null);
    assert.equal(terminal.reaped, false);
    const profile = JSON.parse(await readFile(join(evidence, 'PROFILE-TERMINAL.json'), 'utf8'));
    assert.equal(profile.exclusivelyCreated, true);
    assert.equal(profile.noChildCreated, true);
    assert.equal(profile.removed, true);
    await assert.rejects(access(profile.path), { code: 'ENOENT' });
    await assert.rejects(access(join(evidence, 'OWNED-CHROME.json')), { code: 'ENOENT' });
    assert.deepEqual(await readdir(root), ['evidence']);
  } finally {
    if (groupAbsent) await rm(root, { recursive: true });
  }
});
