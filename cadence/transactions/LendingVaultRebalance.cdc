import "LendingStrategyV1"

transaction() {
    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage.borrow<&LendingStrategyV1.Vault>(
            from: /storage/LendingTestVault
        ) ?? panic("no test vault")
        vault.rebalance()
    }
}
