# Database

PostgreSQL is authoritative. Flyway owns schema evolution; production does not use Hibernate auto-DDL.

Core tables: `users` and `sessions` for authentication; `accounts` and `account_balances` for typed monetary accounts; `payments` for payment state; `ledger_transactions` and `ledger_entries` for immutable double-entry history; `idempotency_keys` for durable request deduplication; `psp_webhook_events` for webhook deduplication; `refunds` for refund state; `payment_status_history` for an operational timeline; `outbox` for reliable event publication; and `audit_log` for security/audit events.

Balance changes and ledger postings occur atomically. The database enforces positive posting amounts, valid directions, valid account types, foreign keys, uniqueness, and deferred transaction balance.
