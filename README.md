# Stack-Stakes 💧

**Liquid Staking Protocol on Stacks Blockchain**

Stack-Stakes enables users to stake STX while maintaining liquidity through derivative tokens, featuring auto-compounding rewards, delegation marketplace, and comprehensive DeFi integration capabilities.

## 🌟 Key Features

### For Stakers

- **Liquid Staking**: Stake STX and receive tradeable liquid tokens maintaining DeFi accessibility
- **Auto-Compounding**: Automatic reward reinvestment with 0.5% per cycle yield
- **Instant Liquidity**: Trade or use liquid tokens in DeFi without unstaking delays
- **Flexible Unstaking**: 2-week cooling period with queue management system

### For Validators

- **Delegation Marketplace**: Compete for delegations with custom commission rates
- **Flexible Commission**: Set commission rates up to 20% with marketplace optimization
- **Reward Distribution**: Automated commission collection and reward processing
- **Validator Tools**: Registration, deactivation, and performance tracking

### For DeFi Users

- **Lending/Borrowing**: Use liquid tokens as collateral for STX loans (75% max LTV)
- **Yield Farming**: Earn additional yield on liquid tokens (2%+ APY)
- **Token Transfers**: Peer-to-peer liquid token transactions
- **Liquidation Protection**: Automated liquidation at 90% LTV for lender protection

## 📊 Smart Contract Architecture

### Core Components

1. **Staking Infrastructure**

   - Dynamic exchange rate calculation based on accumulated rewards
   - Minimum stake requirement (1 STX) with protocol fee collection (1%)
   - Comprehensive validator management with commission controls
   - Global protocol statistics and emergency pause functionality

2. **Liquid Token System**

   - Derivative tokens representing staked STX with accrued rewards
   - Auto-compounding mechanism with cycle-based reward calculation
   - Transfer functionality for DeFi integration and peer transactions
   - Unstaking queue with 2-week cooling period management

3. **Delegation Marketplace**

   - Competitive validator offers with custom commission rates (max 15%)
   - Minimum/maximum delegation limits with duration controls
   - Delegation request system for optimal validator selection
   - Performance tracking and offer management tools

4. **DeFi Integration**
   - Lending pools with liquid tokens as collateral
   - Automated liquidation system protecting lender interests
   - Yield farming with bonus rates for longer commitments
   - Comprehensive LTV ratio monitoring and risk management

## 🚀 Getting Started

### Prerequisites

- Stacks wallet (Hiro Wallet recommended)
- STX tokens for staking
- Clarinet for local development

### Deployment

```bash
# Install Clarinet
npm install -g @hirosystems/clarinet-cli

# Clone repository
git clone <repository-url>
cd flexstake

# Deploy to testnet
clarinet deploy --testnet

# Deploy to mainnet
clarinet deploy --mainnet
```

### Usage Examples

#### Staking STX for Liquid Tokens

```clarity
(contract-call? .flexstake stake-stx
    'SP1VALIDATOR123...  ;; Validator address
    u10000000)          ;; 10 STX stake amount
```

#### Creating Validator Delegation Offer

```clarity
(contract-call? .flexstake create-delegation-offer
    u1000               ;; 10% commission rate
    u5000000            ;; 5 STX minimum delegation
    u100000000          ;; 100 STX maximum delegation
    u4320)              ;; 30 days duration
```

#### Auto-Compounding Rewards

```clarity
(contract-call? .flexstake auto-compound-rewards
    'SP1VALIDATOR123...)  ;; Validator address
```

#### Creating Lending Position

```clarity
(contract-call? .flexstake create-lending-position
    u20000000           ;; 20 liquid tokens as collateral
    u10000000           ;; 10 STX borrow amount
    u500                ;; 5% interest rate
    u8640)              ;; 60 days duration
```

#### Initiating Unstaking

```clarity
(contract-call? .flexstake initiate-unstaking
    'SP1VALIDATOR123... ;; Validator address
    u5000000)           ;; 5 liquid tokens to unstake
```

## 📈 Contract Functions

### Staking Operations

- `stake-stx()` - Stake STX and receive liquid tokens
- `initiate-unstaking()` - Begin unstaking process with cooling period
- `complete-unstaking()` - Complete unstaking after cooling period
- `auto-compound-rewards()` - Compound accumulated rewards automatically

### Validator Management

- `register-validator()` - Register as validator with commission rate
- `update-validator-commission()` - Adjust validator commission rate
- `distribute-rewards()` - Distribute staking rewards to delegators
- `claim-validator-rewards()` - Claim validator commission earnings

### Liquid Token Operations

- `transfer-liquid-tokens()` - Transfer tokens between users
- `calculate-liquid-tokens()` - Calculate liquid tokens for STX amount
- `calculate-stx-value()` - Calculate STX value of liquid tokens
- `get-liquid-token-balance()` - Check user's liquid token balance

### Delegation Marketplace

- `create-delegation-offer()` - Create validator delegation offer
- `accept-delegation-offer()` - Accept delegation offer and stake
- `cancel-delegation-offer()` - Cancel active delegation offer

### DeFi Integration

- `create-lending-position()` - Borrow against liquid token collateral
- `repay-lending-position()` - Repay loan and reclaim collateral
- `liquidate-lending-position()` - Liquidate undercollateralized positions
- `deposit-for-yield()` - Deposit tokens for yield farming

## 🔒 Security Features

- **Dynamic Exchange Rate**: Automatic rate updates based on reward accumulation
- **Cooling Periods**: 2-week unstaking period preventing manipulation
- **LTV Monitoring**: Real-time loan-to-value ratio tracking with liquidation triggers
- **Commission Limits**: Maximum commission rates preventing excessive fees
- **Emergency Controls**: Contract pause and position closure for security incidents

## 📊 Use Cases

### Individual Stakers

- **Maintain Liquidity**: Stake STX without losing DeFi access
- **Compound Growth**: Automatic reward reinvestment maximizing returns
- **Risk Management**: Diversify across multiple validators
- **Flexible Exit**: Trade liquid tokens or unstake with cooling period

### Institutional Investors

- **Large Scale Staking**: Efficient delegation to multiple validators
- **DeFi Integration**: Use liquid tokens across DeFi protocols
- **Risk Management**: Automated liquidation protection in lending
- **Yield Optimization**: Combine staking rewards with DeFi yield

### Validators

- **Competitive Advantage**: Attract delegations through marketplace
- **Flexible Pricing**: Adjust commission rates based on performance
- **Automated Operations**: Streamlined reward distribution
- **Marketing Platform**: Showcase performance to attract delegators

### DeFi Protocols

- **Collateral Integration**: Accept liquid tokens as collateral
- **Yield Strategies**: Build products using auto-compounding tokens
- **Liquidity Provision**: Enhanced liquidity through tradeable stakes
- **Risk Management**: Leverage liquidation mechanisms for safety

## 📋 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built on Stacks | Secured by Bitcoin | Liquid Staking for the Future**
