# Security model

Production API access is authenticated with a database-backed, random session token stored in an HttpOnly cookie. Tokens are hashed before storage and expire. Authorization is enforced server-side; frontend route protection is not trusted.

Webhook requests are verified against the raw request body using HMAC-SHA256 and constant-time comparison. Provider event IDs are unique in PostgreSQL, making duplicate webhook delivery idempotent.

Money is held in PostgreSQL, never in Redis or browser state. SQL uses parameterized JDBC statements. Errors return safe structured messages rather than stack traces or SQL details. CORS is allow-list based and credentials-aware.

Production secrets must be injected by the deployment platform. No API keys, passwords, private keys, or webhook secrets belong in Git.
