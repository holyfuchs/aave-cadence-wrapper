import "EVM"
import "FlowEVMBridge"

/// Thin adapter over MORE Markets' `AaveOracle` EVM contract. Looks up the
/// ERC20 address for a Cadence vault type via `FlowEVMBridge`, calls
/// `AaveOracle.getAssetPrice(address)`, and returns the USD price (8-decimal)
/// as `UFix64`.
///
/// AaveOracle: 0x7287f12c268d7Dff22AAa5c2AA242D7640041cB1 (FlowEVM mainnet).
///
/// Not wired to `DeFiActions.PriceOracle` — the yield-vault strategy doesn't
/// need it. If a consumer wants the full connector surface, wrap this in an
/// outer adapter.
access(all) contract AaveV3PriceOracle {

    access(all) let ORACLE: EVM.EVMAddress

    access(all) struct PriceOracle {
        access(self) let coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>
        access(self) let oracleAddress: EVM.EVMAddress

        init(
            coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>,
            oracleAddress: EVM.EVMAddress
        ) {
            pre { coa.check(): "oracle COA capability is invalid" }
            self.coa = coa
            self.oracleAddress = oracleAddress
        }

        access(all) fun price(ofToken: Type): UFix64? {
            let asset = FlowEVMBridge.getAssociatedEVMAddress(with: ofToken)
            if asset == nil {
                return nil
            }
            let coa = self.coa.borrow() ?? panic("oracle COA capability no longer resolves")
            let result = coa.call(
                to: self.oracleAddress,
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
            // Aave quotes USD in 1e8. UFix64 is 8-decimal fixed-point — the
            // raw integer maps 1:1 into UFix64's scaled representation.
            return UFix64(UInt64(raw)) / 100_000_000.0
        }
    }

    access(all) fun createOracle(
        coa: Capability<auth(EVM.Call) &EVM.CadenceOwnedAccount>
    ): PriceOracle {
        return PriceOracle(coa: coa, oracleAddress: self.ORACLE)
    }

    /// Stateless price query against a borrowed COA reference. `ofToken`
    /// must have a registered ERC20 mapping in FlowEVMBridge. Returns USD
    /// 8-decimal as UFix64, or nil if no mapping / oracle reports zero.
    access(all) fun getPrice(
        coa: auth(EVM.Call) &EVM.CadenceOwnedAccount,
        ofToken: Type
    ): UFix64? {
        let asset = FlowEVMBridge.getAssociatedEVMAddress(with: ofToken)
        if asset == nil {
            return nil
        }
        let result = coa.call(
            to: self.ORACLE,
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
        return UFix64(UInt64(raw)) / 100_000_000.0
    }

    init() {
        self.ORACLE = EVM.addressFromString("7287f12c268d7Dff22AAa5c2AA242D7640041cB1")
    }
}
