import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

export async function saveCapture({ evidence, images, name, bytes, updateImages = false }) {
  await mkdir(join(evidence, 'screenshots'), { recursive: true });
  await writeFile(join(evidence, 'screenshots', name), bytes, { flag: 'wx' });
  if (updateImages === true) {
    await mkdir(images, { recursive: true });
    await writeFile(join(images, name), bytes);
  }
}
