import "AaveV3Pool"

/// Creates a MORE Markets position under the signer. Bridge fees are paid
/// from the AaveV3Pool *contract account's* FlowToken vault, not the
/// signer's — keep that contract account funded.
transaction() {
    prepare(signer: auth(BorrowValue, SaveValue, Capabilities) &Account) {
        if signer.storage.borrow<&AaveV3Pool.Position>(
            from: AaveV3Pool.PositionStoragePath
        ) != nil {
            return
        }

        let position <- AaveV3Pool.createMainnetPosition()
        signer.storage.save(<- position, to: AaveV3Pool.PositionStoragePath)

        let cap = signer.capabilities.storage.issue<&{AaveV3Pool.PositionPublic}>(
            AaveV3Pool.PositionStoragePath
        )
        signer.capabilities.publish(cap, at: AaveV3Pool.PositionPublicPath)
    }
}
