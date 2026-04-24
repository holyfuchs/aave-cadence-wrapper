import "FlowYieldVaultsLendingStrategies"

/// Returns the test vault's position summary (collateral USD, debt USD,
/// yield native units).
access(all) fun main(owner: Address): FlowYieldVaultsLendingStrategies.PositionSummary {
    let acct = getAuthAccount<auth(BorrowValue) &Account>(owner)
    let vault = acct.storage
        .borrow<&FlowYieldVaultsLendingStrategies.LendingStrategyVault>(
            from: /storage/LendingTestVault
        ) ?? panic("no test vault")
    return vault.positionSummary()
}
