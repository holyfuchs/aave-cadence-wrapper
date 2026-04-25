import "FungibleToken"
import "FlowToken"
import "Burner"
import "EVM"
import "FlowEVMBridgeUtils"
import "FlowEVMBridgeConfig"

/// Multi-route Uniswap-V3 swapper for KittyPunch on Flow EVM. The router
/// + quoter EVM addresses and the executor COA are baked into the contract
/// (configured at `init()`), so a `Swapper` struct only needs to carry its
/// route table — `[(inType, outType) → V3 path]`. Callers ask the swapper
/// to swap *into a specific outType*; it picks the right route by
/// `(inVault.getType(), outType)`.
///
/// Pricing via the V3 quoter (`quoteExactInput` / `quoteExactOutput`);
/// trades via `exactInput` / `exactOutput`. The contract account's COA at
/// `/storage/UniswapV3SwapperV1COA` must be funded with FLOW to cover
/// bridge fees on the Cadence↔EVM round-trip.
access(all) contract UniswapV3SwapperV1 {

    /// KittyPunch UniV3 router (FlowEVM mainnet).
    access(all) let ROUTER: EVM.EVMAddress
    /// KittyPunch UniV3 quoter (FlowEVM mainnet).
    access(all) let QUOTER: EVM.EVMAddress
    /// Storage path of the contract-account COA used by every Swapper
    /// produced by this contract.
    access(all) let coaStoragePath: StoragePath
    /// Capability to the executor COA. Internal — Swapper structs use it
    /// via the `coa()` helper rather than holding their own copy.
    access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

    /// Estimated swap pricing.
    access(all) struct Quote {
        access(all) let inType: Type
        access(all) let outType: Type
        access(all) let inAmount: UFix64
        access(all) let outAmount: UFix64

        view init(inType: Type, outType: Type, inAmount: UFix64, outAmount: UFix64) {
            self.inType = inType
            self.outType = outType
            self.inAmount = inAmount
            self.outAmount = outAmount
        }
    }

    /// One supported direction. Routes are uni-directional; if you want to
    /// swap both ways, register two Routes (forward + reverse) with the
    /// reversed `tokenPath` and `feePath`.
    access(all) struct Route {
        access(all) let inType: Type
        access(all) let outType: Type
        access(all) let tokenPath: [EVM.EVMAddress]
        access(all) let feePath: [UInt32]

        init(
            inType: Type,
            outType: Type,
            tokenPath: [EVM.EVMAddress],
            feePath: [UInt32]
        ) {
            pre {
                tokenPath.length >= 2: "tokenPath must contain at least two addresses"
                feePath.length == tokenPath.length - 1: "feePath length must be tokenPath.length - 1"
                FlowEVMBridgeConfig.getTypeAssociated(with: tokenPath[0]) == inType:
                    "inType not associated with tokenPath[0]"
                FlowEVMBridgeConfig.getTypeAssociated(with: tokenPath[tokenPath.length - 1]) == outType:
                    "outType not associated with tokenPath[last]"
            }
            self.inType = inType
            self.outType = outType
            self.tokenPath = tokenPath
            self.feePath = feePath
        }
    }

    /// `ISwapRouter.ExactInputParams`.
    access(all) struct ExactInputParams {
        access(all) let path: EVM.EVMBytes
        access(all) let recipient: EVM.EVMAddress
        access(all) let amountIn: UInt256
        access(all) let amountOutMinimum: UInt256

        init(path: EVM.EVMBytes, recipient: EVM.EVMAddress, amountIn: UInt256, amountOutMinimum: UInt256) {
            self.path = path
            self.recipient = recipient
            self.amountIn = amountIn
            self.amountOutMinimum = amountOutMinimum
        }
    }

    /// `ISwapRouter.ExactOutputParams`.
    access(all) struct ExactOutputParams {
        access(all) let path: EVM.EVMBytes
        access(all) let recipient: EVM.EVMAddress
        access(all) let amountOut: UInt256
        access(all) let amountInMaximum: UInt256

        init(path: EVM.EVMBytes, recipient: EVM.EVMAddress, amountOut: UInt256, amountInMaximum: UInt256) {
            self.path = path
            self.recipient = recipient
            self.amountOut = amountOut
            self.amountInMaximum = amountInMaximum
        }
    }

    access(all) struct Swapper {
        /// Routes keyed by `"<inType.identifier>|<outType.identifier>"`.
        access(self) var routes: {String: Route}

        init() {
            self.routes = {}
        }

        /// Add a route. Reverts if a route with the same `(inType, outType)`
        /// pair is already registered.
        access(all) fun addRoute(_ route: Route) {
            let key = UniswapV3SwapperV1.routeKey(inType: route.inType, outType: route.outType)
            assert(self.routes[key] == nil, message: "duplicate route: \(key)")
            self.routes[key] = route
        }

        /// Whether this swapper can route `inType → outType`.
        access(all) view fun supports(inType: Type, outType: Type): Bool {
            return self.routes[UniswapV3SwapperV1.routeKey(inType: inType, outType: outType)] != nil
        }

        /// All registered routes (for inspection / UI).
        access(all) view fun supportedRoutes(): [Route] {
            return self.routes.values
        }

        access(self) view fun mustRoute(inType: Type, outType: Type): Route {
            return self.routes[UniswapV3SwapperV1.routeKey(inType: inType, outType: outType)]
                ?? panic("no route for \(inType.identifier) → \(outType.identifier)")
        }

        access(all) fun quoteIn(
            inType: Type,
            outType: Type,
            forDesired: UFix64
        ): Quote {
            let route = self.mustRoute(inType: inType, outType: outType)
            let outToken = route.tokenPath[route.tokenPath.length - 1]
            let inToken = route.tokenPath[0]
            let evmDesired = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forDesired, erc20Address: outToken
            )
            let pathBytes = UniswapV3SwapperV1.buildPathBytes(route: route, exactOutput: true)
            let evmIn = UniswapV3SwapperV1.runQuoter(
                signature: "quoteExactOutput(bytes,uint256)",
                path: pathBytes, amount: evmDesired
            )
            let inCadence = evmIn != nil
                ? FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(evmIn!, erc20Address: inToken)
                : nil
            return Quote(
                inType: inType, outType: outType,
                inAmount: inCadence ?? 0.0,
                outAmount: inCadence != nil ? forDesired : 0.0
            )
        }

        access(all) fun quoteOut(
            inType: Type,
            outType: Type,
            forProvided: UFix64
        ): Quote {
            let route = self.mustRoute(inType: inType, outType: outType)
            let inToken = route.tokenPath[0]
            let outToken = route.tokenPath[route.tokenPath.length - 1]
            let evmProvided = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
                forProvided, erc20Address: inToken
            )
            let pathBytes = UniswapV3SwapperV1.buildPathBytes(route: route, exactOutput: false)
            let evmOut = UniswapV3SwapperV1.runQuoter(
                signature: "quoteExactInput(bytes,uint256)",
                path: pathBytes, amount: evmProvided
            )
            let outCadence = evmOut != nil
                ? FlowEVMBridgeUtils.convertERC20AmountToCadenceAmount(evmOut!, erc20Address: outToken)
                : nil
            return Quote(
                inType: inType, outType: outType,
                inAmount: outCadence != nil ? forProvided : 0.0,
                outAmount: outCadence ?? 0.0
            )
        }

        /// Exact-in: consume entire `inVault`, return `outType` Vault.
        access(all) fun swap(
            quote: Quote?,
            inVault: @{FungibleToken.Vault},
            outType: Type
        ): @{FungibleToken.Vault} {
            let route = self.mustRoute(inType: inVault.getType(), outType: outType)
            let amountOutMin = quote?.outAmount
                ?? self.quoteOut(
                    inType: route.inType, outType: route.outType,
                    forProvided: inVault.balance
                ).outAmount
            return <- UniswapV3SwapperV1.runExactInput(
                route: route, exactVaultIn: <- inVault, amountOutMin: amountOutMin
            )
        }

        /// Exact-out: pull only what's needed from `maxIn` to deliver
        /// `desiredOut` of `outType`. Unspent input stays in `maxIn`.
        access(all) fun swapExactOut(
            maxIn: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
            outType: Type,
            desiredOut: UFix64
        ): @{FungibleToken.Vault} {
            let route = self.mustRoute(inType: maxIn.getType(), outType: outType)
            let q = self.quoteIn(
                inType: route.inType, outType: route.outType,
                forDesired: desiredOut
            )
            assert(q.inAmount > 0.0, message: "swapExactOut: not quotable")
            assert(maxIn.balance >= q.inAmount, message: "swapExactOut: maxIn insufficient")
            return <- UniswapV3SwapperV1.runExactOutput(
                route: route, maxIn: maxIn,
                quotedIn: q.inAmount, desiredOut: desiredOut
            )
        }
    }

    /// Mint a fresh, empty Swapper. Caller registers routes via
    /// `swapper.addRoute(...)` before storing it.
    access(all) fun createSwapper(): Swapper {
        return Swapper()
    }

    /// Top up the contract-account COA with FLOW. The COA pays bridge
    /// fees on every swap; needs periodic funding from outside.
    access(all) fun fundCOA(from: @FlowToken.Vault) {
        let coa = self.coa()
        coa.deposit(from: <- from)
    }

    // -----------------------------------------------------------------
    // Contract-level executor — every Swapper struct runs through these.
    // The contract account's COA is the EVM-side actor for all swaps.
    // -----------------------------------------------------------------

    access(self) fun coa(): auth(EVM.Owner) &EVM.CadenceOwnedAccount {
        return self.coaCapability.borrow() ?? panic("contract COA capability invalid")
    }

    access(contract) fun runExactInput(
        route: Route,
        exactVaultIn: @{FungibleToken.Vault},
        amountOutMin: UFix64
    ): @{FungibleToken.Vault} {
        let coa = self.coa()
        let feeVault <- self.withdrawBridgeFee(coa: coa)
        let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

        let inToken = route.tokenPath[0]
        let outToken = route.tokenPath[route.tokenPath.length - 1]

        let evmAmountIn = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
            exactVaultIn.balance, erc20Address: inToken
        )
        let evmAmountOutMin = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
            amountOutMin, erc20Address: outToken
        )
        coa.depositTokens(vault: <- exactVaultIn, feeProvider: feeVaultRef)

        self.mustCall(coa: coa, to: inToken,
            signature: "approve(address,uint256)",
            args: [self.ROUTER, evmAmountIn], gasLimit: 120_000)

        let params = ExactInputParams(
            path: self.buildPathBytes(route: route, exactOutput: false),
            recipient: coa.address(),
            amountIn: evmAmountIn,
            amountOutMinimum: evmAmountOutMin
        )
        let res = coa.call(
            to: self.ROUTER,
            data: EVM.encodeABIWithSignature(
                "exactInput((bytes,address,uint256,uint256))", [params]
            ),
            gasLimit: 10_000_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(res.status == EVM.Status.successful, message: "exactInput reverted: \(res.errorMessage)")
        let amountOut = EVM.decodeABI(types: [Type<UInt256>()], data: res.data)[0] as! UInt256

        self.mustCall(coa: coa, to: inToken,
            signature: "approve(address,uint256)",
            args: [self.ROUTER, 0 as UInt256], gasLimit: 60_000)

        let outVault <- coa.withdrawTokens(
            type: route.outType, amount: amountOut, feeProvider: feeVaultRef
        )
        self.returnFee(coa: coa, feeVault: <- feeVault)
        return <- outVault
    }

    access(contract) fun runExactOutput(
        route: Route,
        maxIn: auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
        quotedIn: UFix64,
        desiredOut: UFix64
    ): @{FungibleToken.Vault} {
        let coa = self.coa()
        let feeVault <- self.withdrawBridgeFee(coa: coa)
        let feeVaultRef = &feeVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

        let inToken = route.tokenPath[0]
        let outToken = route.tokenPath[route.tokenPath.length - 1]
        let evmAmountInMax = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
            quotedIn, erc20Address: inToken
        )
        let evmDesiredOut = FlowEVMBridgeUtils.convertCadenceAmountToERC20Amount(
            desiredOut, erc20Address: outToken
        )

        let inSlice <- maxIn.withdraw(amount: quotedIn)
        coa.depositTokens(vault: <- inSlice, feeProvider: feeVaultRef)

        let _ = self.mustCall(coa: coa, to: inToken,
            signature: "approve(address,uint256)",
            args: [self.ROUTER, evmAmountInMax], gasLimit: 120_000)

        let params = ExactOutputParams(
            path: self.buildPathBytes(route: route, exactOutput: true),
            recipient: coa.address(),
            amountOut: evmDesiredOut,
            amountInMaximum: evmAmountInMax
        )
        let res = coa.call(
            to: self.ROUTER,
            data: EVM.encodeABIWithSignature(
                "exactOutput((bytes,address,uint256,uint256))", [params]
            ),
            gasLimit: 10_000_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(res.status == EVM.Status.successful, message: "exactOutput reverted: \(res.errorMessage)")
        let actualIn = EVM.decodeABI(types: [Type<UInt256>()], data: res.data)[0] as! UInt256

        self.mustCall(coa: coa, to: inToken,
            signature: "approve(address,uint256)",
            args: [self.ROUTER, 0 as UInt256], gasLimit: 60_000)

        if actualIn < evmAmountInMax {
            let unspent = evmAmountInMax - actualIn
            let refund <- coa.withdrawTokens(
                type: route.inType, amount: unspent, feeProvider: feeVaultRef
            )
            maxIn.deposit(from: <- refund)
        }

        let outVault <- coa.withdrawTokens(
            type: route.outType, amount: evmDesiredOut, feeProvider: feeVaultRef
        )
        self.returnFee(coa: coa, feeVault: <- feeVault)
        return <- outVault
    }

    access(contract) fun runQuoter(signature: String, path: EVM.EVMBytes, amount: UInt256): UInt256? {
        let coa = self.coa()
        let res = coa.dryCall(
            to: self.QUOTER,
            data: EVM.encodeABIWithSignature(signature, [path, amount]),
            gasLimit: 10_000_000,
            value: EVM.Balance(attoflow: 0)
        )
        if res.status != EVM.Status.successful { return nil }
        let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: res.data)
        if decoded.length == 0 { return nil }
        return decoded[0] as! UInt256
    }

    access(contract) fun buildPathBytes(route: Route, exactOutput: Bool): EVM.EVMBytes {
        let nHops = route.feePath.length
        let last = route.tokenPath.length - 1
        var out: [UInt8] = []

        fun appendAddr(_ a: EVM.EVMAddress) {
            let fixed = a.bytes
            var i = 0
            while i < 20 { out.append(fixed[i]); i = i + 1 }
        }
        fun appendFee(_ f: UInt32) {
            pre { f <= 0xFFFFFF: "fee exceeds uint24" }
            out.append(UInt8((f >> 16) & 0xFF))
            out.append(UInt8((f >> 8) & 0xFF))
            out.append(UInt8(f & 0xFF))
        }

        if exactOutput {
            appendAddr(route.tokenPath[last])
            var i = 0
            while i < nHops {
                appendFee(route.feePath[nHops - 1 - i])
                appendAddr(route.tokenPath[last - (i + 1)])
                i = i + 1
            }
        } else {
            appendAddr(route.tokenPath[0])
            var i = 0
            while i < nHops {
                appendFee(route.feePath[i])
                appendAddr(route.tokenPath[i + 1])
                i = i + 1
            }
        }
        return EVM.EVMBytes(value: out)
    }

    access(contract) fun withdrawBridgeFee(
        coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount
    ): @FlowToken.Vault {
        let bal = EVM.Balance(attoflow: 0)
        bal.setFLOW(flow: 2.0 * FlowEVMBridgeUtils.calculateBridgeFee(bytes: 256))
        return <- coa.withdraw(balance: bal)
    }

    access(contract) fun returnFee(
        coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount,
        feeVault: @FlowToken.Vault
    ) {
        if feeVault.balance > 0.0 {
            coa.deposit(from: <- feeVault)
        } else {
            Burner.burn(<- feeVault)
        }
    }

    access(contract) fun mustCall(
        coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount,
        to: EVM.EVMAddress,
        signature: String,
        args: [AnyStruct],
        gasLimit: UInt64
    ) {
        let res = coa.call(
            to: to,
            data: EVM.encodeABIWithSignature(signature, args),
            gasLimit: gasLimit,
            value: EVM.Balance(attoflow: 0)
        )
        assert(
            res.status == EVM.Status.successful,
            message: "EVM call \(signature) reverted: \(res.errorMessage)"
        )
    }

    access(all) view fun routeKey(inType: Type, outType: Type): String {
        return "\(inType.identifier)|\(outType.identifier)"
    }

    init() {
        self.ROUTER = EVM.addressFromString("eEDC6Ff75e1b10B903D9013c358e446a73d35341")
        self.QUOTER = EVM.addressFromString("370A8DF17742867a44e56223EC20D82092242C85")
        self.coaStoragePath = /storage/UniswapV3SwapperV1COA

        let coa <- EVM.createCadenceOwnedAccount()
        self.account.storage.save(<- coa, to: self.coaStoragePath)
        self.coaCapability = self.account.capabilities.storage
            .issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(self.coaStoragePath)
    }
}
