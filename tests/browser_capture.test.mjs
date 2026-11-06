import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, readFile, writeFile, access, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { saveCapture } from '../scripts/browser_capture.mjs';

for (const existing of [false, true]) {
  test('default capture preserves public files, existing folder: ' + existing, async () => {
    const root = await mkdtemp(join(tmpdir(), 'capture-test-'));
    try {
      const images = join(root, 'public'), evidence = join(root, 'run');
      const before = Buffer.from('existing public image'), bytes = Buffer.from('new capture');
      if (existing) { await mkdir(images); await writeFile(join(images, 'view.png'), before); }
      await saveCapture({ evidence, images, name: 'view.png', bytes });
      assert.deepEqual(await readFile(join(evidence, 'screenshots/view.png')), bytes);
      if (existing) assert.deepEqual(await readFile(join(images, 'view.png')), before);
      else await assert.rejects(access(images), { code: 'ENOENT' });
    } finally { await rm(root, { recursive: true }); }
  });
}

test('explicit image update keeps the run original and replaces the public image', async () => {
  const root = await mkdtemp(join(tmpdir(), 'capture-test-'));
  try {
    const images = join(root, 'public'), evidence = join(root, 'run');
    const bytes = Buffer.from('explicit new capture');
    await mkdir(images); await writeFile(join(images, 'view.png'), 'old public image');
    await saveCapture({ evidence, images, name: 'view.png', bytes, updateImages: true });
    assert.deepEqual(await readFile(join(evidence, 'screenshots/view.png')), bytes);
    assert.deepEqual(await readFile(join(images, 'view.png')), bytes);
    await assert.rejects(saveCapture({ evidence, images, name: 'view.png', bytes: Buffer.from('retry'), updateImages: true }), { code: 'EEXIST' });
    assert.deepEqual(await readFile(join(images, 'view.png')), bytes);
  } finally { await rm(root, { recursive: true }); }
});
