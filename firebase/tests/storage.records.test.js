import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';
import { as, makeEnv } from './helpers.js';

// D-58 health record files (UC6.1): PDF/JPG/PNG, <= 10 MB, written once by the patient.
let env;
const P = 'u-patient';
const path = `health_records/${P}/r1`;
const pdf = { contentType: 'application/pdf' };

beforeAll(async () => {
  env = await makeEnv();
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), path), new Uint8Array([1, 2, 3]), pdf);
  });
});

const patient = () => as(env, 'patient', P).storage();

describe('upload', () => {
  test('PDF, JPG and PNG into their own folder', async () => {
    for (const [i, contentType] of ['application/pdf', 'image/jpeg', 'image/png'].entries()) {
      await assertSucceeds(uploadBytes(ref(patient(), `health_records/${P}/n${i}`), new Uint8Array([1]), { contentType }));
    }
  });
  test('UC6.1 E1 other types are refused', async () => {
    await assertFails(
      uploadBytes(ref(patient(), `health_records/${P}/n9`), new Uint8Array([1]), { contentType: 'application/msword' }),
    );
  });
  test('larger than 10 MB is refused', async () => {
    await assertFails(uploadBytes(ref(patient(), `health_records/${P}/big`), new Uint8Array(10485761), pdf));
  });
  test('not into another patient\'s folder, and not by staff', async () => {
    await assertFails(uploadBytes(ref(patient(), 'health_records/u-other/n1'), new Uint8Array([1]), pdf));
    const doctor = as(env, 'doctor', 'u-doctor').storage();
    await assertFails(uploadBytes(ref(doctor, 'health_records/u-doctor/n1'), new Uint8Array([1]), pdf));
  });
  test('an existing file cannot be replaced', async () => {
    await assertFails(uploadBytes(ref(patient(), path), new Uint8Array([9]), pdf));
  });
});

describe('read and delete', () => {
  test('the owner reads and deletes', async () => {
    await assertSucceeds(getBytes(ref(patient(), path)));
    await assertSucceeds(deleteObject(ref(patient(), path)));
  });
  test('nobody else reads directly (the doctor goes through FastAPI)', async () => {
    await assertFails(getBytes(ref(as(env, 'doctor', 'u-doctor').storage(), path)));
    await assertFails(getBytes(ref(as(env, 'patient', 'u-other').storage(), path)));
  });
});
