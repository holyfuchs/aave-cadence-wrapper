#test_fork(network: "mainnet", height: 149_391_841)

import Test
import BlockchainHelpers
import "AaveV3Pool"

import "test_helpers.cdc"

/// Fork integration test for AaveV3Pool against MORE Markets on FlowEVM.
/// Runs against real mainnet state at block 149_391_841.

access(all) let admin = Test.createAccount()
access(all) var snapshot: UInt64 = 0

access(all) fun beforeEach() { Test.reset(to: snapshot) }

access(all) fun setup() {
    deploy_aave_v3_pool()
    snapshot = getCurrentBlockHeight()
}

/// Sanity: the compiled-in Pool constant matches the deployed MORE Markets proxy.
access(all) fun testMainnetPoolConstant() {
    let expected = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d"
    let actual = "0x\(AaveV3Pool.POOL_MAINNET.toString())"
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

/// Raw-EVM path: wrap FLOW → WFLOW manually, supplyEVM, then use the
/// vault-shaped `borrow` to get PYUSD0 out as a Cadence vault.
access(all) fun testSupplyWFLOWBorrowPYUSD0() {
    let _ = mintFlow(to: admin, amount: 1000.0)
    execute_setup_position(account: admin)
    execute_supply_flow_borrow_pyusd(
        account: admin,
        flowAmount: 500.0,
        pyusd0Amount: 1_000_000 // 1 PYUSD0 (6 decimals)
    )

    let data = get_account_data(account: admin)
    Test.assert(data.totalCollateralBase > 0, message: "no collateral")
    Test.assert(data.totalDebtBase > 0, message: "no debt")
    Test.assert(data.healthFactor < UInt256.max, message: "health factor not reduced")

    // 1 PYUSD0 (6 decimals) round-trips to 1.0 UFix64 via the bridge.
    let pyusdVaultBalance = get_vault_balance(
        account: admin,
        path: /storage/pyusd0Vault
    )
    Test.assertEqual(1.0, pyusdVaultBalance)
}

/// Vault path: mint PYUSD0, `deposit` bridges + supplies, `setUseAsCollateral`
/// flips the asset, then `borrowEVM` lands WFLOW ERC20 in the COA.
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
