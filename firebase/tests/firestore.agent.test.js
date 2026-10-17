import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, doc, getDoc, getDocs, limit, orderBy, query, setDoc, where,
} from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// FR-14.1 AI Health Agent history (agent_messages, Table 4.2.3.16; D-34).
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
    await setDoc(doc(db, `users/${P}`), { role: 'patient', assignedDoctorId: 'u-doctor' });
    await setDoc(doc(db, 'users/u-other'), { role: 'patient', assignedDoctorId: 'd2' });
    await setDoc(doc(db, 'agent_messages/mine'), { patientId: P, role: 'agent', text: 'hi', sentAt: new Date() });
    await setDoc(doc(db, 'agent_messages/theirs'), { patientId: 'u-other', role: 'agent', text: 'hi', sentAt: new Date() });
  });
});

const patient = () => as(env, 'patient', P).firestore();

describe('FR-14.1 agent_messages', () => {
  test('patient reads own chat history query', async () => {
    const q = query(collection(patient(), 'agent_messages'),
      where('patientId', '==', P), orderBy('sentAt', 'asc'), limit(100));
    await assertSucceeds(getDocs(q));
  });
  test('patient cannot read another patient\'s chat', async () => {
    await assertFails(getDoc(doc(patient(), 'agent_messages/theirs')));
  });
  test('assigned doctor can read; others cannot', async () => {
    await assertSucceeds(getDoc(doc(as(env, 'doctor', 'u-doctor').firestore(), 'agent_messages/mine')));
    await assertFails(getDoc(doc(as(env, 'family_member').firestore(), 'agent_messages/mine')));
    await assertFails(getDoc(doc(as(env, 'pharmacist').firestore(), 'agent_messages/mine')));
  });
  test('nobody writes directly (FastAPI only, so replies cannot be forged)', async () => {
    await assertFails(addDoc(collection(patient(), 'agent_messages'),
      { patientId: P, role: 'agent', text: 'forged', sentAt: new Date() }));
  });
});

describe('FR-14.3 triage_outcomes', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'triage_outcomes/mine'),
        { patientId: P, symptoms: ['headache'], severity: 'mild', outcome: 'monitor_at_home', generatedAt: new Date() });
    });
  });
  test('patient and assigned doctor read; family cannot', async () => {
    await assertSucceeds(getDoc(doc(patient(), 'triage_outcomes/mine')));
    await assertSucceeds(getDoc(doc(as(env, 'doctor', 'u-doctor').firestore(), 'triage_outcomes/mine')));
    await assertFails(getDoc(doc(as(env, 'family_member').firestore(), 'triage_outcomes/mine')));
  });
  test('outcomes cannot be written from the app (no forged results)', async () => {
    await assertFails(addDoc(collection(patient(), 'triage_outcomes'),
      { patientId: P, symptoms: [], severity: 'mild', outcome: 'monitor_at_home' }));
  });
});

describe('D-76 Harvey AI notes in the doctor chat', () => {
  test('patient and assigned doctor query the chat alerts; another doctor cannot', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'agent_messages/alert'),
        { patientId: P, role: 'agent', kind: 'chat_alert', doctorId: 'u-doctor', text: 'x', sentAt: new Date() });
    });
    const alerts = (db) => query(collection(db, 'agent_messages'),
      where('patientId', '==', P), where('kind', '==', 'chat_alert'), orderBy('sentAt', 'asc'));
    await assertSucceeds(getDocs(alerts(patient())));
    await assertSucceeds(getDocs(alerts(as(env, 'doctor', 'u-doctor').firestore())));
    await assertFails(getDocs(alerts(as(env, 'doctor', 'd2').firestore())));
  });
});

