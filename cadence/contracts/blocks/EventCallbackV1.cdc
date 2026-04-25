/// First concrete event-callback trigger. Pairs a check function with a
/// callback function (both TODO) and fires the callback the first time the
/// check returns true. `tick()` is the public poke; subsequent ticks after
/// firing are no-ops.
access(all) contract EventCallbackV1 {

    access(all) entitlement Manage

    access(all) struct CheckedCallback {
    }

    access(all) resource Trigger {
        access(self) var fired: Bool

        init() {
            self.fired = false
        }

        access(all) view fun hasFired(): Bool {
            return self.fired
        }

        access(Manage) fun tick() {
            if self.fired { return }
            // TODO: invoke the registered check + callback functions here.
            self.fired = true
        }
    }

    access(all) fun createTrigger(): @Trigger {
        return <- create Trigger()
    }
}
