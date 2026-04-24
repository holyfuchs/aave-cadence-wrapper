import Test
import "AaveWrapper"

/// Deploy AaveWrapper to the service account at the project-root path.
access(all) fun deploy_aave_wrapper() {
    let err = Test.deployContract(
        name: "AaveWrapper",
        path: "cadence/contracts/AaveWrapper.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

/// Deploy YieldVault (depends on AaveWrapper being deployed first).
access(all) fun deploy_yield_vault() {
    let err = Test.deployContract(
        name: "YieldVault",
        path: "cadence/contracts/YieldVault.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

/// Create a PYUSD0-collateral / FlowToken-debt strategy under `account`.
access(all) fun execute_setup_pyusd_flow_strategy(account: Test.TestAccount) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/SetupPyusdFlowStrategy.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: []
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Mint PYUSD0 and deposit into the account's YieldVault strategy.
access(all) fun execute_deposit_to_pyusd_strategy(
    account: Test.TestAccount,
    pyusdAmount: UFix64,
    borrowAmount: UInt256
) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/DepositToPyusdStrategy.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: [pyusdAmount, borrowAmount]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Poke the strategy — if Aave HF has dropped below the contract's
/// MIN_HEALTH_FACTOR, it will repay some of its internal debt holdings.
access(all) fun execute_rebalance_strategy(account: Test.TestAccount) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/RebalanceStrategy.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: []
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Read the Aave account data for the account's public YieldVault strategy.
access(all) fun get_strategy_account_data(account: Test.TestAccount): AaveWrapper.AccountData {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetStrategyAccountData.cdc"),
        [account.address]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! AaveWrapper.AccountData
}

/// Read the debt balance held inside the account's public YieldVault strategy.
access(all) fun get_strategy_debt(account: Test.TestAccount): UFix64 {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetStrategyDebt.cdc"),
        [account.address]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UFix64
}

/// Run `cadence/transactions/SetupPosition.cdc` as `account`.
access(all) fun execute_setup_position(account: Test.TestAccount) {
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/SetupPosition.cdc"),
        authorizers: [account.address],
        signers: [account],
        arguments: []
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Read a FungibleToken.Vault balance at `path` in the account's storage.
access(all) fun get_vault_balance(account: Test.TestAccount, path: StoragePath): UFix64 {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetVaultBalance.cdc"),
        [account.address, path]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UFix64
}

/// Read the ERC20 balance held by the account's Position COA.
access(all) fun get_erc20_balance(account: Test.TestAccount, tokenHex: String): UInt256 {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetErc20Balance.cdc"),
        [account.address, tokenHex]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UInt256
}

/// Read AaveWrapper's `AccountData` view for an account.
access(all) fun get_account_data(account: Test.TestAccount): AaveWrapper.AccountData {
    let result = Test.executeScript(
        Test.readFile("cadence/scripts/GetAccountData.cdc"),
        [account.address]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! AaveWrapper.AccountData
}

/// Run SupplyFlowBorrowPyusd.cdc: wrap `flowAmount` FLOW → WFLOW, supply it,
/// then borrow `pyusd0Amount` PYUSD0 (6 decimals) to the COA.
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
    log(result.computationUsed)
    Test.expect(result, Test.beSucceeded())
}

/// Deploy the PyusdMinter helper contract to the bridge account
/// (0x1e4aa0b87d10b141). Required before `execute_supply_pyusd_borrow_wflow`.
access(all) fun deploy_pyusd_minter() {
    let bridge = Test.getAccount(0x1e4aa0b87d10b141)
    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/DeployPyusdMinter.cdc"),
        authorizers: [bridge.address],
        signers: [bridge],
        arguments: [Test.readFile("cadence/contracts/PyusdMinter.cdc")]
    ))
    Test.expect(result, Test.beSucceeded())
}

/// Run SupplyPyusdBorrowWflow.cdc: mint `pyusdSupplyAmount` bridged PYUSD0,
/// supply it, then borrow `wflowBorrowAmount` WFLOW (18 decimals) to the COA.
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
