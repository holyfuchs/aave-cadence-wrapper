import "FungibleToken"
import "FlowToken"
import "MOREV1"
import "UniswapV3SwapperV1"

/// One-time fixture funding for the lending block stack. Tops up the
/// contract-account COAs / fee vaults that pay bridge fees on every
/// Cadence↔EVM round-trip:
///   * `UniswapV3SwapperV1`'s contract COA — covers swap-leg bridge fees.
///   * `MOREV1`'s `/storage/flowTokenVault` — covers supply/borrow/repay/
///     withdraw bridge fees.
///
/// Run once after deployment. `swapperFlow` and `moreFlow` are the FLOW
/// amounts to deposit into each.
transaction(swapperFlow: UFix64, moreFlow: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let provider = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("signer has no FlowToken vault")

        let swapperFund <- provider.withdraw(amount: swapperFlow) as! @FlowToken.Vault
        UniswapV3SwapperV1.fundCOA(from: <- swapperFund)

        let moreFund <- provider.withdraw(amount: moreFlow)
        MOREV1.fundFees(from: <- moreFund)
    }
}
