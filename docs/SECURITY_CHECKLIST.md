# Security checklist

- PostgreSQL is authoritative for money.
- Session tokens are random, hashed at rest, HttpOnly, and expiring.
- Passwords use BCrypt.
- Webhooks verify raw-body HMAC with constant-time comparison.
- Provider event IDs are unique.
- SQL uses parameterized JDBC.
- CORS is allow-listed and credentialed.
- Production secrets are environment supplied.
- API errors avoid stack traces and SQL details.
- Financial discrepancies are reported, not silently repaired.
