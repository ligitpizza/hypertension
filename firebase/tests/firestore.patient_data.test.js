import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, doc, getDoc, getDocs, limit, orderBy, query, setDoc, where,
} from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 2 dashboard reads: vital_readings, risk_scores, medications, appointments
// (FR-2.1, NFR-2.2, docs/04 rules summary).
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
    await setDoc(doc(db, 'users/u-family_member'), { role: 'family_member', patientId: P });
    for (const [id, owner] of [['mine', P], ['theirs', OTHER]]) {
      await setDoc(doc(db, `vital_readings/${id}`),
        { patientId: owner, systolic: 128, diastolic: 82, timestamp: new Date() });
      await setDoc(doc(db, `risk_scores/${id}`),
        { patientId: owner, scores: {}, modelUsed: 'x', generatedAt: new Date() });
      await setDoc(doc(db, `medications/${id}`),
        { patientId: owner, name: 'Lisinopril', dosage: '10mg', schedule: 'morning' });
      await setDoc(doc(db, `appointments/${id}`),
        { patientId: owner, doctorId: owner === P ? DOCTOR : 'd2', dateTime: new Date(), status: 'booked' });
    }
  });
});

const patient = () => as(env, 'patient', P).firestore();
const doctor = () => as(env, 'doctor', DOCTOR).firestore();
const family = () => as(env, 'family_member').firestore();
const pharmacist = () => as(env, 'pharmacist').firestore();
const admin = () => as(env, 'admin').firestore();

const COLLECTIONS = ['vital_readings', 'risk_scores', 'medications', 'appointments'];

describe('FR-2.1 patient reads own dashboard data', () => {
  test.each(COLLECTIONS)('patient reads own %s', async (c) => {
    await assertSucceeds(getDoc(doc(patient(), `${c}/mine`)));
  });
  test.each(COLLECTIONS)('patient cannot read another patient %s', async (c) => {
    await assertFails(getDoc(doc(patient(), `${c}/theirs`)));
  });
  test('dashboard query for latest readings is allowed', async () => {
    const q = query(collection(patient(), 'vital_readings'),
      where('patientId', '==', P), orderBy('timestamp', 'desc'), limit(20));
    await assertSucceeds(getDocs(q));
  });
  test('unfiltered query is denied', async () => {
    await assertFails(getDocs(collection(patient(), 'vital_readings')));
  });
});

describe('NFR-2.2 other roles', () => {
  test.each(COLLECTIONS)('assigned doctor reads %s', async (c) => {
    await assertSucceeds(getDoc(doc(doctor(), `${c}/mine`)));
  });
  test.each(COLLECTIONS)('unassigned doctor cannot read %s', async (c) => {
    await assertFails(getDoc(doc(doctor(), `${c}/theirs`)));
  });
  test.each(['vital_readings', 'risk_scores'])('linked family reads %s (FR-14.2)', async (c) => {
    await assertSucceeds(getDoc(doc(family(), `${c}/mine`)));
    await assertFails(getDoc(doc(family(), `${c}/theirs`)));
  });
  test.each(['medications', 'appointments'])('family cannot read %s', async (c) => {
    await assertFails(getDoc(doc(family(), `${c}/mine`)));
  });
  test.each(COLLECTIONS)('pharmacist cannot read %s', async (c) => {
    await assertFails(getDoc(doc(pharmacist(), `${c}/mine`)));
  });
  test.each(COLLECTIONS)('admin reads %s', async (c) => {
    await assertSucceeds(getDoc(doc(admin(), `${c}/theirs`)));
  });
});

describe('writes are server-only for now', () => {
  test.each(COLLECTIONS)('patient cannot write %s from the client', async (c) => {
    await assertFails(addDoc(collection(patient(), c), { patientId: P }));
  });
  test('dose_logs stay closed until Module 5', async () => {
    await assertFails(getDocs(collection(patient(), 'dose_logs')));
  });
});
