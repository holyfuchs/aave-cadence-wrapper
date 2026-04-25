import "EVM"

/// Mock to probe what operations the Cadence test runtime allows when
/// called from test top-level (script-style context) vs only within a
/// transaction. Each probe is a separate function so we can run them
/// independently and pinpoint the exact blocker.
access(all) contract ResourceMock {

    access(all) resource Foo {
        access(all) let label: String
        access(all) var counter: UInt64

        init(label: String) {
            self.label = label
            self.counter = 0
        }

        access(all) fun bump() {
            self.counter = self.counter + 1
        }
    }

    access(all) let fooStoragePath: StoragePath

    /// (1) Just mint and return a resource. Already shown to work.
    access(all) fun mint(label: String): @Foo {
        return <- create Foo(label: label)
    }

    /// (2) Mutate a contract-account-stored resource via internal ref.
    /// Probes whether script context allows writing back through a
    /// borrowed `&Foo` to update its `var` field.
    access(all) fun bumpStored() {
        let foo = self.account.storage.borrow<&Foo>(from: self.fooStoragePath)
            ?? panic("no stored foo")
        foo.bump()
    }

    /// (3) Read the counter back. Pure read.
    access(all) view fun storedCounter(): UInt64 {
        return self.account.storage
            .borrow<&Foo>(from: self.fooStoragePath)!.counter
    }

    /// (4) Create an EVM CadenceOwnedAccount and immediately destroy it.
    /// This is what `MOREV1.createMainnetPosition()` does internally.
    access(all) fun probeCreateCOA() {
        let coa <- EVM.createCadenceOwnedAccount()
        destroy coa
    }

    init() {
        self.fooStoragePath = /storage/resourceMockFoo
        self.account.storage.save(<- create Foo(label: "stored"), to: self.fooStoragePath)
    }
}
