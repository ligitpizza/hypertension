import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 6 health records (FR-6.1, FR-6.2; UC6.1-UC6.3; D-58).
let env;
const P = 'u-patient';
const DOCTOR = 'u-doctor';

beforeAll(async () => {
  env = await makeEnv();
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${P}`), { role: 'patient', assignedDoctorId: DOCTOR });
    const base = { patientId: P, category: 'lab_result', fileUrl: `health_records/${P}/x` };
    await setDoc(doc(db, 'health_records/shared'), { ...base, sharedWithDoctor: true });
    await setDoc(doc(db, 'health_records/private'), { ...base, sharedWithDoctor: false });
  });
});

describe('UC6.1 the patient', () => {
  test('lists their own records', async () => {
    const db = as(env, 'patient', P).firestore();
    await assertSucceeds(getDocs(query(collection(db, 'health_records'), where('patientId', '==', P))));
  });
  test('cannot read another patient\'s records', async () => {
    const db = as(env, 'patient', 'u-other').firestore();
    await assertFails(getDoc(doc(db, 'health_records/shared')));
  });
  test('cannot write records directly (FastAPI only)', async () => {
    const db = as(env, 'patient', P).firestore();
    await assertFails(setDoc(doc(db, 'health_records/new'), { patientId: P, category: 'other' }));
    await assertFails(updateDoc(doc(db, 'health_records/private'), { sharedWithDoctor: true }));
  });
});

describe('UC6.3 the doctor', () => {
  test('the assigned doctor reads shared records only', async () => {
    const db = as(env, 'doctor', DOCTOR).firestore();
    await assertSucceeds(getDoc(doc(db, 'health_records/shared')));
    await assertFails(getDoc(doc(db, 'health_records/private')));
    await assertSucceeds(
      getDocs(query(collection(db, 'health_records'), where('patientId', '==', P), where('sharedWithDoctor', '==', true))),
    );
    await assertFails(getDocs(query(collection(db, 'health_records'), where('patientId', '==', P))));
  });
  test('another doctor reads nothing', async () => {
    const db = as(env, 'doctor', 'u-doctor2').firestore();
    await assertFails(getDoc(doc(db, 'health_records/shared')));
  });
});
