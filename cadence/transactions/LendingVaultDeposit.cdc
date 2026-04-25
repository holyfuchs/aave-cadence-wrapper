import PyusdMinter from 0x1e4aa0b87d10b141
import "LendingStrategyV1"

/// Mint `amount` PYUSD0 and deposit into the test Vault at
/// `/storage/LendingTestVault`. The Vault self-resolves its Profile via
/// its stored `profileCap`.
transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage.borrow<&LendingStrategyV1.Vault>(
            from: /storage/LendingTestVault
        ) ?? panic("no test vault — run CreateLendingVault first")
        vault.deposit(from: <- PyusdMinter.mint(amount: amount))
    }
}
