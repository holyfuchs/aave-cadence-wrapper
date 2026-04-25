import Test
import "LendingStrategyV1"

// -----------------------------------------------------------------------------
// Deployments
// -----------------------------------------------------------------------------

access(all) fun deploy(_ name: String, _ path: String) {
    let err = Test.deployContract(name: name, path: path, arguments: [])
    Test.expect(err, Test.beNil())
}

access(all) fun deploy_pass_holder_mock() {
    deploy("PassHolderMock", "cadence/tests/mocks/PassHolderMock.cdc")
}

access(all) fun deploy_vault_holder_mock() {
    deploy("VaultHolderMock", "cadence/tests/mocks/VaultHolderMock.cdc")
}

/// Deploys blocks + interfaces + registry + strategy.
access(all) fun deploy_lending_strategy_stack() {
    deploy("LimitedAccessV1", "cadence/contracts/blocks/LimitedAccessV1.cdc")
    deploy("MOREV1", "cadence/contracts/blocks/MOREV1.cdc")
    deploy("MOREOracleV1", "cadence/contracts/blocks/MOREOracleV1.cdc")
    deploy("UniswapV3SwapperV1", "cadence/contracts/blocks/swappers/UniswapV3SwapperV1.cdc")
    deploy("FlowYieldVaultsInterfaces", "cadence/contracts/FlowYieldVaultsInterfaces.cdc")
    deploy("FlowYieldVaultsRegistry", "cadence/contracts/FlowYieldVaultsRegistry.cdc")
    deploy("LendingStrategyV1", "cadence/contracts/strategies/LendingStrategyV1.cdc")
}


/// PyusdMinter is special — it must be deployed onto the FlowEVMBridge
/// account (0x1e4aa0b87d10b141) so it shares access(account) scope with
/// the bridged PYUSD0 contract and can call `mintTokens`.
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

// -----------------------------------------------------------------------------
// Transactions
// -----------------------------------------------------------------------------

/// One-time fixture funding for the block stack — tops up
/// `UniswapV3SwapperV1`'s contract COA + `MOREV1`'s fee vault so swaps
/// and Aave round-trips can pay bridge fees.
access(all) fun execute_fund_lending_blocks(
    account: Test.TestAccount,
    swapperFlow: UFix64,
    moreFlow: UFix64
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/FundLendingBlocks.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: [swapperFlow, moreFlow]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Create + register a Profile (PYUSD0/WFLOW/MOET) at
/// /storage/lendingStrategyV1Profile, with the supplied health band.
/// Returns the registry's contract account — the only account that can
/// register profiles (holds the Manager).
access(all) fun get_registry_admin(): Test.TestAccount {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetRegistryAdmin.cdc"), []
    )
    Test.expect(result, Test.beSucceeded())
    return Test.getAccount(result.returnValue! as! Address)
}

/// Profile creation is signed by the registry's contract account.
access(all) fun execute_create_lending_profile(
    name: String,
    minHealth: UFix64,
    maxHealth: UFix64
) {
    let signer = get_registry_admin()
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/CreateLendingProfile.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [name, minHealth, maxHealth]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Admin grants `recipient` `allowance` Vault-creation slots. Publishes
/// the pass cap to `recipient`'s inbox.
/// Access-pass issuance is signed by the strategy admin = the account
/// that owns the Profile resource, which is the registry's contract
/// account (where the Profile lives).
access(all) fun execute_issue_lending_access(
    profileName: String,
    recipient: Address,
    allowance: UInt64
) {
    let signer = get_registry_admin()
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/IssueLendingAccess.cdc"),
        authorizers: [signer.address],
        signers: [signer],
        arguments: [profileName, recipient, allowance]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// User claims their pass and mints a Vault from the registered Profile.
access(all) fun execute_create_lending_vault(
    user: Test.TestAccount,
    profileName: String
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/CreateLendingVault.cdc"),
        authorizers: [user.address],
        signers: [user],
        arguments: [profileName]
    ))
    Test.expect(result, Test.beSucceeded())
}

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

access(all) fun get_lending_summary(
    account: Test.TestAccount
): LendingStrategyV1.PositionSummary {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetLendingSummary.cdc"),
        [account.address]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! LendingStrategyV1.PositionSummary
}

access(all) fun get_lending_types(profileName: String): [Type] {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetLendingTypes.cdc"),
        [profileName]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! [Type]
}

access(all) fun get_vault_balance(account: Test.TestAccount, path: StoragePath): UFix64 {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetVaultBalance.cdc"),
        [account.address, path]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UFix64
}

access(all) fun get_withdrawn_collateral_balance(account: Test.TestAccount): UFix64 {
    return get_vault_balance(account: account, path: /storage/withdrawnCollateral)
}
