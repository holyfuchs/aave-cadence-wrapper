import "AaveWrapper"
import "FungibleToken"
import "FlowToken"

/// YieldVault pairs an AaveWrapper position with a debt-holding vault.
///
/// A `Strategy` is configured with two Cadence FungibleToken types: the
/// *collateral* type (what you deposit) and the *debt* type (what it borrows).
/// On `deposit`, the strategy supplies the incoming vault via the Aave
/// wrapper, flips the asset to collateral-mode, borrows `borrowAmount` of the
/// debt token, and stores the borrowed balance inside its own FT vault.
/// `rebalance` is public: anyone can poke the strategy and if its Aave health
/// factor has dropped below `MIN_HEALTH_FACTOR`, it repays
/// `REBALANCE_REPAY_FRACTION` of its debt holdings back into the Pool.
access(all) contract YieldVault {

    access(all) entitlement Manage

    /// Health-factor floor, Aave 1e18 precision. 1.5e18 = HF of 1.5.
    access(all) let MIN_HEALTH_FACTOR: UInt256
    /// Fraction of internally-held debt tokens to repay on a trigger.
    access(all) let REBALANCE_REPAY_FRACTION: UFix64

    access(all) event StrategyCreated(collateralType: String, debtType: String)
    access(all) event Deposited(collateralAmount: UFix64, debtAmount: UFix64)
    access(all) event Rebalanced(repaid: UFix64, healthFactorBefore: UInt256, healthFactorAfter: UInt256)

    access(all) let StrategyStoragePath: StoragePath
    access(all) let StrategyPublicPath: PublicPath

    access(all) resource interface StrategyPublic {
        access(all) view fun debtBalance(): UFix64
        access(all) view fun collateralType(): Type
        access(all) view fun debtType(): Type
        access(all) fun getAccountData(): AaveWrapper.AccountData
        /// Public — anyone can poke this to top the position up.
        access(all) fun rebalance(): Bool
    }

    access(all) resource Strategy: StrategyPublic {
        access(self) let position: @AaveWrapper.Position
        access(self) let debtHoldings: @{FungibleToken.Vault}
        access(self) let _collateralType: Type
        access(self) let _debtType: Type

        init(
            collateralType: Type,
            debtType: Type,
            emptyDebtVault: @{FungibleToken.Vault},
            feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        ) {
            pre {
                emptyDebtVault.getType() == debtType:
                    "empty vault type must match debtType"
                emptyDebtVault.balance == 0.0:
                    "empty vault must be empty"
            }
            self.position <- AaveWrapper.createMainnetPosition(feeProvider: feeProvider)
            self.debtHoldings <- emptyDebtVault
            self._collateralType = collateralType
            self._debtType = debtType
            emit StrategyCreated(
                collateralType: collateralType.identifier,
                debtType: debtType.identifier
            )
        }

        access(all) view fun collateralType(): Type { return self._collateralType }
        access(all) view fun debtType(): Type { return self._debtType }
        access(all) view fun debtBalance(): UFix64 { return self.debtHoldings.balance }

        access(all) fun getAccountData(): AaveWrapper.AccountData {
            return self.position.getUserAccountData()
        }

        /// Fund the underlying Position's COA with FLOW for EVM gas.
        access(Manage) fun fundGas(from: @{FungibleToken.Vault}) {
            self.position.depositFlow(from: <- from)
        }

        /// Deposit collateral → supply → borrow → hold debt internally.
        access(Manage) fun deposit(
            vault: @{FungibleToken.Vault},
            borrowAmount: UInt256
        ) {
            pre {
                vault.getType() == self._collateralType:
                    "deposit type does not match strategy collateralType"
            }
            let collateralAmount = vault.balance
            self.position.supply(vault: <- vault)
            self.position.setUseAsCollateral(
                vaultType: self._collateralType,
                useAsCollateral: true
            )
            let borrowed <- self.position.borrow(
                vaultType: self._debtType,
                amount: borrowAmount
            )
            let debtAmount = borrowed.balance
            self.debtHoldings.deposit(from: <- borrowed)
            emit Deposited(collateralAmount: collateralAmount, debtAmount: debtAmount)
        }

        /// Public keeper-style endpoint. If Aave's health factor has dropped
        /// below `YieldVault.MIN_HEALTH_FACTOR`, withdraw
        /// `YieldVault.REBALANCE_REPAY_FRACTION` of the internally-held debt
        /// and send it back to the Pool. Returns true iff it acted.
        access(all) fun rebalance(): Bool {
            let before = self.position.getUserAccountData()
            if before.healthFactor >= YieldVault.MIN_HEALTH_FACTOR {
                return false
            }
            if self.debtHoldings.balance == 0.0 {
                return false
            }

            let toRepay = self.debtHoldings.balance * YieldVault.REBALANCE_REPAY_FRACTION
            let payment <- self.debtHoldings.withdraw(amount: toRepay)
            let leftover <- self.position.repay(vault: <- payment)
            let dust = leftover.balance
            self.debtHoldings.deposit(from: <- leftover)

            let after = self.position.getUserAccountData()
            emit Rebalanced(
                repaid: toRepay - dust,
                healthFactorBefore: before.healthFactor,
                healthFactorAfter: after.healthFactor
            )
            return true
        }
    }

    access(all) fun createStrategy(
        collateralType: Type,
        debtType: Type,
        emptyDebtVault: @{FungibleToken.Vault},
        feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    ): @Strategy {
        return <- create Strategy(
            collateralType: collateralType,
            debtType: debtType,
            emptyDebtVault: <- emptyDebtVault,
            feeProvider: feeProvider
        )
    }

    init() {
        // 1.5 in Aave's 1e18 precision.
        self.MIN_HEALTH_FACTOR = 1_500_000_000_000_000_000
        self.REBALANCE_REPAY_FRACTION = 0.5
        self.StrategyStoragePath = /storage/YieldVaultStrategy
        self.StrategyPublicPath = /public/YieldVaultStrategy
    }
}
