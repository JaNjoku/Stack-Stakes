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
