import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, doc, getDoc, getDocs, limitToLast, orderBy, query, serverTimestamp,
  setDoc, updateDoc, where,
} from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 10 secure messaging (FR-10.1, UC10.1, UC10.3 E1; NFR-2.1; D-07, D-42).
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
    await setDoc(doc(db, `users/${DOCTOR}`), { role: 'doctor', name: 'Dr John', email: 'j@x.my' });
    await setDoc(doc(db, 'users/d2'), { role: 'doctor', name: 'Dr Two' });
    await setDoc(doc(db, 'messages/m1'), {
      senderId: P, recipientId: DOCTOR, encryptedText: 'abc', isFlagged: true,
      sentAt: new Date(), senderPublicKey: 'pk1', recipientPublicKey: 'pk2',
    });
  });
});

const patient = () => as(env, 'patient', P).firestore();
const doctor = () => as(env, 'doctor', DOCTOR).firestore();

function msg(senderId, recipientId, extra = {}) {
  return {
    senderId, recipientId, encryptedText: 'ciphertext', isFlagged: false,
    sentAt: serverTimestamp(), senderPublicKey: 'a', recipientPublicKey: 'b', ...extra,
  };
}

describe('D-42 keys and the doctor profile', () => {
  test('a user publishes their own public key', async () => {
    await assertSucceeds(updateDoc(doc(patient(), `users/${P}`), { publicKey: 'base64key' }));
  });
  test('a user cannot change role while publishing a key', async () => {
    await assertFails(updateDoc(doc(patient(), `users/${P}`), { publicKey: 'k', role: 'admin' }));
  });
  test('a patient reads only their assigned doctor', async () => {
    await assertSucceeds(getDoc(doc(patient(), `users/${DOCTOR}`)));
    await assertFails(getDoc(doc(patient(), 'users/d2')));
  });
});

describe('FR-10.1 sending', () => {
  test('patient -> assigned doctor', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'messages'), msg(P, DOCTOR)));
  });
  test('doctor -> assigned patient', async () => {
    await assertSucceeds(addDoc(collection(doctor(), 'messages'), msg(DOCTOR, P)));
  });
  test('patient cannot message another doctor', async () => {
    await assertFails(addDoc(collection(patient(), 'messages'), msg(P, 'd2')));
  });
  test('doctor cannot message an unassigned patient', async () => {
    await assertFails(addDoc(collection(doctor(), 'messages'), msg(DOCTOR, OTHER)));
  });
  test('cannot send as someone else', async () => {
    await assertFails(addDoc(collection(patient(), 'messages'), msg(DOCTOR, P)));
  });
  test('cannot backdate or add unknown fields', async () => {
    await assertFails(addDoc(collection(patient(), 'messages'), msg(P, DOCTOR, { sentAt: new Date(2020, 0, 1) })));
    await assertFails(addDoc(collection(patient(), 'messages'), msg(P, DOCTOR, { plaintext: 'leak' })));
  });
});

describe('reading', () => {
  test('both participants read; others cannot', async () => {
    await assertSucceeds(getDoc(doc(patient(), 'messages/m1')));
    await assertSucceeds(getDoc(doc(doctor(), 'messages/m1')));
    await assertFails(getDoc(doc(as(env, 'patient', OTHER).firestore(), 'messages/m1')));
    await assertFails(getDoc(doc(as(env, 'admin').firestore(), 'messages/m1')));
  });
  test('thread query in one direction is allowed', async () => {
    const q = query(collection(patient(), 'messages'),
      where('senderId', '==', P), where('recipientId', '==', DOCTOR), orderBy('sentAt'), limitToLast(100));
    await assertSucceeds(getDocs(q));
  });
  test('inbox query by recipient is allowed', async () => {
    const q = query(collection(doctor(), 'messages'), where('recipientId', '==', DOCTOR), orderBy('sentAt', 'desc'));
    await assertSucceeds(getDocs(q));
  });
});

describe('UC10.3 E1 dismissing a flag', () => {
  test('the receiving doctor clears the flag', async () => {
    await assertSucceeds(updateDoc(doc(doctor(), 'messages/m1'), { isFlagged: false }));
  });
  test('the patient cannot clear it, and nobody can edit the text', async () => {
    await assertFails(updateDoc(doc(patient(), 'messages/m1'), { isFlagged: false }));
    await assertFails(updateDoc(doc(doctor(), 'messages/m1'), { encryptedText: 'x' }));
  });
});
