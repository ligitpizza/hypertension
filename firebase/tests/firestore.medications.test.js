import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where,
} from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 5 medications and dose_logs (FR-5.1-5.4, NFR-2.2; D-43).
let env;
const P = 'u-patient';
const OTHER = 'u-other';
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
    await setDoc(doc(db, `users/${OTHER}`), { role: 'patient', assignedDoctorId: 'someone-else' });
    for (const [id, owner] of [['mine', P], ['theirs', OTHER]]) {
      await setDoc(doc(db, `medications/${id}`),
        { patientId: owner, name: 'Amlodipine', dosage: '5mg', schedule: '08:00' });
      await setDoc(doc(db, `dose_logs/${id}_202610140800`), {
        medicationId: id, scheduledTime: new Date(), status: 'taken', confirmedAt: new Date(),
      });
    }
  });
});

const patient = () => as(env, 'patient', P).firestore();
const doctor = () => as(env, 'doctor', DOCTOR).firestore();
const family = () => as(env, 'family_member').firestore();

describe('FR-5.1 medications are written only through the API', () => {
  test('patient cannot create, edit or delete directly', async () => {
    await assertFails(setDoc(doc(patient(), 'medications/new'),
      { patientId: P, name: 'X', dosage: '1', schedule: '08:00' }));
    await assertFails(updateDoc(doc(patient(), 'medications/mine'), { dosage: '10mg' }));
    await assertFails(deleteDoc(doc(patient(), 'medications/mine')));
  });
});

describe('FR-5.3 dose_logs follow the parent medication', () => {
  const todays = (db, med) => getDocs(query(collection(db, 'dose_logs'),
    where('medicationId', '==', med), where('scheduledTime', '>=', new Date(0))));

  test('patient reads own dose logs (single and query)', async () => {
    await assertSucceeds(getDoc(doc(patient(), 'dose_logs/mine_202610140800')));
    await assertSucceeds(todays(patient(), 'mine'));
  });
  test('assigned doctor reads them', async () => {
    await assertSucceeds(todays(doctor(), 'mine'));
  });
  test('another patient\'s logs are denied', async () => {
    await assertFails(getDoc(doc(patient(), 'dose_logs/theirs_202610140800')));
    await assertFails(todays(patient(), 'theirs'));
    await assertFails(todays(doctor(), 'theirs'));
  });
  test('family cannot read dose logs', async () => {
    await assertFails(todays(family(), 'mine'));
  });
  test('nobody writes dose logs from the client', async () => {
    await assertFails(setDoc(doc(patient(), 'dose_logs/mine_202610142000'),
      { medicationId: 'mine', scheduledTime: new Date(), status: 'taken' }));
    await assertFails(updateDoc(doc(patient(), 'dose_logs/mine_202610140800'),
      { status: 'missed' }));
  });
});
