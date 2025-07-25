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
