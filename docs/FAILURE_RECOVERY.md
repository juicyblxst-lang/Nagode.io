# Failure recovery

Provider timeouts and failures do not occur inside the database transaction that holds financial locks. A payment is first durably held, then provider interaction is performed, then a separate transaction authorizes or reverses it.

Duplicate requests are resolved through durable idempotency. Duplicate webhook events are rejected by the unique provider event ID. Outbox publication is at-least-once and failures remain observable. Reconciliation reports discrepancies rather than inventing balancing money.
