// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

public protocol Promo: AnyObject {}
public protocol Tax: AnyObject {}
@Instantiable(generateDependencyTree: true)
public final class Cart: Instantiable {
    public init(promo: (any Promo)?, tax: (any Tax)?, total: Total) { self.promo = promo; self.tax = tax; self.total = total }
    @Instantiated(onlyIfAvailable: true) let promo: (any Promo)?
    @Instantiated(onlyIfAvailable: true) let tax: (any Tax)?
    @Instantiated let total: Total
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Total: Instantiable {
    public init(promo: (any Promo)?) { self.promo = promo }
    @Received let promo: (any Promo)?
    let differentialValueCreationStamp = ProbeStamp.next()
}
