import "AaveWrapper"
import "FungibleToken"
import "FlowToken"

/// Creates a MORE Markets position resource at the signer's storage, wired to
/// the signer's own FlowToken vault as the bridge fee provider.
transaction() {
    prepare(signer: auth(BorrowValue, SaveValue, Capabilities) &Account) {
        if signer.storage.borrow<&AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        ) != nil {
            return
        }

        let feeProvider = signer.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(/storage/flowTokenVault)

        let position <- AaveWrapper.createMainnetPosition(feeProvider: feeProvider)
        signer.storage.save(<- position, to: AaveWrapper.PositionStoragePath)

        let cap = signer.capabilities.storage.issue<&{AaveWrapper.PositionPublic}>(
            AaveWrapper.PositionStoragePath
        )
        signer.capabilities.publish(cap, at: AaveWrapper.PositionPublicPath)
    }
}
