#test_fork(network: "mainnet", height: 142_691_298)

import Test
import BlockchainHelpers

import "test_helpers.cdc"

/// Like `LendingStrategy_test.cdc` but swaps via the real KittyPunch Uniswap
/// V3 pool instead of `MockSwapper`. Fork block 142_691_298 is where
/// FlowActions' own UniswapV3SwapConnectors fork test runs, so the V3 pools
/// are known to have liquidity there.
///
/// Strategy layout:
///   collateral = bridged PYUSD0
///   debt       = FlowToken (WFLOW on EVM)
///   yield      = MOET (native Cadence FT, borrowed via V3 multi-hop
///                      WFLOW → PYUSD0 → MOET)

access(all) let admin = Test.createAccount()
access(all) var snapshot: UInt64 = 0

access(all) fun beforeEach() { Test.reset(to: snapshot) }

access(all) fun setup() {
    deploy_lending_strategy_stack()
    deploy_pyusd_minter()
    let _ = mintFlow(to: admin, amount: 1000.0)
    snapshot = getCurrentBlockHeight()
}

access(all) fun testDeposit() {
    execute_setup_lending_strategy_live(account: admin)
    execute_lending_vault_deposit(account: admin, amount: 1000.0)

    let types = get_lending_types(account: admin)
    log("collateral: \(types[0].identifier)")
    log("debt:       \(types[1].identifier)")
    log("yield:      \(types[2].identifier)")
    Test.assert(
        types[0] != types[2],
        message: "yield must be distinct from collateral"
    )

    let s = get_lending_summary(account: admin)
    log("after deposit: \(s.collateral) / \(s.debt) / \(s.yield)")
    Test.assert(s.collateral > 900.0, message: "expected ~$1000 collateral")
    Test.assert(s.debt > 0.0, message: "expected non-zero debt")
    Test.assert(s.yield > 0.0, message: "expected non-zero yield — real V3 swap executed")
}

/// Withdraw 500 PYUSD0 collateral: the strategy swaps MOET → WFLOW via the
/// real V3 multi-hop (MOET → PYUSD0 → WFLOW), repays the pro-rata slice of
/// debt, and pulls 500 PYUSD0 back from Aave to the caller.
access(all) fun testWithdraw() {
    execute_setup_lending_strategy_live(account: admin)
    execute_lending_vault_deposit(account: admin, amount: 1000.0)

    let before = get_lending_summary(account: admin)
    log("before withdraw: \(before.collateral) / \(before.debt) / \(before.yield)")
    Test.assert(before.debt > 0.0, message: "need outstanding debt to unwind")

    execute_lending_vault_withdraw(account: admin, amount: 500.0)

    let after = get_lending_summary(account: admin)
    log("after withdraw:  \(after.collateral) / \(after.debt) / \(after.yield)")
    Test.assert(after.collateral < before.collateral, message: "collateral did not decrease")
    Test.assert(after.debt < before.debt, message: "debt did not decrease")
    Test.assert(after.yield < before.yield, message: "yield should fund the repay")

    Test.assertEqual(500.0, get_withdrawn_collateral_balance(account: admin))
}

/// Rebalance is a stub right now (TODO in
/// `LendingStrategyVault.rebalance`). Just exercise the entrypoint —
/// failures are logged, not fatal.
access(all) fun testRebalance() {
    execute_setup_lending_strategy_live(account: admin)
    execute_lending_vault_deposit(account: admin, amount: 1000.0)

    let before = get_lending_summary(account: admin)
    let result = try_lending_vault_rebalance(account: admin)
    if result.status == Test.ResultStatus.succeeded {
        log("rebalance succeeded")
    } else {
        let msg = result.error?.message ?? "unknown"
        log("rebalance failed: ".concat(msg))
    }
    let after = get_lending_summary(account: admin)
    log("rebalance before: \(before.debt) → after: \(after.debt)")
}
