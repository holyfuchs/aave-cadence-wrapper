import "AaveV3Pool"
import "EVM"
import "FungibleToken"
import "FlowToken"

/// Supply `flowAmount` FLOW (native → WFLOW via WFLOW.deposit) as collateral
/// using the raw-EVM path, then use the vault-shaped `borrow` to get PYUSD0
/// out as a Cadence vault, stored at /storage/pyusd0Vault.
transaction(flowAmount: UFix64, pyusd0Amount: UInt256) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let pyusd0Type = CompositeType(
            "A.1e4aa0b87d10b141.EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.Vault"
        ) ?? panic("Invalid PYUSD0 bridged vault type")

        let position = signer.storage.borrow<auth(AaveV3Pool.Manage) &AaveV3Pool.Position>(
            from: AaveV3Pool.PositionStoragePath
        )!

        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!

        let attoflowPerFlow: UInt = 10_000_000_000
        position.depositFlow(from: <- flowVault.withdraw(amount: flowAmount))

        // Wrap FLOW native → WFLOW ERC20 inside the COA. Keep 1 FLOW for gas.
        let wflow = EVM.addressFromString("d3bf53dac106a0290b0483ecbc89d40fcc961f3e")
        let attoflowBalance = UInt(flowAmount * 100_000_000.0) * attoflowPerFlow
        let gasReserve: UInt = 100_000_000 * attoflowPerFlow
        let wrapResult = position.callEVM(
            to: wflow,
            data: EVM.encodeABIWithSignature("deposit()", []),
            gasLimit: 200_000,
            value: attoflowBalance - gasReserve
        )
        assert(
            wrapResult.status == EVM.Status.successful,
            message: "WFLOW.deposit reverted: \(wrapResult.errorMessage)"
        )

        let wflowBalance = position.erc20BalanceOf(token: wflow)
        position.supplyEVM(asset: wflow, amount: wflowBalance)
        position.setUseAsCollateralEVM(asset: wflow, useAsCollateral: true)

        let borrowedVault <- position.borrow(vaultType: pyusd0Type, amount: pyusd0Amount)
        signer.storage.save(<- borrowedVault, to: /storage/pyusd0Vault)
    }
}
