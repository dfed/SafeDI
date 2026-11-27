// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

@Instantiable
public final class Feed: Instantiable {
    public init(postBuilder: Instantiator<Post>, viewer: Viewer) { self.postBuilder = postBuilder; self.viewer = viewer }
    @Instantiated let postBuilder: Instantiator<Post>
    @Received let viewer: Viewer
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Post: Instantiable {
    public init(feedBuilder: Instantiator<Feed>, viewer: Viewer) { self.feedBuilder = feedBuilder; self.viewer = viewer }
    @Instantiated let feedBuilder: Instantiator<Feed>
    @Instantiated let viewer: Viewer
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Viewer: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
