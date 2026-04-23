import "AaveWrapper"

/// Creates a MORE Markets (Aave v3) position resource under the signer's storage,
/// using the mainnet Pool proxy baked into AaveWrapper.
transaction() {
    prepare(signer: auth(BorrowValue, SaveValue, Capabilities) &Account) {
        if signer.storage.borrow<&AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        ) != nil {
            return
        }

        let position <- AaveWrapper.createMainnetPosition()
        signer.storage.save(<- position, to: AaveWrapper.PositionStoragePath)

        let cap = signer.capabilities.storage.issue<&{AaveWrapper.PositionPublic}>(
            AaveWrapper.PositionStoragePath
        )
        signer.capabilities.publish(cap, at: AaveWrapper.PositionPublicPath)
    }
}
