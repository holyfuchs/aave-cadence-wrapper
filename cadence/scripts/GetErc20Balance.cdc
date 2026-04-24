import "AaveV3Pool"
import "EVM"

access(all) fun main(owner: Address, tokenHex: String): UInt256 {
    let cap = getAccount(owner).capabilities
        .borrow<&{AaveV3Pool.PositionPublic}>(AaveV3Pool.PositionPublicPath)
        ?? panic("No public AaveV3Pool position at this account")
    return cap.erc20BalanceOf(token: EVM.addressFromString(tokenHex))
}
