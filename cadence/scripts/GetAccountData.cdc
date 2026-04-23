import "AaveWrapper"

access(all) fun main(owner: Address): AaveWrapper.AccountData {
    let cap = getAccount(owner).capabilities
        .borrow<&{AaveWrapper.PositionPublic}>(AaveWrapper.PositionPublicPath)
        ?? panic("No public Aave position at this account")
    return cap.getUserAccountData()
}
