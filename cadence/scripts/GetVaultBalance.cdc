import "FungibleToken"

/// Read the balance of a FungibleToken.Vault stored at `path` on `owner`.
/// Uses getAuthAccount because test/storage paths don't always have a
/// published balance capability for bridged vaults.
access(all) fun main(owner: Address, path: StoragePath): UFix64 {
    let acct = getAuthAccount<auth(BorrowValue) &Account>(owner)
    let vault = acct.storage.borrow<&{FungibleToken.Balance}>(from: path)
    return vault?.balance ?? 0.0
}
