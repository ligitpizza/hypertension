import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 13 (FR-13.x, D-66): orders and stock are written only by FastAPI.
let env;
const P = 'u-patient';

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
    await setDoc(doc(db, 'medication_orders/mine'),
      { patientId: P, paymentStatus: 'pending', fulfilmentStatus: 'awaiting_confirmation' });
    await setDoc(doc(db, 'medication_orders/theirs'),
      { patientId: 'u-other', paymentStatus: 'pending', fulfilmentStatus: 'awaiting_confirmation' });
    await setDoc(doc(db, 'medication_stock/s1'), { name: 'Amlodipine 5mg', units: 100 });
    await setDoc(doc(db, 'payment_transactions/t1'), { orderId: 'mine', amount: 15 });
    await setDoc(doc(db, 'delivery_tracking_events/e1'), { orderId: 'mine', status: 'dispatched' });
  });
});

const patient = () => as(env, 'patient', P).firestore();
const pharmacist = () => as(env, 'pharmacist').firestore();
const admin = () => as(env, 'admin').firestore();
const doctor = () => as(env, 'doctor').firestore();
const family = () => as(env, 'family_member').firestore();

describe('medication_orders', () => {
  test('patient reads own order only', async () => {
    await assertSucceeds(getDoc(doc(patient(), 'medication_orders/mine')));
    await assertFails(getDoc(doc(patient(), 'medication_orders/theirs')));
  });
  test('pharmacist and admin read orders', async () => {
    await assertSucceeds(getDoc(doc(pharmacist(), 'medication_orders/theirs')));
    await assertSucceeds(getDoc(doc(admin(), 'medication_orders/theirs')));
  });
  test('doctor and family cannot read orders', async () => {
    await assertFails(getDoc(doc(doctor(), 'medication_orders/mine')));
    await assertFails(getDoc(doc(family(), 'medication_orders/mine')));
  });
  test('nobody writes orders from the client (e.g. marking itself paid)', async () => {
    await assertFails(updateDoc(doc(patient(), 'medication_orders/mine'), { paymentStatus: 'paid' }));
    await assertFails(updateDoc(doc(pharmacist(), 'medication_orders/mine'), { fulfilmentStatus: 'collected' }));
    await assertFails(setDoc(doc(patient(), 'medication_orders/new'), { patientId: P }));
  });
});

describe('medication_stock', () => {
  test('pharmacist and admin read stock', async () => {
    await assertSucceeds(getDoc(doc(pharmacist(), 'medication_stock/s1')));
    await assertSucceeds(getDoc(doc(admin(), 'medication_stock/s1')));
  });
  test('patients cannot read stock and nobody writes it from the client', async () => {
    await assertFails(getDoc(doc(patient(), 'medication_stock/s1')));
    await assertFails(updateDoc(doc(pharmacist(), 'medication_stock/s1'), { units: 999 }));
  });
});

describe('payment and tracking records stay server-only', () => {
  test.each([['payment_transactions', 't1'], ['delivery_tracking_events', 'e1']])(
    '%s is not readable from the client', async (c, id) => {
      await assertFails(getDoc(doc(patient(), `${c}/${id}`)));
      await assertFails(getDoc(doc(admin(), `${c}/${id}`)));
    });
});
