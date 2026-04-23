import PyusdMinter from 0x1e4aa0b87d10b141
import "AaveWrapper"
import "EVM"
import "FungibleToken"
import "FlowToken"

/// Mirror of SupplyFlowBorrowPyusd.cdc — supply PYUSD0 as collateral, borrow
/// WFLOW. Uses PyusdMinter (deployed to the bridge account during test setup)
/// to fabricate PYUSD0 since no faucet exists on mainnet.
transaction(pyusdSupplyAmount: UFix64, wflowBorrowAmount: UInt256) {
    prepare(signer: auth(Storage, BorrowValue, Capabilities) &Account) {
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

        // Gas for the COA's EVM calls.
        let gas <- flowVault.withdraw(amount: 10.0)
        position.depositFlow(from: <- gas)

        // Mint PYUSD0 as a Cadence FT, then supply (bridges to ERC20, approves, supplies).
        let pyusdVault <- PyusdMinter.mint(amount: pyusdSupplyAmount)
        position.supply(vault: <- pyusdVault, feeProvider: flowVault)

        let pyusd0Addr = EVM.addressFromString("99af3eea856556646c98c8b9b2548fe815240750")
        let wflowAddr = EVM.addressFromString("d3bf53dac106a0290b0483ecbc89d40fcc961f3e")

        position.setUseAsCollateralEVM(asset: pyusd0Addr, useAsCollateral: true)
        position.borrowEVM(asset: wflowAddr, amount: wflowBorrowAmount)

        let wflowBal = position.erc20BalanceOf(token: wflowAddr)
        assert(wflowBal >= wflowBorrowAmount, message: "no WFLOW borrowed")
    }
}
