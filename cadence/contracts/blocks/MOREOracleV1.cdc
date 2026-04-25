import "EVM"
import "FlowEVMBridge"

/// Thin adapter over MORE Markets' `AaveOracle` EVM contract. Looks up the
/// ERC20 address for a Cadence vault type via `FlowEVMBridge`, calls
/// `AaveOracle.getAssetPrice(address)`, and returns the USD price
/// (8-decimal) as `UFix64`.
///
/// The oracle EVM address and the executor COA are baked into the contract
/// (`init()`), so `createPriceOracle()` is a no-arg factory.
access(all) contract MOREOracleV1 {

    /// MORE Markets `AaveOracle` (FlowEVM mainnet).
    access(all) let ORACLE: EVM.EVMAddress
    /// Storage path of the contract-account COA used for oracle reads.
    access(all) let coaStoragePath: StoragePath
    access(self) let coaCapability: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>

    access(all) struct PriceOracle {
        init() {}

        /// Aave quotes prices in USD. No on-chain USD type exists, so we
        /// surface the UFix64 placeholder convention.
        access(all) view fun unitOfAccount(): Type {
            return Type<UFix64>()
        }

        access(all) fun price(ofToken: Type): UFix64? {
            let asset = FlowEVMBridge.getAssociatedEVMAddress(with: ofToken)
            if asset == nil {
                return nil
            }
            let coa = MOREOracleV1.coaCapability.borrow()
                ?? panic("oracle COA capability no longer resolves")
            let result = coa.call(
                to: MOREOracleV1.ORACLE,
                data: EVM.encodeABIWithSignature("getAssetPrice(address)", [asset!]),
                gasLimit: 100_000,
                value: EVM.Balance(attoflow: 0)
            )
            if result.status != EVM.Status.successful {
                return nil
            }
            let decoded = EVM.decodeABI(types: [Type<UInt256>()], data: result.data)
            let raw = decoded[0] as! UInt256
            if raw == 0 {
                return nil
            }
            // Aave quotes USD in 1e8. UFix64 is 8-decimal fixed-point —
            // the raw integer maps 1:1 into UFix64's scaled representation.
            return UFix64(UInt64(raw)) / 100_000_000.0
        }
    }

    /// Mint a stateless PriceOracle handle. All reads go through the
    /// contract-account COA against the hardcoded `ORACLE` address.
    access(all) fun createPriceOracle(): MOREOracleV1.PriceOracle {
        return MOREOracleV1.PriceOracle()
    }

    init() {
        self.ORACLE = EVM.addressFromString("7287f12c268d7Dff22AAa5c2AA242D7640041cB1")
        self.coaStoragePath = /storage/MOREOracleV1COA

        let coa <- EVM.createCadenceOwnedAccount()
        self.account.storage.save(<- coa, to: self.coaStoragePath)
        self.coaCapability = self.account.capabilities.storage
            .issue<auth(EVM.Call) &EVM.CadenceOwnedAccount>(self.coaStoragePath)
    }
}
