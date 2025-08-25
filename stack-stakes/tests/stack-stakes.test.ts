
import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

const contractName = "stack-stakes";

describe("Stack-Stakes Protocol", () => {
  beforeEach(() => {
    // Reset simnet state before each test
    simnet.setEpoch("3.0");
  });

  describe("Core Staking Functionality", () => {
    describe("Validator Management", () => {
      it("should allow validator registration with valid commission", () => {
        const commissionRate = 1000; // 10%
        
        const { result } = simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(commissionRate)],
          wallet1
        );
        
        expect(result).toBeOk(Cl.bool(true));
        
        // Verify validator is registered
        const validator = simnet.callReadOnlyFn(
          contractName,
          "get-staking-pool",
          [Cl.principal(wallet1)],
          wallet1
        );
        
        expect(validator.result).toBeSome(Cl.tuple({
          active: Cl.bool(true),
          "commission-rate": Cl.uint(commissionRate),
          "last-reward-cycle": Cl.uint(0),
          "liquid-tokens-issued": Cl.uint(0),
          "total-delegated": Cl.uint(0),
          "validator-rewards": Cl.uint(0),
        }));
      });

      it("should reject validator registration with invalid commission rate", () => {
        const invalidCommissionRate = 2500; // 25% (exceeds max 20%)
        
        const { result } = simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(invalidCommissionRate)],
          wallet1
        );
        
        expect(result).toBeErr(Cl.uint(103)); // err-invalid-amount
      });

      it("should prevent duplicate validator registration", () => {
        const commissionRate = 1000;
        
        // First registration should succeed
        simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(commissionRate)],
          wallet1
        );
        
        // Second registration should fail
        const { result } = simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(commissionRate)],
          wallet1
        );
        
        expect(result).toBeErr(Cl.uint(105)); // err-already-staking
      });

      it("should allow validator to update commission rate", () => {
        const initialCommission = 1000;
        const newCommission = 1500;
        
        // Register validator
        simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(initialCommission)],
          wallet1
        );
        
        // Update commission
        const { result } = simnet.callPublicFn(
          contractName,
          "update-validator-commission",
          [Cl.uint(newCommission)],
          wallet1
        );
        
        expect(result).toBeOk(Cl.bool(true));
        
        // Verify commission was updated
        const validator = simnet.callReadOnlyFn(
          contractName,
          "get-staking-pool",
          [Cl.principal(wallet1)],
          wallet1
        );
        
        expect(validator.result).toBeSome(Cl.tuple({
          active: Cl.bool(true),
          "commission-rate": Cl.uint(newCommission),
          "last-reward-cycle": Cl.uint(0),
          "liquid-tokens-issued": Cl.uint(0),
          "total-delegated": Cl.uint(0),
          "validator-rewards": Cl.uint(0),
        }));
        // Note: Detailed property validation will be added in next commit phase
      });

      it("should allow validator to deactivate", () => {
        const commissionRate = 1000;
        
        // Register validator
        simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(commissionRate)],
          wallet1
        );
        
        // Deactivate validator
        const { result } = simnet.callPublicFn(
          contractName,
          "deactivate-validator",
          [],
          wallet1
        );
        
        expect(result).toBeOk(Cl.bool(true));
        
        // Verify validator is deactivated
        const validator = simnet.callReadOnlyFn(
          contractName,
          "get-staking-pool",
          [Cl.principal(wallet1)],
          wallet1
        );
        
        expect(validator.result).toBeSome(Cl.tuple({
          active: Cl.bool(false),
          "commission-rate": Cl.uint(commissionRate),
          "last-reward-cycle": Cl.uint(0),
          "liquid-tokens-issued": Cl.uint(0),
          "total-delegated": Cl.uint(0),
          "validator-rewards": Cl.uint(0),
        }));
        // Note: Active status validation will be added in next commit phase
      });
    });

    describe("Basic Staking Operations", () => {
      beforeEach(() => {
        // Register a validator for staking tests
        simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(1000)], // 10% commission
          wallet1
        );
      });

      it("should allow users to stake STX with minimum amount", () => {
        const stakeAmount = 1000000; // 1 STX (minimum)
        
        const { result } = simnet.callPublicFn(
          contractName,
          "stake-stx",
          [Cl.principal(wallet1), Cl.uint(stakeAmount)],
          wallet2
        );
        
        expect(result).toBeOk(Cl.uint(1000000));
        
        // Verify user stake was created
        const userStake = simnet.callReadOnlyFn(
          contractName,
          "get-user-stake",
          [Cl.principal(wallet2), Cl.principal(wallet1)],
          wallet2
        );
        
        expect(userStake.result).toBeSome(Cl.tuple({
          "stx-amount": Cl.uint(990000), // After 1% protocol fee
          "liquid-tokens": Cl.uint(1000000),
          "stake-height": Cl.uint(simnet.blockHeight),
          "unstaking-height": Cl.none(),
          "rewards-claimed": Cl.uint(0),
        }));
      });

      it("should reject staking below minimum amount", () => {
        const belowMinimum = 500000; // 0.5 STX
        
        const { result } = simnet.callPublicFn(
          contractName,
          "stake-stx",
          [Cl.principal(wallet1), Cl.uint(belowMinimum)],
          wallet2
        );
        
        expect(result).toBeErr(Cl.uint(103)); // err-invalid-amount
      });

      it("should reject staking with inactive validator", () => {
        // Deactivate validator
        simnet.callPublicFn(
          contractName,
          "deactivate-validator",
          [],
          wallet1
        );
        
        const stakeAmount = 1000000;
        
        const { result } = simnet.callPublicFn(
          contractName,
          "stake-stx",
          [Cl.principal(wallet1), Cl.uint(stakeAmount)],
          wallet2
        );
        
        expect(result).toBeErr(Cl.uint(108)); // err-invalid-validator
      });

      it("should calculate correct liquid tokens on staking", () => {
        const stakeAmount = 10000000; // 10 STX
        
        const { result } = simnet.callPublicFn(
          contractName,
          "stake-stx",
          [Cl.principal(wallet1), Cl.uint(stakeAmount)],
          wallet2
        );
        
        // The contract returns the full amount as liquid tokens, not net stake
        // Since exchange rate is 1:1 initially and liquid tokens = stx amount
        expect(result).toBeOk(Cl.uint(stakeAmount));
        
        // Verify liquid token balance
        const balance = simnet.callReadOnlyFn(
          contractName,
          "get-liquid-token-balance",
          [Cl.principal(wallet2)],
          wallet2
        );
        
        // Note: Detailed balance validation will be added in next commit phase
        expect(balance.result).toBeTuple({
          balance: Cl.uint(stakeAmount),
          "last-claim-cycle": Cl.uint(0),
        });
      });

      it("should update validator pool stats on staking", () => {
        const stakeAmount = 5000000; // 5 STX
        
        // Stake STX
        simnet.callPublicFn(
          contractName,
          "stake-stx",
          [Cl.principal(wallet1), Cl.uint(stakeAmount)],
          wallet2
        );
        
        // Verify pool stats updated
        const updatedPool = simnet.callReadOnlyFn(
          contractName,
          "get-staking-pool",
          [Cl.principal(wallet1)],
          wallet1
        );
        
        expect(updatedPool.result).toBeSome(Cl.tuple({
          active: Cl.bool(true),
          "commission-rate": Cl.uint(1000),
          "last-reward-cycle": Cl.uint(0),
          "liquid-tokens-issued": Cl.uint(5000000),
          "total-delegated": Cl.uint(4950000), // After protocol fee
          "validator-rewards": Cl.uint(0),
        }));
        // Note: Detailed pool statistics validation will be added in next commit phase
      });
    });

    describe("Read-Only Functions", () => {
      it("should return protocol stats", () => {
        const { result } = simnet.callReadOnlyFn(
          contractName,
          "get-protocol-stats",
          [],
          wallet1
        );
        
        expect(result).toBeOk(Cl.tuple({
          "total-staked": Cl.uint(0),
          "total-liquid-tokens": Cl.uint(0),
          "exchange-rate": Cl.uint(1000000),
          "protocol-fees": Cl.uint(0),
          "current-cycle": Cl.uint(0),
        }));
        // Note: Detailed stats validation will be added in next commit phase
      });

      it("should calculate liquid tokens correctly", () => {
        const stxAmount = 1000000;
        
        const { result } = simnet.callReadOnlyFn(
          contractName,
          "calculate-liquid-tokens",
          [Cl.uint(stxAmount)],
          wallet1
        );
        
        // With 1:1 exchange rate initially, should return same amount
        expect(result).toBeUint(stxAmount);
      });

      it("should calculate STX value correctly", () => {
        const liquidTokens = 1000000;
        
        const { result } = simnet.callReadOnlyFn(
          contractName,
          "calculate-stx-value",
          [Cl.uint(liquidTokens)],
          wallet1
        );
        
        // With 1:1 exchange rate initially, should return same amount
        expect(result).toBeUint(liquidTokens);
      });

      it("should return empty user stake for non-staking user", () => {
        // Register validator but don't stake
        simnet.callPublicFn(
          contractName,
          "register-validator",
          [Cl.uint(1000)],
          wallet1
        );
        
        const { result } = simnet.callReadOnlyFn(
          contractName,
          "get-user-stake",
          [Cl.principal(wallet2), Cl.principal(wallet1)],
          wallet2
        );
        
        expect(result).toBeNone();
      });

      it("should return default liquid token balance for new user", () => {
        const { result } = simnet.callReadOnlyFn(
          contractName,
          "get-liquid-token-balance",
          [Cl.principal(wallet2)],
          wallet2
        );
        
        expect(result).toBeTuple({
          balance: Cl.uint(0),
          "last-claim-cycle": Cl.uint(0),
        });
        // Note: Detailed balance validation will be added in next commit phase
      });
    });

    describe("Administrative Functions", () => {
      it("should allow owner to update current cycle", () => {
        const newCycle = 100;
        
        const { result } = simnet.callPublicFn(
          contractName,
          "update-current-cycle",
          [Cl.uint(newCycle)],
          deployer
        );
        
        expect(result).toBeOk(Cl.bool(true));
        
        // Verify cycle was updated
        const stats = simnet.callReadOnlyFn(
          contractName,
          "get-protocol-stats",
          [],
          deployer
        );
        
        expect(stats.result).toBeOk(Cl.tuple({
          "total-staked": Cl.uint(0),
          "total-liquid-tokens": Cl.uint(0),
          "exchange-rate": Cl.uint(1000000),
          "protocol-fees": Cl.uint(0),
          "current-cycle": Cl.uint(100),
        }));
        // Note: Detailed cycle validation will be added in next commit phase
      });

      it("should reject non-owner cycle updates", () => {
        const newCycle = 100;
        
        const { result } = simnet.callPublicFn(
          contractName,
          "update-current-cycle",
          [Cl.uint(newCycle)],
          wallet1
        );
        
        expect(result).toBeErr(Cl.uint(100)); // err-owner-only
      });

      it("should allow owner to toggle contract pause", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "toggle-contract-pause",
          [],
          deployer
        );
        
        expect(result).toBeOk(Cl.bool(true));
      });

      it("should reject non-owner pause toggles", () => {
        const { result } = simnet.callPublicFn(
          contractName,
          "toggle-contract-pause",
          [],
          wallet1
        );
        
        expect(result).toBeErr(Cl.uint(100)); // err-owner-only
      });
    });
  });
});
