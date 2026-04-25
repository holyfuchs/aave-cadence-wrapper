import "LimitedAccessV1"
import "LendingStrategyV1"
import "FlowYieldVaultsRegistry"
import "PassHolderMock"

/// Claim the access pass from the signer's inbox and stash the
/// capability in `PassHolderMock` so a script can read it back as a
/// value. Test-only.
transaction(profileName: String) {
    prepare(signer: auth(Inbox) &Account) {
        let publicPath = PublicPath(identifier: "lendingStrategyV1Profile_\(profileName)")!
        let registryAcct = getAccount(FlowYieldVaultsRegistry.adminAddress())
        let profileRef = registryAcct.capabilities
            .borrow<&LendingStrategyV1.Profile>(publicPath)
            ?? panic("no published profile")

        let pass = signer.inbox.claim<&LimitedAccessV1.LimitedAccessPass>(
            profileRef.inboxName(addr: signer.address),
            provider: LimitedAccessV1.providerAddress()
        ) ?? panic("could not claim pass cap from inbox")

        PassHolderMock.store(addr: signer.address, pass: pass)
    }
}
