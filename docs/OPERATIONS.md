# Operations

Health: `/actuator/health`. Metrics: `/actuator/prometheus`.

Reconciliation checks materialized account balances against ledger-derived balances and checks global ledger imbalance. A discrepancy is reported; the system does not invent balancing entries.

Outbox publication is at-least-once. Publication failures are retained with attempt count and a bounded error message. Consumers must be idempotent.

PSP webhooks are safe to retry. Provider event IDs are unique and duplicate delivery has no additional financial effect.

Incident response should preserve ledger history, investigate the affected payment/reference, and use reconciliation before any corrective financial action.
