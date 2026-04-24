import "PyusdMinter"
import "FungibleToken"
import "FlowToken"
import "MOET"
import "EVM"
import "DeFiActions"
import "DeFiActionsUtils"
import "UniswapV3SwapConnectors"
import "FlowYieldVaultsLendingStrategies"
import "FlowYieldVaultsInterfaces"

/// Same as SetupLendingStrategy.cdc but wires a *real* KittyPunch Uniswap V3
/// Swapper for debt↔yield instead of `MockSwapper`. Needs a fork block where
/// a WFLOW↔PYUSD0 V3 pool has real liquidity (e.g. 142_691_298 — the block
/// the FlowActions' UniswapV3SwapConnectors fork test runs against).
///
/// Addresses (KittyPunch, FlowEVM mainnet):
///   Factory: 0xca6d7Bb03334bBf135902e1d919a5feccb461632
///   Router:  0xeEDC6Ff75e1b10B903D9013c358e446a73d35341
///   Quoter:  0x370A8DF17742867a44e56223EC20D82092242C85
///   WFLOW:   0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
///   PYUSD0:  0x99aF3EeA856556646C98c8B9b2548Fe815240750
transaction() {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let pyusd0Type = CompositeType(
            "A.1e4aa0b87d10b141.EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.Vault"
        ) ?? panic("PYUSD0 bridged type not registered")

        // The Swapper needs an auth(EVM.Owner) COA capability — it calls
        // the V3 router directly. Issue a Capability to the signer's COA
        // (assumes /storage/evm holds a COA; if not, create one first).
        if signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm) == nil {
            let coa <- EVM.createCadenceOwnedAccount()
            signer.storage.save(<- coa, to: /storage/evm)
        }
        // Fund the swapper's COA with FLOW for EVM gas + bridge fees. The V3
        // Swapper uses `coa.withdraw` internally to pay bridge fees during
        // the Cadence↔EVM round-trip.
        let flowProvider = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!
        let gasFund <- flowProvider.withdraw(amount: 50.0)
        let coaRef = signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm)!
        coaRef.deposit(from: <- (gasFund as! @FlowToken.Vault))

        let coaCap = signer.capabilities.storage
            .issue<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(/storage/evm)

        let factory = EVM.addressFromString("ca6d7Bb03334bBf135902e1d919a5feccb461632")
        let router  = EVM.addressFromString("eEDC6Ff75e1b10B903D9013c358e446a73d35341")
        let quoter  = EVM.addressFromString("370A8DF17742867a44e56223EC20D82092242C85")
        let wflow   = EVM.addressFromString("d3bF53DAC106A0290B0483EcBC89d40FcC961f3e")
        let pyusd0  = EVM.addressFromString("99aF3EeA856556646C98c8B9b2548Fe815240750")
        let moet    = EVM.addressFromString("213979bB8A9A86966999b3AA797C1fcf3B967ae2")

        // debtYieldSwapper: WFLOW (debt) → MOET (yield) via multi-hop
        // through PYUSD0. No direct WFLOW/MOET V3 pool on KittyPunch, so
        // we route WFLOW → PYUSD0 (fee 3000) → MOET (fee 100).
        let debtYieldSwapper = UniswapV3SwapConnectors.Swapper(
            factoryAddress: factory,
            routerAddress: router,
            quoterAddress: quoter,
            tokenPath: [wflow, pyusd0, moet],
            feePath: [3000 as UInt32, 100 as UInt32],
            inVault: Type<@FlowToken.Vault>(),
            outVault: Type<@MOET.Vault>(),
            coaCapability: coaCap,
            uniqueID: nil
        )

        // collateralDebtSwapper: PYUSD0 (collateral) → WFLOW (debt) direct.
        let collateralDebtSwapper = UniswapV3SwapConnectors.Swapper(
            factoryAddress: factory,
            routerAddress: router,
            quoterAddress: quoter,
            tokenPath: [pyusd0, wflow],
            feePath: [3000 as UInt32],
            inVault: pyusd0Type,
            outVault: Type<@FlowToken.Vault>(),
            coaCapability: coaCap,
            uniqueID: nil
        )

        let strategy = FlowYieldVaultsLendingStrategies.createLendingStrategy(
            collateralDebtSwapper: collateralDebtSwapper,
            debtYieldSwapper: debtYieldSwapper,
            yieldTokenType: Type<@MOET.Vault>(),
            debtTokenType: Type<@FlowToken.Vault>(),
            collateralTokenType: pyusd0Type,
            minHealth: 1.2,
            maxHealth: 2.0
        )

        let vault <- strategy.createYieldVault(name: "pyusd-flow-live")
        signer.storage.save(<- vault, to: /storage/LendingTestVault)
    }
}
