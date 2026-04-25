import "FungibleToken"
import "LendingStrategyV1"

transaction(amount: UFix64) {
    prepare(signer: auth(Storage) &Account) {
        let vault = signer.storage.borrow<auth(FungibleToken.Withdraw) &LendingStrategyV1.Vault>(
            from: /storage/LendingTestVault
        ) ?? panic("no test vault")

        let collateral <- vault.withdraw(amount: amount)

        if let existing = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/withdrawnCollateral
        ) {
            existing.deposit(from: <- collateral)
        } else {
            signer.storage.save(<- collateral, to: /storage/withdrawnCollateral)
        }
    }
}
