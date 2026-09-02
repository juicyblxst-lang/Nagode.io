# Testing

CI performs backend Maven verification, frontend TypeScript checking, frontend production build, and backend Docker image build.

Financial tests should cover double-entry balance, insufficient funds under concurrency, durable idempotency, valid/invalid payment transitions, duplicate webhooks, refund limits, and reconciliation mismatches. Cloud smoke tests should use sandbox data only.

No performance number is claimed here unless it has been produced by an actual CI or deployment run.
