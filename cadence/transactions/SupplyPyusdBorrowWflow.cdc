import PyusdMinter from 0x1e4aa0b87d10b141
import "AaveWrapper"
import "EVM"
import "FungibleToken"
import "FlowToken"

/// Supply PYUSD0 as collateral, borrow WFLOW into the COA.
transaction(pyusdSupplyAmount: UFix64, wflowBorrowAmount: UInt256) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let position = signer.storage.borrow<auth(AaveWrapper.Manage) &AaveWrapper.Position>(
            from: AaveWrapper.PositionStoragePath
        )!

        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!

        let gas <- flowVault.withdraw(amount: 10.0)
        position.depositFlow(from: <- gas)

        let pyusdVault <- PyusdMinter.mint(amount: pyusdSupplyAmount)
        position.supply(vault: <- pyusdVault)

        let pyusd0Addr = EVM.addressFromString("99af3eea856556646c98c8b9b2548fe815240750")
        let wflowAddr = EVM.addressFromString("d3bf53dac106a0290b0483ecbc89d40fcc961f3e")

        position.setUseAsCollateralEVM(asset: pyusd0Addr, useAsCollateral: true)
        position.borrowEVM(asset: wflowAddr, amount: wflowBorrowAmount)

        let wflowBal = position.erc20BalanceOf(token: wflowAddr)
        assert(wflowBal >= wflowBorrowAmount, message: "no WFLOW borrowed")
    }
}
