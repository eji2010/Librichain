;; ------------------------------------------------------------------
;; BlockRead.clar
;; Decentralized E-Library Smart Contract
;; - Author registration
;; - Book registration (metadata)
;; - Buy (permanent) with royalty split
;; - Borrow (temporary) with block-height expiry
;; - Reviews & ratings
;; - Admin (platform owner) controls
;; Version: 1.0
;; ------------------------------------------------------------------

(define-data-var owner principal tx-sender) ;; contract deployer is owner

;; Basic counters
(define-data-var total-books uint u0)

;; Platform fee (percentage in whole numbers, e.g., 5 = 5%)
(define-data-var platform-fee uint u5)

;; ----------------------------
;; Data structures
;; ----------------------------

;; Authors map: principal -> { name, registered? }
(define-map authors
  { author: principal }
  { name: (string-ascii 50), registered: bool }
)

;; Books map: book-id -> book-record
;; book-record fields: title, author, price (buy price), borrow-price, borrow-duration (blocks), available
(define-map books
  { book-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 256),
    author: principal,
    price: uint,
    borrow-price: uint,
    borrow-duration: uint,
    available: bool
  }
)

;; Ownerships map: composite key {book-id, reader} -> {purchased: bool}
(define-map ownerships
  { book-id: uint, reader: principal }
  { purchased: bool }
)

;; Borrows map: composite key {book-id, reader} -> expiry-block-height (uint)
(define-map borrows
  { book-id: uint, reader: principal }
  { expiry: uint }  ;; 0 means not borrowed
)

;; Reviews:
;; book-review-counter: book-id -> uint (tracks next review id)
(define-map book-review-counter
  { book-id: uint } { next-id: uint })

;; reviews map: {book-id, review-id} -> { reviewer, rating, comment, timestamp }
(define-map reviews
  { book-id: uint, review-id: uint }
  {
    reviewer: principal,
    rating: uint,
    comment: (string-ascii 200),
    timestamp: uint
  }
)

;; ----------------------------
;; Helpers & modifiers
;; ----------------------------

(define-read-only (is-owner (who principal))
  (is-eq (var-get owner) who)
)

(define-private (assert-owner)
  (ok (asserts! (is-eq (var-get owner) tx-sender) (err u100)))
)

;; ----------------------------
;; PUBLIC: Author Registration
;; ----------------------------

(define-public (register-author (name (string-ascii 50)))
  (begin
    (map-set authors {author: tx-sender} {name: name, registered: true})
    (print {event: "author-registered", author: tx-sender, name: name})
    (ok "AUTHOR_REGISTERED")
  )
)

(define-read-only (is-registered-author (p principal))
  (match (map-get? authors {author: p})
    entry (get registered entry)
    false
  )
)

;; ----------------------------
;; PUBLIC: Add / Update / Remove Book
;; ----------------------------

(define-public (add-book
  (title (string-ascii 100))
  (description (string-ascii 256))
  (price uint)                ;; price to buy
  (borrow-price uint)         ;; price to borrow temporarily
  (borrow-duration uint)      ;; duration in blocks
)
  (let ((author-data (map-get? authors {author: tx-sender})))
    (begin
      ;; Caller must be a registered author
      (asserts! (is-some author-data) (err u200))
      (asserts! (get registered (unwrap-panic author-data)) (err u201))
      (var-set total-books (+ (var-get total-books) u1))
      (let ((bid (var-get total-books)))
        (map-set books {book-id: bid}
          {
            title: title,
            description: description,
            author: tx-sender,
            price: price,
            borrow-price: borrow-price,
            borrow-duration: borrow-duration,
            available: true
          })
        (print {event: "book-added", book-id: bid, title: title, author: tx-sender})
        (ok bid)
      )
    )
  )
)

;; Update book details (only book.author or platform owner)
(define-public (update-book
  (book-id uint)
  (title (string-ascii 100))
  (description (string-ascii 256))
  (price uint)
  (borrow-price uint)
  (borrow-duration uint)
  (available bool)
)
  (match (map-get? books {book-id: book-id})
    book
    (let ((author (get author book)))
      (begin
        (asserts! (or (is-eq tx-sender author) (is-eq tx-sender (var-get owner))) (err u202))
        (map-set books {book-id: book-id}
          {
            title: title,
            description: description,
            author: author,
            price: price,
            borrow-price: borrow-price,
            borrow-duration: borrow-duration,
            available: available
          })
        (print {event: "book-updated", book-id: book-id})
        (ok "BOOK_UPDATED")
      )
    )
    (err u203)
  )
)

;; Fixed all string literals to use standard ASCII double quotes
(define-public (remove-book (book-id uint))
  (match (map-get? books {book-id: book-id})
    book
    (let ((author (get author book)))
      (begin
        (asserts! (or (is-eq tx-sender author) (is-eq tx-sender (var-get owner))) (err u204))
        (map-set books {book-id: book-id}
          {
            title: (get title book),
            description: (get description book),
            author: author,
            price: (get price book),
            borrow-price: (get borrow-price book),
            borrow-duration: (get borrow-duration book),
            available: false
          })
        (print {event: "book-removed", book-id: book-id})
        (ok "BOOK_REMOVED")
      )
    )
    (err u205)
  )
)

;; ----------------------------
;; PUBLIC: Purchase Book (permanent ownership)
;; ----------------------------
(define-public (buy-book (book-id uint) (payment uint))
  (match (map-get? books {book-id: book-id})
    book
    (let (
          (price (get price book))
          (author (get author book))
          (fee (var-get platform-fee))
         )
      (begin
        (asserts! (get available book) (err u206))
        (asserts! (>= payment price) (err u207))
        ;; compute splits
        (let ((platform-cut (/ (* price fee) u100))
              (author-cut (- price platform-cut)))
          ;; transfer platform cut to owner
          (try! (stx-transfer? platform-cut tx-sender (var-get owner)))
          ;; transfer remainder to author
          (try! (stx-transfer? author-cut tx-sender author))
          ;; mark ownership
          (map-set ownerships {book-id: book-id, reader: tx-sender} {purchased: true})
          (print {event: "book-purchased", book-id: book-id, buyer: tx-sender, price: price})
          (ok "BOOK_PURCHASED")
        )
      )
    )
    (err u208)
  )
)

;; ----------------------------
;; PUBLIC: Borrow Book (temporary access)
;; ----------------------------
;; Ensured block-height is used correctly with proper spacing
(define-public (borrow-book (book-id uint) (payment uint))
  (match (map-get? books {book-id: book-id})
    book
    (let (
          (bprice (get borrow-price book))
          (bduration (get borrow-duration book))
          (author (get author book))
          (fee (var-get platform-fee))
          (current-height stacks-block-height)
         )
      (begin
        (asserts! (get available book) (err u209))
        (asserts! (>= payment bprice) (err u210))
        ;; compute splits
        (let ((platform-cut (/ (* bprice fee) u100))
              (author-cut (- bprice platform-cut))
              (expiry (+ current-height bduration)))
          ;; transfer platform cut
          (try! (stx-transfer? platform-cut tx-sender (var-get owner)))
          ;; transfer author cut
          (try! (stx-transfer? author-cut tx-sender author))
          ;; set borrow expiry
          (map-set borrows {book-id: book-id, reader: tx-sender} {expiry: expiry})
          (print {event: "book-borrowed", book-id: book-id, borrower: tx-sender, until: expiry, price: bprice})
          (ok expiry)
        )
      )
    )
    (err u211)
  )
)

;; Public read-only: check if a reader owns (purchased) a book
(define-read-only (is-purchased (book-id uint) (reader principal))
  (match (map-get? ownerships {book-id: book-id, reader: reader})
    own (get purchased own)
    false
  )
)

;; Public read-only: check borrow expiry (0 if not borrowed)
(define-read-only (get-borrow-expiry (book-id uint) (reader principal))
  (match (map-get? borrows {book-id: book-id, reader: reader})
    b (get expiry b)
    u0
  )
)

;; Public read-only: can-read? (true if purchased OR borrowed and expiry > block-height)
(define-read-only (can-read (book-id uint) (reader principal))
  (let ((purchased (is-purchased book-id reader))
        (expiry (get-borrow-expiry book-id reader))
        (current-height stacks-block-height))
    (or purchased (> expiry current-height))
  )
)

;; ----------------------------
;; Reviews
;; ----------------------------

(define-public (add-review (book-id uint) (rating uint) (comment (string-ascii 200)))
  (begin
    (asserts! (and (>= rating u1) (<= rating u5)) (err u212)) ;; 1..5
    (match (map-get? books {book-id: book-id})
      book
      (let ((purchased (is-purchased book-id tx-sender))
            (expiry (get-borrow-expiry book-id tx-sender))
            (current-height stacks-block-height))
        ;; allow review if purchased OR currently borrowed (expiry > block-height)
        (asserts! (or purchased (> expiry current-height)) (err u213))
        ;; get next review id
        (let ((current-counter (map-get? book-review-counter {book-id: book-id}))
              (next-id (match current-counter
                         counter (get next-id counter)
                         u1)))
          (begin
            ;; increment counter
            (map-set book-review-counter {book-id: book-id} {next-id: (+ next-id u1)})
            (map-set reviews {book-id: book-id, review-id: next-id}
              { reviewer: tx-sender, rating: rating, comment: comment, timestamp: current-height})
            (print {event: "review-added", book-id: book-id, review-id: next-id, reviewer: tx-sender, rating: rating})
            (ok next-id)
          )
        )
      )
      (err u214)
    )
  )
)

(define-read-only (get-review (book-id uint) (review-id uint))
  (map-get? reviews {book-id: book-id, review-id: review-id})
)

(define-read-only (get-next-review-id (book-id uint))
  (match (map-get? book-review-counter {book-id: book-id})
    c (ok (get next-id c))
    (ok u1)
  )
)

;; ----------------------------
;; Admin functions (owner only)
;; ----------------------------

(define-public (set-platform-fee (new-fee uint))
  (begin
    (try! (assert-owner))
    (asserts! (<= new-fee u20) (err u215)) ;; cap fee at 20%
    (var-set platform-fee new-fee)
    (ok "PLATFORM_FEE_UPDATED")
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    (try! (assert-owner))
    (var-set owner new-owner)
    (ok "OWNER_TRANSFERRED")
  )
)

;; Owner can withdraw any STX accidentally left in the contract (owner-only)
(define-public (withdraw (amount uint) (to principal))
  (begin
    (try! (assert-owner))
    (try! (stx-transfer? amount (as-contract tx-sender) to))
    (ok "WITHDRAWN")
  )
)

;; ----------------------------
;; Read-only: Query functions
;; ----------------------------

(define-read-only (get-book (book-id uint))
  (map-get? books {book-id: book-id})
)

(define-read-only (get-total-books)
  (ok (var-get total-books))
)

(define-read-only (get-author (author-principal principal))
  (map-get? authors {author: author-principal})
)

(define-read-only (get-book-owner-and-status (book-id uint) (reader principal))
  {purchased: (is-purchased book-id reader), borrow-expiry: (get-borrow-expiry book-id reader)}
)
