#test_fork(network: "mainnet", height: 149_391_841)

import Test
import BlockchainHelpers

import "test_helpers.cdc"

access(all) let admin = Test.createAccount()
access(all) var snapshot: UInt64 = 0

access(all) fun beforeEach() { Test.reset(to: snapshot) }

access(all) fun setup() {
    deploy_lending_strategy_stack()
    deploy_pyusd_minter()
    let _ = mintFlow(to: admin, amount: 1000.0)
    snapshot = getCurrentBlockHeight()
}

/// Deposit 1000 PYUSD0 collateral. Vault supplies it to MORE Markets,
/// borrows 50% of available FLOW headroom, swaps FLOW → PYUSD0 yield.
access(all) fun testDeposit() {
    execute_setup_lending_strategy(account: admin, swapperLiquidity: 10000.0)
    execute_lending_vault_deposit(account: admin, amount: 1000.0)

    let s = get_lending_summary(account: admin)
    Test.assert(s.collateral > 900.0, message: "expected ~$1000 collateral")
    Test.assert(s.debt > 0.0, message: "expected non-zero debt")
    Test.assert(s.yield > 0.0, message: "expected non-zero yield")
}

/// Full withdraw unwind: yield → debt swap, pro-rata repay, collateral pull,
/// bridge out. Caller receives exactly `amount` collateral.
access(all) fun testWithdraw() {
    execute_setup_lending_strategy(account: admin, swapperLiquidity: 10000.0)
    execute_lending_vault_deposit(account: admin, amount: 1000.0)

    let before = get_lending_summary(account: admin)
    Test.assert(before.debt > 0.0, message: "need outstanding debt to unwind")

    execute_lending_vault_withdraw(account: admin, amount: 500.0)

    let after = get_lending_summary(account: admin)
    Test.assert(after.collateral < before.collateral, message: "collateral did not decrease")
    Test.assert(after.debt < before.debt, message: "debt did not decrease")
    Test.assert(after.yield < before.yield, message: "yield should fund the repay")

    Test.assertEqual(500.0, get_withdrawn_collateral_balance(account: admin))
}
