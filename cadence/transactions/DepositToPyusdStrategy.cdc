import PyusdMinter from 0x1e4aa0b87d10b141
import "YieldVault"
import "FungibleToken"
import "FlowToken"

transaction(pyusdAmount: UFix64, borrowAmount: UInt256) {
    prepare(signer: auth(BorrowValue) &Account) {
        let strategy = signer.storage.borrow<auth(YieldVault.Manage) &YieldVault.Strategy>(
            from: YieldVault.StrategyStoragePath
        ) ?? panic("No YieldVault strategy — run SetupPyusdFlowStrategy first")

        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!

        strategy.fundGas(from: <- flowVault.withdraw(amount: 10.0))

        let pyusdVault <- PyusdMinter.mint(amount: pyusdAmount)
        strategy.deposit(vault: <- pyusdVault, borrowAmount: borrowAmount)
    }
}
