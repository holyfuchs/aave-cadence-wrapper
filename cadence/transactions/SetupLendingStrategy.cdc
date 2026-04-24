import PyusdMinter from 0x1e4aa0b87d10b141
import MockSwapper from 0x6b00ff876c299c61
import "FungibleToken"
import "FlowToken"
import "DeFiActions"
import "DeFiActionsUtils"
import "FlowYieldVaultsLendingStrategies"
import "FlowYieldVaultsInterfaces"

/// Sets up an end-to-end lending strategy the test can drive:
///   - Collateral = bridged PYUSD0
///   - Debt       = FlowToken (= WFLOW on the EVM side)
///   - Yield      = bridged PYUSD0 (same type as collateral to keep the test simple)
///
/// Funds two MockSwapper source vaults with plenty of liquidity so
/// deposit/withdraw can swap both ways.
///
/// `priceRatio = 0.04` means 1 FLOW → 0.04 PYUSD0 (rough FLOW price in USD).
transaction(initialSwapperPyusdLiquidity: UFix64) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let pyusd0Type = CompositeType(
            "A.1e4aa0b87d10b141.EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.Vault"
        ) ?? panic("PYUSD0 bridged type not registered")

        // Liquidity for the MockSwapper: pre-fund a PYUSD0 vault and use the
        // signer's FlowToken vault for the FLOW side.
        if signer.storage.borrow<&{FungibleToken.Vault}>(from: /storage/swapperPyusdPool) == nil {
            let empty <- DeFiActionsUtils.getEmptyVault(pyusd0Type)
            signer.storage.save(<- empty, to: /storage/swapperPyusdPool)
        }
        let pool = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/swapperPyusdPool
        )!
        let seed <- PyusdMinter.mint(amount: initialSwapperPyusdLiquidity)
        pool.deposit(from: <- seed)

        let flowCap = signer.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(/storage/flowTokenVault)
        let pyusdCap = signer.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(/storage/swapperPyusdPool)

        // debtYieldSwapper: FLOW (debt) ↔ PYUSD0 (yield). priceRatio = 0.04
        // means 1 FLOW → 0.04 PYUSD0; swapBack gives 1 PYUSD0 → 25 FLOW.
        let debtYieldSwapper = MockSwapper.Swapper(
            inVault: Type<@FlowToken.Vault>(),
            outVault: pyusd0Type,
            inVaultSource: flowCap,
            outVaultSource: pyusdCap,
            priceRatio: 0.04,
            uniqueID: nil
        )

        // collateralDebtSwapper: PYUSD0 ↔ FLOW. Not used by the current
        // deposit/withdraw paths but required by LendingStrategy's init.
        let collateralDebtSwapper = MockSwapper.Swapper(
            inVault: pyusd0Type,
            outVault: Type<@FlowToken.Vault>(),
            inVaultSource: pyusdCap,
            outVaultSource: flowCap,
            priceRatio: 25.0,
            uniqueID: nil
        )

        let strategy = FlowYieldVaultsLendingStrategies.createLendingStrategy(
            collateralDebtSwapper: collateralDebtSwapper,
            debtYieldSwapper: debtYieldSwapper,
            yieldTokenType: pyusd0Type,
            debtTokenType: Type<@FlowToken.Vault>(),
            collateralTokenType: pyusd0Type,
            minHealth: 1.2,
            maxHealth: 2.0
        )

        let vault <- strategy.createYieldVault(name: "pyusd-flow-test")
        signer.storage.save(<- vault, to: /storage/LendingTestVault)
    }
}
