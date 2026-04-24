import "YieldVault"

/// Anyone can call this. Strategy decides internally whether to repay based
/// on the health-factor threshold baked into the YieldVault contract.
transaction() {
    prepare(signer: &Account) {
        let cap = getAccount(signer.address).capabilities
            .borrow<&{YieldVault.StrategyPublic}>(YieldVault.StrategyPublicPath)
            ?? panic("No public YieldVault strategy")
        let _ = cap.rebalance()
    }
}
