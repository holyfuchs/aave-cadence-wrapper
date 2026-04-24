import "EVM"
import "FungibleToken"
import "FlowToken"
import "FlowEVMBridge"

/// AaveWrapper exposes a Cadence resource that wraps an Aave v3 position on
/// FlowEVM (MORE Markets). The resource internally owns a COA — that COA's
/// EVM address is the Aave "user". Moving the resource between accounts moves
/// the position with it.
///
/// The public API is Cadence-native: supply/repay accept a FungibleToken vault,
/// borrow/withdraw return one. The wrapper bridges to/from EVM internally via
/// the COA's built-in bridge methods.
///
/// Aave v3 note: the only supported interestRateMode is 2 (variable).
access(all) contract AaveWrapper {

    access(all) entitlement Manage

    access(all) let VARIABLE_RATE: UInt256
    access(all) let MAX_UINT256: UInt256
    /// MORE Markets (Aave v3 fork) Pool proxy on FlowEVM mainnet.
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
        access(self) let feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        access(all) let pool: EVM.EVMAddress

        init(
            pool: EVM.EVMAddress,
            feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        ) {
            pre { feeProvider.check(): "fee provider capability is invalid" }
            self.coa <- EVM.createCadenceOwnedAccount()
            self.feeProvider = feeProvider
            self.pool = pool
            emit PositionCreated(evmAddress: self.coa.address().toString())
        }

        /// Borrow the stored fee provider reference. Used internally for every
        /// Cadence↔EVM bridge call.
        access(self) fun fees(): auth(FungibleToken.Withdraw) &FlowToken.Vault {
            return self.feeProvider.borrow()
                ?? panic("fee provider capability no longer resolves")
        }

        access(all) view fun evmAddress(): EVM.EVMAddress {
            return self.coa.address()
        }

        /// Fund the internal COA with FLOW so it can pay EVM gas.
        access(Manage) fun depositFlow(from: @{FungibleToken.Vault}) {
            self.coa.deposit(from: <- (from as! @FlowToken.Vault))
        }

        /// Bridge `vault` into the COA and supply it to the Pool.
        access(Manage) fun supply(vault: @{FungibleToken.Vault}) {
            let vaultType = vault.getType()
            let asset = FlowEVMBridge.getAssociatedEVMAddress(with: vaultType)
                ?? panic("No EVM mapping for vault type \(vaultType.identifier)")

            let before = self.erc20BalanceOf(token: asset)
            self.coa.depositTokens(vault: <- vault, feeProvider: self.fees())
            let amount = self.erc20BalanceOf(token: asset) - before

            self.supplyEVM(asset: asset, amount: amount)
        }

        /// Supply an ERC20 already held by this COA. Use when you've acquired
        /// the asset on the EVM side directly (e.g., wrapping FLOW into WFLOW,
        /// swapping on a DEX) and don't need the Cadence bridge round-trip.
        access(Manage) fun supplyEVM(asset: EVM.EVMAddress, amount: UInt256) {
            self.mustCall(
                to: asset,
                data: EVM.encodeABIWithSignature(
                    "approve(address,uint256)",
                    [self.pool, amount]
                ),
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

        /// Borrow an ERC20 to the COA without bridging out. Returns after the
        /// Pool has credited the borrowed amount to the COA's ERC20 balance.
        access(Manage) fun borrowEVM(asset: EVM.EVMAddress, amount: UInt256) {
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "borrow(address,uint256,uint256,uint16,address)",
                    [asset, amount, AaveWrapper.VARIABLE_RATE, 0 as UInt16, self.coa.address()]
                ),
                gasLimit: 600_000
            )
            emit Borrowed(asset: asset.toString(), amount: amount)
        }

        /// Toggle an asset's collateral flag using its EVM address directly.
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

        /// Balance of `token` held by this COA. Public so callers can size
        /// supply/repay calls after an EVM-side operation changes the balance.
        access(all) fun erc20BalanceOf(token: EVM.EVMAddress): UInt256 {
            let result = self.coa.call(
                to: token,
                data: EVM.encodeABIWithSignature(
                    "balanceOf(address)",
                    [self.coa.address()]
                ),
                gasLimit: 100_000,
                value: EVM.Balance(attoflow: 0)
            )
            assert(result.status == EVM.Status.successful, message: "balanceOf failed")
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: result.data)
            return decoded[0] as! UInt256
        }

        /// Withdraw `amount` of the asset corresponding to `vaultType` from the
        /// Pool and bridge it back out as a Cadence vault. Pass
        /// `AaveWrapper.MAX_UINT256` to withdraw the full aToken balance.
        access(Manage) fun withdraw(
            vaultType: Type,
            amount: UInt256
        ): @{FungibleToken.Vault} {
            let asset = FlowEVMBridge.getAssociatedEVMAddress(with: vaultType)
                ?? panic("No EVM mapping for vault type \(vaultType.identifier)")

            let before = self.erc20BalanceOf(token: asset)
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "withdraw(address,uint256,address)",
                    [asset, amount, self.coa.address()]
                ),
                gasLimit: 500_000
            )
            let received = self.erc20BalanceOf(token: asset) - before
            emit Withdrawn(asset: asset.toString(), amount: received)

            return <- self.coa.withdrawTokens(
                type: vaultType,
                amount: received,
                feeProvider: self.fees()
            )
        }

        /// Borrow `amount` of the asset corresponding to `vaultType` against
        /// existing collateral, bridging it out as a Cadence vault.
        access(Manage) fun borrow(
            vaultType: Type,
            amount: UInt256
        ): @{FungibleToken.Vault} {
            let asset = FlowEVMBridge.getAssociatedEVMAddress(with: vaultType)
                ?? panic("No EVM mapping for vault type \(vaultType.identifier)")

            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "borrow(address,uint256,uint256,uint16,address)",
                    [asset, amount, AaveWrapper.VARIABLE_RATE, 0 as UInt16, self.coa.address()]
                ),
                gasLimit: 600_000
            )
            emit Borrowed(asset: asset.toString(), amount: amount)

            return <- self.coa.withdrawTokens(
                type: vaultType,
                amount: amount,
                feeProvider: self.fees()
            )
        }

        /// Bridge `vault` into the COA and repay debt for the matching asset.
        /// Returns any dust left over after repayment (Aave rounds down; extra
        /// tokens that weren't needed to cover the debt come back to the caller).
        access(Manage) fun repay(
            vault: @{FungibleToken.Vault}
        ): @{FungibleToken.Vault} {
            let vaultType = vault.getType()
            let asset = FlowEVMBridge.getAssociatedEVMAddress(with: vaultType)
                ?? panic("No EVM mapping for vault type \(vaultType.identifier)")

            // Stash an empty twin of the incoming vault so we have something
            // to return when the Pool consumes the whole payment (bridge
            // refuses zero-amount withdrawTokens).
            let empty <- vault.createEmptyVault()

            let before = self.erc20BalanceOf(token: asset)
            self.coa.depositTokens(vault: <- vault, feeProvider: self.fees())
            let bridgedIn = self.erc20BalanceOf(token: asset) - before

            self.mustCall(
                to: asset,
                data: EVM.encodeABIWithSignature(
                    "approve(address,uint256)",
                    [self.pool, bridgedIn]
                ),
                gasLimit: 100_000
            )
            self.mustCall(
                to: self.pool,
                data: EVM.encodeABIWithSignature(
                    "repay(address,uint256,uint256,address)",
                    [asset, bridgedIn, AaveWrapper.VARIABLE_RATE, self.coa.address()]
                ),
                gasLimit: 500_000
            )
            let leftover = self.erc20BalanceOf(token: asset) - (before)
            emit Repaid(asset: asset.toString(), amount: bridgedIn - leftover)

            if leftover == 0 {
                return <- empty
            }
            destroy empty
            return <- self.coa.withdrawTokens(
                type: vaultType,
                amount: leftover,
                feeProvider: self.fees()
            )
        }

        access(Manage) fun setUseAsCollateral(vaultType: Type, useAsCollateral: Bool) {
            let asset = FlowEVMBridge.getAssociatedEVMAddress(with: vaultType)
                ?? panic("No EVM mapping for vault type \(vaultType.identifier)")
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

        /// Escape hatch — call any EVM contract from this COA for ops not
        /// wrapped above (flash loans, liquidation, isolation-mode tweaks).
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

    access(all) fun createPosition(
        pool: EVM.EVMAddress,
        feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    ): @Position {
        return <- create Position(pool: pool, feeProvider: feeProvider)
    }

    access(all) fun createMainnetPosition(
        feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    ): @Position {
        return <- create Position(pool: self.POOL_MAINNET, feeProvider: feeProvider)
    }

    init() {
        self.VARIABLE_RATE = 2
        self.MAX_UINT256 = UInt256.max
        self.POOL_MAINNET = EVM.addressFromString("bC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d")
        self.PositionStoragePath = /storage/AaveWrapperPosition
        self.PositionPublicPath = /public/AaveWrapperPosition
    }
}
