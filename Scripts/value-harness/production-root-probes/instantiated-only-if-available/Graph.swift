import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(checkout: Checkout) { self.checkout = checkout }
    @Instantiated let checkout: Checkout
    let differentialValueCreationStamp = ProbeStamp.next()
}

public protocol FraudCheck: AnyObject {}
public protocol Coupons: AnyObject {}

@Instantiable
public final class Checkout: Instantiable {
    public init(fraud: (any FraudCheck)?, coupons: (any Coupons)?, summary: Summary) { self.fraud = fraud; self.coupons = coupons; self.summary = summary }
    @Instantiated(onlyIfAvailable: true) let fraud: (any FraudCheck)?
    @Instantiated(onlyIfAvailable: true) let coupons: (any Coupons)?
    @Instantiated let summary: Summary
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [FraudCheck.self])
public final class FraudCheckImpl: Instantiable, FraudCheck {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Summary: Instantiable {
    public init(fraud: (any FraudCheck)?, coupons: (any Coupons)?) { self.fraud = fraud; self.coupons = coupons }
    @Received let fraud: (any FraudCheck)?
    @Received(onlyIfAvailable: true) let coupons: (any Coupons)?
    let differentialValueCreationStamp = ProbeStamp.next()
}
