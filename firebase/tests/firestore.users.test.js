import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where,
} from 'firebase/firestore';
import { as, makeEnv } from './helpers.js';

// Module 1 rules: users + health_profiles (FR-1.3, NFR-2.2, docs/04 rules summary).
let env;

const PATIENT = 'u-patient';
const OTHER_PATIENT = 'u-other-patient';
const DOCTOR = 'u-doctor';
const OTHER_DOCTOR = 'u-other-doctor';

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
    await setDoc(doc(db, `users/${PATIENT}`), {
      email: 'p@x.my', name: 'Pat', role: 'patient', isActive: true,
      onboardingComplete: true, assignedDoctorId: DOCTOR, linkCode: 'ABC234',
    });
    await setDoc(doc(db, `users/${OTHER_PATIENT}`), {
      email: 'o@x.my', name: 'Other', role: 'patient', isActive: true,
      onboardingComplete: true, assignedDoctorId: OTHER_DOCTOR,
    });
    await setDoc(doc(db, `users/${DOCTOR}`), { email: 'd@x.my', name: 'Dr', role: 'doctor', isActive: true });
    await setDoc(doc(db, 'users/u-family_member'), {
      email: 'f@x.my', name: 'Fam', role: 'family_member', isActive: true, patientId: PATIENT,
    });
    await setDoc(doc(db, `health_profiles/${PATIENT}`), {
      patientId: PATIENT, personalInfo: '{}', medicalHistory: '{}', lifestyleFactors: '{}',
    });
    await setDoc(doc(db, `health_profiles/${OTHER_PATIENT}`), {
      patientId: OTHER_PATIENT, personalInfo: '{}', medicalHistory: '{}', lifestyleFactors: '{}',
    });
  });
});

const patient = () => as(env, 'patient', PATIENT).firestore();
const doctor = () => as(env, 'doctor', DOCTOR).firestore();
const family = () => as(env, 'family_member').firestore();
const pharmacist = () => as(env, 'pharmacist').firestore();
const admin = () => as(env, 'admin').firestore();

describe('FR-1.3 users: read access per role', () => {
  test('patient reads own profile', async () => {
    await assertSucceeds(getDoc(doc(patient(), `users/${PATIENT}`)));
  });
  test('patient cannot read another patient', async () => {
    await assertFails(getDoc(doc(patient(), `users/${OTHER_PATIENT}`)));
  });
  test('doctor reads an assigned patient', async () => {
    await assertSucceeds(getDoc(doc(doctor(), `users/${PATIENT}`)));
  });
  test('doctor cannot read an unassigned patient', async () => {
    await assertFails(getDoc(doc(doctor(), `users/${OTHER_PATIENT}`)));
  });
  test('doctor can list only assigned patients (FR-8.1 query)', async () => {
    const q = query(collection(doctor(), 'users'),
      where('role', '==', 'patient'), where('assignedDoctorId', '==', DOCTOR));
    await assertSucceeds(getDocs(q));
    await assertFails(getDocs(query(collection(doctor(), 'users'), where('role', '==', 'patient'))));
  });
  test('family member cannot read the patient users doc', async () => {
    await assertFails(getDoc(doc(family(), `users/${PATIENT}`)));
  });
  test('family member reads own profile', async () => {
    await assertSucceeds(getDoc(doc(family(), 'users/u-family_member')));
  });
  test('pharmacist cannot read patients', async () => {
    await assertFails(getDoc(doc(pharmacist(), `users/${PATIENT}`)));
  });
  test('admin reads any user', async () => {
    await assertSucceeds(getDoc(doc(admin(), `users/${OTHER_PATIENT}`)));
  });
  test('unauthenticated cannot read users', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), `users/${PATIENT}`)));
  });
});

describe('FR-1.1 / FR-1.6 users: writes', () => {
  test('nobody can create a users doc from the client (server-only)', async () => {
    await assertFails(setDoc(doc(as(env, 'patient', 'u-new').firestore(), 'users/u-new'),
      { email: 'n@x.my', name: 'New', role: 'patient', isActive: true }));
    await assertFails(setDoc(doc(admin(), 'users/u-x'), { role: 'admin' }));
  });
  test('patient can change own name', async () => {
    await assertSucceeds(updateDoc(doc(patient(), `users/${PATIENT}`), { name: 'Patricia' }));
  });
  test('patient cannot escalate own role', async () => {
    await assertFails(updateDoc(doc(patient(), `users/${PATIENT}`), { role: 'admin' }));
  });
  test('patient cannot change account status or onboarding flag', async () => {
    await assertFails(updateDoc(doc(patient(), `users/${PATIENT}`), { isActive: false, name: 'x' }));
    await assertFails(updateDoc(doc(patient(), `users/${PATIENT}`), { onboardingComplete: false }));
  });
  test('patient cannot choose own doctor', async () => {
    await assertFails(updateDoc(doc(patient(), `users/${PATIENT}`), { assignedDoctorId: OTHER_DOCTOR }));
  });
  test('family member cannot link itself to another patient', async () => {
    await assertFails(updateDoc(doc(family(), 'users/u-family_member'), { patientId: OTHER_PATIENT }));
  });
  test('doctor cannot edit a patient users doc', async () => {
    await assertFails(updateDoc(doc(doctor(), `users/${PATIENT}`), { name: 'x' }));
  });
  test('admin can deactivate and reassign (FR-11.1, FR-11.2)', async () => {
    await assertSucceeds(updateDoc(doc(admin(), `users/${PATIENT}`),
      { isActive: false, assignedDoctorId: OTHER_DOCTOR }));
  });
  test('admin cannot change a role directly (claims are set by FastAPI)', async () => {
    await assertFails(updateDoc(doc(admin(), `users/${PATIENT}`), { role: 'doctor' }));
  });
  test('no client can delete a user', async () => {
    await assertFails(deleteDoc(doc(admin(), `users/${PATIENT}`)));
    await assertFails(deleteDoc(doc(patient(), `users/${PATIENT}`)));
  });
});

describe('FR-1.4 health_profiles', () => {
  test('patient reads own health profile', async () => {
    await assertSucceeds(getDoc(doc(patient(), `health_profiles/${PATIENT}`)));
  });
  test('patient cannot read another health profile', async () => {
    await assertFails(getDoc(doc(patient(), `health_profiles/${OTHER_PATIENT}`)));
  });
  test('assigned doctor reads the health profile (FR-8.2)', async () => {
    await assertSucceeds(getDoc(doc(doctor(), `health_profiles/${PATIENT}`)));
  });
  test('unassigned doctor cannot read the health profile', async () => {
    await assertFails(getDoc(doc(doctor(), `health_profiles/${OTHER_PATIENT}`)));
  });
  test('family member and pharmacist cannot read health profiles', async () => {
    await assertFails(getDoc(doc(family(), `health_profiles/${PATIENT}`)));
    await assertFails(getDoc(doc(pharmacist(), `health_profiles/${PATIENT}`)));
  });
  test('admin reads health profiles (docs/04: admin read all)', async () => {
    await assertSucceeds(getDoc(doc(admin(), `health_profiles/${PATIENT}`)));
  });
  test('no client writes health profiles (onboarding goes through FastAPI)', async () => {
    const body = { patientId: PATIENT, personalInfo: '{}', medicalHistory: '{}', lifestyleFactors: '{}' };
    await assertFails(setDoc(doc(patient(), `health_profiles/${PATIENT}`), body));
    await assertFails(updateDoc(doc(admin(), `health_profiles/${PATIENT}`), { personalInfo: 'x' }));
  });
});
