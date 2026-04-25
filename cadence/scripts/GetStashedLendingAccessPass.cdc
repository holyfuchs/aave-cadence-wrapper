import "LimitedAccessV1"
import "PassHolderMock"

access(all) fun main(addr: Address): Capability<&LimitedAccessV1.LimitedAccessPass> {
    return PassHolderMock.get(addr: addr)
        ?? panic("no pass stashed for \(addr)")
}
