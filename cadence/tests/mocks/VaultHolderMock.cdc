import "LendingStrategyV1"

/// Test-only side-channel for stashing a `LendingStrategyV1.Vault`
/// resource inside a contract dict so it can be picked up later — by
/// either a transaction or by test top-level code calling `take`.
access(all) contract VaultHolderMock {

    access(self) let vaults: @{Address: LendingStrategyV1.Vault}

    access(all) fun store(addr: Address, vault: @LendingStrategyV1.Vault) {
        let old <- self.vaults[addr] <- vault
        destroy old
    }

    access(all) fun take(addr: Address): @LendingStrategyV1.Vault {
        return <- (self.vaults.remove(key: addr)
            ?? panic("no vault stashed for \(addr)"))
    }

    access(all) view fun has(addr: Address): Bool {
        return self.vaults[addr] != nil
    }

    init() {
        self.vaults <- {}
    }
}
