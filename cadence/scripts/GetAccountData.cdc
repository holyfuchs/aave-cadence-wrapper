import "AaveV3Pool"

access(all) fun main(owner: Address): AaveV3Pool.AccountData {
    let cap = getAccount(owner).capabilities
        .borrow<&{AaveV3Pool.PositionPublic}>(AaveV3Pool.PositionPublicPath)
        ?? panic("No public AaveV3Pool position at this account")
    return cap.getUserAccountData()
}
