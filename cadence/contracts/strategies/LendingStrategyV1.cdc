import "FungibleToken"
import "FlowYieldVaultsInterfaces"

// Blocks
import "MOREV1"
import "MOREOracleV1"
import "LimitedAccessV1"
import "UniswapV3SwapperV1"

/// Lending-based yield strategy. The contract is just *logic* — every
/// concrete block (token types, swap routes, oracle) is supplied by the
/// `Profile` resource, so one strategy contract can power many distinct
/// profiles (e.g. PYUSD/WFLOW/MOET, USDC/WBTC/sUSDC, …) without
/// re-deploying.
///
/// On `deposit`: supply collateral, flag as collateral, borrow up to
/// `minHealth` (sized via `MOREV1.Position.maxBorrowAtHealth`), swap debt
/// to yield. `withdraw` is the inverse: pro-rata yield→debt swap, repay,
/// pull collateral back out.
access(all) contract LendingStrategyV1 {

    access(all) entitlement Admin

    access(all) event ProfileCreated(profileUUID: UInt64)
    access(all) event VaultCreated(vaultUUID: UInt64, profileUUID: UInt64)

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

    /// Per-strategy-instance config. Holds:
    ///   * empty collateral / debt / yield vault markers (type identity)
    ///   * a multi-route swapper — routes are added post-create via
    ///     `addSwapRoute` so the Profile creator can register exactly the
    ///     directions the strategy needs (debt→yield, yield→debt, …)
    ///   * a price oracle handle
    ///   * the `minHealth` / `maxHealth` band
    ///   * a `@LimitedAccessV1.Manager` for per-address gating
    access(all) resource Profile: FlowYieldVaultsInterfaces.Profile {
        access(all) let collateralToken: @{FungibleToken.Vault}
        access(all) let debtToken: @{FungibleToken.Vault}
        access(all) let yieldToken: @{FungibleToken.Vault}

        access(all) var swapper: UniswapV3SwapperV1.Swapper
        access(all) let priceOracle: MOREOracleV1.PriceOracle
        access(all) let minHealth: UFix64
        access(all) let maxHealth: UFix64
        access(all) let accessManager: @LimitedAccessV1.Manager

        init(
            collateralToken: @{FungibleToken.Vault},
            debtToken: @{FungibleToken.Vault},
            yieldToken: @{FungibleToken.Vault},
            minHealth: UFix64,
            maxHealth: UFix64
        ) {
            pre {
                collateralToken.balance == 0.0: "collateral marker must be empty"
                debtToken.balance == 0.0: "debt marker must be empty"
                yieldToken.balance == 0.0: "yield marker must be empty"
                minHealth > 1.0: "minHealth must be > 1.0"
                maxHealth >= minHealth: "maxHealth must be >= minHealth"
            }
            self.collateralToken <- collateralToken
            self.debtToken <- debtToken
            self.yieldToken <- yieldToken
            self.swapper = UniswapV3SwapperV1.createSwapper()
            self.priceOracle = MOREOracleV1.createPriceOracle()
            self.minHealth = minHealth
            self.maxHealth = maxHealth
            self.accessManager <- LimitedAccessV1.createManager()
        }

        access(all) view fun collateralType(): Type {
            return self.collateralToken.getType()
        }
        access(all) view fun debtType(): Type {
            return self.debtToken.getType()
        }
        access(all) view fun yieldType(): Type {
            return self.yieldToken.getType()
        }

        access(all) view fun info(): {String: String} {
            return {
                "description": "lending strategy",
                "collateral": self.collateralType().identifier,
                "debt": self.debtType().identifier,
                "yield": self.yieldType().identifier,
                "protocol": "MOREV1"
            }
        }

        /// Issue (or replace) an access pass for `addr` via this Profile's
        /// Manager. Admin-gated. Inbox name to claim from is exposed via
        /// `inboxName(addr:)`.
        access(Admin) fun issueAccessPass(addr: Address, allowance: UInt64) {
            let mgr = &self.accessManager
                as auth(LimitedAccessV1.Admin) &LimitedAccessV1.Manager
            mgr.issue(addr: addr, allowance: allowance)
        }

        /// Inbox key under which `addr`'s pass capability is published.
        access(all) view fun inboxName(addr: Address): String {
            return self.accessManager.inboxName(addr: addr)
        }

        /// Register a swap route on this Profile's swapper. Admin-gated —
        /// the Profile creator wires up every direction the strategy needs
        /// (typically `debtType→yieldType` and `yieldType→debtType`, plus
        /// `collateralType→debtType` if collateral can be unwound).
        access(Admin) fun addSwapRoute(_ route: UniswapV3SwapperV1.Route) {
            self.swapper.addRoute(route)
        }

        /// Mint a Vault. Access-pass gating is currently a TODO no-op
        /// while the sender-identity story is being designed; the Manager
        /// is already wired in so we can flip it on without a Profile change.
        access(all) fun createVault(
            pass: Capability<&LimitedAccessV1.LimitedAccessPass>,
            profileCap: Capability<&Profile>
        ): @Vault {
            let passRef = pass.borrow() ?? panic("invalid access-pass capability")
            passRef.consume()
            let vault <- create Vault(
                profileCap: profileCap,
                profileUUID: self.uuid,
                yieldTokens: <- self.yieldToken.createEmptyVault()
            )
            emit VaultCreated(vaultUUID: vault.uuid, profileUUID: self.uuid)
            return <- vault
        }
    }

    /// User-held position resource. Holds a `Capability<&Profile>` so it
    /// can self-resolve its profile (lives on the registry contract
    /// account); methods don't take profile args.
    access(all) resource Vault {
        access(self) let position: @MOREV1.Position
        access(self) let yieldTokens: @{FungibleToken.Vault}
        access(all) let profileUUID: UInt64
        access(all) let profileCap: Capability<&Profile>

        init(
            profileCap: Capability<&Profile>,
            profileUUID: UInt64,
            yieldTokens: @{FungibleToken.Vault}
        ) {
            pre {
                profileCap.check(): "profileCap doesn't resolve"
                profileCap.borrow()!.uuid == profileUUID: "profileCap UUID mismatch"
            }
            self.profileCap = profileCap
            self.profileUUID = profileUUID
            self.position <- MOREV1.createMainnetPosition()
            self.yieldTokens <- yieldTokens
        }

        /// Borrow the live profile reference. Panics if the profile was
        /// removed/relocated.
        access(self) view fun profile(): &Profile {
            let ref = self.profileCap.borrow()
                ?? panic("profileCap no longer resolves")
            assert(ref.uuid == self.profileUUID, message: "profile UUID changed")
            return ref
        }

        /// USD-denominated collateral & debt; yield in its own token's
        /// natural units.
        access(all) fun positionSummary(): PositionSummary {
            let data = self.position.getUserAccountData()
            return PositionSummary(
                collateral: MOREV1.base8ToUFix64(data.totalCollateralBase),
                debt: MOREV1.base8ToUFix64(data.totalDebtBase),
                yield: self.yieldTokens.balance
            )
        }

        /// Supply collateral → flag as collateral → borrow up to
        /// `profile.minHealth` → swap debt to yield.
        access(all) fun deposit(from collateral: @{FungibleToken.Vault}) {
            let profile = self.profile()
            assert(
                collateral.getType() == profile.collateralType(),
                message: "Invalid collateral type"
            )
            self.position.deposit(from: <- collateral)
            self.position.setUseAsCollateral(
                vaultType: profile.collateralType(),
                useAsCollateral: true
            )

            let debtPriceUsd = profile.priceOracle.price(ofToken: profile.debtType())
                ?? panic("no debt-token price")
            let borrowAmount = self.position.maxBorrowAtHealth(
                vaultType: profile.debtType(),
                targetHealth: profile.minHealth,
                debtPriceUsd: debtPriceUsd
            )
            if borrowAmount == 0 {
                return
            }
            let debt <- self.position.borrow(
                vaultType: profile.debtType(),
                amount: borrowAmount
            )
            let yield <- profile.swapper.swap(
                quote: nil,
                inVault: <- debt,
                outType: profile.yieldType()
            )
            self.yieldTokens.deposit(from: <- yield)
        }

        /// Pro-rata unwind: swap `fraction = withdrawUsd / totalCollUsd`
        /// of yield → debt, repay, then withdraw `amount` collateral.
        access(FungibleToken.Withdraw) fun withdraw(
            amount: UFix64
        ): @{FungibleToken.Vault} {
            pre { amount > 0.0: "withdraw amount must be > 0" }
            let profile = self.profile()
            let data = self.position.getUserAccountData()
            let totalCollateralUsd = MOREV1.base8ToUFix64(data.totalCollateralBase)
            assert(totalCollateralUsd > 0.0, message: "no collateral to withdraw")

            let priceCollateral = profile.priceOracle.price(ofToken: profile.collateralType())
                ?? panic("no collateral price")
            let withdrawUsd = amount * priceCollateral
            let fraction = withdrawUsd / totalCollateralUsd
            let totalDebtUsd = MOREV1.base8ToUFix64(data.totalDebtBase)

            if totalDebtUsd > 0.0 && self.yieldTokens.balance > 0.0 {
                let yieldToSwap = self.yieldTokens.balance * fraction
                let yieldOut <- self.yieldTokens.withdraw(amount: yieldToSwap)
                let debt <- profile.swapper.swap(
                    quote: nil,
                    inVault: <- yieldOut,
                    outType: profile.debtType()
                )
                let leftover <- self.position.repay(vault: <- debt)
                if leftover.balance > 0.0 {
                    let back <- profile.swapper.swap(
                        quote: nil,
                        inVault: <- leftover,
                        outType: profile.yieldType()
                    )
                    self.yieldTokens.deposit(from: <- back)
                } else {
                    destroy leftover
                }
            }

            // UFix64 collateral amount → raw UInt256 in collateral-token's
            // native decimals, then withdraw via MOREV1.
            let collateralAsset = MOREV1.assetFor(profile.collateralType())
            let decimals = self.position.erc20Decimals(token: collateralAsset)
            let scale = MOREV1.tenToThe(decimals)
            let rawAmount = UInt256(UInt64(amount * 100_000_000.0)) * scale / 100_000_000

            return <- self.position.withdraw(
                vaultType: profile.collateralType(),
                amount: rawAmount
            )
        }

        access(all) fun rebalance() {
            let _ = self.profile()
            // TODO: repay/borrow back toward profile.minHealth..maxHealth band.
        }
    }

    access(all) fun createProfile(
        collateralToken: @{FungibleToken.Vault},
        debtToken: @{FungibleToken.Vault},
        yieldToken: @{FungibleToken.Vault},
        minHealth: UFix64,
        maxHealth: UFix64
    ): @Profile {
        let profile <- create Profile(
            collateralToken: <- collateralToken,
            debtToken: <- debtToken,
            yieldToken: <- yieldToken,
            minHealth: minHealth,
            maxHealth: maxHealth
        )
        emit ProfileCreated(profileUUID: profile.uuid)
        return <- profile
    }
}
