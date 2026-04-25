import "LendingStrategyV1"

/// Admin grants `recipient` `allowance` Vault-creation slots against the
/// Profile registered under `profileName`. Publishes the access pass
/// capability to `recipient`'s inbox; recipient claims it inside
/// `CreateLendingVault.cdc`.
///
/// Signed by the strategy admin = the registry's contract account, which
/// holds the Profile resource at `/storage/lendingStrategyV1Profile_<profileName>`.
transaction(profileName: String, recipient: Address, allowance: UInt64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let storagePath = StoragePath(identifier: "lendingStrategyV1Profile_\(profileName)")!
        let profile = signer.storage
            .borrow<auth(LendingStrategyV1.Admin) &LendingStrategyV1.Profile>(from: storagePath)
            ?? panic("no profile at \(storagePath.toString())")
        profile.issueAccessPass(addr: recipient, allowance: allowance)
    }
}
