
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_POOL_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_CRISIS_NOT_ACTIVE (err u105))
(define-constant ERR_ORGANIZATION_NOT_VERIFIED (err u106))
(define-constant ERR_DISTRIBUTION_FAILED (err u107))
(define-constant ERR_INVALID_ORACLE (err u108))
(define-constant ERR_POOL_LOCKED (err u109))
(define-constant ERR_ALREADY_DISTRIBUTED (err u110))
(define-constant ERR_MILESTONE_NOT_FOUND (err u111))
(define-constant ERR_INVALID_PERCENTAGE (err u112))
(define-constant ERR_MILESTONE_COMPLETED (err u113))
(define-constant ERR_INSUFFICIENT_MILESTONE_FUNDS (err u114))
(define-constant ERR_POOL_DEADLINE_NOT_REACHED (err u115))
(define-constant ERR_NO_CONTRIBUTION (err u116))
(define-constant ERR_ALREADY_WITHDRAWN (err u117))

(define-data-var next-pool-id uint u1)
(define-data-var next-crisis-id uint u1)
(define-data-var oracle-address (optional principal) none)
(define-data-var contract-paused bool false)
(define-data-var next-milestone-id uint u1)
(define-data-var withdrawal-deadline-blocks uint u144)

(define-map donation-pools uint {
    creator: principal,
    name: (string-ascii 64),
    description: (string-ascii 256),
    target-amount: uint,
    current-amount: uint,
    crisis-type: (string-ascii 32),
    created-at: uint,
    locked: bool,
    distributed: bool
})

(define-map donor-contributions { pool-id: uint, donor: principal } uint)

(define-map verified-organizations principal {
    name: (string-ascii 64),
    description: (string-ascii 256),
    verified-at: uint,
    active: bool
})

(define-map active-crises uint {
    crisis-type: (string-ascii 32),
    severity: uint,
    location: (string-ascii 128),
    confirmed-at: uint,
    confirmed-by: principal,
    active: bool
})

(define-map crisis-distributions { crisis-id: uint, pool-id: uint } {
    organization: principal,
    amount: uint,
    distributed-at: uint,
    tx-hash: (buff 32)
})

(define-map pool-crisis-mapping { pool-id: uint } uint)

(define-map pool-milestones { pool-id: uint, milestone-id: uint } {
    title: (string-ascii 128),
    description: (string-ascii 256),
    percentage: uint,
    completed: bool,
    released-amount: uint,
    created-at: uint,
    completed-at: (optional uint)
})

(define-map milestone-progress-reports { pool-id: uint, milestone-id: uint } {
    organization: principal,
    report: (string-ascii 512),
    submitted-at: uint,
    verified-by: principal,
    verified-at: uint
})

(define-map pool-milestone-count { pool-id: uint } uint)

(define-map donor-withdrawals { pool-id: uint, donor: principal } bool)

(define-public (set-oracle (new-oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (var-set oracle-address (some new-oracle)))))

(define-public (toggle-contract-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (var-set contract-paused (not (var-get contract-paused))))))

(define-public (set-withdrawal-deadline (blocks uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (var-set withdrawal-deadline-blocks blocks))))

(define-public (create-donation-pool (name (string-ascii 64)) (description (string-ascii 256)) (target-amount uint) (crisis-type (string-ascii 32)))
    (let ((pool-id (var-get next-pool-id)))
        (begin
            (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
            (asserts! (> target-amount u0) ERR_INVALID_AMOUNT)
            (map-set donation-pools pool-id {
                creator: tx-sender,
                name: name,
                description: description,
                target-amount: target-amount,
                current-amount: u0,
                crisis-type: crisis-type,
                created-at: stacks-block-height,
                locked: false,
                distributed: false
            })
            (var-set next-pool-id (+ pool-id u1))
            (ok pool-id))))

(define-public (donate-to-pool (pool-id uint) (amount uint))
    (let (
        (pool (unwrap! (map-get? donation-pools pool-id) ERR_POOL_NOT_FOUND))
        (current-contribution (default-to u0 (map-get? donor-contributions { pool-id: pool-id, donor: tx-sender })))
    )
        (begin
            (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            (asserts! (not (get locked pool)) ERR_POOL_LOCKED)
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            (map-set donation-pools pool-id (merge pool {
                current-amount: (+ (get current-amount pool) amount)
            }))
            (map-set donor-contributions { pool-id: pool-id, donor: tx-sender } (+ current-contribution amount))
            (ok true))))

(define-public (verify-organization (org principal) (name (string-ascii 64)) (description (string-ascii 256)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set verified-organizations org {
            name: name,
            description: description,
            verified-at: stacks-block-height,
            active: true
        })
        (ok true)))

(define-public (deactivate-organization (org principal))
    (let ((org-data (unwrap! (map-get? verified-organizations org) ERR_ORGANIZATION_NOT_VERIFIED)))
        (begin
            (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
            (map-set verified-organizations org (merge org-data { active: false }))
            (ok true))))

(define-public (confirm-crisis (crisis-type (string-ascii 32)) (severity uint) (location (string-ascii 128)))
    (let ((crisis-id (var-get next-crisis-id)))
        (begin
            (asserts! (is-some (var-get oracle-address)) ERR_INVALID_ORACLE)
            (asserts! (is-eq tx-sender (unwrap! (var-get oracle-address) ERR_INVALID_ORACLE)) ERR_UNAUTHORIZED)
            (asserts! (and (>= severity u1) (<= severity u5)) ERR_INVALID_AMOUNT)
            (map-set active-crises crisis-id {
                crisis-type: crisis-type,
                severity: severity,
                location: location,
                confirmed-at: stacks-block-height,
                confirmed-by: tx-sender,
                active: true
            })
            (var-set next-crisis-id (+ crisis-id u1))
            (trigger-fund-release crisis-id crisis-type)
            (ok crisis-id))))

(define-public (distribute-funds (crisis-id uint) (pool-id uint) (organization principal))
    (let (
        (crisis (unwrap! (map-get? active-crises crisis-id) ERR_CRISIS_NOT_ACTIVE))
        (pool (unwrap! (map-get? donation-pools pool-id) ERR_POOL_NOT_FOUND))
        (org (unwrap! (map-get? verified-organizations organization) ERR_ORGANIZATION_NOT_VERIFIED))
        (distribution-key { crisis-id: crisis-id, pool-id: pool-id })
    )
        (begin
            (asserts! (get active crisis) ERR_CRISIS_NOT_ACTIVE)
            (asserts! (get active org) ERR_ORGANIZATION_NOT_VERIFIED)
            (asserts! (get locked pool) ERR_POOL_LOCKED)
            (asserts! (not (get distributed pool)) ERR_ALREADY_DISTRIBUTED)
            (asserts! (is-none (map-get? crisis-distributions distribution-key)) ERR_ALREADY_DISTRIBUTED)
            (asserts! (> (get current-amount pool) u0) ERR_INSUFFICIENT_FUNDS)
            (try! (as-contract (stx-transfer? (get current-amount pool) tx-sender organization)))
            (map-set crisis-distributions distribution-key {
                organization: organization,
                amount: (get current-amount pool),
                distributed-at: stacks-block-height,
                tx-hash: (unwrap-panic (get-txid))
            })
            (map-set donation-pools pool-id (merge pool { distributed: true }))
            (ok (get current-amount pool)))))

(define-public (create-milestone (pool-id uint) (title (string-ascii 128)) (description (string-ascii 256)) (percentage uint))
    (let (
        (pool (unwrap! (map-get? donation-pools pool-id) ERR_POOL_NOT_FOUND))
        (milestone-count (default-to u0 (map-get? pool-milestone-count { pool-id: pool-id })))
        (milestone-id (+ milestone-count u1))
    )
        (begin
            (asserts! (is-eq tx-sender (get creator pool)) ERR_UNAUTHORIZED)
            (asserts! (and (> percentage u0) (<= percentage u100)) ERR_INVALID_PERCENTAGE)
            (asserts! (not (get locked pool)) ERR_POOL_LOCKED)
            (map-set pool-milestones { pool-id: pool-id, milestone-id: milestone-id } {
                title: title,
                description: description,
                percentage: percentage,
                completed: false,
                released-amount: u0,
                created-at: stacks-block-height,
                completed-at: none
            })
            (map-set pool-milestone-count { pool-id: pool-id } milestone-id)
            (ok milestone-id))))

(define-public (submit-milestone-report (pool-id uint) (milestone-id uint) (report (string-ascii 512)))
    (let (
        (pool (unwrap! (map-get? donation-pools pool-id) ERR_POOL_NOT_FOUND))
        (org (unwrap! (map-get? verified-organizations tx-sender) ERR_ORGANIZATION_NOT_VERIFIED))
        (milestone (unwrap! (map-get? pool-milestones { pool-id: pool-id, milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
    )
        (begin
            (asserts! (get active org) ERR_ORGANIZATION_NOT_VERIFIED)
            (asserts! (not (get completed milestone)) ERR_MILESTONE_COMPLETED)
            (map-set milestone-progress-reports { pool-id: pool-id, milestone-id: milestone-id } {
                organization: tx-sender,
                report: report,
                submitted-at: stacks-block-height,
                verified-by: tx-sender,
                verified-at: stacks-block-height
            })
            (ok true))))

(define-public (release-milestone-funds (pool-id uint) (milestone-id uint) (organization principal))
    (let (
        (pool (unwrap! (map-get? donation-pools pool-id) ERR_POOL_NOT_FOUND))
        (milestone (unwrap! (map-get? pool-milestones { pool-id: pool-id, milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
        (org (unwrap! (map-get? verified-organizations organization) ERR_ORGANIZATION_NOT_VERIFIED))
        (report (unwrap! (map-get? milestone-progress-reports { pool-id: pool-id, milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
        (release-amount (/ (* (get current-amount pool) (get percentage milestone)) u100))
    )
        (begin
            (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
            (asserts! (get locked pool) ERR_POOL_LOCKED)
            (asserts! (get active org) ERR_ORGANIZATION_NOT_VERIFIED)
            (asserts! (not (get completed milestone)) ERR_MILESTONE_COMPLETED)
            (asserts! (> release-amount u0) ERR_INSUFFICIENT_MILESTONE_FUNDS)
            (try! (as-contract (stx-transfer? release-amount tx-sender organization)))
            (map-set pool-milestones { pool-id: pool-id, milestone-id: milestone-id } (merge milestone {
                completed: true,
                released-amount: release-amount,
                completed-at: (some stacks-block-height)
            }))
            (ok release-amount))))

(define-public (withdraw-from-inactive-pool (pool-id uint))
    (let (
        (pool (unwrap! (map-get? donation-pools pool-id) ERR_POOL_NOT_FOUND))
        (contribution (unwrap! (map-get? donor-contributions { pool-id: pool-id, donor: tx-sender }) ERR_NO_CONTRIBUTION))
        (already-withdrawn (default-to false (map-get? donor-withdrawals { pool-id: pool-id, donor: tx-sender })))
        (blocks-since-creation (- stacks-block-height (get created-at pool)))
    )
        (begin
            (asserts! (not (get locked pool)) ERR_POOL_LOCKED)
            (asserts! (not (get distributed pool)) ERR_ALREADY_DISTRIBUTED)
            (asserts! (>= blocks-since-creation (var-get withdrawal-deadline-blocks)) ERR_POOL_DEADLINE_NOT_REACHED)
            (asserts! (> contribution u0) ERR_NO_CONTRIBUTION)
            (asserts! (not already-withdrawn) ERR_ALREADY_WITHDRAWN)
            (try! (as-contract (stx-transfer? contribution tx-sender tx-sender)))
            (map-set donor-withdrawals { pool-id: pool-id, donor: tx-sender } true)
            (map-set donation-pools pool-id (merge pool {
                current-amount: (- (get current-amount pool) contribution)
            }))
            (ok contribution))))

(define-private (trigger-fund-release (crisis-id uint) (crisis-type (string-ascii 32)))
    (let ((matching-pools (filter-pools-by-crisis-type crisis-type)))
        (fold lock-matching-pools matching-pools crisis-id)))

(define-private (lock-matching-pools (pool-info { pool-id: uint, crisis-type: (string-ascii 32) }) (crisis-id uint))
    (let (
        (pool-id (get pool-id pool-info))
        (pool (unwrap! (map-get? donation-pools pool-id) crisis-id))
    )
        (if (is-eq (get crisis-type pool) (get crisis-type pool-info))
            (begin
                (map-set donation-pools pool-id (merge pool { locked: true }))
                (map-set pool-crisis-mapping { pool-id: pool-id } crisis-id)
                crisis-id)
            crisis-id)))

(define-private (filter-pools-by-crisis-type (target-crisis-type (string-ascii 32)))
    (list 
        { pool-id: u1, crisis-type: target-crisis-type }
        { pool-id: u2, crisis-type: target-crisis-type }
        { pool-id: u3, crisis-type: target-crisis-type }
        { pool-id: u4, crisis-type: target-crisis-type }
        { pool-id: u5, crisis-type: target-crisis-type }
    ))

(define-private (get-txid)
    (ok 0x0000000000000000000000000000000000000000000000000000000000000000))

(define-read-only (get-pool-info (pool-id uint))
    (map-get? donation-pools pool-id))

(define-read-only (get-donor-contribution (pool-id uint) (donor principal))
    (map-get? donor-contributions { pool-id: pool-id, donor: donor }))

(define-read-only (get-organization-info (org principal))
    (map-get? verified-organizations org))

(define-read-only (get-crisis-info (crisis-id uint))
    (map-get? active-crises crisis-id))

(define-read-only (get-distribution-info (crisis-id uint) (pool-id uint))
    (map-get? crisis-distributions { crisis-id: crisis-id, pool-id: pool-id }))

(define-read-only (get-contract-info)
    {
        next-pool-id: (var-get next-pool-id),
        next-crisis-id: (var-get next-crisis-id),
        oracle-address: (var-get oracle-address),
        contract-paused: (var-get contract-paused)
    })

(define-read-only (get-pool-crisis-mapping (pool-id uint))
    (map-get? pool-crisis-mapping { pool-id: pool-id }))

(define-read-only (get-milestone-info (pool-id uint) (milestone-id uint))
    (map-get? pool-milestones { pool-id: pool-id, milestone-id: milestone-id }))

(define-read-only (get-milestone-report (pool-id uint) (milestone-id uint))
    (map-get? milestone-progress-reports { pool-id: pool-id, milestone-id: milestone-id }))

(define-read-only (get-pool-milestone-count (pool-id uint))
    (map-get? pool-milestone-count { pool-id: pool-id }))

(define-read-only (get-withdrawal-deadline)
    (var-get withdrawal-deadline-blocks))

(define-read-only (get-donor-withdrawal-status (pool-id uint) (donor principal))
    (default-to false (map-get? donor-withdrawals { pool-id: pool-id, donor: donor })))

(define-read-only (can-withdraw-from-pool (pool-id uint) (donor principal))
    (match (map-get? donation-pools pool-id)
        pool
            (let (
                (contribution (default-to u0 (map-get? donor-contributions { pool-id: pool-id, donor: donor })))
                (already-withdrawn (default-to false (map-get? donor-withdrawals { pool-id: pool-id, donor: donor })))
                (blocks-since-creation (- stacks-block-height (get created-at pool)))
            )
                (and
                    (not (get locked pool))
                    (not (get distributed pool))
                    (>= blocks-since-creation (var-get withdrawal-deadline-blocks))
                    (> contribution u0)
                    (not already-withdrawn)
                ))
        false))

