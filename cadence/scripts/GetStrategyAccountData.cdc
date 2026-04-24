import "YieldVault"
import "AaveWrapper"

access(all) fun main(owner: Address): AaveWrapper.AccountData {
    let cap = getAccount(owner).capabilities
        .borrow<&{YieldVault.StrategyPublic}>(YieldVault.StrategyPublicPath)
        ?? panic("No public YieldVault strategy")
    return cap.getAccountData()
}
