import "LendingStrategyV1"
import "FlowYieldVaultsRegistry"

/// `[collateralType, debtType, yieldType]` for the registered profile.
access(all) fun main(profileName: String): [Type] {
    let publicPath = PublicPath(identifier: "lendingStrategyV1Profile_\(profileName)")!
    let registry = getAccount(FlowYieldVaultsRegistry.adminAddress())
    let profile = registry.capabilities
        .borrow<&LendingStrategyV1.Profile>(publicPath)
        ?? panic("no profile published under \(profileName)")
    return [profile.collateralType(), profile.debtType(), profile.yieldType()]
}
