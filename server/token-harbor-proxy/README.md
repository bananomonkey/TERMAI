# TERMAI shared-AI gateway

This Worker provides the shared TERMAI AI access without putting the Token
Harbor key into the APK, Flutter code, Firebase Remote Config, or Firestore.

```
Android app ──Firebase ID token──▶ Worker ──server-side key──▶ tokenharbor.ai
```

## What is protected

- `TOKEN_HARBOR_API_KEY` is a Worker secret, never returned by `/config`.
- `/v1/chat/completions` requires a valid Firebase ID token. The Worker
  verifies the RS256 signature locally against Google's public JWKS, so there
  is no extra Identity Toolkit call per request.
- The model is forced to `PROMO_MODEL`; clients cannot select another model.
- `max_tokens` is capped, streaming is rejected, and the request body is
  size-limited.
- Per-user and global daily counters run in Cloudflare KV (or a weaker
  in-memory fallback if KV is not bound).
- Promo end date, model, notice version, limits, and the key can be changed
  without an app update.

## Free-tier fit

- Cloudflare Workers free plan: 100,000 requests/day.
- Cloudflare KV free plan: 100,000 reads/day and 1,000 writes/day. Two counter
  writes per request means roughly 500 requests/day on the free KV write
  quota. Set `GLOBAL_DAILY_LIMIT` below that for the free tier (the example
  uses 800, which is the hard cap; the KV write quota is the tighter practical
  limit). A paid KV plan is not required for a small audience.
- Firebase Authentication anonymous sign-in is free at normal hobby scale.
- Token Harbor's `deepseek-v4.1-flash:free` route is the free upstream model.
- No VPS and no paid API are required. Cloudflare does not require a payment
  card for the Workers/KV free plan.

## One-time setup

1. Create a Cloudflare account and install Wrangler:
   ```bash
   cd server/token-harbor-proxy
   npm install
   npx wrangler login
   ```
2. Create a KV namespace for durable rate limits:
   ```bash
   npx wrangler kv namespace create PROMO_KV
   ```
   Paste the returned id into `wrangler.toml` and uncomment the
   `[[kv_namespaces]]` block.
3. Set the Token Harbor key as a secret:
   ```bash
   npx wrangler secret put TOKEN_HARBOR_API_KEY
   ```
4. In `wrangler.toml`, set:
   - `FIREBASE_PROJECT_ID` — already `termai-4fdcc`.
   - `PROMO_ENDS_AT` — one shared end date exactly 7 days after the promo
     starts, in UTC ISO-8601.
   - limits and `PROMO_PRIVACY_URL` as needed.
5. Enable **Anonymous** sign-in in Firebase Console → Authentication → Sign-in
   method. The app only uses it to authorize the gateway; it does not expose an
   email or sync progress.
6. Deploy:
   ```bash
   npx wrangler deploy
   ```
   Wrangler prints the public URL, for example
   `https://termai-token-harbor-proxy.<account>.workers.dev`.
7. Add that URL as the GitHub Actions repository variable
   `TERMAI_AI_PROXY_URL` (Settings → Secrets and variables → Actions →
   Variables), or pass it to a local build:
   ```bash
   flutter build apk --release \
     --dart-define=TERMAI_AI_PROXY_URL=https://termai-token-harbor-proxy.<account>.workers.dev
   ```
   Without `TERMAI_AI_PROXY_URL` the shared feature stays dormant and the app
   uses the user's personal AI settings.

## Rotating the key or extending the promo

- Key: `npx wrangler secret put TOKEN_HARBOR_API_KEY` (no redeploy needed).
- Date/model/limits: edit the `[vars]` block and `npx wrangler deploy`.

The app fetches `/config` at startup and caches it briefly. After
`PROMO_ENDS_AT` it automatically stops using the gateway and returns to the
user's personal provider.

## Local development

```bash
npx wrangler dev --var FIREBASE_PROJECT_ID:termai-4fdcc --var PROMO_ENDS_AT:...
```

Do not commit `.dev.vars`, `.wrangler/`, or any API key. The local
`.gitignore` in this folder excludes them.
