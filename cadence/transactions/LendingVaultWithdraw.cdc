import "FungibleToken"
import "FlowYieldVaultsLendingStrategies"
import "FlowYieldVaultsInterfaces"

/// Withdraw `amount` of collateral from the test vault at
/// /storage/LendingTestVault; save returned collateral at
/// /storage/withdrawnCollateral for the test to inspect.
transaction(amount: UFix64) {
    prepare(signer: auth(Storage) &Account) {
        let vault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FlowYieldVaultsInterfaces.YieldVault}>(
            from: /storage/LendingTestVault
        ) ?? panic("no test vault")

        let collateral <- vault.withdraw(amount: amount)

        // Merge with any previously-withdrawn collateral so the test can
        // read the cumulative balance from one path.
        if let existing = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/withdrawnCollateral
        ) {
            existing.deposit(from: <- collateral)
        } else {
            signer.storage.save(<- collateral, to: /storage/withdrawnCollateral)
        }
    }
}
