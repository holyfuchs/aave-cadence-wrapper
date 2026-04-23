import "AaveWrapper"
import "EVM"
import "FungibleToken"
import "FlowToken"

/// Integration flow exercising real MORE Markets state:
///   1. Ensure a position exists.
///   2. Move `flowAmount` FLOW into the COA's native EVM balance.
///   3. Wrap it into WFLOW by calling WFLOW.deposit() with that value.
///   4. Supply the WFLOW to the Pool and enable it as collateral.
///   5. Borrow `pyusd0Amount` of PYUSD0 to the COA.
///   6. Save the resulting PYUSD0 balance data for the test to assert on.
///
/// WFLOW: 0xd3bf53dac106a0290b0483ecbc89d40fcc961f3e
/// PYUSD0: 0x99af3eea856556646c98c8b9b2548fe815240750
transaction(flowAmount: UFix64, pyusd0Amount: UInt256) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let pyusd0Type = CompositeType(
            "A.1e4aa0b87d10b141.EVMVMBridgedToken_99af3eea856556646c98c8b9b2548fe815240750.Vault"
        ) ?? panic("Invalid PYUSD0 bridged vault type")

        if signer.storage.borrow<&AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        ) == nil {
            let p <- AaveWrapper.createMainnetPosition()
            signer.storage.save(<- p, to: AaveWrapper.PositionStoragePath)
            let cap = signer.capabilities.storage.issue<&{AaveWrapper.PositionPublic}>(
                AaveWrapper.PositionStoragePath
            )
            signer.capabilities.publish(cap, at: AaveWrapper.PositionPublicPath)
        }

        let position = signer.storage.borrow<auth(AaveWrapper.Manage) &AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        )!

        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!

        // 1 FLOW == 10^18 attoflow. UFix64 has 8 decimal places (fixed point),
        // so multiply by 10^10 to go UFix64 → attoflow.
        let attoflowPerFlow: UInt = 10_000_000_000
        let fund <- flowVault.withdraw(amount: flowAmount)
        position.depositFlow(from: <- fund)

        let wflow = EVM.addressFromString("d3bf53dac106a0290b0483ecbc89d40fcc961f3e")

        // Wrap native FLOW → WFLOW. Leave ~0.1 FLOW in native for gas.
        let attoflowBalance = UInt(flowAmount * 100_000_000.0) * attoflowPerFlow
        let gasReserve: UInt = 100_000_000 * attoflowPerFlow // 1 FLOW
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

        // Borrow as a Cadence FungibleToken.Vault — Aave sends PYUSD0 to the
        // COA, then the wrapper bridges it back out to Cadence.
        let borrowedVault <- position.borrow(
            vaultType: pyusd0Type,
            amount: pyusd0Amount,
            feeProvider: flowVault
        )
        signer.storage.save(<- borrowedVault, to: /storage/pyusd0Vault)
    }
}
