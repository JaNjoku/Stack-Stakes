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

;; Delegation marketplace
(define-map delegation-offers
    uint
    {
        validator: principal,
        offered-commission: uint,
        minimum-delegation: uint,
        maximum-delegation: uint,
        duration: uint,
        active: bool,
        created-height: uint,
        delegators-count: uint,
    }
)

(define-data-var offer-counter uint u0)

;; Delegation requests from users
(define-map delegation-requests
    {
        user: principal,
        offer-id: uint,
    }
    {
        amount: uint,
        accepted: bool,
        created-height: uint,
    }
)

;; DeFi integration - Lending/borrowing against liquid tokens
(define-map lending-pools
    uint
    {
        lender: principal,
        collateral-amount: uint, ;; Liquid tokens as collateral
        borrowed-amount: uint, ;; STX borrowed
        interest-rate: uint,
        duration: uint,
        active: bool,
        created-height: uint,
    }
)

(define-data-var lending-counter uint u0)

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

;; Unstaking functionality
(define-public (initiate-unstaking
        (validator principal)
        (liquid-token-amount uint)
    )
    (let (
            (user-stake (unwrap!
                (map-get? user-stakes {
                    user: tx-sender,
                    validator: validator,
                })
                err-not-staking
            ))
            (stx-value (calculate-stx-value liquid-token-amount))
            (request-id (var-get unstaking-counter))
            (user-balance (get-liquid-token-balance tx-sender))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-not-authorized)
            (asserts! (> liquid-token-amount u0) err-invalid-amount)
            (asserts! (>= (get balance user-balance) liquid-token-amount)
                err-insufficient-balance
            )
            (asserts! (is-none (get unstaking-height user-stake))
                err-unstaking-period
            )
            ;; Create unstaking request
            (map-set unstaking-requests {
                user: tx-sender,
                request-id: request-id,
            } {
                amount: stx-value,
                liquid-tokens: liquid-token-amount,
                initiated-height: stacks-block-height,
                completed: false,
            })
            ;; Update user stake with unstaking height
            (map-set user-stakes {
                user: tx-sender,
                validator: validator,
            }
                (merge user-stake { unstaking-height: (some stacks-block-height) })
            )
            ;; Update liquid token balance
            (map-set liquid-token-balances tx-sender {
                balance: (- (get balance user-balance) liquid-token-amount),
                last-claim-cycle: (get last-claim-cycle user-balance),
            })
            (var-set unstaking-counter (+ request-id u1))
            (ok request-id)
        )
    )
)

(define-public (complete-unstaking (request-id uint))
    (let ((request (unwrap!
            (map-get? unstaking-requests {
                user: tx-sender,
                request-id: request-id,
            })
            err-pool-not-found
        )))
        (begin
            (asserts! (not (get completed request)) err-not-authorized)
            (asserts!
                (>= stacks-block-height
                    (+ (get initiated-height request) UNSTAKING-PERIOD)
                )
                err-unstaking-period
            )
            ;; Transfer STX back to user
            (unwrap!
                (as-contract (stx-transfer? (get amount request) tx-sender tx-sender))
                err-insufficient-balance
            )
            ;; Mark request as completed
            (map-set unstaking-requests {
                user: tx-sender,
                request-id: request-id,
            }
                (merge request { completed: true })
            )
            ;; Update global stats
            (var-set total-staked (- (var-get total-staked) (get amount request)))
            (var-set total-liquid-tokens
                (- (var-get total-liquid-tokens) (get liquid-tokens request))
            )
            (ok true)
        )
    )
)

;; Rewards distribution and claiming
(define-public (distribute-rewards
        (validator principal)
        (rewards-amount uint)
    )
    (let (
            (pool (unwrap! (map-get? staking-pools validator) err-pool-not-found))
            (commission (/ (* rewards-amount (get commission-rate pool)) u10000))
            (net-rewards (- rewards-amount commission))
        )
        (begin
            (asserts! (is-eq tx-sender validator) err-not-authorized)
            (asserts! (get active pool) err-invalid-validator)
            (asserts! (> rewards-amount u0) err-invalid-amount)
            ;; Update pool with validator commission
            (map-set staking-pools validator
                (merge pool {
                    validator-rewards: (+ (get validator-rewards pool) commission),
                    last-reward-cycle: (var-get current-cycle),
                })
            )
            ;; Update exchange rate with net rewards
            (unwrap! (update-exchange-rate net-rewards) err-not-authorized)
            ;; Update total staked to reflect rewards
            (var-set total-staked (+ (var-get total-staked) net-rewards))
            (ok true)
        )
    )
)

(define-public (claim-validator-rewards)
    (let (
            (pool (unwrap! (map-get? staking-pools tx-sender) err-pool-not-found))
            (rewards (get validator-rewards pool))
        )
        (begin
            (asserts! (> rewards u0) err-invalid-amount)
            ;; Transfer validator rewards
            (unwrap! (as-contract (stx-transfer? rewards tx-sender tx-sender))
                err-insufficient-balance
            )
            ;; Reset validator rewards
            (map-set staking-pools tx-sender
                (merge pool { validator-rewards: u0 })
            )
            (ok rewards)
        )
    )
)

(define-public (claim-staking-rewards (validator principal))
    (let (
            (user-stake (unwrap!
                (map-get? user-stakes {
                    user: tx-sender,
                    validator: validator,
                })
                err-not-staking
            ))
            (current-value (calculate-stx-value (get liquid-tokens user-stake)))
            (original-stake (get stx-amount user-stake))
            (rewards (if (> current-value original-stake)
                (- current-value original-stake)
                u0
            ))
        )
        (begin
            (asserts! (> rewards u0) err-invalid-amount)
            ;; Auto-compound by converting rewards to liquid tokens
            (let ((additional-liquid-tokens (calculate-liquid-tokens rewards)))
                (map-set user-stakes {
                    user: tx-sender,
                    validator: validator,
                }
                    (merge user-stake {
                        liquid-tokens: (+ (get liquid-tokens user-stake)
                            additional-liquid-tokens
                        ),
                        rewards-claimed: (+ (get rewards-claimed user-stake) rewards),
                    })
                )
                ;; Update user liquid token balance
                (let ((current-balance (get-liquid-token-balance tx-sender)))
                    (map-set liquid-token-balances tx-sender {
                        balance: (+ (get balance current-balance) additional-liquid-tokens),
                        last-claim-cycle: (var-get current-cycle),
                    })
                )
                (ok additional-liquid-tokens)
            )
        )
    )
)

;; Liquid token transfer functionality
(define-public (transfer-liquid-tokens
        (recipient principal)
        (amount uint)
    )
    (let (
            (sender-balance (get-liquid-token-balance tx-sender))
            (recipient-balance (get-liquid-token-balance recipient))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-not-authorized)
            (asserts! (> amount u0) err-invalid-amount)
            (asserts! (>= (get balance sender-balance) amount)
                err-insufficient-balance
            )
            (asserts! (not (is-eq tx-sender recipient)) err-invalid-amount)
            ;; Update sender balance
            (map-set liquid-token-balances tx-sender {
                balance: (- (get balance sender-balance) amount),
                last-claim-cycle: (get last-claim-cycle sender-balance),
            })
            ;; Update recipient balance
            (map-set liquid-token-balances recipient {
                balance: (+ (get balance recipient-balance) amount),
                last-claim-cycle: (var-get current-cycle),
            })
            (ok true)
        )
    )
)

;; Auto-compounding mechanism
(define-public (auto-compound-rewards (validator principal))
    (let (
            (user-stake (unwrap!
                (map-get? user-stakes {
                    user: tx-sender,
                    validator: validator,
                })
                err-not-staking
            ))
            (pool (unwrap! (map-get? staking-pools validator) err-pool-not-found))
            (user-balance (get-liquid-token-balance tx-sender))
            (cycles-since-claim (- (var-get current-cycle) (get last-claim-cycle user-balance)))
        )
        (begin
            (asserts! (> cycles-since-claim u0) err-invalid-amount)
            (asserts! (get active pool) err-invalid-validator)
            ;; Calculate accumulated rewards based on cycles
            (let (
                    (current-value (calculate-stx-value (get liquid-tokens user-stake)))
                    (reward-rate (/ u50 u10000)) ;; 0.5% per cycle
                    (accumulated-rewards (/ (* current-value reward-rate cycles-since-claim) u1))
                )
                (if (> accumulated-rewards u0)
                    (let ((additional-liquid-tokens (calculate-liquid-tokens accumulated-rewards)))
                        ;; Update user stake
                        (map-set user-stakes {
                            user: tx-sender,
                            validator: validator,
                        }
                            (merge user-stake {
                                liquid-tokens: (+ (get liquid-tokens user-stake)
                                    additional-liquid-tokens
                                ),
                                rewards-claimed: (+ (get rewards-claimed user-stake)
                                    accumulated-rewards
                                ),
                            })
                        )
                        ;; Update liquid token balance
                        (map-set liquid-token-balances tx-sender {
                            balance: (+ (get balance user-balance)
                                additional-liquid-tokens
                            ),
                            last-claim-cycle: (var-get current-cycle),
                        })
                        (ok additional-liquid-tokens)
                    )
                    (ok u0)
                )
            )
        )
    )
)

;; Read-only functions for rewards
(define-read-only (get-unstaking-request
        (user principal)
        (request-id uint)
    )
    (map-get? unstaking-requests {
        user: user,
        request-id: request-id,
    })
)

(define-read-only (calculate-pending-rewards
        (user principal)
        (validator principal)
    )
    (match (map-get? user-stakes {
        user: user,
        validator: validator,
    })
        stake (let (
                (current-value (calculate-stx-value (get liquid-tokens stake)))
                (original-stake (get stx-amount stake))
            )
            (ok (if (> current-value original-stake)
                (- current-value original-stake)
                u0
            ))
        )
        (ok u0)
    )
)

(define-read-only (get-user-yield
        (user principal)
        (validator principal)
    )
    (match (map-get? user-stakes {
        user: user,
        validator: validator,
    })
        stake (let (
                (current-value (calculate-stx-value (get liquid-tokens stake)))
                (original-stake (get stx-amount stake))
                (yield-percentage (if (> original-stake u0)
                    (/ (* (- current-value original-stake) u10000) original-stake)
                    u0
                ))
            )
            (ok yield-percentage)
        )
        (ok u0)
    )
)

;; Delegation marketplace functions
(define-public (create-delegation-offer
        (offered-commission uint)
        (minimum-delegation uint)
        (maximum-delegation uint)
        (duration uint)
    )
    (let ((offer-id (var-get offer-counter)))
        (begin
            (asserts! (not (var-get contract-paused)) err-not-authorized)
            (asserts! (is-some (map-get? staking-pools tx-sender))
                err-invalid-validator
            )
            (asserts! (<= offered-commission u1500) err-invalid-amount) ;; Max 15% for marketplace
            (asserts! (> minimum-delegation u0) err-invalid-amount)
            (asserts! (>= maximum-delegation minimum-delegation)
                err-invalid-amount
            )
            (asserts! (> duration u0) err-invalid-amount)
            (map-set delegation-offers offer-id {
                validator: tx-sender,
                offered-commission: offered-commission,
                minimum-delegation: minimum-delegation,
                maximum-delegation: maximum-delegation,
                duration: duration,
                active: true,
                created-height: stacks-block-height,
                delegators-count: u0,
            })
            (var-set offer-counter (+ offer-id u1))
            (ok offer-id)
        )
    )
)

(define-public (accept-delegation-offer
        (offer-id uint)
        (amount uint)
    )
    (let (
            (offer (unwrap! (map-get? delegation-offers offer-id) err-pool-not-found))
            (existing-request (map-get? delegation-requests {
                user: tx-sender,
                offer-id: offer-id,
            }))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-not-authorized)
            (asserts! (get active offer) err-not-authorized)
            (asserts! (>= amount (get minimum-delegation offer))
                err-invalid-amount
            )
            (asserts! (<= amount (get maximum-delegation offer))
                err-invalid-amount
            )
            (asserts! (is-none existing-request) err-already-staking)
            ;; Create delegation request
            (map-set delegation-requests {
                user: tx-sender,
                offer-id: offer-id,
            } {
                amount: amount,
                accepted: false,
                created-height: stacks-block-height,
            })
            ;; Stake with the validator from the offer
            (unwrap! (stake-stx (get validator offer) amount)
                err-insufficient-balance
            )
            ;; Update offer statistics
            (map-set delegation-offers offer-id
                (merge offer { delegators-count: (+ (get delegators-count offer) u1) })
            )
            (ok true)
        )
    )
)

(define-public (cancel-delegation-offer (offer-id uint))
    (let ((offer (unwrap! (map-get? delegation-offers offer-id) err-pool-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get validator offer)) err-not-authorized)
            (asserts! (get active offer) err-not-authorized)
            (map-set delegation-offers offer-id (merge offer { active: false }))
            (ok true)
        )
    )
)

;; DeFi integration - Lending against liquid tokens
(define-public (create-lending-position
        (collateral-amount uint)
        (borrow-amount uint)
        (interest-rate uint)
        (duration uint)
    )
    (let (
            (lending-id (var-get lending-counter))
            (user-balance (get-liquid-token-balance tx-sender))
            (collateral-value (calculate-stx-value collateral-amount))
            (ltv-ratio (/ (* borrow-amount u100) collateral-value)) ;; Loan-to-value ratio
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-not-authorized)
            (asserts! (>= (get balance user-balance) collateral-amount)
                err-insufficient-balance
            )
            (asserts! (<= ltv-ratio u75) err-invalid-amount) ;; Max 75% LTV
            (asserts! (> borrow-amount u0) err-invalid-amount)
            (asserts! (> duration u0) err-invalid-amount)
            ;; Lock collateral
            (map-set liquid-token-balances tx-sender {
                balance: (- (get balance user-balance) collateral-amount),
                last-claim-cycle: (get last-claim-cycle user-balance),
            })
            ;; Create lending position
            (map-set lending-pools lending-id {
                lender: tx-sender,
                collateral-amount: collateral-amount,
                borrowed-amount: borrow-amount,
                interest-rate: interest-rate,
                duration: duration,
                active: true,
                created-height: stacks-block-height,
            })
            ;; Transfer borrowed STX to user
            (unwrap!
                (as-contract (stx-transfer? borrow-amount tx-sender tx-sender))
                err-insufficient-balance
            )
            (var-set lending-counter (+ lending-id u1))
            (ok lending-id)
        )
    )
)

(define-public (repay-lending-position (lending-id uint))
    (let (
            (position (unwrap! (map-get? lending-pools lending-id) err-pool-not-found))
            (interest (/ (* (get borrowed-amount position) (get interest-rate position))
                u10000
            ))
            (total-repayment (+ (get borrowed-amount position) interest))
            (user-balance (get-liquid-token-balance tx-sender))
        )
        (begin
            (asserts! (is-eq tx-sender (get lender position)) err-not-authorized)
            (asserts! (get active position) err-not-authorized)
            (asserts! (>= (stx-get-balance tx-sender) total-repayment)
                err-insufficient-balance
            )
            ;; Transfer repayment to contract
            (unwrap!
                (stx-transfer? total-repayment tx-sender (as-contract tx-sender))
                err-insufficient-balance
            )
            ;; Return collateral to user
            (map-set liquid-token-balances tx-sender {
                balance: (+ (get balance user-balance) (get collateral-amount position)),
                last-claim-cycle: (get last-claim-cycle user-balance),
            })
            ;; Close lending position
            (map-set lending-pools lending-id (merge position { active: false }))
            (ok true)
        )
    )
)

;; Liquidation mechanism for undercollateralized positions
(define-public (liquidate-lending-position (lending-id uint))
    (let (
            (position (unwrap! (map-get? lending-pools lending-id) err-pool-not-found))
            (current-collateral-value (calculate-stx-value (get collateral-amount position)))
            (ltv-ratio (/ (* (get borrowed-amount position) u100) current-collateral-value))
        )
        (begin
            (asserts! (get active position) err-not-authorized)
            (asserts! (> ltv-ratio u90) err-not-authorized) ;; Liquidate if LTV > 90%
            ;; Transfer collateral to liquidator as reward
            (let ((liquidator-balance (get-liquid-token-balance tx-sender)))
                (map-set liquid-token-balances tx-sender {
                    balance: (+ (get balance liquidator-balance)
                        (get collateral-amount position)
                    ),
                    last-claim-cycle: (get last-claim-cycle liquidator-balance),
                })
            )
            ;; Close position
            (map-set lending-pools lending-id (merge position { active: false }))
            (ok true)
        )
    )
)

;; Yield farming with liquid tokens
(define-public (deposit-for-yield
        (amount uint)
        (farming-period uint)
    )
    (let (
            (user-balance (get-liquid-token-balance tx-sender))
            (yield-rate (/ u200 u10000)) ;; 2% base yield
            (bonus-rate (if (> farming-period u4320)
                (/ u50 u10000)
                u0
            ))
            ;; 0.5% bonus for 30+ days
            (total-rate (+ yield-rate bonus-rate))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-not-authorized)
            (asserts! (>= (get balance user-balance) amount)
                err-insufficient-balance
            )
            (asserts! (> amount u0) err-invalid-amount)
            (asserts! (>= farming-period u144) err-invalid-amount) ;; Min 1 day
            ;; Lock tokens for yield farming
            (map-set liquid-token-balances tx-sender {
                balance: (- (get balance user-balance) amount),
                last-claim-cycle: (get last-claim-cycle user-balance),
            })
            ;; Calculate and add yield after farming period (simplified)
            (let ((yield-amount (/ (* amount total-rate farming-period) u52560)))
                ;; Annualized
                (map-set liquid-token-balances tx-sender {
                    balance: (+ (- (get balance user-balance) amount) amount yield-amount),
                    last-claim-cycle: (var-get current-cycle),
                })
                (ok yield-amount)
            )
        )
    )
)

;; Read-only functions for marketplace and DeFi
(define-read-only (get-delegation-offer (offer-id uint))
    (map-get? delegation-offers offer-id)
)

(define-read-only (get-delegation-request
        (user principal)
        (offer-id uint)
    )
    (map-get? delegation-requests {
        user: user,
        offer-id: offer-id,
    })
)

(define-read-only (get-lending-position (lending-id uint))
    (map-get? lending-pools lending-id)
)

(define-read-only (get-active-offers)
    (ok (var-get offer-counter))
)

(define-read-only (calculate-ltv-ratio (lending-id uint))
    (match (map-get? lending-pools lending-id)
        position (let (
                (collateral-value (calculate-stx-value (get collateral-amount position)))
                (borrowed-amount (get borrowed-amount position))
            )
            (ok (if (> collateral-value u0)
                (/ (* borrowed-amount u100) collateral-value)
                u0
            ))
        )
        (ok u0)
    )
)

(define-read-only (get-marketplace-stats)
    (ok {
        total-offers: (var-get offer-counter),
        total-lending-positions: (var-get lending-counter),
        protocol-tvl: (var-get total-staked),
        liquid-token-supply: (var-get total-liquid-tokens),
    })
)

;; Emergency functions
(define-public (emergency-close-lending-position (lending-id uint))
    (let ((position (unwrap! (map-get? lending-pools lending-id) err-pool-not-found)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (map-set lending-pools lending-id (merge position { active: false }))
            (ok true)
        )
    )
)

(define-public (update-protocol-parameters
        (new-min-stake uint)
        (new-fee-rate uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-min-stake u0) err-invalid-amount)
        (asserts! (<= new-fee-rate u500) err-invalid-amount) ;; Max 5% fee
        ;; Note: Would need to add these as data variables in a full implementation
        (ok true)
    )
)
