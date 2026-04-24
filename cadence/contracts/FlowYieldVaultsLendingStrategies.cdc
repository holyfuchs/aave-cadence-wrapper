import "FungibleToken"
import "EVM"
import "FlowEVMBridge"
import "DeFiActions"
import "DeFiActionsUtils"
import "AaveV3Pool"
import "AaveV3PriceOracle"
import "FlowYieldVaultsInterfaces"

/// Factory for `LendingStrategy` instances and their `LendingStrategyVault`
/// yield vaults.
///
/// On deposit the vault:
///   1. Supplies the incoming collateral vault to its Aave position.
///   2. Enables it as collateral.
///   3. Borrows 50% of `availableBorrowsBase` worth of debt tokens (sized
///      via the AaveOracle price of the debt token).
///   4. Swaps the borrowed debt through `debtYieldSwapper` into yield tokens.
///   5. Stores the yield tokens in the vault's internal FT vault.
access(all) contract FlowYieldVaultsLendingStrategies {

    access(all) event LendingStrategyCreated()
    access(all) event LendingStrategyVaultCreated()

    /// Fraction of `availableBorrowsBase` the strategy borrows on each
    /// deposit (expressed as UFix64, 0.5 = 50%). Leaves headroom so a price
    /// tick doesn't immediately push the position under liquidation.
    access(all) let BORROW_UTILIZATION: UFix64

    access(all) struct PositionSummary {
        access(all) let collateral: UFix64
        access(all) let debt: UFix64
        access(all) let yield: UFix64

        view init(collateral: UFix64, debt: UFix64, yield: UFix64) {
            self.collateral = collateral
            self.debt = debt
            self.yield = yield
        }
    }

    access(all) struct LendingStrategy: FlowYieldVaultsInterfaces.Strategy {
        access(all) let collateralTokenType: Type
        access(all) let debtTokenType: Type
        access(all) let yieldTokenType: Type
        access(all) let collateralDebtSwapper: {DeFiActions.Swapper}
        access(all) let debtYieldSwapper: {DeFiActions.Swapper}
        access(all) let minHealth: UFix64
        access(all) let maxHealth: UFix64

        init(
            collateralDebtSwapper: {DeFiActions.Swapper},
            debtYieldSwapper: {DeFiActions.Swapper},
            yieldTokenType: Type,
            debtTokenType: Type,
            collateralTokenType: Type,
            minHealth: UFix64,
            maxHealth: UFix64
        ) {
            self.collateralDebtSwapper = collateralDebtSwapper
            self.debtYieldSwapper = debtYieldSwapper
            self.yieldTokenType = yieldTokenType
            self.debtTokenType = debtTokenType
            self.collateralTokenType = collateralTokenType
            self.minHealth = minHealth
            self.maxHealth = maxHealth
        }

        access(all) fun createYieldVault(name _: String): @{FlowYieldVaultsInterfaces.YieldVault} {
            let vault <- create LendingStrategyVault(strategy: self)
            emit LendingStrategyVaultCreated()
            return <- vault
        }

        access(all) view fun info(): {String: String} {
            return {
                "description": "lending strategy",
                "collateral": self.collateralTokenType.identifier,
                "debt": self.debtTokenType.identifier,
                "yield": self.yieldTokenType.identifier,
                "protocol": "AaveV3Pool"
            }
        }
    }

    access(all) resource LendingStrategyVault: FlowYieldVaultsInterfaces.YieldVault {
        access(self) let strategy: LendingStrategy
        access(self) let position: @AaveV3Pool.Position
        access(self) let yieldTokens: @{FungibleToken.Vault}

        access(all) view fun collateralType(): Type { return self.strategy.collateralTokenType }
        access(all) view fun debtType(): Type { return self.strategy.debtTokenType }
        access(all) view fun yieldType(): Type { return self.strategy.yieldTokenType }

        /// USD-denominated summary (8-decimal → UFix64). `yield` is in the
        /// yield token's natural units.
        access(all) fun positionSummary(): PositionSummary {
            let data = self.position.getUserAccountData()
            return PositionSummary(
                collateral: FlowYieldVaultsLendingStrategies.base8ToUFix64(data.totalCollateralBase),
                debt: FlowYieldVaultsLendingStrategies.base8ToUFix64(data.totalDebtBase),
                yield: self.yieldTokens.balance
            )
        }

        /// Supply collateral → flip to collateral mode → borrow debt →
        /// swap debt to yield → store yield.
        access(all) fun deposit(from collateral: @{FungibleToken.Vault}) {
            pre {
                collateral.getType() == self.strategy.collateralTokenType:
                    "Invalid collateral type"
            }
            self.position.deposit(from: <- collateral)
            self.position.setUseAsCollateral(
                vaultType: self.strategy.collateralTokenType,
                useAsCollateral: true
            )

            let borrowAmount = self.computeBorrowAmount()
            if borrowAmount == 0 {
                return
            }

            let debt <- self.position.borrow(
                vaultType: self.strategy.debtTokenType,
                amount: borrowAmount
            )
            let yield <- self.swapDebtToYield(debt: <- debt)
            self.yieldTokens.deposit(from: <- yield)
        }

        /// Withdraw `amount` collateral (in the collateral token's natural
        /// units). Pro-rata unwinds the position: swaps yield → debt via the
        /// `debtYieldSwapper`, repays the proportional slice of debt, then
        /// withdraws the collateral slice from Aave and bridges it back.
        ///
        /// If the yield side doesn't have enough to cover the required
        /// repayment the call panics — the caller should size withdraws
        /// against `positionSummary()`.
        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            let data = self.position.getUserAccountData()
            let totalCollateralUsd = FlowYieldVaultsLendingStrategies.base8ToUFix64(data.totalCollateralBase)
            if totalCollateralUsd == 0.0 || amount == 0.0 {
                // Nothing to unwind — return an empty vault.
                return <- DeFiActionsUtils.getEmptyVault(self.strategy.collateralTokenType)
            }

            let coa = self.position.borrowCOA()
            let priceCollateral = AaveV3PriceOracle.getPrice(
                coa: coa, ofToken: self.strategy.collateralTokenType
            ) ?? panic("no collateral price")
            let priceDebt = AaveV3PriceOracle.getPrice(
                coa: coa, ofToken: self.strategy.debtTokenType
            ) ?? panic("no debt price")

            // Fraction of total collateral being unwound (USD-denominated).
            let withdrawUsd = amount * priceCollateral
            let fraction = withdrawUsd / totalCollateralUsd
            let totalDebtUsd = FlowYieldVaultsLendingStrategies.base8ToUFix64(data.totalDebtBase)
            let debtToRepayUsd = totalDebtUsd * fraction
            let debtToRepayTokens = priceDebt > 0.0 ? (debtToRepayUsd / priceDebt) : 0.0

            // Pay down debt if any.
            if debtToRepayTokens > 0.0 && self.yieldTokens.balance > 0.0 {
                let quote = self.quoteYieldToDebt(desiredDebt: debtToRepayTokens)
                let yieldNeeded = quote.inAmount
                assert(
                    yieldNeeded <= self.yieldTokens.balance,
                    message: "insufficient yield to cover debt (need \(yieldNeeded), have \(self.yieldTokens.balance))"
                )
                let yieldOut <- self.yieldTokens.withdraw(amount: yieldNeeded)
                let debt <- self.yieldToDebt(yield: <- yieldOut, quote: quote)
                let leftover <- self.position.repay(vault: <- debt)
                if leftover.balance > 0.0 {
                    let back <- self.debtToYield(debt: <- leftover)
                    self.yieldTokens.deposit(from: <- back)
                } else {
                    destroy leftover
                }
            }

            // Withdraw `amount` collateral. Convert UFix64 → raw UInt256.
            let collateralAsset = FlowEVMBridge.getAssociatedEVMAddress(with: self.strategy.collateralTokenType)
                ?? panic("collateral not bridged")
            let decimals = self.position.erc20Decimals(token: collateralAsset)
            let scale = FlowYieldVaultsLendingStrategies.tenToThe(decimals)
            // rawAmount = (amount * 10^8) * 10^decimals / 10^8
            let rawAmount = UInt256(UInt64(amount * 100_000_000.0)) * scale / 100_000_000
            return <- self.position.withdraw(
                vaultType: self.strategy.collateralTokenType,
                amount: rawAmount
            )
        }

        /// Swap `debt` into yield tokens (chooses `swap` / `swapBack` by the
        /// `debtYieldSwapper`'s `inType()`).
        access(self) fun debtToYield(debt: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            if self.strategy.debtYieldSwapper.inType() == self.strategy.debtTokenType {
                return <- self.strategy.debtYieldSwapper.swap(quote: nil, inVault: <- debt)
            }
            return <- self.strategy.debtYieldSwapper.swapBack(quote: nil, residual: <- debt)
        }

        /// Swap `yield` tokens into debt tokens (optionally with a quote for
        /// exact output).
        access(self) fun yieldToDebt(
            yield: @{FungibleToken.Vault},
            quote: {DeFiActions.Quote}?
        ): @{FungibleToken.Vault} {
            if self.strategy.debtYieldSwapper.inType() == self.strategy.debtTokenType {
                return <- self.strategy.debtYieldSwapper.swapBack(quote: quote, residual: <- yield)
            }
            return <- self.strategy.debtYieldSwapper.swap(quote: quote, inVault: <- yield)
        }

        /// Quote `desiredDebt` tokens out from the yield side.
        access(self) fun quoteYieldToDebt(desiredDebt: UFix64): {DeFiActions.Quote} {
            // With the swapper oriented debt→yield: quoteIn(forDesired: X, reverse: true)
            // returns the inAmount of yield needed for X debt out.
            if self.strategy.debtYieldSwapper.inType() == self.strategy.debtTokenType {
                return self.strategy.debtYieldSwapper.quoteIn(forDesired: desiredDebt, reverse: true)
            }
            // Swapper is yield→debt natively: quoteIn(forDesired: X, reverse: false).
            return self.strategy.debtYieldSwapper.quoteIn(forDesired: desiredDebt, reverse: false)
        }

        access(all) fun rebalance() {
            // TODO: repay debt if HF < minHealth, borrow more if HF > maxHealth.
        }

        view access(all) fun isAvailableToWithdraw(amount _: UFix64): Bool {
            return false
        }

        view access(all) fun getSupportedVaultTypes(): {Type: Bool} {
            return { self.strategy.collateralTokenType: true }
        }

        view access(all) fun isSupportedVaultType(type: Type): Bool {
            return type == self.strategy.collateralTokenType
        }

        /// Max additional debt that can be borrowed while keeping Aave's
        /// health factor at `strategy.minHealth`. Delegates the arithmetic
        /// to `AaveV3Pool.Position.maxBorrowAtHealth` and just supplies the
        /// oracle price.
        access(self) fun computeBorrowAmount(): UInt256 {
            let price = AaveV3PriceOracle.getPrice(
                coa: self.position.borrowCOA(),
                ofToken: self.strategy.debtTokenType
            ) ?? panic("no debt-token price from AaveV3PriceOracle")
            return self.position.maxBorrowAtHealth(
                vaultType: self.strategy.debtTokenType,
                targetHealth: self.strategy.minHealth,
                debtPriceUsd: price
            )
        }

        /// Run `debt` through `debtYieldSwapper`, picking `swap` vs
        /// `swapBack` based on which side the debt type is on.
        access(self) fun swapDebtToYield(debt: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            if self.strategy.debtYieldSwapper.inType() == self.strategy.debtTokenType {
                return <- self.strategy.debtYieldSwapper.swap(quote: nil, inVault: <- debt)
            }
            return <- self.strategy.debtYieldSwapper.swapBack(quote: nil, residual: <- debt)
        }

        init(strategy: LendingStrategy) {
            self.strategy = strategy
            self.position <- AaveV3Pool.createMainnetPosition()
            self.yieldTokens <- DeFiActionsUtils.getEmptyVault(strategy.yieldTokenType)
        }
    }

    access(all) view fun base8ToUFix64(_ raw: UInt256): UFix64 {
        if raw == 0 { return 0.0 }
        let capped: UInt256 = raw > UInt256(UInt64.max) ? UInt256(UInt64.max) : raw
        return UFix64(UInt64(capped)) / 100_000_000.0
    }

    access(all) view fun tenToThe(_ exp: UInt8): UInt256 {
        var result: UInt256 = 1
        var i: UInt8 = 0
        while i < exp {
            result = result * 10
            i = i + 1
        }
        return result
    }

    access(all) fun createLendingStrategy(
        collateralDebtSwapper: {DeFiActions.Swapper},
        debtYieldSwapper: {DeFiActions.Swapper},
        yieldTokenType: Type,
        debtTokenType: Type,
        collateralTokenType: Type,
        minHealth: UFix64,
        maxHealth: UFix64
    ): LendingStrategy {
        let strategy = LendingStrategy(
            collateralDebtSwapper: collateralDebtSwapper,
            debtYieldSwapper: debtYieldSwapper,
            yieldTokenType: yieldTokenType,
            debtTokenType: debtTokenType,
            collateralTokenType: collateralTokenType,
            minHealth: minHealth,
            maxHealth: maxHealth
        )
        emit LendingStrategyCreated()
        return strategy
    }

    init() {
        self.BORROW_UTILIZATION = 0.5
    }
}
