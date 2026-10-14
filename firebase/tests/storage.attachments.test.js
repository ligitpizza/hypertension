import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes, deleteObject } from 'firebase/storage';
import { as, makeEnv } from './helpers.js';

// D-52 message attachments: encrypted bytes, written by the sender, read by the two people.
let env;
const P = 'u-patient';
const DOCTOR = 'u-doctor';
const path = `message_attachments/${P}/${DOCTOR}/m1`;
const opaque = { contentType: 'application/octet-stream' };

beforeAll(async () => {
  env = await makeEnv();
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), path), new Uint8Array([1, 2, 3]), opaque);
  });
});

const patient = () => as(env, 'patient', P).storage();
const doctor = () => as(env, 'doctor', DOCTOR).storage();

describe('upload', () => {
  test('the sender uploads opaque bytes to their own folder', async () => {
    await assertSucceeds(
      uploadBytes(ref(patient(), `message_attachments/${P}/${DOCTOR}/m2`), new Uint8Array([1]), opaque),
    );
  });
  test('not into someone else\'s folder', async () => {
    await assertFails(
      uploadBytes(ref(doctor(), `message_attachments/${P}/${DOCTOR}/m3`), new Uint8Array([1]), opaque),
    );
  });
  test('plain image types are refused (must be encrypted bytes)', async () => {
    await assertFails(
      uploadBytes(ref(patient(), `message_attachments/${P}/${DOCTOR}/m4`), new Uint8Array([1]), {
        contentType: 'image/jpeg',
      }),
    );
  });
  test('larger than 10 MB is refused', async () => {
    const big = new Uint8Array(10485760 + 65);
    await assertFails(uploadBytes(ref(patient(), `message_attachments/${P}/${DOCTOR}/m5`), big, opaque));
  });
  test('an existing file cannot be overwritten', async () => {
    await assertFails(uploadBytes(ref(patient(), path), new Uint8Array([9]), opaque));
  });
  test('an existing file cannot be deleted', async () => {
    await assertFails(deleteObject(ref(patient(), path)));
  });
});

describe('download', () => {
  test('sender and recipient can read', async () => {
    await assertSucceeds(getBytes(ref(patient(), path)));
    await assertSucceeds(getBytes(ref(doctor(), path)));
  });
  test('nobody else can', async () => {
    await assertFails(getBytes(ref(as(env, 'patient', 'u-other').storage(), path)));
    await assertFails(getBytes(ref(as(env, 'admin').storage(), path)));
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), path)));
  });
});
