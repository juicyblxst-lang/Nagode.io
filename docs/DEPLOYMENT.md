# Deployment

## Render

The repository contains `render.yaml` for the API, PostgreSQL, and optional Key Value service. Production secrets are supplied through Render environment variables. The API binds to Render's `PORT` and exposes `/actuator/health` for health checks.

## Vercel

The frontend lives under `frontend/`. Configure the Vercel Root Directory as `frontend` and set `NEXT_PUBLIC_API_URL` to the deployed API origin. Only the public API origin belongs in a `NEXT_PUBLIC_*` variable; session and webhook secrets remain server-side.

## Production principles

Database migrations run through Flyway during API startup. PostgreSQL is authoritative. Key Value is disposable. Customer traffic should use TLS and a restricted production CORS allow-list.
