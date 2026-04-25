// import "FungibleToken"
// import "FlowToken"
// import "Burner"
// import "EVM"
// import "FlowEVMBridgeUtils"
// import "FlowEVMBridgeConfig"

// /// Thin wrapper around a Uniswap-V2-style router on Flow EVM (PunchSwap,
// /// etc.). Pricing via `getAmountsIn` / `getAmountsOut`; trades via
// /// `swapExactTokensForTokens` / `swapTokensForExactTokens`.
// access(all) contract UniswapV2SwapperV1 {

//     /// Estimated swap pricing (`inAmount` / `outAmount` in each side's
//     /// UFix64-native units; 0/0 if unquotable).
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
//         access(all) let routerAddress: EVM.EVMAddress
//         access(all) let addressPath: [EVM.EVMAddress]
//         access(self) let inVault: Type
//         access(self) let outVault: Type
//         access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

//         init(
//             routerAddress: EVM.EVMAddress,
//             path: [EVM.EVMAddress],
//             inVault: Type,
//             outVault: Type,
//             coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>
//         ) {
//             pre {
//                 path.length >= 2: "path must contain at least two EVM addresses"
//                 FlowEVMBridgeConfig.getTypeAssociated(with: path[0]) == inVault:
//                     "inVault \(inVault.identifier) not associated with path[0]"
//                 FlowEVMBridgeConfig.getTypeAssociated(with: path[path.length - 1]) == outVault:
//                     "outVault \(outVault.identifier) not associated with path[last]"
//                 coaCapability.check(): "Provided COA Capability is invalid"
//             }
//             self.routerAddress = routerAddress
//             self.addressPath = path
//             self.inVault = inVault
//             self.outVault = outVault
//             self.coaCapability = coaCapability
//         }

//         access(all) view fun inType(): Type { return self.inVault }
//         access(all) view fun outType(): Type { return self.outVault }

//         access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): UniswapV2SwapperV1.Quote {
//             let path = reverse ? self.addressPath.reverse() : self.addressPath
//             let evmDesired = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 forDesired,
//                 erc20Address: path[path.length - 1]
//             )
//             let amountIn = self.routerAmounts(out: false, amount: evmDesired, path: path)
//             return UniswapV2SwapperV1.Quote(
//                 inType: reverse ? self.outVault : self.inVault,
//                 outType: reverse ? self.inVault : self.outVault,
//                 inAmount: amountIn ?? 0.0,
//                 outAmount: amountIn != nil ? forDesired : 0.0
//             )
//         }

//         access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): UniswapV2SwapperV1.Quote {
//             let path = reverse ? self.addressPath.reverse() : self.addressPath
//             let evmProvided = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 forProvided,
//                 erc20Address: path[0]
//             )
//             let amountOut = self.routerAmounts(out: true, amount: evmProvided, path: path)
//             return UniswapV2SwapperV1.Quote(
//                 inType: reverse ? self.outVault : self.inVault,
//                 outType: reverse ? self.inVault : self.outVault,
//                 inAmount: amountOut != nil ? forProvided : 0.0,
//                 outAmount: amountOut ?? 0.0
//             )
//         }

//         access(all) fun swap(
//             quote: UniswapV2SwapperV1.Quote?,
//             inVault: @{FungibleToken.Vault}
//         ): @{FungibleToken.Vault} {
//             let amountOutMin = quote?.outAmount
//                 ?? self.quoteOut(forProvided: inVault.balance, reverse: false).outAmount
//             return <- self.swapExactIn(exactVaultIn: <- inVault, amountOutMin: amountOutMin, reverse: false)
//         }

//         access(all) fun swapBack(
//             quote: UniswapV2SwapperV1.Quote?,
//             residual: @{FungibleToken.Vault}
//         ): @{FungibleToken.Vault} {
//             let amountOutMin = quote?.outAmount
//                 ?? self.quoteOut(forProvided: residual.balance, reverse: true).outAmount
//             return <- self.swapExactIn(exactVaultIn: <- residual, amountOutMin: amountOutMin, reverse: true)
//         }

//         access(all) fun swapExactOut(
//             maxIn: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
//             desiredOut: UFix64
//         ): @{FungibleToken.Vault} {
//             pre {
//                 maxIn.getType() == self.inVault: "maxIn type mismatch"
//             }
//             let q = self.quoteIn(forDesired: desiredOut, reverse: false)
//             assert(q.inAmount > 0.0, message: "swapExactOut: not quotable")
//             assert(maxIn.balance >= q.inAmount, message: "swapExactOut: maxIn insufficient")

//             let coa = self.coaCapability.borrow() ?? panic("invalid COA capability")
//             let feeVault <- self.withdrawBridgeFee(coa: coa)
//             let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

//             let inToken = self.addressPath[0]
//             let evmAmountInMax = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 q.inAmount, erc20Address: inToken
//             )
//             let evmDesiredOut = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 desiredOut, erc20Address: self.addressPath[self.addressPath.length - 1]
//             )

//             let inSlice <- maxIn.withdraw(amount: q.inAmount)
//             coa.depositTokens(vault: <- inSlice, feeProvider: feeVaultRef)

//             let _ = self.mustCall(
//                 coa: coa, to: inToken,
//                 signature: "approve(address,uint256)",
//                 args: [self.routerAddress, evmAmountInMax],
//                 gasLimit: 100_000
//             )

//             let res = self.mustCall(
//                 coa: coa, to: self.routerAddress,
//                 signature: "swapTokensForExactTokens(uint256,uint256,address[],address,uint256)",
//                 args: [
//                     evmDesiredOut,
//                     evmAmountInMax,
//                     self.addressPath,
//                     coa.address(),
//                     UInt256(getCurrentBlock().timestamp)
//                 ],
//                 gasLimit: 1_000_000
//             )
//             let amounts = EVM.decodeABI(types: [Type<[UInt256]>()], data: res.data)[0] as! [UInt256]
//             let actualIn = amounts[0]
//             let actualOut = amounts[amounts.length - 1]

//             let _ = self.mustCall(
//                 coa: coa, to: inToken,
//                 signature: "approve(address,uint256)",
//                 args: [self.routerAddress, 0 as UInt256],
//                 gasLimit: 60_000
//             )

//             if actualIn < evmAmountInMax {
//                 let unspent = evmAmountInMax - actualIn
//                 let refund <- coa.withdrawTokens(
//                     type: self.inVault,
//                     amount: unspent,
//                     feeProvider: feeVaultRef
//                 )
//                 maxIn.deposit(from: <- refund)
//             }

//             let outVault <- coa.withdrawTokens(
//                 type: self.outVault,
//                 amount: actualOut,
//                 feeProvider: feeVaultRef
//             )

//             self.returnFee(coa: coa, feeVault: <- feeVault)
//             return <- outVault
//         }

//         access(self) fun swapExactIn(
//             exactVaultIn: @{FungibleToken.Vault},
//             amountOutMin: UFix64,
//             reverse: Bool
//         ): @{FungibleToken.Vault} {
//             let coa = self.coaCapability.borrow() ?? panic("invalid COA capability")
//             let feeVault <- self.withdrawBridgeFee(coa: coa)
//             let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

//             let path = reverse ? self.addressPath.reverse() : self.addressPath
//             let inTokenAddress = path[0]
//             let outTokenAddress = path[path.length - 1]
//             let outVaultType = reverse ? self.inVault : self.outVault

//             let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 exactVaultIn.balance, erc20Address: inTokenAddress
//             )
//             let evmAmountOutMin = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
//                 amountOutMin, erc20Address: outTokenAddress
//             )
//             coa.depositTokens(vault: <- exactVaultIn, feeProvider: feeVaultRef)

//             let _ = self.mustCall(
//                 coa: coa, to: inTokenAddress,
//                 signature: "approve(address,uint256)",
//                 args: [self.routerAddress, evmAmountIn],
//                 gasLimit: 100_000
//             )

//             let res = self.mustCall(
//                 coa: coa, to: self.routerAddress,
//                 signature: "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
//                 args: [
//                     evmAmountIn,
//                     evmAmountOutMin,
//                     path,
//                     coa.address(),
//                     UInt256(getCurrentBlock().timestamp)
//                 ],
//                 gasLimit: 1_000_000
//             )
//             let amounts = EVM.decodeABI(types: [Type<[UInt256]>()], data: res.data)[0] as! [UInt256]
//             let amountOut = amounts[amounts.length - 1]

//             let outVault <- coa.withdrawTokens(
//                 type: outVaultType,
//                 amount: amountOut,
//                 feeProvider: feeVaultRef
//             )

//             self.returnFee(coa: coa, feeVault: <- feeVault)
//             return <- outVault
//         }

//         access(self) fun routerAmounts(out: Bool, amount: UInt256, path: [EVM.EVMAddress]): UFix64? {
//             let coa = self.coaCapability.borrow() ?? panic("invalid COA capability")
//             let res = coa.dryCall(
//                 to: self.routerAddress,
//                 data: EVM.encodeABIWithSignature(
//                     out ? "getAmountsOut(uint256,address[])" : "getAmountsIn(uint256,address[])",
//                     [amount, path]
//                 ),
//                 gasLimit: 1_000_000,
//                 value: EVM.Balance(attoflow: 0)
//             )
//             if res.status != EVM.Status.successful { return nil }
//             let arr = EVM.decodeABI(types: [Type<[UInt256]>()], data: res.data)[0] as! [UInt256]
//             if arr.length == 0 { return nil }
//             let raw = out ? arr[arr.length - 1] : arr[0]
//             let token = out ? path[path.length - 1] : path[0]
//             return FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(raw, erc20Address: token)
//         }

//         access(self) fun withdrawBridgeFee(
//             coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount
//         ): @FlowToken.Vault {
//             let bal = EVM.Balance(attoflow: 0)
//             bal.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 256))
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
//         ): EVM.Result {
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
//             return res
//         }
//     }
// }
