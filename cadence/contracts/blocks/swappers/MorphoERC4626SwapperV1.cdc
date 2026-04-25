// import "Burner"
// import "FungibleToken"
// import "FlowToken"
// import "EVM"
// import "FlowEVMBridgeConfig"
// import "FlowEVMBridgeUtils"

// /// Morpho ERC4626 vault swapper. Same shape as `ERC4626SwapperV1.Swapper`
// /// but with an `isReversed` flag that flips which side of the asset/share
// /// pair is exposed as `inType()` / `outType()`. Useful when a strategy
// /// holds *shares* as its yield-side input and wants to swap back into the
// /// underlying asset.
// ///
// /// Direction model (canonical forward = assets → shares):
// ///   `assetsToShares == (isReversed == reverse)` for quotes/swaps. So
// ///   `swap` runs assets→shares when `isReversed=false`, shares→assets when
// ///   `isReversed=true`.
// access(all) contract MorphoERC4626SwapperV1 {

//     /// Estimated swap pricing.
//     access(all) struct Quote {
//         access(all) let inType: Type
//         access(all) let outType: Type
//         access(all) let inAmount: UFix64
//         access(all) let outAmount: UFix64

//         view init(inType: Type, outType: Type, inAmount: UFix64, outAmount: UFix64) {
//             self.inType = inType
//             self.outType = outType
//             self.inAmount = inAmount
//             self.outAmount = outAmount
//         }
//     }

//     access(all) struct Swapper {
//         access(all) let vaultAddress: EVM.EVMAddress
//         access(all) let assetEVMAddress: EVM.EVMAddress
//         access(all) let isReversed: Bool
//         access(self) let assetType: Type
//         access(self) let shareType: Type
//         access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

//         init(
//             vaultAddress: EVM.EVMAddress,
//             assetEVMAddress: EVM.EVMAddress,
//             isReversed: Bool,
//             coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>
//         ) {
//             pre { coaCapability.check(): "Provided COA Capability is invalid" }
//             self.vaultAddress = vaultAddress
//             self.assetEVMAddress = assetEVMAddress
//             self.isReversed = isReversed
//             self.coaCapability = coaCapability
//             self.shareType = FlowEVMBridgeConfig.getTypeAssociated(with: vaultAddress)
//                 ?? panic("Morpho vault \(vaultAddress.toString()) not associated — onboard via VM bridge")
//             self.assetType = FlowEVMBridgeConfig.getTypeAssociated(with: assetEVMAddress)
//                 ?? panic("Asset \(assetEVMAddress.toString()) not associated — onboard via VM bridge")
//         }

//         access(all) view fun inType(): Type {
//             return self.isReversed ? self.shareType : self.assetType
//         }
//         access(all) view fun outType(): Type {
//             return self.isReversed ? self.assetType : self.shareType
//         }

//         access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): MorphoERC4626SwapperV1.Quote {
//             let assetsToShares = (self.isReversed == reverse)
//             // assetsToShares: previewMint(shares) → assets needed
//             // sharesToAssets: previewWithdraw(assets) → shares needed
//             if assetsToShares {
//                 let evmShares = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                     forDesired, erc20Address: self.vaultAddress
//                 )
//                 let evmAssets = self.preview("previewMint(uint256)", evmShares)
//                 let assets = evmAssets != nil
//                     ? FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(evmAssets!, erc20Address: self.assetEVMAddress)
//                     : nil
//                 return MorphoERC4626SwapperV1.Quote(
//                     inType: self.assetType, outType: self.shareType,
//                     inAmount: assets ?? 0.0,
//                     outAmount: assets != nil ? forDesired : 0.0
//                 )
//             }
//             let evmAssets = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 forDesired, erc20Address: self.assetEVMAddress
//             )
//             let evmShares = self.preview("previewWithdraw(uint256)", evmAssets)
//             let shares = evmShares != nil
//                 ? FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(evmShares!, erc20Address: self.vaultAddress)
//                 : nil
//             return MorphoERC4626SwapperV1.Quote(
//                 inType: self.shareType, outType: self.assetType,
//                 inAmount: shares ?? 0.0,
//                 outAmount: shares != nil ? forDesired : 0.0
//             )
//         }

//         access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): MorphoERC4626SwapperV1.Quote {
//             let assetsToShares = (self.isReversed == reverse)
//             if assetsToShares {
//                 let evmAssets = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                     forProvided, erc20Address: self.assetEVMAddress
//                 )
//                 let evmShares = self.preview("previewDeposit(uint256)", evmAssets)
//                 let shares = evmShares != nil
//                     ? FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(evmShares!, erc20Address: self.vaultAddress)
//                     : nil
//                 return MorphoERC4626SwapperV1.Quote(
//                     inType: self.assetType, outType: self.shareType,
//                     inAmount: shares != nil ? forProvided : 0.0,
//                     outAmount: shares ?? 0.0
//                 )
//             }
//             let evmShares = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 forProvided, erc20Address: self.vaultAddress
//             )
//             let evmAssets = self.preview("previewRedeem(uint256)", evmShares)
//             let assets = evmAssets != nil
//                 ? FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(evmAssets!, erc20Address: self.assetEVMAddress)
//                 : nil
//             return MorphoERC4626SwapperV1.Quote(
//                 inType: self.shareType, outType: self.assetType,
//                 inAmount: assets != nil ? forProvided : 0.0,
//                 outAmount: assets ?? 0.0
//             )
//         }

//         access(all) fun swap(
//             quote: MorphoERC4626SwapperV1.Quote?,
//             inVault: @{FungibleToken.Vault}
//         ): @{FungibleToken.Vault} {
//             if self.isReversed {
//                 return <- self.sharesToAssets(inVault: <- inVault)
//             }
//             return <- self.assetsToShares(inVault: <- inVault)
//         }

//         access(all) fun swapBack(
//             quote: MorphoERC4626SwapperV1.Quote?,
//             residual: @{FungibleToken.Vault}
//         ): @{FungibleToken.Vault} {
//             if self.isReversed {
//                 return <- self.assetsToShares(inVault: <- residual)
//             }
//             return <- self.sharesToAssets(inVault: <- residual)
//         }

//         access(all) fun swapExactOut(
//             maxIn: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
//             desiredOut: UFix64
//         ): @{FungibleToken.Vault} {
//             pre { maxIn.getType() == self.inType(): "maxIn type mismatch" }
//             // forward direction: !isReversed (asset→share for non-reversed,
//             // share→asset for reversed)
//             let assetsToShares = !self.isReversed
//             let q = self.quoteIn(forDesired: desiredOut, reverse: false)
//             assert(q.inAmount > 0.0, message: "swapExactOut: not quotable")
//             assert(maxIn.balance >= q.inAmount, message: "swapExactOut: maxIn insufficient")

//             let coa = self.coaCapability.borrow() ?? panic("invalid COA capability")
//             let feeVault <- self.withdrawBridgeFee(coa: coa)
//             let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

//             if assetsToShares {
//                 return <- self.exactOutAssetsToShares(
//                     maxIn: maxIn, q: q, desiredOut: desiredOut,
//                     coa: coa, feeVault: <- feeVault, feeVaultRef: feeVaultRef
//                 )
//             }
//             return <- self.exactOutSharesToAssets(
//                 maxIn: maxIn, q: q, desiredOut: desiredOut,
//                 coa: coa, feeVault: <- feeVault, feeVaultRef: feeVaultRef
//             )
//         }

//         access(self) fun exactOutAssetsToShares(
//             maxIn: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
//             q: MorphoERC4626SwapperV1.Quote,
//             desiredOut: UFix64,
//             coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount,
//             feeVault: @FlowToken.Vault,
//             feeVaultRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
//         ): @{FungibleToken.Vault} {
//             let evmShares = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 desiredOut, erc20Address: self.vaultAddress
//             )
//             let evmAssetsApprove = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 q.inAmount, erc20Address: self.assetEVMAddress
//             )

//             let inSlice <- maxIn.withdraw(amount: q.inAmount)
//             coa.depositTokens(vault: <- inSlice, feeProvider: feeVaultRef)

//             let assetBefore = self.erc20BalanceOf(coa: coa, token: self.assetEVMAddress)

//             self.mustCall(
//                 coa: coa, to: self.assetEVMAddress,
//                 signature: "approve(address,uint256)",
//                 args: [self.vaultAddress, evmAssetsApprove],
//                 gasLimit: 100_000
//             )
//             self.mustCall(
//                 coa: coa, to: self.vaultAddress,
//                 signature: "mint(uint256,address)",
//                 args: [evmShares, coa.address()],
//                 gasLimit: 1_000_000
//             )

//             let assetAfter = self.erc20BalanceOf(coa: coa, token: self.assetEVMAddress)
//             let actualSpent = (assetBefore + evmAssetsApprove) - assetAfter

//             self.mustCall(
//                 coa: coa, to: self.assetEVMAddress,
//                 signature: "approve(address,uint256)",
//                 args: [self.vaultAddress, 0 as UInt256],
//                 gasLimit: 60_000
//             )

//             if actualSpent < evmAssetsApprove {
//                 let unspent = evmAssetsApprove - actualSpent
//                 let refund <- coa.withdrawTokens(
//                     type: self.assetType, amount: unspent, feeProvider: feeVaultRef
//                 )
//                 maxIn.deposit(from: <- refund)
//             }

//             let outVault <- coa.withdrawTokens(
//                 type: self.shareType, amount: evmShares, feeProvider: feeVaultRef
//             )
//             self.returnFee(coa: coa, feeVault: <- feeVault)
//             return <- outVault
//         }

//         access(self) fun exactOutSharesToAssets(
//             maxIn: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
//             q: MorphoERC4626SwapperV1.Quote,
//             desiredOut: UFix64,
//             coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount,
//             feeVault: @FlowToken.Vault,
//             feeVaultRef: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
//         ): @{FungibleToken.Vault} {
//             let evmAssets = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 desiredOut, erc20Address: self.assetEVMAddress
//             )

//             let inSlice <- maxIn.withdraw(amount: q.inAmount)
//             coa.depositTokens(vault: <- inSlice, feeProvider: feeVaultRef)

//             let shareBefore = self.erc20BalanceOf(coa: coa, token: self.vaultAddress)
//             let evmSharesIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 q.inAmount, erc20Address: self.vaultAddress
//             )

//             // ERC4626 `withdraw(assets, receiver, owner)` burns just enough
//             // shares from `owner` to deliver `assets`.
//             self.mustCall(
//                 coa: coa, to: self.vaultAddress,
//                 signature: "withdraw(uint256,address,address)",
//                 args: [evmAssets, coa.address(), coa.address()],
//                 gasLimit: 1_000_000
//             )

//             let shareAfter = self.erc20BalanceOf(coa: coa, token: self.vaultAddress)
//             let burnt = (shareBefore + evmSharesIn) - shareAfter

//             if burnt < evmSharesIn {
//                 let unspent = evmSharesIn - burnt
//                 let refund <- coa.withdrawTokens(
//                     type: self.shareType, amount: unspent, feeProvider: feeVaultRef
//                 )
//                 maxIn.deposit(from: <- refund)
//             }

//             let outVault <- coa.withdrawTokens(
//                 type: self.assetType, amount: evmAssets, feeProvider: feeVaultRef
//             )
//             self.returnFee(coa: coa, feeVault: <- feeVault)
//             return <- outVault
//         }

//         access(self) fun assetsToShares(inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
//             let coa = self.coaCapability.borrow() ?? panic("invalid COA capability")
//             let feeVault <- self.withdrawBridgeFee(coa: coa)
//             let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

//             let evmAmount = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 inVault.balance, erc20Address: self.assetEVMAddress
//             )
//             coa.depositTokens(vault: <- inVault, feeProvider: feeVaultRef)

//             let sharesBefore = self.erc20BalanceOf(coa: coa, token: self.vaultAddress)

//             self.mustCall(
//                 coa: coa, to: self.assetEVMAddress,
//                 signature: "approve(address,uint256)",
//                 args: [self.vaultAddress, evmAmount],
//                 gasLimit: 100_000
//             )
//             self.mustCall(
//                 coa: coa, to: self.vaultAddress,
//                 signature: "deposit(uint256,address)",
//                 args: [evmAmount, coa.address()],
//                 gasLimit: 1_000_000
//             )

//             let sharesOut = self.erc20BalanceOf(coa: coa, token: self.vaultAddress) - sharesBefore

//             let outVault <- coa.withdrawTokens(
//                 type: self.shareType, amount: sharesOut, feeProvider: feeVaultRef
//             )
//             self.returnFee(coa: coa, feeVault: <- feeVault)
//             return <- outVault
//         }

//         access(self) fun sharesToAssets(inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
//             let coa = self.coaCapability.borrow() ?? panic("invalid COA capability")
//             let feeVault <- self.withdrawBridgeFee(coa: coa)
//             let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

//             let evmShares = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 inVault.balance, erc20Address: self.vaultAddress
//             )
//             coa.depositTokens(vault: <- inVault, feeProvider: feeVaultRef)

//             let assetBefore = self.erc20BalanceOf(coa: coa, token: self.assetEVMAddress)

//             self.mustCall(
//                 coa: coa, to: self.vaultAddress,
//                 signature: "redeem(uint256,address,address)",
//                 args: [evmShares, coa.address(), coa.address()],
//                 gasLimit: 1_000_000
//             )

//             let assetsOut = self.erc20BalanceOf(coa: coa, token: self.assetEVMAddress) - assetBefore

//             let outVault <- coa.withdrawTokens(
//                 type: self.assetType, amount: assetsOut, feeProvider: feeVaultRef
//             )
//             self.returnFee(coa: coa, feeVault: <- feeVault)
//             return <- outVault
//         }

//         access(self) fun preview(_ signature: String, _ amount: UInt256): UInt256? {
//             let coa = self.coaCapability.borrow() ?? panic("invalid COA capability")
//             let res = coa.dryCall(
//                 to: self.vaultAddress,
//                 data: EVM.encodeABIWithSignature(signature, [amount]),
//                 gasLimit: 500_000,
//                 value: EVM.Balance(attoflow: 0)
//             )
//             if res.status != EVM.Status.successful { return nil }
//             let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: res.data)
//             if decoded.length == 0 { return nil }
//             return decoded[0] as! UInt256
//         }

//         access(self) fun erc20BalanceOf(
//             coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount,
//             token: EVM.EVMAddress
//         ): UInt256 {
//             let res = coa.call(
//                 to: token,
//                 data: EVM.encodeABIWithSignature("balanceOf(address)", [coa.address()]),
//                 gasLimit: 100_000,
//                 value: EVM.Balance(attoflow: 0)
//             )
//             assert(res.status == EVM.Status.successful, message: "balanceOf failed")
//             return EVM.decodeABI(types: [Type<UInt256>()], data: res.data)[0] as! UInt256
//         }

//         access(self) fun withdrawBridgeFee(
//             coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount
//         ): @FlowToken.Vault {
//             let bal = EVM.Balance(attoflow: 0)
//             bal.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 128))
//             return <- coa.withdraw(balance: bal)
//         }

//         access(self) fun returnFee(
//             coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount,
//             feeVault: @FlowToken.Vault
//         ) {
//             if feeVault.balance > 0.0 {
//                 coa.deposit(from: <- feeVault)
//             } else {
//                 Burner.burn(<- feeVault)
//             }
//         }

//         access(self) fun mustCall(
//             coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount,
//             to: EVM.EVMAddress,
//             signature: String,
//             args: [AnyStruct],
//             gasLimit: UInt64
//         ) {
//             let res = coa.call(
//                 to: to,
//                 data: EVM.encodeABIWithSignature(signature, args),
//                 gasLimit: gasLimit,
//                 value: EVM.Balance(attoflow: 0)
//             )
//             assert(
//                 res.status == EVM.Status.successful,
//                 message: "EVM call \(signature) reverted: \(res.errorMessage)"
//             )
//         }
//     }
// }
