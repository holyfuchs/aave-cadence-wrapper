import "YieldVault"

access(all) fun main(owner: Address): UFix64 {
    let cap = getAccount(owner).capabilities
        .borrow<&{YieldVault.StrategyPublic}>(YieldVault.StrategyPublicPath)
        ?? panic("No public YieldVault strategy at this account")
    return cap.debtBalance()
}
