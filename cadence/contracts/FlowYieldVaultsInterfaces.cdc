import "FungibleToken"

/// Contract interface shared between `FlowYieldVaultsRegistry` and concrete
/// strategy contracts.
///
/// - `Profile` is a *resource* interface — concrete profile resources live
///   inside each strategy (e.g. `LendingStrategyV1.Profile`) and are
///   indexed by the registry via public capability.
/// - `Vault` is the user-held position resource, exposing the
///   `FungibleToken` surface shared by all vaults.
access(all) contract interface FlowYieldVaultsInterfaces {

    /// Free-form metadata surface. Implemented by each strategy's
    /// concrete Profile resource. Surfaced by
    /// `FlowYieldVaultsRegistry.profileInfos()` so UIs can list profiles
    /// without hard-coding metadata.
    access(all) resource interface Profile {
        access(all) view fun info(): {String: String}
    }

    /// User-held instance of a profile. Concrete resource type lives in
    /// the strategy contract.
    access(all) resource interface Vault: FungibleToken.Provider, FungibleToken.Receiver {}
}
