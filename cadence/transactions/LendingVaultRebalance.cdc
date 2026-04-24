import "FlowYieldVaultsLendingStrategies"

transaction() {
    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage
            .borrow<&FlowYieldVaultsLendingStrategies.LendingStrategyVault>(
                from: /storage/LendingTestVault
            ) ?? panic("no test vault")
        vault.rebalance()
    }
}
