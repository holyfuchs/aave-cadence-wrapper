import "LendingStrategyV1"

/// Returns the test vault's position summary (collateral USD, debt USD,
/// yield native units).
access(all) fun main(owner: Address): LendingStrategyV1.PositionSummary {
    let acct = getAuthAccount<auth(BorrowValue) &Account>(owner)
    let vault = acct.storage.borrow<&LendingStrategyV1.Vault>(
        from: /storage/LendingTestVault
    ) ?? panic("no test vault")
    return vault.positionSummary()
}
