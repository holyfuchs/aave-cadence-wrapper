/// Per-address limited-use access pass, scoped to a `Manager` resource so
/// multiple strategies / profiles can each maintain their own independent
/// allowance book.
///
/// Identity model — capability-as-proof:
///   * Admin (holding `auth(Admin) &Manager`) calls `manager.issue(addr,
///     allowance)`. That mints a `@LimitedAccessPass` stamped with `addr`,
///     stores it on the LimitedAccessV1 contract account at a path keyed
///     by `(manager.uuid, addr)`, and publishes a capability to that pass
///     via the contract account's inbox under `addr`'s name.
///   * The recipient claims the capability from their inbox. Holding the
///     capability *is* the identity proof — only `addr` could have claimed
///     it. Calling `pass.consume()` decrements one unit of allowance; the
///     pass knows its own address, so `consume()` takes no args.
///
/// Multiple Managers coexist by namespacing storage paths and inbox keys
/// on the manager's UUID — different strategies/profiles can each have
/// their own per-address allowance book without colliding.
access(all) contract LimitedAccessV1 {

    access(all) entitlement Admin

    access(all) event PassIssued(managerUUID: UInt64, addr: Address, allowance: UInt64)
    access(all) event PassRevoked(managerUUID: UInt64, addr: Address)
    access(all) event PassUsed(managerUUID: UInt64, addr: Address, remainingAllowance: UInt64)

    /// Held by the recipient (via published capability). One pass per
    /// `(managerUUID, addr)` pair.
    access(all) resource LimitedAccessPass {
        access(all) let managerUUID: UInt64
        access(all) let addr: Address
        access(all) var remainingAllowance: UInt64

        init(managerUUID: UInt64, addr: Address, allowance: UInt64) {
            self.managerUUID = managerUUID
            self.addr = addr
            self.remainingAllowance = allowance
        }

        /// True iff `account` matches the address this pass was issued to
        /// and the pass still has remaining allowance.
        access(all) view fun isAuthorized(account: Address): Bool {
            return account == self.addr && self.remainingAllowance > 0
        }

        /// Decrement allowance by one.
        access(all) fun consume() {
            pre { self.remainingAllowance > 0: "no remaining allowance" }
            self.remainingAllowance = self.remainingAllowance - 1
            emit PassUsed(
                managerUUID: self.managerUUID,
                addr: self.addr,
                remainingAllowance: self.remainingAllowance
            )
        }

        access(contract) fun setAllowance(_ newAllowance: UInt64) {
            self.remainingAllowance = newAllowance
        }
    }

    /// Per-strategy allowance-book authority. Hold one inside a Profile;
    /// Admin entitlement gates `issue` / `revoke` / `setAllowance`.
    access(all) resource Manager {
        init() {}

        /// Issues (or replaces) the pass for `addr` and re-publishes a
        /// fresh capability via the contract account's inbox. Any
        /// previously claimed capability for the same `(managerUUID, addr)`
        /// remains live (still points at the same pass) — its allowance is
        /// just overwritten.
        access(Admin) fun issue(addr: Address, allowance: UInt64) {
            let path = LimitedAccessV1.passStoragePath(managerUUID: self.uuid, addr: addr)
            if let pass = LimitedAccessV1.account.storage.borrow<&LimitedAccessPass>(from: path) {
                pass.setAllowance(allowance)
                LimitedAccessV1.deletePassCapabilities(path: path)
            } else {
                let pass <- create LimitedAccessPass(
                    managerUUID: self.uuid, addr: addr, allowance: allowance
                )
                LimitedAccessV1.account.storage.save(<- pass, to: path)
            }
            LimitedAccessV1.publishPassCapability(managerUUID: self.uuid, addr: addr)
            emit PassIssued(managerUUID: self.uuid, addr: addr, allowance: allowance)
        }

        /// Destroys the pass, deletes its capability controllers, and
        /// retracts the inbox entry if still unclaimed. Any previously
        /// claimed capability becomes dead (`borrow()` returns `nil`).
        access(Admin) fun revoke(addr: Address) {
            let path = LimitedAccessV1.passStoragePath(managerUUID: self.uuid, addr: addr)
            let pass <- LimitedAccessV1.account.storage.load<@LimitedAccessPass>(from: path)
                ?? panic("no pass for \(addr) under manager \(self.uuid)")
            destroy pass
            LimitedAccessV1.deletePassCapabilities(path: path)
            LimitedAccessV1.unpublishPassCapability(managerUUID: self.uuid, addr: addr)
            emit PassRevoked(managerUUID: self.uuid, addr: addr)
        }

        /// Replace remaining allowance on an existing pass. Panics if no
        /// pass exists for `addr` under this manager.
        access(Admin) fun setAllowance(addr: Address, newAllowance: UInt64) {
            let path = LimitedAccessV1.passStoragePath(managerUUID: self.uuid, addr: addr)
            let pass = LimitedAccessV1.account.storage
                .borrow<&LimitedAccessPass>(from: path)
                ?? panic("no pass for \(addr) under manager \(self.uuid)")
            pass.setAllowance(newAllowance)
        }

        /// Whether a pass is currently held for `addr` under this manager.
        access(all) view fun passExists(addr: Address): Bool {
            return LimitedAccessV1.account.storage.check<@LimitedAccessPass>(
                from: LimitedAccessV1.passStoragePath(managerUUID: self.uuid, addr: addr)
            )
        }

        /// Remaining allowance on `addr`'s pass under this manager. Panics
        /// if no pass exists.
        access(all) view fun remainingAllowance(addr: Address): UInt64 {
            let path = LimitedAccessV1.passStoragePath(managerUUID: self.uuid, addr: addr)
            let pass = LimitedAccessV1.account.storage
                .borrow<&LimitedAccessPass>(from: path)
                ?? panic("no pass for \(addr) under manager \(self.uuid)")
            return pass.remainingAllowance
        }

        /// Inbox key the recipient claims from for this manager's pass.
        access(all) view fun inboxName(addr: Address): String {
            return LimitedAccessV1.inboxNameFor(managerUUID: self.uuid, addr: addr)
        }
    }

    /// Mint a fresh, empty Manager. Caller stores it (e.g. inside a
    /// strategy's Profile resource).
    access(all) fun createManager(): @Manager {
        return <- create Manager()
    }

    /// Address of the contract account — the `provider` recipients use
    /// when claiming a published pass capability from their inbox.
    access(all) view fun providerAddress(): Address {
        return self.account.address
    }

    /// Storage path where this manager's pass for `addr` lives on the
    /// LimitedAccessV1 contract account.
    access(all) view fun passStoragePath(managerUUID: UInt64, addr: Address): StoragePath {
        return StoragePath(
            identifier: "LimitedAccessV1Pass_\(managerUUID)_\(addr.toString())"
        )!
    }

    /// Inbox key under which this manager publishes `addr`'s pass capability.
    access(all) view fun inboxNameFor(managerUUID: UInt64, addr: Address): String {
        return "LimitedAccessPass_\(managerUUID)_\(addr.toString())"
    }

    access(self) fun publishPassCapability(managerUUID: UInt64, addr: Address) {
        let path = self.passStoragePath(managerUUID: managerUUID, addr: addr)
        let cap = self.account.capabilities.storage.issue<&LimitedAccessPass>(path)
        self.account.inbox.publish(
            cap,
            name: self.inboxNameFor(managerUUID: managerUUID, addr: addr),
            recipient: addr
        )
    }

    access(self) fun unpublishPassCapability(managerUUID: UInt64, addr: Address) {
        let _ = self.account.inbox.unpublish<&LimitedAccessPass>(
            self.inboxNameFor(managerUUID: managerUUID, addr: addr)
        )
    }

    access(self) fun deletePassCapabilities(path: StoragePath) {
        let controllers = self.account.capabilities.storage.getControllers(forPath: path)
        for controller in controllers {
            controller.delete()
        }
    }
}
