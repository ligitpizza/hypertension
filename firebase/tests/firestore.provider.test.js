import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, doc, getDoc, getDocs, limit, orderBy, query, setDoc, where,
} from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 8 portal reads (FR-8.1, FR-8.2, FR-8.3; docs/04 rules summary).
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
    await setDoc(doc(db, `users/${P}`), { role: 'patient', name: 'Siti', assignedDoctorId: DOCTOR });
    await setDoc(doc(db, `users/${OTHER}`), { role: 'patient', name: 'Ali', assignedDoctorId: 'd2' });
    for (const [id, owner] of [['mine', P], ['theirs', OTHER]]) {
      const doctorId = owner === P ? DOCTOR : 'd2';
      await setDoc(doc(db, `clinical_notes/${id}`),
        { patientId: owner, doctorId, content: 'S: well', createdAt: new Date() });
      await setDoc(doc(db, `prescriptions/${id}`),
        { patientId: owner, doctorId, medicationDetails: 'Losartan 50mg', isRecurring: false, issuedAt: new Date() });
    }
    await setDoc(doc(db, `care_plans/${P}`), { patientId: P, doctorId: DOCTOR, content: 'Plan', updatedAt: new Date() });
    await setDoc(doc(db, `care_plans/${OTHER}`), { patientId: OTHER, doctorId: 'd2', content: 'Plan', updatedAt: new Date() });
  });
});

const doctor = () => as(env, 'doctor', DOCTOR).firestore();
const patient = () => as(env, 'patient', P).firestore();
const pharmacist = () => as(env, 'pharmacist').firestore();
const family = () => as(env, 'family_member').firestore();
const admin = () => as(env, 'admin').firestore();

describe('UC8.1 doctor patient list', () => {
  test('doctor lists only assigned patients', async () => {
    const q = query(collection(doctor(), 'users'),
      where('role', '==', 'patient'), where('assignedDoctorId', '==', DOCTOR));
    await assertSucceeds(getDocs(q));
  });
  test('doctor cannot list all patients', async () => {
    await assertFails(getDocs(query(collection(doctor(), 'users'), where('role', '==', 'patient'))));
  });
});

describe('FR-8.2 doctor reads assigned patient history', () => {
  test.each(['clinical_notes', 'prescriptions', 'care_plans'])('assigned doctor reads %s', async (c) => {
    await assertSucceeds(getDoc(doc(doctor(), `${c}/${c === 'care_plans' ? P : 'mine'}`)));
  });
  test.each(['clinical_notes', 'prescriptions', 'care_plans'])('doctor cannot read another doctor\'s patient %s', async (c) => {
    await assertFails(getDoc(doc(doctor(), `${c}/${c === 'care_plans' ? OTHER : 'theirs'}`)));
  });
  test.each(['vital_readings', 'risk_scores', 'clinical_notes', 'prescriptions'])(
    'patient detail query on %s is allowed', async (c) => {
      const order = { vital_readings: 'timestamp', risk_scores: 'generatedAt',
        clinical_notes: 'createdAt', prescriptions: 'issuedAt' }[c];
      const q = query(collection(doctor(), c), where('patientId', '==', P), orderBy(order, 'desc'), limit(20));
      await assertSucceeds(getDocs(q));
    });
});

describe('docs/04 other readers', () => {
  test('patient reads own note, prescription and care plan', async () => {
    await assertSucceeds(getDoc(doc(patient(), 'clinical_notes/mine')));
    await assertSucceeds(getDoc(doc(patient(), 'prescriptions/mine')));
    await assertSucceeds(getDoc(doc(patient(), `care_plans/${P}`)));
  });
  test('pharmacist reads prescriptions but not notes', async () => {
    await assertSucceeds(getDoc(doc(pharmacist(), 'prescriptions/theirs')));
    await assertFails(getDoc(doc(pharmacist(), 'clinical_notes/mine')));
  });
  test('family cannot read clinical records', async () => {
    await assertFails(getDoc(doc(family(), 'clinical_notes/mine')));
  });
  test('admin reads', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'clinical_notes/theirs')));
  });
});

describe('FR-8.3 writes go through FastAPI only', () => {
  test.each(['clinical_notes', 'prescriptions'])('doctor cannot write %s directly', async (c) => {
    await assertFails(addDoc(collection(doctor(), c), { patientId: P, doctorId: DOCTOR, content: 'x' }));
  });
  test('doctor cannot write the care plan directly', async () => {
    await assertFails(setDoc(doc(doctor(), `care_plans/${P}`), { patientId: P, doctorId: DOCTOR, content: 'x' }));
  });
});
