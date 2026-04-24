#test_fork(network: "mainnet", height: 149_391_841)

import Test
import BlockchainHelpers
import "AaveWrapper"

import "test_helpers.cdc"

/// Fork integration test for AaveWrapper against MORE Markets on FlowEVM.
/// Runs against real mainnet state at block 149_391_841.

access(all) let admin = Test.createAccount()
access(all) var snapshot: UInt64 = 0

access(all) fun beforeEach() { Test.reset(to: snapshot) }

access(all) fun setup() {
    deploy_aave_wrapper()
    deploy_yield_vault()
    snapshot = getCurrentBlockHeight()
}

/// Sanity: the compiled-in Pool constant matches the deployed MORE Markets proxy.
access(all) fun testMainnetPoolConstant() {
    let expected = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d"
    let actual = "0x\(AaveWrapper.POOL_MAINNET.toString())"
    Test.assertEqual(expected.toLower(), actual.toLower())
}

/// A brand-new COA has no supplies/borrows, so every field is 0 except
/// `healthFactor` which Aave returns as uint256.max.
access(all) fun testFreshPositionAccountData() {
    execute_setup_position(account: admin)

    let data = get_account_data(account: admin)
    Test.assertEqual(0 as UInt256, data.totalCollateralBase)
    Test.assertEqual(0 as UInt256, data.totalDebtBase)
    Test.assertEqual(0 as UInt256, data.availableBorrowsBase)
    Test.assertEqual(UInt256.max, data.healthFactor)
}

/// Supply WFLOW (wrapped from native FLOW) → borrow PYUSD0.
access(all) fun testSupplyWFLOWBorrowPYUSD0() {
    let _ = mintFlow(to: admin, amount: 1000.0)
    execute_setup_position(account: admin)
    execute_supply_flow_borrow_pyusd(
        account: admin,
        flowAmount: 500.0,
        pyusd0Amount: 1_000_000 // 1 PYUSD0 (6 decimals)
    )

    let data = get_account_data(account: admin)
    log(data)
    Test.assert(data.totalCollateralBase > 0, message: "no collateral")
    Test.assert(data.totalDebtBase > 0, message: "no debt")
    Test.assert(data.healthFactor < UInt256.max, message: "health factor not reduced")

    // The borrowed PYUSD0 was bridged back to Cadence as a FungibleToken.Vault
    // at /storage/pyusd0Vault — 1 PYUSD0 (6 decimals) == 1.0 UFix64.
    let pyusdVaultBalance = get_vault_balance(
        account: admin,
        path: /storage/pyusd0Vault
    )
    Test.assertEqual(1.0, pyusdVaultBalance)
}

/// YieldVault: PYUSD0 collateral, FlowToken debt. Mint 1000 PYUSD0, deposit
/// into the strategy, borrow 0.1 WFLOW (bridged back as FlowToken). The
/// FlowToken stays inside the strategy resource and the caller never sees it.
access(all) fun testYieldVaultPyusdToFlow() {
    let _ = mintFlow(to: admin, amount: 100.0)
    deploy_pyusd_minter()
    execute_setup_pyusd_flow_strategy(account: admin)
    execute_deposit_to_pyusd_strategy(
        account: admin,
        pyusdAmount: 1000.0,
        borrowAmount: 100_000_000_000_000_000 // 0.1 WFLOW (18 decimals)
    )

    // 0.1 WFLOW → 0.1 FlowToken after the bridge round-trip.
    Test.assertEqual(0.1, get_strategy_debt(account: admin))
}

/// Rebalance: deposit enough debt that HF drops below the contract threshold
/// (1.5e18), then anyone can call rebalance() to trigger a 50% debt pay-down.
access(all) fun testYieldVaultRebalance() {
    let _ = mintFlow(to: admin, amount: 100.0)
    deploy_pyusd_minter()
    execute_setup_pyusd_flow_strategy(account: admin)
    // ~$10 of collateral → borrow near max so HF drops under 1.5.
    // 1000 PYUSD0 ≈ $1000. With ~80% LTV on stables and FLOW ≈ $0.40,
    // borrowing ~1900 FLOW ($760) puts HF near ~1.09.
    // FLOW ~= $0.038. Collateral ~$1000, liquidation threshold 83%. Borrowing
    // ~16000 FLOW ($608) puts HF near 1.36 — below the 1.5 trigger.
    execute_deposit_to_pyusd_strategy(
        account: admin,
        pyusdAmount: 1000.0,
        borrowAmount: 16_000_000_000_000_000_000_000 // 16000 WFLOW
    )
    let before = get_strategy_debt(account: admin)
    Test.assertEqual(16000.0, before)

    let accountBefore = get_strategy_account_data(account: admin)
    log("HF before rebalance: \(accountBefore.healthFactor)")
    log("totalDebtBase:       \(accountBefore.totalDebtBase)")
    log("totalCollateralBase: \(accountBefore.totalCollateralBase)")

    // Public rebalance — anyone can call.
    execute_rebalance_strategy(account: admin)
    let after = get_strategy_debt(account: admin)
    log("debt after rebalance: \(after)")
    Test.assert(after < before, message: "debt did not decrease")
}

/// Mirror direction: supply PYUSD0 → borrow WFLOW. Fabricates PYUSD0 by
/// deploying a helper to the bridge account so it can call the bridged FT's
/// `access(account) mintTokens`.
access(all) fun testSupplyPYUSDBorrowWFLOW() {
    let _ = mintFlow(to: admin, amount: 100.0)
    execute_setup_position(account: admin)
    deploy_pyusd_minter()
    execute_supply_pyusd_borrow_wflow(
        account: admin,
        pyusdSupplyAmount: 1000.0,
        wflowBorrowAmount: 1_000_000_000_000_000_000 // 1 WFLOW (18 decimals)
    )

    let data = get_account_data(account: admin)
    Test.assert(data.totalCollateralBase > 0, message: "no collateral")
    Test.assert(data.totalDebtBase > 0, message: "no debt")
}
