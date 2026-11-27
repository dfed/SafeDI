import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(cache: LazilyInstantiated<Cache>, feed: Feed, panelBuilder: Instantiator<Panel>) { self.cache = cache; self.feed = feed; self.panelBuilder = panelBuilder }
    @Instantiated let cache: LazilyInstantiated<Cache>
    @Instantiated let feed: Feed
    @Instantiated let panelBuilder: Instantiator<Panel>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Cache: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Feed: Instantiable {
    public init(cache: LazilyInstantiated<Cache>) { self.cache = cache }
    @Received let cache: LazilyInstantiated<Cache>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Panel: Instantiable {
    public init(cache: Cache, rowBuilder: Instantiator<Row>) { self.cache = cache; self.rowBuilder = rowBuilder }
    @Received let cache: Cache
    @Instantiated let rowBuilder: Instantiator<Row>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Row: Instantiable {
    public init(cache: LazilyInstantiated<Cache>?, feed: Feed) { self.cache = cache; self.feed = feed }
    @Received(onlyIfAvailable: true) let cache: LazilyInstantiated<Cache>?
    @Received let feed: Feed
    let differentialValueCreationStamp = ProbeStamp.next()
}
