import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// FR-14.2 family monitoring (UC15.1-UC15.3; D-06, D-62).
let env;
const P = 'u-patient';
const F = 'u-family';

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
    await setDoc(doc(db, `users/${P}`), { role: 'patient', name: 'Siti' });
    await setDoc(doc(db, `users/${F}`), { role: 'family_member', name: 'Aisyah', patientId: P });
    await setDoc(doc(db, 'users/u-stranger'), { role: 'family_member', name: 'X', patientId: null });
    await setDoc(doc(db, 'vital_readings/v1'), { patientId: P, systolic: 120, diastolic: 80 });
    await setDoc(doc(db, 'family_link_requests/r1'), { familyMemberId: 'u-stranger', patientId: P, status: 'pending' });
    await setDoc(doc(db, 'emergency_alerts/e1'), { familyMemberId: F, patientId: P, trigger: 'sos' });
  });
});

describe('UC15.1 the linked family member', () => {
  test('reads the patient they follow and their readings', async () => {
    const db = as(env, 'family_member', F).firestore();
    await assertSucceeds(getDoc(doc(db, `users/${P}`)));
    await assertSucceeds(getDocs(query(collection(db, 'vital_readings'), where('patientId', '==', P))));
  });
  test('an unlinked family member reads nothing (E1 pending state)', async () => {
    const db = as(env, 'family_member', 'u-stranger').firestore();
    await assertFails(getDoc(doc(db, `users/${P}`)));
    await assertFails(getDoc(doc(db, 'vital_readings/v1')));
  });
  test('cannot link themselves by editing their user document', async () => {
    const db = as(env, 'family_member', 'u-stranger').firestore();
    await assertFails(updateDoc(doc(db, 'users/u-stranger'), { patientId: P }));
  });
});

describe('link requests', () => {
  test('the patient and the requester read the request; others cannot', async () => {
    await assertSucceeds(getDoc(doc(as(env, 'patient', P).firestore(), 'family_link_requests/r1')));
    await assertSucceeds(getDoc(doc(as(env, 'family_member', 'u-stranger').firestore(), 'family_link_requests/r1')));
    await assertFails(getDoc(doc(as(env, 'family_member', F).firestore(), 'family_link_requests/r1')));
  });
  test('the patient lists their linked family; nobody writes requests directly', async () => {
    const db = as(env, 'patient', P).firestore();
    await assertSucceeds(
      getDocs(query(collection(db, 'users'), where('role', '==', 'family_member'), where('patientId', '==', P))),
    );
    await assertFails(updateDoc(doc(db, 'family_link_requests/r1'), { status: 'approved' }));
  });
});

describe('UC15.2 emergency alerts', () => {
  test('recipient and patient read; others cannot; no client writes', async () => {
    await assertSucceeds(getDoc(doc(as(env, 'family_member', F).firestore(), 'emergency_alerts/e1')));
    await assertSucceeds(getDoc(doc(as(env, 'patient', P).firestore(), 'emergency_alerts/e1')));
    await assertFails(getDoc(doc(as(env, 'family_member', 'u-stranger').firestore(), 'emergency_alerts/e1')));
    await assertFails(
      updateDoc(doc(as(env, 'family_member', F).firestore(), 'emergency_alerts/e1'), { acknowledgedAt: 1 }),
    );
  });
});
