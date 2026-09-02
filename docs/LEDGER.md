# Ledger

Each monetary movement is represented by a ledger transaction containing immutable debit and credit entries. The database has a deferred constraint trigger that rejects any transaction whose total debits differ from total credits.

Materialized balances are cached representations, updated in the same database transaction as postings. User wallets are debit-normal; merchant payable, PSP suspense, and fee accounts are credit-normal. Account rows are locked in deterministic UUID order before balance validation and updates.

External PSP calls never occur while these financial locks are held. Failures are handled by compensating reversal transactions rather than by editing historical postings.
