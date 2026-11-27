import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(outerBuilder: Instantiator<Outer>, clock: Ticker) { self.outerBuilder = outerBuilder; self.clock = clock }
    @Instantiated let outerBuilder: Instantiator<Outer>
    @Instantiated let clock: Ticker
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Ticker: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Outer: Instantiable {
    public init(ledger: Ledger, innerBuilder: Instantiator<Inner>) { self.ledger = ledger; self.innerBuilder = innerBuilder }
    @Instantiated let ledger: Ledger
    @Instantiated let innerBuilder: Instantiator<Inner>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Ledger: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Inner: Instantiable {
    public init(clock: Ticker?, ledger: Ledger?, missing: Ledger?, note: Note) { self.clock = clock; self.ledger = ledger; self.missing = missing; self.note = note }
    @Received(onlyIfAvailable: true) let clock: Ticker?
    @Received(onlyIfAvailable: true) let ledger: Ledger?
    @Received(onlyIfAvailable: true) let missing: Ledger?
    @Instantiated let note: Note
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Note: Instantiable {
    public init(ledger: Ledger?, clock: Ticker) { self.ledger = ledger; self.clock = clock }
    @Received(onlyIfAvailable: true) let ledger: Ledger?
    @Received let clock: Ticker
    let differentialValueCreationStamp = ProbeStamp.next()
}
