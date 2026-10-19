# Jev proxy — Cloudflare Worker

A tiny TypeScript Worker that mirrors `server/jev_server.py` so the Godot
HTML5 build (and any native build without a local Python server) can
talk to the TypeSafe Jev API without ever shipping the API key to the
client.

The game sends candidates + hints to `/guess`; the Worker forwards
them to `https://api.typesafe.ai/v1/systemone` with the key stored in
the Cloudflare secret store, and returns the chosen candidate ID.

## One-time setup

1. **Install Node.js** (any LTS ≥ 18) — https://nodejs.org
2. **Install project deps** (from this directory):

   ```powershell
   cd server\jev_worker
   npm install
   ```

3. **Sign in to Cloudflare** (opens a browser once, then caches the token):

   ```powershell
   npx wrangler login
   ```

   You will need a free Cloudflare account at https://dash.cloudflare.com
   first. The Workers free plan (100,000 requests/day) is plenty.

4. **Store the TypeSafe key as a secret** — this is the only place the
   key is written. It never enters git or the Worker source:

   ```powershell
   npx wrangler secret put JEV_API_KEY
   ```

   Wrangler prompts you to paste the key; it is uploaded directly to
   Cloudflare and encrypted at rest.

5. **(Optional) lock down CORS** by editing `wrangler.jsonc`:

   ```jsonc
   "JEV_ALLOWED_ORIGIN": "https://html-classic.itch.zone"
   ```

   Leave as `"*"` while you are testing locally; tighten before you make
   the itch.io page public.

## Deploy

```powershell
npx wrangler deploy
```

The output prints the public URL, something like:

```
Published jev-proxy (0.42 sec)
  https://jev-proxy.<your-subdomain>.workers.dev
```

Copy that URL. The game endpoint is `<URL>/guess`.

## Smoke test

```powershell
# Health check (no key, no CORS enforcement)
curl https://jev-proxy.<your-subdomain>.workers.dev/health

# Full guess call
curl -X POST "https://jev-proxy.<your-subdomain>.workers.dev/guess" `
  -H "Content-Type: application/json" `
  -d '{
    "candidates": [
      {"id": "a", "name": "Alpha", "features": ["cars", "arena"]},
      {"id": "b", "name": "Beta",  "features": ["cards", "deckbuilding"]}
    ],
    "hints": ["Build a scoring hand with jokers"],
    "previous_guesses": [],
    "level": 1
  }'
```

Expected: `{"guess_id":"b","reason":"..."}`.

## Point the game at the Worker

In `scripts/main.gd` the client reads the endpoint from an env var
first, then falls back to a hardcoded `DEFAULT_JEV_URL` constant.
Update that constant to your Worker URL:

```gdscript
const DEFAULT_JEV_URL := "https://jev-proxy.<your-subdomain>.workers.dev/guess"
```

Once deployed and the game is restarted, the Jev side panel should
switch its chip from `OFFLINE MODE` to `MODEL CONNECTED` as soon as
the first hint is submitted and the Worker responds successfully. If
the Worker is down or returns an invalid candidate ID, the game falls
back to the offline heuristic Jev automatically (no crash) and the
chip switches to `OFFLINE FALLBACK`.

## Local development

To iterate on the Worker without deploying:

```powershell
# Create .dev.vars (git-ignored) with the key for local use only
"JEV_API_KEY=<paste key>" | Out-File -Encoding ascii .dev.vars

npx wrangler dev
# Serves at http://127.0.0.1:8787
```

Point the game at `http://127.0.0.1:8787/guess` (via `JEV_API_URL`
env var or by temporarily editing `DEFAULT_JEV_URL`).

## Rotating or deleting the key

```powershell
npx wrangler secret put JEV_API_KEY        # overwrite
npx wrangler secret delete JEV_API_KEY     # remove
```

## Troubleshooting

- `502 Jev could not reach the model.` — the TypeSafe API is unreachable
  or returned an error. The game will fall back to offline Jev.
- `500 Jev proxy is missing JEV_API_KEY.` — you deployed before setting
  the secret. Run `npx wrangler secret put JEV_API_KEY` and redeploy.
- CORS errors in browser console on the itch.io build — set
  `JEV_ALLOWED_ORIGIN` to `*` while debugging, or add the exact origin
  shown in the error message.
