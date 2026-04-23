import "AaveWrapper"
import "EVM"

/// Returns the ERC20 balance that the account's AaveWrapper.Position COA holds
/// for `tokenHex` (20-byte hex, no 0x prefix).
access(all) fun main(owner: Address, tokenHex: String): UInt256 {
    let cap = getAccount(owner).capabilities
        .borrow<&{AaveWrapper.PositionPublic}>(AaveWrapper.PositionPublicPath)
        ?? panic("No public Aave position at this account")
    return cap.erc20BalanceOf(token: EVM.addressFromString(tokenHex))
}
