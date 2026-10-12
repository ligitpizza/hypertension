import { afterAll, beforeAll, describe, test } from 'vitest';
import { assertFails } from '@firebase/rules-unit-testing';
import { ref, uploadString, getBytes } from 'firebase/storage';
import { ROLES, as, makeEnv } from './helpers.js';

let env;

beforeAll(async () => {
  env = await makeEnv();
});
afterAll(async () => {
  await env.cleanup();
});

describe('Inc0 baseline: Storage denies all until Module 6', () => {
  test.each(ROLES)('%s cannot upload', async (role) => {
    await assertFails(uploadString(ref(as(env, role).storage(), `records/u-${role}/a.txt`), 'x'));
  });

  test('unauthenticated user cannot read', async () => {
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), 'records/any/a.txt')));
  });
});
