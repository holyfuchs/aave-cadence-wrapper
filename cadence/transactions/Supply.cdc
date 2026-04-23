import "AaveWrapper"
import "FungibleToken"
import "FlowToken"

/// Withdraws `amount` of the signer's `vaultPath` balance and supplies it to
/// the Aave position. The signer's FlowToken vault pays the bridge fee.
transaction(vaultPath: StoragePath, amount: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let position = signer.storage.borrow<auth(AaveWrapper.Manage) &AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        ) ?? panic("No Aave position — run SetupPosition first")

        let src = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>(
            from: vaultPath
        ) ?? panic("No provider vault at \(vaultPath)")

        let feeProvider = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("No FlowToken vault for bridge fee")

        let vault <- src.withdraw(amount: amount)
        position.supply(vault: <- vault, feeProvider: feeProvider)
    }
}
