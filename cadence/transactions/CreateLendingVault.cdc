import "LimitedAccessV1"
import "LendingStrategyV1"
import "FlowYieldVaultsRegistry"

/// Look up the registered Profile by `profileName`, claim the access-pass
/// capability from the signer's inbox, and mint a
/// `LendingStrategyV1.Vault`. The vault stores its own
/// `Capability<&Profile>` (taken from a public path on the registry's
/// contract account) so subsequent `deposit` / `withdraw` calls don't
/// need the profile name. Saved at `/storage/LendingTestVault`.
transaction(profileName: String) {
    prepare(signer: auth(Storage, Inbox) &Account) {
        // Existence check via registry (panics if name unknown).
        let _ = FlowYieldVaultsRegistry.getProfile(name: profileName)
            ?? panic("no profile registered under \(profileName)")

        // Strategy-typed cap published by `CreateLendingProfile.cdc` on
        // the registry's contract account.
        let publicPath = PublicPath(identifier: "lendingStrategyV1Profile_\(profileName)")!
        let registryAcct = getAccount(FlowYieldVaultsRegistry.adminAddress())
        let profileCap = registryAcct.capabilities
            .get<&LendingStrategyV1.Profile>(publicPath)
        let profileRef = profileCap.borrow()
            ?? panic("strategy-typed profile cap does not resolve")

        let pass = signer.inbox.claim<&LimitedAccessV1.LimitedAccessPass>(
            profileRef.inboxName(addr: signer.address),
            provider: LimitedAccessV1.providerAddress()
        ) ?? panic("could not claim pass cap from inbox")

        let vault <- profileRef.createVault(pass: pass, profileCap: profileCap)
        signer.storage.save(<- vault, to: /storage/LendingTestVault)
    }
}
