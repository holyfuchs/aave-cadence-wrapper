import PyusdMinter from 0x1e4aa0b87d10b141
import "AaveV3Pool"
import "EVM"
import "FungibleToken"
import "FlowToken"

/// Mint bridged PYUSD0 as a Cadence vault, deposit it into the Aave position
/// (bridges + supplies), enable it as collateral, then borrow WFLOW on the
/// EVM side into the COA.
transaction(pyusdSupplyAmount: UFix64, wflowBorrowAmount: UInt256) {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let position = signer.storage.borrow<auth(AaveV3Pool.Manage) &AaveV3Pool.Position>(
            from: AaveV3Pool.PositionStoragePath
        )!

        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        )!

        position.depositFlow(from: <- flowVault.withdraw(amount: 10.0))

        let pyusdVault <- PyusdMinter.mint(amount: pyusdSupplyAmount)
        let pyusd0Type = pyusdVault.getType()
        position.deposit(from: <- pyusdVault)
        position.setUseAsCollateral(vaultType: pyusd0Type, useAsCollateral: true)

        let wflowAddr = EVM.addressFromString("d3bf53dac106a0290b0483ecbc89d40fcc961f3e")
        position.borrowEVM(asset: wflowAddr, amount: wflowBorrowAmount)

        let wflowBal = position.erc20BalanceOf(token: wflowAddr)
        assert(wflowBal >= wflowBorrowAmount, message: "no WFLOW borrowed")
    }
}
