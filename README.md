# Librichain

Decentralized e‑library smart contract written in Clarity for the Stacks blockchain.  
Provides author registration, book management, buy/borrow flows with royalty split, reviews, and simple admin controls.

 Features
- Author registration & management
- Add / update / remove books (metadata, pricing, borrow duration)
- Buy (permanent ownership) with platform fee split
- Borrow (temporary access) with block-height expiry
- Ownership & borrow tracking
- Reviews with per-book counters and timestamps
- Admin: set platform fee (capped 20%), transfer ownership, withdraw STX

 Repository layout
- contracts/Librichain.clar — main contract
- (tests/) — Clarinet tests (recommended)
## Requirements
- Node.js (for Clarinet tooling)
- Clarinet (https://github.com/hirosystems/clarinet)
- Stacks Core / local devnet (optional)

Install Clarinet (example, Windows PowerShell):
- npm i -g @hirosystems/clarinet

## Quickstart (local development)
1. Compile & run tests:
   - clarinet test
2. Open interactive console:
   - clarinet console
3. Deploy contract in local devnet via Clarinet test configuration (see Clarinet docs).

 Contract API (public functions)
- register-author (name: (string-ascii 50)) — register tx-sender as author
- add-book (title desc price borrow-price borrow-duration) — add new book (author only)
- update-book (book-id title desc price borrow-price borrow-duration available) — edit book (author or owner)
- remove-book (book-id) — mark unavailable (author or owner)
- buy-book (book-id payment) — purchase book permanently (STX transfer & splits)
- borrow-book (book-id payment) — borrow for borrow-duration blocks
- add-review (book-id rating comment) — add review if purchased or currently borrowed
- set-platform-fee (new-fee) — owner only, capped at 20%
- transfer-ownership (new-owner) — owner only
- withdraw (amount to) — owner only, withdraw STX from contract

Read-only helpers:
- get-book, get-total-books, get-author, is-purchased, get-borrow-expiry, can-read, get-review, get-next-review-id, get-book-owner-and-status

 Example Clarinet calls
- Register author:
  (contract-call? .librichain register-author "Alice")
- Add book:
  (contract-call? .librichain add-book "Title" "Desc" u1000000 u100000 u100)
- Buy book:
  (contract-call? .librichain buy-book u1 u1000000)

(Note: Clarinet console sets tx-sender for calls; wrap integer amounts with `u` as Clarity uint literals.)

 Events / Prints
Key events are printed by the contract: `author-registered`, `book-added`, `book-updated`, `book-removed`, `book-purchased`, `book-borrowed`, `review-added`. Monitor node/clarinet output to track them.

 Security notes
- Platform fee stored as whole percent (e.g., 5 = 5%).
- Payment amounts are asserted against listed prices; callers must send correct STX amounts when invoking via a transaction helper.
- Review and read-access rely on purchased flag or borrow expiry checks.
- Recommend third-party audit before production deployment.

 Contributing
PRs and issues welcome. Add Clarinet tests for new features and edge cases.

 License
Suggested: MIT — update as needed.
