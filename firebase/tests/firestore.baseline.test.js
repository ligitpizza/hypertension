import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, addDoc, collection } from 'firebase/firestore';
import { ROLES, as, makeEnv } from './helpers.js';

let env;

beforeAll(async () => {
  env = await makeEnv();
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'symptom_catalog/chest_pain'),
      { name: 'Chest Pain', category: 'common', isRedFlag: true });
    await setDoc(doc(ctx.firestore(), 'unlisted_collection/x1'), { note: 'no rule opens this' });
  });
});

describe('Inc0 baseline: symptom_catalog (UC14.1, server-only writes)', () => {
  test.each(ROLES)('%s can read symptom_catalog', async (role) => {
    await assertSucceeds(getDoc(doc(as(env, role).firestore(), 'symptom_catalog/chest_pain')));
  });

  test('unauthenticated user cannot read symptom_catalog', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'symptom_catalog/chest_pain')));
  });

  test.each(ROLES)('%s cannot write symptom_catalog', async (role) => {
    await assertFails(setDoc(doc(as(env, role).firestore(), 'symptom_catalog/x'),
      { name: 'X', category: 'common', isRedFlag: false }));
  });
});

describe('Inc0 baseline: audit_logs are server-only (FR-1.5)', () => {
  test.each(ROLES)('%s cannot create audit_logs', async (role) => {
    await assertFails(addDoc(collection(as(env, role).firestore(), 'audit_logs'),
      { userId: `u-${role}`, action: 'FORGED', details: '', timestamp: new Date() }));
  });
});

describe('Inc0 baseline: deny by default until a module opens access (NFR-2.2)', () => {
  // medication_orders opened with Module 13 (D-66); see firestore.orders.test.js.
  test.each(ROLES)('%s cannot read a collection no rule opens', async (role) => {
    await assertFails(getDoc(doc(as(env, role).firestore(), 'unlisted_collection/x1')));
  });

  test('unauthenticated user cannot write anywhere', async () => {
    await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'users/x'), { name: 'x' }));
  });
});
