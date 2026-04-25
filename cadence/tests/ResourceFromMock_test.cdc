#test_fork(network: "mainnet-fork", height: 149_391_841)

import Test
import "ResourceMock"

/// Probe what operations the Cadence test runtime allows when invoked
/// straight from test top-level (no transaction wrapper).

access(all) fun setup() {
    let err = Test.deployContract(
        name: "ResourceMock",
        path: "cadence/tests/mocks/ResourceMock.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

/// (1) Mint + return a fresh resource. Confirmed to work in the
/// previous run.
access(all) fun testMint() {
    let foo <- ResourceMock.mint(label: "hello")
    log("(1) got foo: \(foo.label)")
    destroy foo
}

/// (2) Mutate a contract-stored resource through a borrowed `&Foo`
/// reference. Hypothesis: writes back to chain storage might block.
access(all) fun testBumpStored() {
    let before = ResourceMock.storedCounter()
    log("(2) counter before bump: \(before)")
    ResourceMock.bumpStored()
    let after = ResourceMock.storedCounter()
    log("(2) counter after bump: \(after)")
    Test.assertEqual(before + 1, after)
}

/// (3) Create an EVM CadenceOwnedAccount and destroy it. Hypothesis:
/// EVM-side mutations from script context might hang against the
/// upstream fork node.
/// HANGS — confirmed. `EVM.createCadenceOwnedAccount()` from test
/// top-level (script context) never returns. Same call from inside a
/// transaction works fine. This is the root cause of the
/// `Profile.createVault` hang we saw earlier (it goes through
/// `MOREV1.createMainnetPosition()` → `EVM.createCadenceOwnedAccount()`).
// access(all) fun testCreateCOA() {
//     log("(3) before EVM.createCadenceOwnedAccount()")
//     ResourceMock.probeCreateCOA()
//     log("(3) after EVM.createCadenceOwnedAccount() — survived")
// }
