import "EVM"
import "FungibleToken"
import "FlowToken"
import "FlowEVMBridge"

/// Wrapper over the MORE Markets lending pool on FlowEVM.
///
/// A `Position` owns a COA (its EVM address = the Aave user). The contract
/// account's FlowToken vault at `/storage/flowTokenVault` pays Cadence-side
/// bridge fees — keep it funded.
///
/// Cadence-shape API (`deposit / borrow / withdraw / repay` with FT vaults
/// and `Type`) sits next to a raw-EVM path (`supplyEVM / borrowEVM / …`)
/// that takes `EVMAddress + UInt256` for flows that don't round-trip the
/// bridge (native-FLOW→WFLOW, DEX swaps, etc.).
access(all) contract MOREV1 {

    access(all) entitlement Manage

    access(all) let VARIABLE_RATE: UInt256
    access(all) let MAX_UINT256: UInt256
    access(all) let POOL_MAINNET: EVM.EVMAddress

    access(all) event PositionCreated(evmAddress: String)
    access(all) event Supplied(asset: String, amount: UInt256)
    access(all) event Withdrawn(asset: String, amount: UInt256)
    access(all) event Borrowed(asset: String, amount: UInt256)
    access(all) event Repaid(asset: String, amount: UInt256)

    access(all) let PositionStoragePath: StoragePath
    access(all) let PositionPublicPath: PublicPath

    access(all) resource interface PositionPublic {
        access(all) view fun evmAddress(): EVM.EVMAddress
        access(all) fun getUserAccountData(): AccountData
        access(all) fun erc20BalanceOf(token: EVM.EVMAddress): UInt256
    }

    access(all) struct AccountData {
        access(all) let totalCollateralBase: UInt256
        access(all) let totalDebtBase: UInt256
        access(all) let availableBorrowsBase: UInt256
        access(all) let currentLiquidationThreshold: UInt256
        access(all) let ltv: UInt256
        access(all) let healthFactor: UInt256

        init(
            totalCollateralBase: UInt256,
            totalDebtBase: UInt256,
            availableBorrowsBase: UInt256,
            currentLiquidationThreshold: UInt256,
            ltv: UInt256,
            healthFactor: UInt256
        ) {
            self.totalCollateralBase = totalCollateralBase
            self.totalDebtBase = totalDebtBase
            self.availableBorrowsBase = availableBorrowsBase
            self.currentLiquidationThreshold = currentLiquidationThreshold
            self.ltv = ltv
            self.healthFactor = healthFactor
        }
    }

    access(all) resource Position: PositionPublic {
        access(self) let coa: @EVM.CadenceOwnedAccount
        access(all) let pool: EVM.EVMAddress

        init(pool: EVM.EVMAddress) {
            self.coa <- EVM.createCadenceOwnedAccount()
            self.pool = pool
            emit PositionCreated(evmAddress: self.coa.address().toString())
        }

        access(all) view fun evmAddress(): EVM.EVMAddress {
            return self.coa.address()
        }

        /// Owner-only handle on the COA (arbitrary EVM calls, native-token
        /// wraps, DEX swaps).
        access(Manage) fun borrowCOA(): auth(EVM.Owner, EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount {
            return &self.coa as auth(EVM.Owner, EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount
        }

        access(Manage) fun depositFlow(from: @{FungibleToken.Vault}) {
            self.coa.deposit(from: <- (from as! @FlowToken.Vault))
        }

        access(all) fun erc20Decimals(token: EVM.EVMAddress): UInt8 {
            let result = self.coa.call(
                to: token,
                data: EVM.encodeABIWithSignature("decimals()", []),
                gasLimit: 50_000,
                value: EVM.Balance(attoflow: 0)
            )
            assert(result.status == EVM.Status.successful, message: "decimals() failed")
            let decoded = EVM.decodeABI(types: [Type<UInt8>()], data: result.data)
            return decoded[0] as! UInt8
        }

        access(all) fun erc20BalanceOf(token: EVM.EVMAddress): UInt256 {
            let result = self.coa.call(
                to: token,
                data: EVM.encodeABIWithSignature("balanceOf(address)", [self.coa.address()]),
                gasLimit: 100_000,
                value: EVM.Balance(attoflow: 0)
            )
            assert(result.status == EVM.Status.successful, message: "balanceOf failed")
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: result.data)
            return decoded[0] as! UInt256
        }

        access(all) fun getUserAccountData(): AccountData {
            let result = self.coa.call(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "getUserAccountData(address)",
                    [self.coa.address()]
                ),
                gasLimit: 200_000,
                value: EVM.Balance(attoflow: 0)
            )
            assert(result.status == EVM.Status.successful, message: "getUserAccountData failed")
            let types = [
                Type<UInt256>(), Type<UInt256>(), Type<UInt256>(),
                Type<UInt256>(), Type<UInt256>(), Type<UInt256>()
            ]
            let decoded = EVM.decodeABI(types: types, data: result.data)
            return AccountData(
                totalCollateralBase: decoded[0] as! UInt256,
                totalDebtBase: decoded[1] as! UInt256,
                availableBorrowsBase: decoded[2] as! UInt256,
                currentLiquidationThreshold: decoded[3] as! UInt256,
                ltv: decoded[4] as! UInt256,
                healthFactor: decoded[5] as! UInt256
            )
        }

        // --- Vault-shaped Aave operations ---

        access(Manage) fun deposit(from: @{FungibleToken.Vault}) {
            let vaultType = from.getType()
            let asset = MOREV1.assetFor(vaultType)
            let before = self.erc20BalanceOf(token: asset)
            self.coa.depositTokens(vault: <- from, feeProvider: MOREV1.fees())
            let amount = self.erc20BalanceOf(token: asset) - before
            self.supplyEVM(asset: asset, amount: amount)
        }

        access(Manage) fun borrow(vaultType: Type, amount: UInt256): @{FungibleToken.Vault} {
            self.borrowEVM(asset: MOREV1.assetFor(vaultType), amount: amount)
            return <- self.coa.withdrawTokens(
                type: vaultType,
                amount: amount,
                feeProvider: MOREV1.fees()
            )
        }

        access(Manage) fun withdraw(vaultType: Type, amount: UInt256): @{FungibleToken.Vault} {
            let asset = MOREV1.assetFor(vaultType)
            let before = self.erc20BalanceOf(token: asset)
            self.withdrawEVM(asset: asset, amount: amount)
            let received = self.erc20BalanceOf(token: asset) - before
            return <- self.coa.withdrawTokens(
                type: vaultType,
                amount: received,
                feeProvider: MOREV1.fees()
            )
        }

        access(Manage) fun repay(vault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            let vaultType = vault.getType()
            let asset = MOREV1.assetFor(vaultType)
            let empty <- vault.createEmptyVault()
            let before = self.erc20BalanceOf(token: asset)
            self.coa.depositTokens(vault: <- vault, feeProvider: MOREV1.fees())
            let bridgedIn = self.erc20BalanceOf(token: asset) - before
            self.repayEVM(asset: asset, amount: bridgedIn)
            let leftover = self.erc20BalanceOf(token: asset) - before
            if leftover == 0 {
                return <- empty
            }
            destroy empty
            return <- self.coa.withdrawTokens(
                type: vaultType,
                amount: leftover,
                feeProvider: MOREV1.fees()
            )
        }

        access(Manage) fun setUseAsCollateral(vaultType: Type, useAsCollateral: Bool) {
            self.setUseAsCollateralEVM(
                asset: MOREV1.assetFor(vaultType),
                useAsCollateral: useAsCollateral
            )
        }

        /// Additional borrow amount (raw UInt256 in debt-token native
        /// decimals) that, when drawn against the current position, leaves
        /// the health factor at `targetHealth` exactly.
        ///
        /// Aave's HF is `(totalCollateralBase × liquidationThreshold_bps /
        /// 10000) / totalDebtBase`. Setting that to `targetHealth` and
        /// solving for `totalDebtBase` gives the maximum total debt in base
        /// currency; the additional borrow is the difference against the
        /// current debt. Zero if the position is already at or above
        /// `targetHealth`'s leverage.
        ///
        /// `debtPriceUsd` is the debt token's USD price (8-decimal UFix64) —
        /// the caller supplies it (typically from `AaveV3PriceOracle`) so
        /// this wrapper stays oracle-agnostic.
        access(all) fun maxBorrowAtHealth(
            vaultType: Type,
            targetHealth: UFix64,
            debtPriceUsd: UFix64
        ): UInt256 {
            pre {
                targetHealth > 0.0: "targetHealth must be > 0"
                debtPriceUsd > 0.0: "debtPriceUsd must be > 0"
            }
            let data = self.getUserAccountData()
            // Work in Aave's native 8-decimal UInt256 to avoid UFix64 overflow
            // when positions are multi-thousand-token-sized.
            let collBase = data.totalCollateralBase             // USD 8-dec
            let debtBase = data.totalDebtBase                   // USD 8-dec
            let ltBps = data.currentLiquidationThreshold        // 0..10000
            let targetHf8 = UInt256(UInt64(targetHealth * 100_000_000.0))
            // maxDebt_USD_8 = collBase × ltBps × 1e8 / (10000 × targetHf8)
            //              = collBase × ltBps / 10000 / (targetHf8 / 1e8)
            let maxDebtBase = collBase * ltBps * 100_000_000 / 10000 / targetHf8
            if maxDebtBase <= debtBase {
                return 0
            }
            let additionalDebtBase = maxDebtBase - debtBase

            // Convert USD 8-dec → debt-token raw units:
            //   debtTokens_raw = additionalDebtBase × 10^decimals / priceUsd_8
            let priceUsd8 = UInt256(UInt64(debtPriceUsd * 100_000_000.0))
            if priceUsd8 == 0 { return 0 }
            let asset = MOREV1.assetFor(vaultType)
            let decimals = self.erc20Decimals(token: asset)
            let scale = MOREV1.tenToThe(decimals)
            return additionalDebtBase * scale / priceUsd8
        }

        // --- Raw-EVM operations ---

        access(Manage) fun supplyEVM(asset: EVM.EVMAddress, amount: UInt256) {
            self.mustCall(
                to: asset,
                data: EVM.encodeABIWithSignature("approve(address,uint256)", [self.pool, amount]),
                gasLimit: 100_000
            )
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "supply(address,uint256,address,uint16)",
                    [asset, amount, self.coa.address(), 0 as UInt16]
                ),
                gasLimit: 500_000
            )
            emit Supplied(asset: asset.toString(), amount: amount)
        }

        access(Manage) fun borrowEVM(asset: EVM.EVMAddress, amount: UInt256) {
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "borrow(address,uint256,uint256,uint16,address)",
                    [asset, amount, MOREV1.VARIABLE_RATE, 0 as UInt16, self.coa.address()]
                ),
                gasLimit: 600_000
            )
            emit Borrowed(asset: asset.toString(), amount: amount)
        }

        access(Manage) fun repayEVM(asset: EVM.EVMAddress, amount: UInt256) {
            self.mustCall(
                to: asset,
                data: EVM.encodeABIWithSignature("approve(address,uint256)", [self.pool, amount]),
                gasLimit: 100_000
            )
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "repay(address,uint256,uint256,address)",
                    [asset, amount, MOREV1.VARIABLE_RATE, self.coa.address()]
                ),
                gasLimit: 500_000
            )
            emit Repaid(asset: asset.toString(), amount: amount)
        }

        access(Manage) fun withdrawEVM(asset: EVM.EVMAddress, amount: UInt256) {
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "withdraw(address,uint256,address)",
                    [asset, amount, self.coa.address()]
                ),
                gasLimit: 500_000
            )
            emit Withdrawn(asset: asset.toString(), amount: amount)
        }

        access(Manage) fun setUseAsCollateralEVM(asset: EVM.EVMAddress, useAsCollateral: Bool) {
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "setUserUseReserveAsCollateral(address,bool)",
                    [asset, useAsCollateral]
                ),
                gasLimit: 200_000
            )
        }

        access(Manage) fun setUserEMode(categoryId: UInt8) {
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature("setUserEMode(uint8)", [categoryId]),
                gasLimit: 200_000
            )
        }

        access(Manage) fun liquidationCall(
            collateralAsset: EVM.EVMAddress,
            debtAsset: EVM.EVMAddress,
            user: EVM.EVMAddress,
            debtToCover: UInt256,
            receiveAToken: Bool
        ) {
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "liquidationCall(address,address,address,uint256,bool)",
                    [collateralAsset, debtAsset, user, debtToCover, receiveAToken]
                ),
                gasLimit: 800_000
            )
        }

        access(Manage) fun callEVM(
            to: EVM.EVMAddress,
            data: [UInt8],
            gasLimit: UInt64,
            value: UInt
        ): EVM.Result {
            return self.coa.call(
                to: to,
                data: data,
                gasLimit: gasLimit,
                value: EVM.Balance(attoflow: value)
            )
        }

        access(self) fun mustCall(to: EVM.EVMAddress, data: [UInt8], gasLimit: UInt64) {
            let result = self.coa.call(
                to: to,
                data: data,
                gasLimit: gasLimit,
                value: EVM.Balance(attoflow: 0)
            )
            assert(
                result.status == EVM.Status.successful,
                message: "EVM call reverted: \(result.errorMessage)"
            )
        }
    }

    access(all) fun createPosition(pool: EVM.EVMAddress): @Position {
        return <- create Position(pool: pool)
    }

    access(all) fun createMainnetPosition(): @Position {
        return <- create Position(pool: self.POOL_MAINNET)
    }

    // --- contract-level helpers ---

    access(all) view fun assetFor(_ vaultType: Type): EVM.EVMAddress {
        return FlowEVMBridge.getAssociatedEVMAddress(with: vaultType)
            ?? panic("No EVM mapping for vault type \(vaultType.identifier)")
    }

    /// Convert an Aave 8-decimal `UInt256` (USD base-currency value) into
    /// UFix64. Caps to UInt64.max to avoid UFix64 overflow at silly sizes.
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

    access(all) fun fees(): auth(FungibleToken.Withdraw) &FlowToken.Vault {
        return self.account.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("MOREV1 contract account has no FlowToken vault to pay bridge fees")
    }

    /// Top up the contract-account FlowToken vault used to pay bridge fees.
    access(all) fun fundFees(from: @{FungibleToken.Vault}) {
        let flow <- from as! @FlowToken.Vault
        if let existing = self.account.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault) {
            existing.deposit(from: <- flow)
        } else {
            let fresh <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
            fresh.deposit(from: <- flow)
            self.account.storage.save(<- fresh, to: /storage/flowTokenVault)
        }
    }

    init() {
        self.VARIABLE_RATE = 2
        self.MAX_UINT256 = UInt256.max
        self.POOL_MAINNET = EVM.addressFromString("bC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d")
        self.PositionStoragePath = /storage/MOREV1Position
        self.PositionPublicPath = /public/MOREV1Position
    }
}
