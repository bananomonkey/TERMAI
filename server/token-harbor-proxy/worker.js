// TERMAI shared-AI gateway.
//
// The Token Harbor key lives only in a Worker secret. The Android app never
// receives it. Every chat request must carry a valid Firebase ID token, and
// per-user/global daily counters limit abuse. Promo dates and the model name
// are public Worker variables, so they can be changed without an app update.

const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8' };

function json(status, body, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...extra },
  });
}

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type,x-termai-client',
  };
}

function promoConfig(env) {
  const endsAt = (env.PROMO_ENDS_AT || '').trim();
  const end = Date.parse(endsAt);
  const enabled = String(env.PROMO_ENABLED ?? 'true').toLowerCase() !== 'false';
  return {
    enabled: enabled && Number.isFinite(end) && Date.now() < end,
    ends_at: Number.isFinite(end) ? new Date(end).toISOString() : null,
    notice_version: Number.parseInt(env.PROMO_NOTICE_VERSION || '1', 10) || 1,
    model: (env.PROMO_MODEL || 'deepseek-v4.1-flash:free').trim(),
    privacy_url: (env.PROMO_PRIVACY_URL || '').trim(),
  };
}

let keyCache = { expiresAt: 0, keys: [] };

function b64urlBytes(value) {
  let s = String(value).replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function b64urlJson(value) {
  return JSON.parse(new TextDecoder().decode(b64urlBytes(value)));
}

async function firebaseKeys() {
  if (Date.now() < keyCache.expiresAt) return keyCache.keys;
  const res = await fetch(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
    { headers: { accept: 'application/json' } },
  );
  if (!res.ok) throw new Error(`Firebase JWKS HTTP ${res.status}`);
  const data = await res.json();
  if (!Array.isArray(data.keys)) throw new Error('Firebase JWKS has no keys');
  const maxAge = /max-age=(\d+)/i.exec(res.headers.get('cache-control') || '');
  const ttl = Math.min(Math.max(Number(maxAge?.[1] || 3600), 300), 21600);
  keyCache = { expiresAt: Date.now() + ttl * 1000, keys: data.keys };
  return keyCache.keys;
}

async function verifyFirebase(idToken, env) {
  const projectId = (env.FIREBASE_PROJECT_ID || '').trim();
  if (!projectId) {
    throw new Error('server_misconfigured: FIREBASE_PROJECT_ID is empty');
  }
  const parts = String(idToken).split('.');
  if (parts.length !== 3) return null;
  let header, payload;
  try {
    header = b64urlJson(parts[0]);
    payload = b64urlJson(parts[1]);
  } catch {
    return null;
  }
  if (header.alg !== 'RS256' || !header.kid) return null;
  const keys = await firebaseKeys();
  const jwk = keys.find((k) => k.kid === header.kid && k.kty === 'RSA');
  if (!jwk) return null;
  let key;
  try {
    key = await crypto.subtle.importKey(
      'jwk',
      { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
  } catch {
    return null;
  }
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) return null;
  const now = Math.floor(Date.now() / 1000);
  if (payload.aud !== projectId) return null;
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null;
  if (typeof payload.exp !== 'number' || payload.exp <= now) return null;
  if (typeof payload.iat !== 'number' || payload.iat > now + 300) return null;
  if (typeof payload.sub !== 'string' || payload.sub.length === 0) return null;
  const provider = payload.firebase?.sign_in_provider || '';
  if (provider !== 'google.com') {
    // Only users signed in with Google may use the shared promo.
    return null;
  }
  return payload.sub;
}

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

async function bumpCounter(kv, key, limit) {
  if (!kv) return true;
  const current = Number.parseInt((await kv.get(key)) || '0', 10) || 0;
  if (current >= limit) return false;
  await kv.put(key, String(current + 1), { expirationTtl: 2 * 24 * 60 * 60 });
  return true;
}

// Per-isolate fallback when KV is not bound. Bind PROMO_KV in production for
// a real shared limit; this fallback still stops accidental runaway loops.
const memoryCounts = new Map();

function memoryBump(key, limit) {
  const current = memoryCounts.get(key) || 0;
  if (current >= limit) return false;
  memoryCounts.set(key, current + 1);
  return true;
}

async function rateLimit(env, uid) {
  const day = todayKey();
  const userLimit = Math.max(
    1,
    Number.parseInt(env.MAX_REQUESTS_PER_DAY || '40', 10) || 40,
  );
  const globalLimit = Math.max(
    1,
    Number.parseInt(env.GLOBAL_DAILY_LIMIT || '800', 10) || 800,
  );
  const kv = env.PROMO_KV;
  if (kv) {
    const globalOk = await bumpCounter(kv, `global:${day}`, globalLimit);
    if (!globalOk) return { ok: false, reason: 'global_daily_limit' };
    const userOk = await bumpCounter(kv, `user:${uid}:${day}`, userLimit);
    if (!userOk) return { ok: false, reason: 'user_daily_limit' };
    return { ok: true };
  }
  if (!memoryBump(`global:${day}`, globalLimit)) {
    return { ok: false, reason: 'global_daily_limit' };
  }
  if (!memoryBump(`user:${uid}:${day}`, userLimit)) {
    return { ok: false, reason: 'user_daily_limit' };
  }
  return { ok: true };
}

function validateChatBody(raw, model) {
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return { error: 'invalid_json' };
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return { error: 'invalid_body' };
  }
  if (body.stream === true) return { error: 'stream_not_supported' };
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return { error: 'messages_required' };
  }
  if (body.messages.length > 40) return { error: 'too_many_messages' };
  if (JSON.stringify(body).length > 240000) return { error: 'request_too_large' };
  for (const m of body.messages) {
    if (!m || typeof m !== 'object') return { error: 'invalid_message' };
    if (typeof m.role !== 'string') return { error: 'invalid_role' };
    if (m.content == null) return { error: 'invalid_content' };
  }
  if (body.tools != null) {
    if (!Array.isArray(body.tools) || body.tools.length > 32) {
      return { error: 'invalid_tools' };
    }
  }
  body.model = model;
  body.stream = false;
  const maxTokens = Number(
    body.max_tokens ?? body.max_completion_tokens ?? 1200,
  );
  body.max_tokens = Math.min(
    Math.max(Number.isFinite(maxTokens) ? maxTokens : 1200, 64),
    4096,
  );
  if (body.temperature != null) {
    const t = Number(body.temperature);
    body.temperature = Number.isFinite(t) ? Math.min(Math.max(t, 0), 1.5) : 0.7;
  }
  return { body };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method === 'GET' && url.pathname === '/config') {
      return json(200, promoConfig(env), corsHeaders());
    }

    if (request.method === 'GET' && url.pathname === '/health') {
      return json(200, { ok: true }, corsHeaders());
    }

    if (request.method !== 'POST' || url.pathname !== '/v1/chat/completions') {
      return json(404, { error: { code: 'not_found', message: 'Not found' } });
    }

    const promo = promoConfig(env);
    if (!promo.enabled) {
      return json(403, {
        error: {
          code: 'promo_ended',
          message:
            'The shared TERMAI access has ended. Add your own API key in settings.',
        },
      });
    }

    const auth = request.headers.get('authorization') || '';
    const match = /^Bearer\s+(.+)$/i.exec(auth.trim());
    if (!match) {
      return json(401, {
        error: {
          code: 'shared_auth',
          message: 'Firebase authorization required.',
        },
      });
    }

    let uid;
    try {
      uid = await verifyFirebase(match[1], env);
    } catch (e) {
      return json(503, {
        error: {
          code: 'server_misconfigured',
          message: String(e.message || e),
        },
      });
    }
    if (!uid) {
      return json(401, {
        error: {
          code: 'shared_auth',
          message: 'Invalid or expired Firebase token.',
        },
      });
    }

    const limit = await rateLimit(env, uid);
    if (!limit.ok) {
      return json(429, {
        error: {
          code: limit.reason,
          message:
            'Daily shared-AI limit reached. Try tomorrow or add your own API key.',
        },
      });
    }

    const raw = await request.text();
    const parsed = validateChatBody(raw, promo.model);
    if (parsed.error) {
      return json(400, { error: { code: parsed.error, message: parsed.error } });
    }

    const key = (env.TOKEN_HARBOR_API_KEY || '').trim();
    if (!key) {
      return json(503, {
        error: {
          code: 'server_misconfigured',
          message: 'TOKEN_HARBOR_API_KEY is empty',
        },
      });
    }

    let upstream;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 120000);
      upstream = await fetch('https://tokenharbor.ai/v1/chat/completions', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${key}`,
        },
        body: JSON.stringify(parsed.body),
        signal: controller.signal,
      });
      clearTimeout(timer);
    } catch (e) {
      return json(502, {
        error: {
          code: 'upstream_unavailable',
          message: `Upstream request failed: ${e.message || e}`,
        },
      });
    }

    const text = await upstream.text();
    if (upstream.status === 401 || upstream.status === 403) {
      return json(502, {
        error: {
          code: 'shared_upstream',
          message:
            'Token Harbor rejected the shared request. The promo key or region may be unavailable.',
        },
      });
    }
    if (upstream.status === 429) {
      return json(429, {
        error: {
          code: 'shared_upstream_limit',
          message:
            'The shared Token Harbor route is rate-limited. Try later or add your own API key.',
        },
      });
    }
    return new Response(text, {
      status: upstream.status,
      headers: {
        'content-type':
          upstream.headers.get('content-type') ||
          'application/json; charset=utf-8',
        'cache-control': 'no-store',
      },
    });
  },
};
