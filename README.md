# Nagode.io

A cloud-first payment and wallet platform focused on financial correctness, secure payment orchestration, and operational visibility.

## Architecture

```text
Vercel / Next.js -> Render / Spring Boot -> Render PostgreSQL
                                  |
                                  +-> Render Key Value (non-authoritative)
```

PostgreSQL is the authority for money. Key Value is only cache/coordination. The frontend never calculates authoritative balances.

## Financial model

- Integer minor units; no floating-point money.
- Immutable double-entry ledger postings.
- Database-enforced debit/credit equality.
- Deterministic row locking for concurrent balance changes.
- Materialized balances updated atomically with ledger postings.
- Explicit payment state transitions.
- Durable idempotency with request hashes and exact response replay.
- PSP calls outside financial database locks.
- HMAC-SHA256 signed and deduplicated webhooks.
- Transactional outbox with at-least-once delivery.
- Safe refunds and reconciliation.

## API

Versioned endpoints live under `/api/v1`.

Core routes include `GET /api/v1/wallet`, `GET /api/v1/payments`, `POST /api/v1/payments`, `GET /api/v1/payments/{id}`, `POST /api/v1/payments/{id}/refund`, `POST /api/v1/webhooks/psp`, `POST /api/v1/reconciliation/run`, and `GET /api/v1/reconciliation`.

Payment and refund creation require `Idempotency-Key`.

## Deployment

Render hosts the backend and managed PostgreSQL. Render Key Value is used only where ephemeral coordination is useful. Vercel hosts the Next.js frontend. No real secrets are committed.

## Verification

GitHub Actions is the source of truth for cloud compilation, tests, type checking, dependency checks, and Docker/frontend build verification. Deployment smoke tests are designed for sandbox/test data only.

See `docs/` for architecture, security, database, ledger, API, deployment, operations, and testing documentation.
