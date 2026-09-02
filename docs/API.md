# API

All customer API routes are under `/api/v1`.

Authentication: `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`.

Wallet: `GET /wallet`.

Payments: `GET /payments`, `POST /payments`, `GET /payments/{id}`. Payment creation requires `Idempotency-Key` and an integer amount in minor units.

Refunds: `POST /payments/{id}/refund`, also requiring `Idempotency-Key`.

PSP: `POST /webhooks/psp`, authenticated with `X-PSP-Signature` and deduplicated with `X-PSP-Event-Id`.

Operations: `POST /reconciliation/run`, `GET /reconciliation`.

Errors use JSON with `error` and safe `message` fields. Internal database and stack details are not returned.
