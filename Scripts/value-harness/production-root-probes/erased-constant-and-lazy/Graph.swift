import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(player: LazilyInstantiated<Player>, track: AnyTrack, deckBuilder: Instantiator<Deck>) { self.player = player; self.track = track; self.deckBuilder = deckBuilder }
    @Instantiated let player: LazilyInstantiated<Player>
    @Instantiated(fulfilledByType: "Song", erasedToConcreteExistential: true) let track: AnyTrack
    @Instantiated let deckBuilder: Instantiator<Deck>
    let differentialValueCreationStamp = ProbeStamp.next()
}

public protocol Track: AnyObject {}
public struct AnyTrack { public let base: any Track; public init(_ base: any Track) { self.base = base } }

@Instantiable
public final class Player: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Song: Instantiable, Track {
    public init(player: LazilyInstantiated<Player>) { self.player = player }
    @Received let player: LazilyInstantiated<Player>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Deck: Instantiable {
    public init(track: AnyTrack, player: LazilyInstantiated<Player>) { self.track = track; self.player = player }
    @Received let track: AnyTrack
    @Received let player: LazilyInstantiated<Player>
    let differentialValueCreationStamp = ProbeStamp.next()
}
