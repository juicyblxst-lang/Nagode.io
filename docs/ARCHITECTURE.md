# Architecture

Nagode.io uses a Vercel-hosted Next.js application and a Render-hosted Spring Boot API backed by Render PostgreSQL. Key Value is optional ephemeral infrastructure for cache/coordination and is never the authority for money.

The backend owns financial state. PostgreSQL transactions protect ledger postings and balances. External PSP calls occur outside transactions holding financial locks. The initial architecture deliberately avoids Kafka: the transactional outbox and polling are sufficient for the first deployment and keep operations simple.
