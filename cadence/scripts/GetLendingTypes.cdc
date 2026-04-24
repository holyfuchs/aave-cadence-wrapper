import "FlowYieldVaultsLendingStrategies"

/// Returns `[collateralType, debtType, yieldType]` for the test vault.
access(all) fun main(owner: Address): [Type] {
    let acct = getAuthAccount<auth(BorrowValue) &Account>(owner)
    let vault = acct.storage
        .borrow<&FlowYieldVaultsLendingStrategies.LendingStrategyVault>(
            from: /storage/LendingTestVault
        ) ?? panic("no test vault")
    return [vault.collateralType(), vault.debtType(), vault.yieldType()]
}
