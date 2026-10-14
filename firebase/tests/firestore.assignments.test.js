import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// D-54 doctor assignment requests (FR-7.2, UC7.3).
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
    await setDoc(doc(db, 'doctor_assignment_requests/r1'), {
      patientId: P, requestedBy: DOCTOR, kind: 'reassign', status: 'pending',
    });
    await setDoc(doc(db, 'doctor_assignment_requests/r2'), {
      patientId: 'u-other', requestedBy: 'u-other', kind: 'new_patient', status: 'pending',
    });
  });
});

describe('reading', () => {
  test('admin reads every request', async () => {
    await assertSucceeds(getDocs(collection(as(env, 'admin').firestore(), 'doctor_assignment_requests')));
  });
  test('the patient sees requests about them', async () => {
    const db = as(env, 'patient', P).firestore();
    await assertSucceeds(getDocs(query(collection(db, 'doctor_assignment_requests'), where('patientId', '==', P))));
    await assertFails(getDoc(doc(db, 'doctor_assignment_requests/r2')));
  });
  test('the requesting doctor sees their own request', async () => {
    const db = as(env, 'doctor', DOCTOR).firestore();
    await assertSucceeds(getDoc(doc(db, 'doctor_assignment_requests/r1')));
    await assertFails(getDoc(doc(db, 'doctor_assignment_requests/r2')));
  });
});

describe('writing', () => {
  test('nobody writes from the client (API only)', async () => {
    await assertFails(setDoc(doc(as(env, 'patient', P).firestore(), 'doctor_assignment_requests/r3'), {
      patientId: P, requestedBy: P, kind: 'new_patient', status: 'pending',
    }));
    await assertFails(updateDoc(doc(as(env, 'admin').firestore(), 'doctor_assignment_requests/r1'), {
      status: 'approved',
    }));
  });
});

describe('doctors list (reassignment suggestions)', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/u-doctor'), { role: 'doctor', name: 'Dr John' });
      await setDoc(doc(db, 'users/d2'), { role: 'doctor', name: 'Dr Aminah' });
      await setDoc(doc(db, 'users/u-other'), { role: 'patient', name: 'Ali', assignedDoctorId: 'd2' });
    });
  });
  test('a doctor can list other doctors', async () => {
    const db = as(env, 'doctor', 'u-doctor').firestore();
    await assertSucceeds(getDocs(query(collection(db, 'users'), where('role', '==', 'doctor'))));
  });
  test('but not another doctor\'s patients', async () => {
    await assertFails(getDoc(doc(as(env, 'doctor', 'u-doctor').firestore(), 'users/u-other')));
  });
  test('patients cannot list doctors', async () => {
    const db = as(env, 'patient', 'u-patient').firestore();
    await assertFails(getDocs(query(collection(db, 'users'), where('role', '==', 'doctor'))));
  });
});
