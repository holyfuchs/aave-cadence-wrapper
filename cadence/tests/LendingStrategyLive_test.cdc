#test_fork(network: "mainnet-fork", height: 149_391_841)

import Test
import BlockchainHelpers

import "test_helpers.cdc"

import "LendingStrategyV1"
import "FlowYieldVaultsRegistry"
import "LimitedAccessV1"
import "PassHolderMock"
import "VaultHolderMock"

/// End-to-end live test against real mainnet state at fork block
/// 149_391_841 — real KittyPunch UniV3 pools, real MORE Markets pool,
/// real bridged PYUSD0. Only PYUSD0 is minted from a mock so we have
/// collateral to deposit.
///
/// Strategy layout (PYUSD0/WFLOW/MOET):
///   collateral = bridged PYUSD0
///   debt       = FlowToken (WFLOW on EVM)
///   yield      = MOET, swapped via WFLOW → PYUSD0 → MOET multi-hop V3

access(all) let admin = Test.createAccount()
access(all) let user = Test.createAccount()
access(all) let profileName = "pyusd-flow-v1"
access(all) var snapshot: UInt64 = 0

access(all) fun beforeEach() { Test.reset(to: snapshot) }

/// One-shot fixture: deploy block stack + PyusdMinter, mint admin FLOW,
/// fund block COAs, claim registry Manager, register the profile.
access(all) fun setup() {
    deploy_lending_strategy_stack()
    deploy_pyusd_minter()
    let _ = mintFlow(to: admin, amount: 1000.0)
    execute_fund_lending_blocks(account: admin, swapperFlow: 100.0, moreFlow: 100.0)
    execute_create_lending_profile(
        name: profileName, minHealth: 1.2, maxHealth: 2.0
    )
    snapshot = getCurrentBlockHeight()
}

access(all) fun testDeposit() {
    execute_issue_lending_access(profileName: profileName, recipient: user.address, allowance: 1)
    execute_create_lending_vault(user: user, profileName: profileName)
    execute_lending_vault_deposit(account: user, amount: 1000.0)

    let types = get_lending_types(profileName: profileName)
    log("collateral: \(types[0].identifier)")
    log("debt:       \(types[1].identifier)")
    log("yield:      \(types[2].identifier)")
    Test.assert(
        types[0] != types[2],
        message: "yield must be distinct from collateral"
    )

    let s = get_lending_summary(account: user)
    log("after deposit: \(s.collateral) / \(s.debt) / \(s.yield)")
    Test.assert(s.collateral > 900.0, message: "expected ~$1000 collateral")
    Test.assert(s.debt > 0.0, message: "expected non-zero debt")
    Test.assert(s.yield > 0.0, message: "expected non-zero yield — real V3 swap executed")
}

access(all) fun testWithdraw() {
    execute_issue_lending_access(profileName: profileName, recipient: user.address, allowance: 1)
    execute_create_lending_vault(user: user, profileName: profileName)
    execute_lending_vault_deposit(account: user, amount: 1000.0)

    let before = get_lending_summary(account: user)
    log("before withdraw: \(before.collateral) / \(before.debt) / \(before.yield)")
    Test.assert(before.debt > 0.0, message: "need outstanding debt to unwind")

    execute_lending_vault_withdraw(account: user, amount: 500.0)

    let after = get_lending_summary(account: user)
    log("after withdraw:  \(after.collateral) / \(after.debt) / \(after.yield)")
    Test.assert(after.collateral < before.collateral, message: "collateral did not decrease")
    Test.assert(after.debt < before.debt, message: "debt did not decrease")
    Test.assert(after.yield < before.yield, message: "yield should fund the repay")

    Test.assertEqual(500.0, get_withdrawn_collateral_balance(account: user))
}

/// Experiment: side-channel the access-pass capability through a mock
/// contract (`PassHolderMock`) so a script can fetch it back as a
/// value, then pass it as an argument to a vault-creation tx.
access(all) fun testHere() {
    deploy_pass_holder_mock()

    execute_issue_lending_access(
        profileName: profileName, recipient: user.address, allowance: 1
    )

    // User claims pass from inbox + stashes the cap in PassHolderMock.
    let stashResult = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/StashLendingAccessPass.cdc"),
        authorizers: [user.address],
        signers: [user],
        arguments: [profileName]
    ))
    Test.expect(stashResult, Test.beSucceeded())

    let cap = PassHolderMock.get(addr: user.address)!
    Test.assert(cap.check(), message: "cap does not resolve")
    log("got cap value back into test runtime: \(cap.getType().identifier)")

    // (1) Vault creation in a transaction → vault parked in VaultHolderMock.
    deploy_vault_holder_mock()
    let createResult = Test.executeTransaction(Test.Transaction(
        code: Test.readFile("cadence/transactions/CreateAndStashLendingVault.cdc"),
        authorizers: [user.address],
        signers: [user],
        arguments: [profileName]
    ))
    Test.expect(createResult, Test.beSucceeded())
    Test.assert(VaultHolderMock.has(addr: user.address), message: "vault not stashed")

    // (2) Pull the vault resource back into test top-level.
    let vault <- VaultHolderMock.take(addr: user.address)
    log("got vault resource into test runtime: uuid=\(vault.uuid) profileUUID=\(vault.profileUUID)")

    // (3) Try depositing through it from test top-level. This calls
    // into MORE supply / borrow + V3 swap, which triggers EVM ops via
    // the existing Position COA — *and HANGS* the same way
    // `EVM.createCadenceOwnedAccount()` does. Confirmed empirically:
    // any EVM mutation invoked from test top-level deadlocks. Code
    // left commented for reference.
    //
    // let pyusd <- PyusdMinter.mint(amount: 1000.0)
    // vault.deposit(from: <- pyusd)
    // let s = vault.positionSummary()
    // log("post-deposit summary: \(s.collateral) / \(s.debt) / \(s.yield)")

    destroy vault
}

// access(all) fun testRebalance() {
//     execute_issue_lending_access(profileName: profileName, recipient: admin.address, allowance: 1)
//     execute_create_lending_vault(user: admin, profileName: profileName)
//     execute_lending_vault_deposit(account: admin, amount: 1000.0)

//     let before = get_lending_summary(account: admin)
//     let result = try_lending_vault_rebalance(account: admin)
//     if result.status == Test.ResultStatus.succeeded {
//         log("rebalance succeeded")
//     } else {
//         let msg = result.error?.message ?? "unknown"
//         log("rebalance failed: \(msg)")
//     }
//     let after = get_lending_summary(account: admin)
//     log("rebalance before: \(before.debt) → after: \(after.debt)")
// }
