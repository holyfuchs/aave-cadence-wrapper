import Test
import BlockchainHelpers

/// Smoke test for the LendingStrategyV1 Profile/Vault creation path.
/// Deploys the block stack, creates a Profile with FlowToken markers,
/// issues an access pass, and mints a Vault. Doesn't exercise deposit /
/// withdraw — those need a real swap configuration and live MORE-pool
/// reserves and are commented out elsewhere.
access(all) let admin = Test.createAccount()
access(all) var snapshot: UInt64 = 0

access(all) fun setup() {
    deployBlockStack()
    snapshot = getCurrentBlockHeight()
}

access(all) fun beforeEach() {
    Test.reset(to: snapshot)
}

access(all) fun deployBlockStack() {
    deploy("LimitedAccessV1", "cadence/contracts/blocks/LimitedAccessV1.cdc")
    deploy("MOREV1", "cadence/contracts/blocks/MOREV1.cdc")
    deploy("MOREOracleV1", "cadence/contracts/blocks/MOREOracleV1.cdc")
    deploy("UniswapV3SwapperV1", "cadence/contracts/blocks/swappers/UniswapV3SwapperV1.cdc")
    deploy("LendingStrategyV1", "cadence/contracts/strategies/LendingStrategyV1.cdc")
}

access(all) fun deploy(_ name: String, _ path: String) {
    let err = Test.deployContract(name: name, path: path, arguments: [])
    Test.expect(err, Test.beNil())
}

/// Profile + Vault round-trip: build empties, create profile, issue pass,
/// mint vault. Asserts the transaction succeeds end-to-end.
access(all) fun testCreateVault() {
    // The LimitedAccessV1 contract account is where the pass capability
    // gets published — same account every contract was deployed to here
    // (the test framework deploys to a fresh service account).
    let addrResult = Test.executeScript(
        Test.readFile("cadence/scripts/GetLimitedAccessAddr.cdc"), []
    )
    Test.expect(addrResult, Test.beSucceeded())
    let limitedAccessAcct = addrResult.returnValue! as! Address

    let result = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/CreateLendingProfileAndVault.cdc"),
        authorizers: [admin.address],
        signers: [admin],
        arguments: [limitedAccessAcct]
    ))
    Test.expect(result, Test.beSucceeded())
}
