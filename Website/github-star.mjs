import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

const repo = 'arden-deq/Good-Text-Viewer';
const site = 'https://goodtextviewer.allmightdev.com';
const pages = new Set(['/', '/ko/', '/downloads/', '/ko/downloads/']);
const flowCookie = '__Host-gtv-star-flow';
const resultCookie = '__Host-gtv-star-result';

function cookie(name, value, age) {
  return `${name}=${value}; Max-Age=${age}; Path=/; Secure; HttpOnly; SameSite=Lax`;
}

function sign(secret, name, payload) {
  return createHmac('sha256', secret).update(`${name}:${payload}`).digest('base64url');
}

function seal(secret, name, data, age) {
  const payload = Buffer.from(JSON.stringify({ ...data, expiresAt: Date.now() + age * 1000 })).toString('base64url');
  return cookie(name, `${payload}.${sign(secret, name, payload)}`, age);
}

function unseal(req, secret, name) {
  const entry = req.headers.cookie?.split(/;\s*/).find((field) => field.startsWith(`${name}=`));
  if (!entry) return null;

  const [payload, signature] = entry.slice(name.length + 1).split('.');
  if (!/^[\w-]+$/.test(payload) || !signature || !/^[\w-]{43}$/.test(signature)) return null;
  if (!timingSafeEqual(Buffer.from(signature), Buffer.from(sign(secret, name, payload)))) return null;

  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    return data.expiresAt > Date.now() && pages.has(data.page) ? data : null;
  } catch {
    return null;
  }
}

function redirect(res, location, cookies = []) {
  res.writeHead(303, { Location: location, 'Set-Cookie': cookies });
  res.end();
}

export function createStarServer({ clientId, clientSecret, origin = site, request = fetch }) {
  if (!clientId || !clientSecret) throw new Error('GitHub App credentials are required');
  const callback = `${origin}/star/callback`;

  function github(url, options) {
    return request(url, { signal: AbortSignal.timeout(7000), redirect: 'error', ...options });
  }

  async function start(req, res) {
    if (req.headers.origin !== origin) {
      res.writeHead(403).end();
      return;
    }

    let body = '';
    for await (const chunk of req) {
      body += chunk.toString();
      if (body.length > 1024) {
        res.writeHead(413).end();
        return;
      }
    }
    const page = new URLSearchParams(body).get('page');
    if (!pages.has(page)) {
      res.writeHead(400).end();
      return;
    }

    const state = randomBytes(32).toString('base64url');
    const verifier = randomBytes(32).toString('base64url');
    const authorization = new URL('https://github.com/login/oauth/authorize');
    authorization.search = new URLSearchParams({
      client_id: clientId,
      redirect_uri: callback,
      state,
      code_challenge: createHash('sha256').update(verifier).digest('base64url'),
      code_challenge_method: 'S256',
    });
    redirect(res, authorization.href, [
      seal(clientSecret, flowCookie, { page, state, verifier }, 600),
      cookie(resultCookie, '', 0),
    ]);
  }

  async function finish(req, res, query) {
    const flow = unseal(req, clientSecret, flowCookie);
    if (!flow || query.get('state') !== flow.state) {
      res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' }).end('GitHub authorization expired or could not be verified. Return to Good Text Viewer and try again.');
      return;
    }

    let status = query.get('error') === 'access_denied' ? 'cancelled' : 'failed';
    let stars = null;
    const code = query.get('code');
    if (code && !query.has('error')) {
      try {
        const exchange = await github('https://github.com/login/oauth/access_token', {
          method: 'POST',
          headers: { Accept: 'application/json' },
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            code,
            code_verifier: flow.verifier,
            redirect_uri: callback,
          }),
        });
        if (!exchange.ok) throw new Error('Token exchange failed');
        const { access_token: accessToken } = await exchange.json();
        if (!accessToken) throw new Error('GitHub did not return a user token');

        const headers = {
          Accept: 'application/vnd.github+json',
          Authorization: `Bearer ${accessToken}`,
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'GoodTextViewer-Site',
        };
        const added = await github(`https://api.github.com/user/starred/${repo}`, {
          method: 'PUT', headers: { ...headers, 'Content-Length': '0' }, body: '',
        });
        if (added.status !== 204) throw new Error(`GitHub star request returned ${added.status}`);
        status = 'starred';

        const repository = await github(`https://api.github.com/repos/${repo}`, { headers: { ...headers, 'Cache-Control': 'no-cache' } });
        if (repository.ok) {
          const count = (await repository.json()).stargazers_count;
          if (Number.isSafeInteger(count) && count >= 0) stars = count;
        }
      } catch {
        console.error('GitHub star flow:', status === 'starred' ? 'count refresh failed' : 'GitHub request failed');
      }
    }

    redirect(res, `${flow.page}?github-star=1`, [
      cookie(flowCookie, '', 0),
      seal(clientSecret, resultCookie, { page: flow.page, status, stars }, 120),
    ]);
  }

  const server = createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    try {
      const url = new URL(req.url, origin);
      if (req.method === 'POST' && url.pathname === '/star/start') {
        await start(req, res);
      } else if (req.method === 'GET' && url.pathname === '/star/callback') {
        await finish(req, res, url.searchParams);
      } else if (req.method === 'GET' && url.pathname === '/star/result') {
        const result = unseal(req, clientSecret, resultCookie);
        const match = result && url.searchParams.get('page') === result.page;
        res.writeHead(match ? 200 : 404, {
          'Content-Type': 'application/json; charset=utf-8',
          'Set-Cookie': cookie(resultCookie, '', 0),
        }).end(JSON.stringify(match ? { status: result.status, stars: result.stars } : {}));
      } else {
        res.writeHead(404).end();
      }
    } catch {
      if (!res.headersSent) res.writeHead(500);
      res.end();
    }
  });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = createStarServer({
    clientId: process.env.GTV_GITHUB_CLIENT_ID,
    clientSecret: process.env.GTV_GITHUB_CLIENT_SECRET,
  });
  server.listen(38629, '127.0.0.1');
}
