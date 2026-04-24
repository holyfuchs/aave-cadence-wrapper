import Test
import "AaveV3Pool"
import "FlowYieldVaultsLendingStrategies"
import "FungibleToken"

// -----------------------------------------------------------------------------
// Deployments
// -----------------------------------------------------------------------------

access(all) fun deploy_aave_v3_pool() {
    let err = Test.deployContract(
        name: "AaveV3Pool",
        path: "cadence/contracts/AaveV3Pool.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deploy_aave_v3_price_oracle() {
    let err = Test.deployContract(
        name: "AaveV3PriceOracle",
        path: "cadence/contracts/AaveV3PriceOracle.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deploy_flow_yield_vaults_interfaces() {
    let err = Test.deployContract(
        name: "FlowYieldVaultsInterfaces",
        path: "cadence/contracts/FlowYieldVaultsInterfaces.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deploy_flow_yield_vaults() {
    let err = Test.deployContract(
        name: "FlowYieldVaults",
        path: "cadence/contracts/FlowYieldVaults.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deploy_flow_yield_vaults_early_access() {
    let err = Test.deployContract(
        name: "FlowYieldVaultsEarlyAccess",
        path: "cadence/contracts/FlowYieldVaultsEarlyAccess.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deploy_flow_yield_vaults_lending_strategies() {
    let err = Test.deployContract(
        name: "FlowYieldVaultsLendingStrategies",
        path: "cadence/contracts/FlowYieldVaultsLendingStrategies.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deploy_mock_swapper() {
    let err = Test.deployContract(
        name: "MockSwapper",
        path: "cadence/tests/mocks/MockSwapper.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

/// PyusdMinter is special — it must be deployed onto the FlowEVMBridge
/// account (0x1e4aa0b87d10b141) so it shares access(account) scope with the
/// bridged PYUSD0 contract and can call `mintTokens`.
access(all) fun deploy_pyusd_minter() {
    let bridge = Test.getAccount(0x1e4aa0b87d10b141)
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/DeployPyusdMinter.cdc"),
        authorizers: [bridge.address],
        signers: [bridge],
        arguments: [Test.readFile("cadence/tests/mocks/PyusdMinter.cdc")]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Deploys the whole lending-strategy stack in dependency order.
access(all) fun deploy_lending_strategy_stack() {
    deploy_aave_v3_pool()
    deploy_aave_v3_price_oracle()
    deploy_flow_yield_vaults_interfaces()
    deploy_flow_yield_vaults()
    deploy_flow_yield_vaults_early_access()
    deploy_flow_yield_vaults_lending_strategies()
    deploy_mock_swapper()
}

// -----------------------------------------------------------------------------
// Transactions
// -----------------------------------------------------------------------------

access(all) fun execute_setup_position(account: Test.TestAccount) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/SetupPosition.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: []
    ))
    Test.expect(result, Test.beSucceeded())
}

access(all) fun execute_supply_flow_borrow_pyusd(
    account: Test.TestAccount,
    flowAmount: UFix64,
    pyusd0Amount: UInt256
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/SupplyFlowBorrowPyusd.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: [flowAmount, pyusd0Amount]
    ))
    Test.expect(result, Test.beSucceeded())
}

access(all) fun execute_supply_pyusd_borrow_wflow(
    account: Test.TestAccount,
    pyusdSupplyAmount: UFix64,
    wflowBorrowAmount: UInt256
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/SupplyPyusdBorrowWflow.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: [pyusdSupplyAmount, wflowBorrowAmount]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Like `execute_setup_lending_strategy` but wires a real KittyPunch V3
/// Swapper instead of `MockSwapper`. Requires a fork block with live
/// WFLOW↔PYUSD0 liquidity.
access(all) fun execute_setup_lending_strategy_live(account: Test.TestAccount) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/SetupLendingStrategyLive.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: []
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Constructs a PYUSD0-collateral / FLOW-debt / PYUSD0-yield lending strategy
/// via MockSwapper, mints a yield vault for `account`, seeds the swapper's
/// PYUSD0 liquidity pool with `swapperLiquidity`.
access(all) fun execute_setup_lending_strategy(
    account: Test.TestAccount,
    swapperLiquidity: UFix64
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/SetupLendingStrategy.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: [swapperLiquidity]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Mint `amount` PYUSD0 and deposit it as collateral into the test vault.
access(all) fun execute_lending_vault_deposit(
    account: Test.TestAccount,
    amount: UFix64
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/LendingVaultDeposit.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: [amount]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Withdraw `amount` of collateral from the test vault; returned collateral
/// accumulates at `/storage/withdrawnCollateral` on the signer.
access(all) fun execute_lending_vault_withdraw(
    account: Test.TestAccount,
    amount: UFix64
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/LendingVaultWithdraw.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: [amount]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Poke the vault's `rebalance()` (currently a no-op stub — see TODO in
/// `FlowYieldVaultsLendingStrategies.LendingStrategyVault.rebalance`).
/// Returns the transaction result so the test can decide how to assert.
access(all) fun try_lending_vault_rebalance(
    account: Test.TestAccount
): Test.TransactionResult {
    return Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/LendingVaultRebalance.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: []
    ))
}

// -----------------------------------------------------------------------------
// Scripts
// -----------------------------------------------------------------------------

access(all) fun get_account_data(account: Test.TestAccount): AaveV3Pool.AccountData {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetAccountData.cdc"),
        [account.address]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! AaveV3Pool.AccountData
}

access(all) fun get_vault_balance(account: Test.TestAccount, path: StoragePath): UFix64 {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetVaultBalance.cdc"),
        [account.address, path]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UFix64
}

access(all) fun get_erc20_balance(account: Test.TestAccount, tokenHex: String): UInt256 {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetErc20Balance.cdc"),
        [account.address, tokenHex]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UInt256
}

access(all) fun get_lending_summary(
    account: Test.TestAccount
): FlowYieldVaultsLendingStrategies.PositionSummary {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetLendingSummary.cdc"),
        [account.address]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! FlowYieldVaultsLendingStrategies.PositionSummary
}

/// Balance of the FT vault the withdraw transaction accumulates collateral
/// into at `/storage/withdrawnCollateral`.
access(all) fun get_withdrawn_collateral_balance(account: Test.TestAccount): UFix64 {
    return get_vault_balance(account: account, path: /storage/withdrawnCollateral)
}

/// Returns `[collateralType, debtType, yieldType]` for the test vault.
access(all) fun get_lending_types(account: Test.TestAccount): [Type] {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetLendingTypes.cdc"),
        [account.address]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! [Type]
}
