import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

export const PROJECT_ID = 'demo-careflow-rules';
export const ROLES = ['patient', 'doctor', 'pharmacist', 'admin', 'family_member'];

export async function makeEnv() {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') },
  });
}

/** Authenticated context carrying the `role` custom claim (FR-1.3). */
export function as(env, role, uid = `u-${role}`) {
  return env.authenticatedContext(uid, { role });
}
