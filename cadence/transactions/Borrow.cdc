import "AaveWrapper"
import "FungibleToken"
import "FlowToken"

/// Borrows `amount` (ERC20 units) of the asset corresponding to `vaultType`
/// against existing collateral, bridges the proceeds into the signer's
/// `depositPath` vault.
transaction(vaultTypeIdentifier: String, amount: UInt256, depositPath: PublicPath) {
    prepare(signer: auth(BorrowValue) &Account) {
        let position = signer.storage.borrow<auth(AaveWrapper.Manage) &AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        ) ?? panic("No Aave position")

        let feeProvider = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("No FlowToken vault for bridge fee")

        let vaultType = CompositeType(vaultTypeIdentifier)
            ?? panic("Invalid vault type identifier")

        let borrowed <- position.borrow(
            vaultType: vaultType,
            amount: amount,
            feeProvider: feeProvider
        )

        let receiver = getAccount(signer.address).capabilities
            .borrow<&{FungibleToken.Receiver}>(depositPath)
            ?? panic("No receiver at \(depositPath)")
        receiver.deposit(from: <- borrowed)
    }
}
