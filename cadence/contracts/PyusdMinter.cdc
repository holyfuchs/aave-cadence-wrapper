import EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750 from 0x1e4aa0b87d10b141
import FungibleToken from 0xf233dcee88fe0abe

/// Fork-test-only helper. Exposes PYUSD0's `access(account) fun mintTokens` as
/// a public function. Only callable after being deployed to
/// 0x1e4aa0b87d10b141 (the FlowEVMBridge account) — any other deployment
/// would fail at compile time because `mintTokens` is account-scoped there.
access(all) contract PyusdMinter {
    access(all) fun mint(amount: UFix64): @{FungibleToken.Vault} {
        return <- EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.mintTokens(amount: amount)
    }
}
