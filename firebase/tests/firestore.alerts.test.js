import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, serverTimestamp,
  setDoc, updateDoc, where,
} from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 9 clinical_alerts (D-32, FR-8.4, FR-9.5, FR-9.6) and fcmTokens (D-33).
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
    const base = {
      patientId: P, type: 'threshold', severity: 'critical', message: 'x', createdAt: new Date(),
    };
    await setDoc(doc(db, 'clinical_alerts/mine'), { ...base, doctorId: DOCTOR, status: 'open' });
    await setDoc(doc(db, 'clinical_alerts/done'),
      { ...base, doctorId: DOCTOR, status: 'dismissed', acknowledgedAt: new Date() });
    await setDoc(doc(db, 'clinical_alerts/theirs'), { ...base, doctorId: 'd2', status: 'open' });
    await setDoc(doc(db, `users/${P}/fcmTokens/tok`), { platform: 'android', createdAt: new Date() });
  });
});

const doctor = () => as(env, 'doctor', DOCTOR).firestore();
const otherDoctor = () => as(env, 'doctor', 'd2-other').firestore();
const patient = () => as(env, 'patient', P).firestore();
const family = () => as(env, 'family_member').firestore();
const admin = () => as(env, 'admin').firestore();

describe('D-32 clinical_alerts read', () => {
  test('addressed doctor reads the alert', async () => {
    await assertSucceeds(getDoc(doc(doctor(), 'clinical_alerts/mine')));
  });
  test('FR-8.4 doctor alerts panel query is allowed', async () => {
    const q = query(collection(doctor(), 'clinical_alerts'),
      where('doctorId', '==', DOCTOR), where('status', '==', 'open'), orderBy('createdAt', 'desc'));
    await assertSucceeds(getDocs(q));
  });
  test('another doctor cannot read it', async () => {
    await assertFails(getDoc(doc(otherDoctor(), 'clinical_alerts/mine')));
  });
  test('unfiltered query fails', async () => {
    await assertFails(getDocs(collection(doctor(), 'clinical_alerts')));
  });
  test('admin reads', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'clinical_alerts/theirs')));
  });
  test.each([['patient', patient], ['family', family]])('%s cannot read', async (_, ctx) => {
    await assertFails(getDoc(doc(ctx(), 'clinical_alerts/mine')));
  });
});

describe('D-32 clinical_alerts write', () => {
  test.each(['acknowledged', 'dismissed'])('doctor sets status %s', async (status) => {
    await assertSucceeds(updateDoc(doc(doctor(), 'clinical_alerts/mine'),
      { status, acknowledgedAt: serverTimestamp() }));
  });
  test('doctor cannot reopen a closed alert', async () => {
    await assertFails(updateDoc(doc(doctor(), 'clinical_alerts/done'),
      { status: 'acknowledged', acknowledgedAt: serverTimestamp() }));
  });
  test('doctor cannot change the message or severity', async () => {
    await assertFails(updateDoc(doc(doctor(), 'clinical_alerts/mine'),
      { status: 'dismissed', acknowledgedAt: serverTimestamp(), severity: 'low' }));
  });
  test('doctor cannot backdate acknowledgedAt', async () => {
    await assertFails(updateDoc(doc(doctor(), 'clinical_alerts/mine'),
      { status: 'acknowledged', acknowledgedAt: new Date(2020, 0, 1) }));
  });
  test('another doctor cannot acknowledge', async () => {
    await assertFails(updateDoc(doc(otherDoctor(), 'clinical_alerts/theirs'),
      { status: 'acknowledged', acknowledgedAt: serverTimestamp() }));
  });
  test.each([['doctor', doctor], ['patient', patient], ['admin', admin]])(
    '%s cannot create or delete', async (_, ctx) => {
      await assertFails(addDoc(collection(ctx(), 'clinical_alerts'),
        { patientId: P, doctorId: DOCTOR, type: 'threshold', status: 'open' }));
      await assertFails(deleteDoc(doc(ctx(), 'clinical_alerts/mine')));
    });
});

describe('D-33 fcmTokens are server-only', () => {
  test('owner cannot read or write tokens directly', async () => {
    await assertFails(getDoc(doc(patient(), `users/${P}/fcmTokens/tok`)));
    await assertFails(setDoc(doc(patient(), `users/${P}/fcmTokens/new`), { platform: 'android' }));
  });
  test('admin cannot read tokens', async () => {
    await assertFails(getDoc(doc(admin(), `users/${P}/fcmTokens/tok`)));
  });
});
