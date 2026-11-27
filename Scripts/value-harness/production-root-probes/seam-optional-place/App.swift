// module: FuzzApp, fills a hole
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(cart: Cart) { self.cart = cart }
    @Instantiated let cart: Cart
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Promo.self])
public final class PromoImpl: Instantiable, Promo {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
