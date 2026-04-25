import "FlowYieldVaultsInterfaces"

/// Registry of yield-vault profiles, keyed by name. Profiles live on
/// whichever account created them; the registry holds public capabilities
/// to them and serves as a discovery index.
///
/// Mutations (`register` / `remove`) are gated by the `Admin` entitlement
/// on the `Manager` resource. The Manager lives on the registry's own
/// contract account at `managerStoragePath` (saved in `init()`), so only
/// the registry's contract account can register or remove profiles.
access(all) contract FlowYieldVaultsRegistry: FlowYieldVaultsInterfaces {

    access(all) entitlement Admin

    access(all) event ProfileRegistered(name: String)
    access(all) event ProfileRemoved(name: String)

    access(all) let managerStoragePath: StoragePath
    access(self) let profiles: {String: Capability<&{FlowYieldVaultsInterfaces.Profile}>}

    /// Authority resource. Hold one (via `claimManager()`) to mutate the
    /// registry. `register` / `remove` are entitlement-gated; reads are
    /// public (`getProfile`, `profileInfos`).
    access(all) resource Manager {

        /// Register `cap` under `name`. Panics if `name` is taken or
        /// `cap` doesn't currently resolve.
        access(Admin) fun register(
            name: String,
            cap: Capability<&{FlowYieldVaultsInterfaces.Profile}>
        ) {
            pre {
                FlowYieldVaultsRegistry.profiles[name] == nil:
                    "Profile already registered: \(name)"
                cap.check(): "Provided profile capability does not resolve"
            }
            FlowYieldVaultsRegistry.profiles[name] = cap
            emit ProfileRegistered(name: name)
        }

        /// Remove the entry under `name`. Existing vaults still hold
        /// their own profile reference and are unaffected.
        access(Admin) fun remove(name: String) {
            pre {
                FlowYieldVaultsRegistry.profiles[name] != nil:
                    "Profile not found: \(name)"
            }
            let _ = FlowYieldVaultsRegistry.profiles.remove(key: name)
            emit ProfileRemoved(name: name)
        }
    }

    /// Look up a registered profile capability by name. Returns `nil` if
    /// not registered. Public.
    access(all) view fun getProfile(name: String): Capability<&{FlowYieldVaultsInterfaces.Profile}>? {
        return self.profiles[name]
    }

    /// Address of the registry's contract account — also the only account
    /// that can borrow the `Manager` and call `register` / `remove`.
    access(all) view fun adminAddress(): Address {
        return self.account.address
    }

    access(all) view fun profileCount(): Int {
        return self.profiles.length
    }

    /// `name → info` for every registered profile.
    access(all) fun profileInfos(): {String: {String: String}} {
        let infos: {String: {String: String}} = {}
        for name in self.profiles {
            if let ref = self.profiles[name]!.borrow() {
                infos[name] = ref.info()
            }
        }
        return infos
    }

    init() {
        self.profiles = {}
        self.managerStoragePath = /storage/FlowYieldVaultsRegistryManager
        self.account.storage.save(<- create Manager(), to: self.managerStoragePath)
    }
}
