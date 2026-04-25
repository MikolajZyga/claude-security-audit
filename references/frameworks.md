# Framework Reference

How to read env vars correctly per stack. Pick the relevant section based on the project's `package.json`, `pyproject.toml`, or equivalent.

## Next.js (App Router and Pages Router)

- Server-only: `process.env.MY_SECRET` — works in API routes, server components, server actions, `getServerSideProps`, middleware.
- Client-exposed: must be prefixed `NEXT_PUBLIC_*` and read as `process.env.NEXT_PUBLIC_X`. The value is **inlined into the JS bundle at build time**.
- `.env.local` is loaded automatically. No `dotenv` import needed.
- For Vercel deploys, also set the var in the Vercel project settings (Environment Variables). `.env.local` is not deployed.
- **Common mistake**: putting a secret in `NEXT_PUBLIC_*`. The whole point of the prefix is "this is shipped to the browser". If it's secret, drop the prefix.

## Vite (React, Vue, Svelte)

- Client-exposed: `import.meta.env.VITE_X` — same caveat as Next: shipped to the browser at build time.
- Server-only secrets don't belong in a Vite app at all (Vite is client-only). Use a separate backend.
- `.env.local` works out of the box.

## Create React App (legacy)

- `process.env.REACT_APP_X` — all values are public, all are baked into the bundle. Treat the whole `REACT_APP_*` namespace as public.

## Expo / React Native (Expo SDK 49+)

- Client-exposed: `process.env.EXPO_PUBLIC_X`. Public.
- Server secrets do not belong in the app bundle. Use EAS secrets for build-time, or a backend for runtime.

## Plain Node.js

- `process.env.X`. To load from `.env.local`, you need `dotenv`:
  ```js
  import 'dotenv/config'  // ESM
  // or
  require('dotenv').config()  // CJS
  ```
  Many starter templates have this in the entry file already. Check before adding.

## Express / Fastify / Hono / NestJS

- Same as plain Node. `dotenv` is usually wired up. Read with `process.env.X`.

## Firebase

This one has a real "is it secret" distinction that catches people out:

- **Firebase web SDK config** (`apiKey`, `authDomain`, `projectId`, `appId`, etc. passed to `initializeApp`) — **public by design**. The `apiKey` here is a project identifier, not a secret. Security is enforced by Firebase Security Rules and App Check, not by hiding this config. It is fine and normal to have this in client code or a `NEXT_PUBLIC_FIREBASE_*` env var. The `google_api_key` rule will flag it; mark as a false positive after confirming it's used in `initializeApp`.
- **Firebase Admin SDK service account JSON** — **fully secret**. Server-only. Never ship to client. Load via `GOOGLE_APPLICATION_CREDENTIALS` pointing to a path, or split the JSON into env vars (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` with `\n` preserved).

## Python

- `os.environ["X"]` or `os.getenv("X", "default")`.
- For local dev, `python-dotenv`: `from dotenv import load_dotenv; load_dotenv(".env.local")` near the entry point.
- FastAPI: same as plain Python. Pydantic Settings is a clean pattern: `class Settings(BaseSettings): api_key: str` reads `API_KEY` from env automatically.

## Rust

- `std::env::var("X")` returns `Result<String, VarError>`.
- For `.env` loading, the `dotenvy` crate: `dotenvy::dotenv().ok();` near the start of `main()`.

## Go

- `os.Getenv("X")`.
- For `.env` loading, the `github.com/joho/godotenv` package: `godotenv.Load(".env.local")`.

## Supabase (any client framework)

- `SUPABASE_URL` and `SUPABASE_ANON_KEY` (or `NEXT_PUBLIC_SUPABASE_*`) — public, used by the JS client. RLS enforces security.
- `SUPABASE_SERVICE_ROLE_KEY` — **fully secret**, server-only, bypasses RLS. Never ship to client. Common leak: someone names it `NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY` to "fix an undefined error" — that's catastrophic.
