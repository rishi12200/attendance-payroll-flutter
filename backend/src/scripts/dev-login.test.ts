import assert from 'node:assert/strict';
import test from 'node:test';
import { fetchIdToken, parseLoginArguments } from './dev-login';

test('parses email and password CLI arguments without printing them', () => {
  assert.deepEqual(
    parseLoginArguments(['--email', 'user@example.com', '--password', 'temporary-password']),
    { email: 'user@example.com', password: 'temporary-password' },
  );
  assert.equal(parseLoginArguments(['--email', 'not-an-email', '--password', 'password']), undefined);
});

test('posts credentials with the runtime API key and returns only the ID token', async () => {
  let requestUrl: URL | undefined;
  let requestBody: Record<string, unknown> | undefined;
  const token = await fetchIdToken(
    { email: 'user@example.com', password: 'temporary-password' },
    'runtime-api-key',
    async (input, init) => {
      requestUrl = new URL(String(input));
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(JSON.stringify({ idToken: 'firebase-id-token', refreshToken: 'unused' }), {
        status: 200,
      });
    },
  );

  assert.equal(token, 'firebase-id-token');
  assert.equal(requestUrl?.searchParams.get('key'), 'runtime-api-key');
  assert.deepEqual(requestBody, {
    email: 'user@example.com',
    password: 'temporary-password',
    returnSecureToken: true,
  });
});

test('does not surface credentials in login failures', async () => {
  await assert.rejects(
    fetchIdToken(
      { email: 'secret@example.com', password: 'secret-password' },
      'runtime-api-key',
      async () =>
        new Response(
          JSON.stringify({ error: { message: 'INVALID_PASSWORD: secret-password' } }),
          { status: 400 },
        ),
    ),
    (error: unknown) => {
      assert.ok(error instanceof Error);
      assert.equal(error.message, 'Firebase sign-in failed (HTTP 400).');
      assert.equal(error.message.includes('secret-password'), false);
      return true;
    },
  );
});
