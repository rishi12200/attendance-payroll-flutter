import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import express, { type Express } from 'express';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { createApp } from '../app';
import { errorHandler } from './error-handler';
import { createAuthMiddleware, requireRole, type IdTokenVerifier } from './auth';

function token(role: string): DecodedIdToken {
  return {
    aud: 'test-project',
    auth_time: 1,
    exp: 4_000_000_000,
    firebase: { identities: {}, sign_in_provider: 'password' },
    iat: 1,
    iss: 'https://securetoken.google.com/test-project',
    sub: 'user-123',
    uid: 'user-123',
    role,
  };
}

async function request(
  app: Express,
  path: string,
  options: RequestInit = {},
): Promise<{ status: number; body: Record<string, unknown> }> {
  const server = createServer(app);
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });

  const address = server.address();
  if (!address || typeof address === 'string') {
    throw new Error('Test server did not bind to a TCP port.');
  }

  try {
    const response = await fetch(`http://127.0.0.1:${address.port}${path}`, options);
    return {
      status: response.status,
      body: (await response.json()) as Record<string, unknown>,
    };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}

function authenticatedApp(verifyIdToken: IdTokenVerifier) {
  const app = express();
  app.get(
    '/admin',
    createAuthMiddleware(verifyIdToken),
    requireRole('admin'),
    (_req, res) => res.json({ allowed: true }),
  );
  app.use(errorHandler);
  return app;
}

test('requires a Bearer token and returns the standard error shape', async () => {
  let verifierCalled = false;
  const app = authenticatedApp(async () => {
    verifierCalled = true;
    return token('admin');
  });

  const result = await request(app, '/admin');
  assert.equal(result.status, 401);
  assert.deepEqual(result.body, {
    error: {
      code: 'UNAUTHORIZED',
      message: 'A valid Bearer token is required.',
      details: {},
    },
  });
  assert.equal(verifierCalled, false);
});

test('verifies the token with revocation checking enabled', async () => {
  let verifiedToken = '';
  let checkedRevocation = false;
  const app = authenticatedApp(async (value, checkRevoked) => {
    verifiedToken = value;
    checkedRevocation = checkRevoked;
    return token('admin');
  });

  const result = await request(app, '/admin', {
    headers: { authorization: 'Bearer test-id-token' },
  });
  assert.equal(result.status, 200);
  assert.equal(verifiedToken, 'test-id-token');
  assert.equal(checkedRevocation, true);
  assert.deepEqual(result.body, { allowed: true });
});

test('maps revoked and invalid Firebase ID tokens to 401', async () => {
  const app = authenticatedApp(async () => {
    throw Object.assign(new Error('token revoked'), { code: 'auth/id-token-revoked' });
  });

  const result = await request(app, '/admin', {
    headers: { authorization: 'Bearer revoked-token' },
  });
  assert.equal(result.status, 401);
  assert.deepEqual(result.body, {
    error: {
      code: 'INVALID_TOKEN',
      message: 'The ID token is invalid or expired.',
      details: {},
    },
  });
});

test('rejects a token whose role is not allowed', async () => {
  const app = authenticatedApp(async () => token('employee'));
  const result = await request(app, '/admin', {
    headers: { authorization: 'Bearer employee-token' },
  });

  assert.equal(result.status, 403);
  assert.deepEqual(result.body, {
    error: {
      code: 'FORBIDDEN',
      message: 'You do not have permission to access this resource.',
      details: {},
    },
  });
});

test('returns an internal error for unexpected verifier failures', async () => {
  const app = authenticatedApp(async () => {
    throw new Error('Firebase is temporarily unavailable');
  });
  const result = await request(app, '/admin', {
    headers: { authorization: 'Bearer test-token' },
  });

  assert.equal(result.status, 500);
  assert.deepEqual(result.body, {
    error: {
      code: 'INTERNAL_SERVER_ERROR',
      message: 'An unexpected error occurred.',
      details: {},
    },
  });
});

test('returns the authenticated user profile from GET /me', async () => {
  let requestedUid = '';
  const app = createApp({
    verifyIdToken: async () => token('employee'),
    getProfile: async (uid) => {
      requestedUid = uid;
      return { name: 'Employee', email: 'employee@example.com', role: 'employee', status: 'active' };
    },
  });

  const result = await request(app, '/me', {
    headers: { authorization: 'Bearer employee-token' },
  });
  assert.equal(result.status, 200);
  assert.equal(requestedUid, 'user-123');
  assert.deepEqual(result.body, {
    uid: 'user-123',
    name: 'Employee',
    email: 'employee@example.com',
    role: 'employee',
    status: 'active',
  });
});

test('rejects a profile whose role differs from the verified token', async () => {
  const app = createApp({
    verifyIdToken: async () => token('admin'),
    getProfile: async () => ({ role: 'employee', status: 'active' }),
  });
  const result = await request(app, '/me', {
    headers: { authorization: 'Bearer admin-token' },
  });

  assert.equal(result.status, 403);
  assert.deepEqual(result.body, {
    error: {
      code: 'ROLE_MISMATCH',
      message: 'The account role does not match its ID token.',
      details: {},
    },
  });
});

test('rejects inactive and missing user profiles with standard errors', async (t) => {
  const cases = [
    {
      name: 'inactive profile',
      profile: { role: 'admin', status: 'inactive' },
      status: 403,
      code: 'ACCOUNT_INACTIVE',
    },
    {
      name: 'missing profile',
      profile: undefined,
      status: 404,
      code: 'USER_NOT_FOUND',
    },
  ];

  for (const scenario of cases) {
    await t.test(scenario.name, async () => {
      const app = createApp({
        verifyIdToken: async () => token('admin'),
        getProfile: async () => scenario.profile,
      });
      const result = await request(app, '/me', {
        headers: { authorization: 'Bearer admin-token' },
      });
      const error = result.body.error as Record<string, unknown>;

      assert.equal(result.status, scenario.status);
      assert.equal(error.code, scenario.code);
      assert.deepEqual(error.details, {});
    });
  }
});

test('returns validation errors for malformed JSON', async () => {
  const app = createApp({
    verifyIdToken: async () => token('admin'),
    getProfile: async () => undefined,
  });
  const result = await request(app, '/me', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: 'Bearer admin-token',
    },
    body: '{',
  });

  assert.equal(result.status, 400);
  assert.deepEqual(result.body, {
    error: {
      code: 'VALIDATION_ERROR',
      message: 'Request body must contain valid JSON.',
      details: {},
    },
  });
});
