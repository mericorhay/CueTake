# CueTake assistant proxy

The app talks to this worker, never to the model provider directly. The worker holds the
provider key, owns the system prompt, wraps the user's message into it, and returns one reply.

Why a proxy rather than a key in the app: anything compiled into an app can be read out of it,
and a leaked provider key is a bill. The prompt also lives here, so it can be changed without
an app release.

## Deploy (Cloudflare Workers)

```bash
cd backend/assistant
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put APP_TOKEN
npx wrangler deploy
```

`APP_TOKEN` is any long random string you choose, for example the output of
`openssl rand -hex 32`. `wrangler deploy` prints the worker URL.

## Point the app at it

Add two repository secrets on GitHub (Settings → Secrets and variables → Actions):

- `CUETAKE_ASSISTANT_URL` — the worker URL from `wrangler deploy`
- `CUETAKE_ASSISTANT_TOKEN` — the same value as `APP_TOKEN`

The TestFlight workflow writes them into `CueTake/Resources/AssistantEndpoint.json` at build
time. That file is gitignored. A build without the secrets still works; the assistant screen
says it is not connected.

## Changing the prompt

Edit `SYSTEM_PROMPT` in `worker.js` and run `npx wrangler deploy`.
