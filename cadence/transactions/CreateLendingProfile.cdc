import "FungibleToken"
import "FlowToken"
import "MOET"
import "EVM"
import "UniswapV3SwapperV1"
import "LendingStrategyV1"
import "FlowYieldVaultsInterfaces"
import "FlowYieldVaultsRegistry"

/// Create a `LendingStrategyV1.Profile` for the PYUSD0/WFLOW/MOET
/// strategy and register it in `FlowYieldVaultsRegistry` under `name`.
/// Saves the profile at `/storage/lendingStrategyV1Profile` on the
/// signer; signer must be the registry's contract account (the only
/// account that can borrow the registry's `Manager`).
///
/// `minHealth` / `maxHealth` are passed in by the caller. Token types
/// and V3 routes are intrinsic to this strategy variant.
transaction(name: String, minHealth: UFix64, maxHealth: UFix64) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let pyusd0Type = CompositeType(
            "A.1e4aa0b87d10b141.EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.Vault"
        ) ?? panic("PYUSD0 bridged type not registered")

        let bridgeAcct = getAccount(0x1e4aa0b87d10b141)
        let pyusd0FT = bridgeAcct.contracts
            .borrow<&{FungibleToken}>(name: "EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750")
            ?? panic("PYUSD0 FT contract not borrowable")
        let coll <- pyusd0FT.createEmptyVault(vaultType: pyusd0Type)
        let debt <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        let yield <- MOET.createEmptyVault(vaultType: Type<@MOET.Vault>())

        let profile <- LendingStrategyV1.createProfile(
            collateralToken: <- coll,
            debtToken: <- debt,
            yieldToken: <- yield,
            minHealth: minHealth,
            maxHealth: maxHealth
        )

        // Register the V3 routes the strategy needs.
        let wflow  = EVM.addressFromString("d3bF53DAC106A0290B0483EcBC89d40FcC961f3e")
        let pyusd0 = EVM.addressFromString("99aF3EeA856556646C98c8B9b2548Fe815240750")
        let moet   = EVM.addressFromString("213979bB8A9A86966999b3AA797C1fcf3B967ae2")

        let admin = &profile as auth(LendingStrategyV1.Admin) &LendingStrategyV1.Profile

        // WFLOW → MOET via WFLOW(3000)→PYUSD0(100)→MOET
        admin.addSwapRoute(UniswapV3SwapperV1.Route(
            inType: Type<@FlowToken.Vault>(),
            outType: Type<@MOET.Vault>(),
            tokenPath: [wflow, pyusd0, moet],
            feePath: [3000 as UInt32, 100 as UInt32]
        ))
        // MOET → WFLOW via MOET(100)→PYUSD0(3000)→WFLOW
        admin.addSwapRoute(UniswapV3SwapperV1.Route(
            inType: Type<@MOET.Vault>(),
            outType: Type<@FlowToken.Vault>(),
            tokenPath: [moet, pyusd0, wflow],
            feePath: [100 as UInt32, 3000 as UInt32]
        ))

        let storagePath = StoragePath(identifier: "lendingStrategyV1Profile_\(name)")!
        let publicPath  = PublicPath(identifier: "lendingStrategyV1Profile_\(name)")!
        signer.storage.save(<- profile, to: storagePath)

        // Two capabilities target the same path:
        //   - interface-typed → handed to the registry under `name`
        //   - strategy-typed  → published at a public path so vaults
        //                       can store a `Capability<&Profile>`
        let ifaceCap = signer.capabilities.storage
            .issue<&{FlowYieldVaultsInterfaces.Profile}>(storagePath)
        let strategyCap = signer.capabilities.storage
            .issue<&LendingStrategyV1.Profile>(storagePath)
        signer.capabilities.publish(strategyCap, at: publicPath)

        let mgr = signer.storage.borrow<auth(FlowYieldVaultsRegistry.Admin) &FlowYieldVaultsRegistry.Manager>(
            from: FlowYieldVaultsRegistry.managerStoragePath
        ) ?? panic("signer doesn't hold the registry Manager")
        mgr.register(name: name, cap: ifaceCap)
    }
}
