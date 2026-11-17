import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { test } from 'node:test';
import { createStarServer } from './github-star.mjs';

const origin = 'https://goodtextviewer.example';

async function runServer(t, request) {
  const server = createStarServer({ clientId: 'test-id', clientSecret: 'test-secret', origin, request });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => {
    server.close();
    server.closeAllConnections();
  });
  return (path, options) => fetch(`http://127.0.0.1:${server.address().port}${path}`, { redirect: 'manual', ...options });
}

function begin(call, page = '/ko/downloads/', source = origin) {
  return call('/star/start', {
    method: 'POST', headers: { Origin: source }, body: new URLSearchParams({ page }),
  });
}

function browserCookie(response, name) {
  return response.headers.get('set-cookie').split(', ').find((part) => part.startsWith(name + '=')).split(';')[0];
}

test('stars the repository with the visitor token and returns the confirmed count', async (t) => {
  const requests = [];
  let verifier;
  const call = await runServer(t, async (url, options) => {
    requests.push(url);
    if (url.endsWith('/access_token')) {
      assert.equal(options.body.get('redirect_uri'), origin + '/star/callback');
      verifier = options.body.get('code_verifier');
      return Response.json({ access_token: 'visitor-token' });
    }
    assert.equal(options.headers.Authorization, 'Bearer visitor-token');
    if (url.includes('/user/starred/')) {
      assert.equal(options.method, 'PUT');
      return new Response(null, { status: 204 });
    }
    return Response.json({ stargazers_count: 5 });
  });

  const start = await begin(call);
  assert.equal(start.status, 303);
  assert.match(start.headers.get('set-cookie'), /Secure; HttpOnly; SameSite=Lax/);
  const authorization = new URL(start.headers.get('location'));
  const state = authorization.searchParams.get('state');
  const flow = browserCookie(start, '__Host-gtv-star-flow');
  const callback = await call(`/star/callback?state=${state}&code=test-code`, { headers: { Cookie: flow } });
  assert.equal(callback.status, 303);
  assert.equal(callback.headers.get('location'), '/ko/downloads/?github-star=1');
  assert.equal(authorization.searchParams.get('code_challenge'), createHash('sha256').update(verifier).digest('base64url'));
  assert.deepEqual(requests, [
    'https://github.com/login/oauth/access_token',
    'https://api.github.com/user/starred/arden-deq/Good-Text-Viewer',
    'https://api.github.com/repos/arden-deq/Good-Text-Viewer',
  ]);

  const result = browserCookie(callback, '__Host-gtv-star-result');
  const confirmation = await call('/star/result?page=/ko/downloads/', { headers: { Cookie: result } });
  assert.deepEqual(await confirmation.json(), { stars: 5 });
  assert.match(confirmation.headers.get('set-cookie'), /Max-Age=0/);
  assert.equal((await call('/star/result?page=/ko/downloads/')).status, 404);
});

test('rejects cross-origin requests, untrusted return pages and callbacks without valid state', async (t) => {
  let githubCalls = 0;
  const call = await runServer(t, () => { githubCalls++; });
  assert.equal((await begin(call, '/', 'https://wrong.example')).status, 403);
  assert.equal((await begin(call, '//wrong.example')).status, 400);
  const start = await begin(call);
  const flow = browserCookie(start, '__Host-gtv-star-flow');
  const invalid = await call('/star/callback?state=wrong&code=test-code', { headers: { Cookie: flow } });
  assert.equal(invalid.headers.get('location'), '/ko/downloads/');
  const auth = new URL(start.headers.get('location'));
  const state = auth.searchParams.get('state');
  const noCookie = await call(`/star/callback?state=${state}&code=test-code`);
  assert.equal(noCookie.headers.get('location'), '/');
  const cancelled = await call(`/star/callback?state=${state}&error=access_denied`, { headers: { Cookie: flow } });
  assert.equal(cancelled.headers.get('location'), '/ko/downloads/');
  assert.doesNotMatch(cancelled.headers.get('set-cookie'), /__Host-gtv-star-result/);
  assert.equal(githubCalls, 0);
});

test('returns to the same page without a result if GitHub rejects the star', async (t) => {
  const call = await runServer(t, async (url) => url.endsWith('/access_token')
    ? Response.json({ access_token: 'visitor-token' })
    : new Response(null, { status: 403 }));
  const start = await begin(call, '/');
  const state = new URL(start.headers.get('location')).searchParams.get('state');
  const flow = browserCookie(start, '__Host-gtv-star-flow');
  const rejected = await call(`/star/callback?state=${state}&code=test-code`, { headers: { Cookie: flow } });
  assert.equal(rejected.headers.get('location'), '/');
  assert.doesNotMatch(rejected.headers.get('set-cookie'), /__Host-gtv-star-result/);
});
