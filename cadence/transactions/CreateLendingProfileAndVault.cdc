import "FungibleToken"
import "FlowToken"
import "LimitedAccessV1"
import "LendingStrategyV1"

/// Build a minimal LendingStrategyV1 Profile, issue an access pass to the
/// signer, claim the pass cap from the inbox, and mint a Vault. Uses
/// `FlowToken.Vault` as a placeholder for all three slots — fine for a
/// "does this compile and create a vault?" smoke test; would fail for a
/// real swap because no V3 routes are registered.
transaction(profileContractAddress: Address) {
    prepare(signer: auth(Storage, Capabilities, Inbox) &Account) {
        let coll <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        let debt <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        let yield <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())

        let profile <- LendingStrategyV1.createProfile(
            collateralToken: <- coll,
            debtToken: <- debt,
            yieldToken: <- yield,
            minHealth: 1.2,
            maxHealth: 2.0
        )

        // Issue an access pass to ourselves via the profile's manager.
        let mgr = &profile.accessManager
            as auth(LimitedAccessV1.Admin) &LimitedAccessV1.Manager
        mgr.issue(addr: signer.address, allowance: 1)
        let inboxName = mgr.inboxName(addr: signer.address)

        let profilePath = /storage/lendingStrategyV1Profile
        signer.storage.save(<- profile, to: profilePath)

        // Claim the pass capability published to our inbox by the
        // LimitedAccessV1 contract account.
        let pass = signer.inbox.claim<&LimitedAccessV1.LimitedAccessPass>(
            inboxName,
            provider: profileContractAddress
        ) ?? panic("could not claim pass cap from inbox")

        let profileRef = signer.storage
            .borrow<&LendingStrategyV1.Profile>(from: profilePath)
            ?? panic("profile not found")
        let vault <- profileRef.createVault(pass: pass)
        signer.storage.save(<- vault, to: /storage/lendingStrategyV1Vault)
    }
}
