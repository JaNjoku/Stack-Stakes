;; Stack-Stakes - Liquid Staking Protocol

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-pool-not-found (err u104))
(define-constant err-already-staking (err u105))
(define-constant err-not-staking (err u106))
(define-constant err-unstaking-period (err u107))
(define-constant err-invalid-validator (err u108))

;; Protocol constants
(define-constant MIN-STAKE-AMOUNT u1000000) ;; 1 STX minimum
(define-constant UNSTAKING-PERIOD u2016) ;; ~2 weeks in blocks
(define-constant PROTOCOL-FEE-RATE u100) ;; 1% protocol fee
(define-constant REWARD-CYCLE u2100) ;; Stacks reward cycle length

;; Data variables
(define-data-var total-staked uint u0)
(define-data-var total-liquid-tokens uint u0)
(define-data-var exchange-rate uint u1000000) ;; 1:1 initially (6 decimals)
(define-data-var protocol-fees uint u0)
(define-data-var contract-paused bool false)
(define-data-var current-cycle uint u0)

;; Staking pool data
(define-map staking-pools
    principal ;; validator
    {
        total-delegated: uint,
        liquid-tokens-issued: uint,
        active: bool,
        commission-rate: uint,
        validator-rewards: uint,
        last-reward-cycle: uint,
    }
)

;; User staking positions
(define-map user-stakes
    {
        user: principal,
        validator: principal,
    }
    {
        stx-amount: uint,
        liquid-tokens: uint,
        stake-height: uint,
        unstaking-height: (optional uint),
        rewards-claimed: uint,
    }
)

;; Liquid token balances
(define-map liquid-token-balances
    principal
    {
        balance: uint,
        last-claim-cycle: uint,
    }
)

;; Unstaking queue
(define-map unstaking-requests
    {
        user: principal,
        request-id: uint,
    }
    {
        amount: uint,
        liquid-tokens: uint,
        initiated-height: uint,
        completed: bool,
    }
)

(define-data-var unstaking-counter uint u0)

;; Read-only functions
(define-read-only (get-staking-pool (validator principal))
    (map-get? staking-pools validator)
)

(define-read-only (get-user-stake
        (user principal)
        (validator principal)
    )
    (map-get? user-stakes {
        user: user,
        validator: validator,
    })
)

(define-read-only (get-liquid-token-balance (user principal))
    (default-to {
        balance: u0,
        last-claim-cycle: u0,
    }
        (map-get? liquid-token-balances user)
    )
)

(define-read-only (get-protocol-stats)
    (ok {
        total-staked: (var-get total-staked),
        total-liquid-tokens: (var-get total-liquid-tokens),
        exchange-rate: (var-get exchange-rate),
        protocol-fees: (var-get protocol-fees),
        current-cycle: (var-get current-cycle),
    })
)

(define-read-only (calculate-liquid-tokens (stx-amount uint))
    (/ (* stx-amount u1000000) (var-get exchange-rate))
)

(define-read-only (calculate-stx-value (liquid-tokens uint))
    (/ (* liquid-tokens (var-get exchange-rate)) u1000000)
)

;; Private functions
(define-private (calculate-protocol-fee (amount uint))
    (/ (* amount PROTOCOL-FEE-RATE) u10000)
)

(define-private (update-exchange-rate (new-rewards uint))
    (let (
            (current-staked (var-get total-staked))
            (current-liquid (var-get total-liquid-tokens))
        )
        (if (> current-liquid u0)
            (let ((new-rate (/ (* (+ current-staked new-rewards) u1000000) current-liquid)))
                (var-set exchange-rate new-rate)
                (ok new-rate)
            )
            (ok (var-get exchange-rate))
        )
    )
)

;; Validator management
(define-public (register-validator (commission-rate uint))
    (begin
        (asserts! (not (var-get contract-paused)) err-not-authorized)
        (asserts! (<= commission-rate u2000) err-invalid-amount) ;; Max 20% commission
        (asserts! (is-none (map-get? staking-pools tx-sender))
            err-already-staking
        )
        (map-set staking-pools tx-sender {
            total-delegated: u0,
            liquid-tokens-issued: u0,
            active: true,
            commission-rate: commission-rate,
            validator-rewards: u0,
            last-reward-cycle: (var-get current-cycle),
        })
        (ok true)
    )
)

(define-public (update-validator-commission (new-commission uint))
    (let ((pool (unwrap! (map-get? staking-pools tx-sender) err-pool-not-found)))
        (begin
            (asserts! (<= new-commission u2000) err-invalid-amount)
            (asserts! (get active pool) err-not-authorized)
            (map-set staking-pools tx-sender
                (merge pool { commission-rate: new-commission })
            )
            (ok true)
        )
    )
)

(define-public (deactivate-validator)
    (let ((pool (unwrap! (map-get? staking-pools tx-sender) err-pool-not-found)))
        (begin
            (asserts! (get active pool) err-not-authorized)
            (map-set staking-pools tx-sender (merge pool { active: false }))
            (ok true)
        )
    )
)

;; Core staking functionality
(define-public (stake-stx
        (validator principal)
        (amount uint)
    )
    (let (
            (pool (unwrap! (map-get? staking-pools validator) err-pool-not-found))
            (liquid-tokens (calculate-liquid-tokens amount))
            (protocol-fee (calculate-protocol-fee amount))
            (net-stake (- amount protocol-fee))
            (existing-stake (map-get? user-stakes {
                user: tx-sender,
                validator: validator,
            }))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-not-authorized)
            (asserts! (get active pool) err-invalid-validator)
            (asserts! (>= amount MIN-STAKE-AMOUNT) err-invalid-amount)
            (asserts! (>= (stx-get-balance tx-sender) amount)
                err-insufficient-balance
            )
            ;; Transfer STX to contract
            (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender))
                err-insufficient-balance
            )
            ;; Update or create user stake
            (match existing-stake
                stake (map-set user-stakes {
                    user: tx-sender,
                    validator: validator,
                }
                    (merge stake {
                        stx-amount: (+ (get stx-amount stake) net-stake),
                        liquid-tokens: (+ (get liquid-tokens stake) liquid-tokens),
                    })
                )
                (map-set user-stakes {
                    user: tx-sender,
                    validator: validator,
                } {
                    stx-amount: net-stake,
                    liquid-tokens: liquid-tokens,
                    stake-height: stacks-block-height,
                    unstaking-height: none,
                    rewards-claimed: u0,
                })
            )
            ;; Update pool stats
            (map-set staking-pools validator
                (merge pool {
                    total-delegated: (+ (get total-delegated pool) net-stake),
                    liquid-tokens-issued: (+ (get liquid-tokens-issued pool) liquid-tokens),
                })
            )
            ;; Update liquid token balance
            (let ((current-balance (get-liquid-token-balance tx-sender)))
                (map-set liquid-token-balances tx-sender {
                    balance: (+ (get balance current-balance) liquid-tokens),
                    last-claim-cycle: (var-get current-cycle),
                })
            )
            ;; Update global stats
            (var-set total-staked (+ (var-get total-staked) net-stake))
            (var-set total-liquid-tokens
                (+ (var-get total-liquid-tokens) liquid-tokens)
            )
            (var-set protocol-fees (+ (var-get protocol-fees) protocol-fee))
            (ok liquid-tokens)
        )
    )
)

;; Administrative functions
(define-public (update-current-cycle (new-cycle uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set current-cycle new-cycle)
        (ok true)
    )
)

(define-public (toggle-contract-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-paused (not (var-get contract-paused)))
        (ok true)
    )
)

(define-public (withdraw-protocol-fees)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let ((fees (var-get protocol-fees)))
            (var-set protocol-fees u0)
            (as-contract (stx-transfer? fees tx-sender contract-owner))
        )
    )
)
