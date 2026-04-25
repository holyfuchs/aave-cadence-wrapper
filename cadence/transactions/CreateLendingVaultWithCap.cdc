import "LimitedAccessV1"
import "LendingStrategyV1"
import "FlowYieldVaultsRegistry"
import "PassHolderMock"

/// Variant of `CreateLendingVault.cdc` that takes the access-pass
/// capability *out of `PassHolderMock`* (test side-channel) instead of
/// claiming it from the signer's inbox. We can't pass `Capability`
/// values as tx arguments — Cadence rejects them as non-importable —
/// so the tx fetches it itself from the mock keyed by signer address.
transaction(profileName: String) {
    prepare(signer: auth(Storage) &Account) {
        let pass = PassHolderMock.get(addr: signer.address)
            ?? panic("no stashed pass cap for \(signer.address)")

        let publicPath = PublicPath(identifier: "lendingStrategyV1Profile_\(profileName)")!
        let registryAcct = getAccount(FlowYieldVaultsRegistry.adminAddress())
        let profileCap = registryAcct.capabilities
            .get<&LendingStrategyV1.Profile>(publicPath)
        let profileRef = profileCap.borrow()
            ?? panic("no published profile")

        let vault <- profileRef.createVault(pass: pass, profileCap: profileCap)
        signer.storage.save(<- vault, to: /storage/LendingTestVault)
    }
}
