import PyusdMinter from 0x1e4aa0b87d10b141
import "FungibleToken"
import "FlowToken"
import "FlowYieldVaultsLendingStrategies"
import "FlowYieldVaultsInterfaces"

/// Mint `amount` PYUSD0 and deposit it into the pre-configured lending vault
/// at /storage/LendingTestVault.
transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage.borrow<&{FlowYieldVaultsInterfaces.YieldVault}>(
            from: /storage/LendingTestVault
        ) ?? panic("no test vault — run SetupLendingStrategy first")

        let pyusd <- PyusdMinter.mint(amount: amount)
        vault.deposit(from: <- pyusd)
    }
}
