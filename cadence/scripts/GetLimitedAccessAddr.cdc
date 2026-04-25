import "LimitedAccessV1"

access(all) fun main(): Address {
    return LimitedAccessV1.providerAddress()
}
