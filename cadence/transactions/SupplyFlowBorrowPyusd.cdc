import "AaveWrapper"
import "EVM"
import "FungibleToken"
import "FlowToken"

/// Supply 500 FLOW (wrapped to WFLOW) → borrow PYUSD0, bridged back to a
/// Cadence vault at /storage/pyusd0Vault.
///
/// WFLOW: 0xd3bf53dac106a0290b0483ecbc89d40fcc961f3e
/// PYUSD0: 0x99af3eea856556646c98c8b9b2548fe815240750
transaction(flowAmount: UFix64, pyusd0Amount: UInt256) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let pyusd0Type = CompositeType(
            "A.1e4aa0b87d10b141.EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.Vault"
        ) ?? panic("Invalid PYUSD0 bridged vault type")

        let position = signer.storage.borrow<auth(AaveWrapper.Manage) &AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        )!

        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!

        let attoflowPerFlow: UInt = 10_000_000_000
        let fund <- flowVault.withdraw(amount: flowAmount)
        position.depositFlow(from: <- fund)

        let wflow = EVM.addressFromString("d3bf53dac106a0290b0483ecbc89d40fcc961f3e")

        // Wrap native FLOW → WFLOW. Leave 1 FLOW in native for gas.
        let attoflowBalance = UInt(flowAmount * 100_000_000.0) * attoflowPerFlow
        let gasReserve: UInt = 100_000_000 * attoflowPerFlow
        let wrapValue = attoflowBalance - gasReserve

        let wrapResult = position.callEVM(
            to: wflow,
            data: EVM.encodeABIWithSignature("deposit()", []),
            gasLimit: 200_000,
            value: wrapValue
        )
        assert(
            wrapResult.status == EVM.Status.successful,
            message: "WFLOW.deposit reverted: \(wrapResult.errorMessage)"
        )

        let wflowBalance = position.erc20BalanceOf(token: wflow)
        assert(wflowBalance > 0, message: "no WFLOW after wrap")

        position.supplyEVM(asset: wflow, amount: wflowBalance)
        position.setUseAsCollateralEVM(asset: wflow, useAsCollateral: true)

        let borrowedVault <- position.borrow(
            vaultType: pyusd0Type,
            amount: pyusd0Amount
        )
        signer.storage.save(<- borrowedVault, to: /storage/pyusd0Vault)
    }
}
