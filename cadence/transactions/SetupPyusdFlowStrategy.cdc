import "YieldVault"
import "FungibleToken"
import "FlowToken"

/// Create a Strategy that takes bridged PYUSD0 as collateral and borrows
/// FlowToken (WFLOW under the hood) as its debt token.
transaction() {
    prepare(signer: auth(BorrowValue, SaveValue, Capabilities) &Account) {
        if signer.storage.borrow<&YieldVault.Strategy>(
            from: YieldVault.StrategyStoragePath
        ) != nil {
            return
        }

        let collateralType = CompositeType(
            "A.1e4aa0b87d10b141.EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.Vault"
        ) ?? panic("Invalid PYUSD0 bridged vault type")
        let debtType = Type<@FlowToken.Vault>()

        let emptyDebtVault <- FlowToken.createEmptyVault(vaultType: debtType)

        let feeProvider = signer.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(/storage/flowTokenVault)

        let strategy <- YieldVault.createStrategy(
            collateralType: collateralType,
            debtType: debtType,
            emptyDebtVault: <- emptyDebtVault,
            feeProvider: feeProvider
        )
        signer.storage.save(<- strategy, to: YieldVault.StrategyStoragePath)

        let cap = signer.capabilities.storage.issue<&{YieldVault.StrategyPublic}>(
            YieldVault.StrategyStoragePath
        )
        signer.capabilities.publish(cap, at: YieldVault.StrategyPublicPath)
    }
}
