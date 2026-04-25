import "LimitedAccessV1"

/// Test-only side-channel for pulling an access-pass capability back out
/// into a script. A transaction signed by the recipient claims the pass
/// from inbox and parks it here via `store`; the test then calls `get`
/// from a script to retrieve the value.
access(all) contract PassHolderMock {

    access(self) let caps: {Address: Capability<&LimitedAccessV1.LimitedAccessPass>}

    /// Anyone can stash a cap under any address — this is a test mock,
    /// not a security boundary.
    access(all) fun store(addr: Address, pass: Capability<&LimitedAccessV1.LimitedAccessPass>) {
        self.caps[addr] = pass
    }

    access(all) view fun get(addr: Address): Capability<&LimitedAccessV1.LimitedAccessPass>? {
        return self.caps[addr]
    }

    init() {
        self.caps = {}
    }
}
