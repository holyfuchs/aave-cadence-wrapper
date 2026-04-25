import "LimitedAccessV1"
import "LendingStrategyV1"
import "FlowYieldVaultsRegistry"
import "PassHolderMock"
import "VaultHolderMock"

/// Test-flow transaction. Pulls the access-pass cap from
/// `PassHolderMock` (keyed by signer address), looks up the registered
/// Profile via the registry, calls `profile.createVault(...)`, and
/// parks the resulting `@Vault` inside `VaultHolderMock` keyed by signer
/// address. Test top-level can then `take` the vault back out as a
/// resource value.
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
        VaultHolderMock.store(addr: signer.address, vault: <- vault)
    }
}
