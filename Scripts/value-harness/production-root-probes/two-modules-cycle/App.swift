// module: FuzzApp
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(viewer: Viewer, feedBuilder: Instantiator<Feed>, local: LocalReader) { self.viewer = viewer; self.feedBuilder = feedBuilder; self.local = local }
    @Instantiated let viewer: Viewer
    @Instantiated let feedBuilder: Instantiator<Feed>
    @Instantiated let local: LocalReader
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class LocalReader: Instantiable {
    public init(viewer: Viewer) { self.viewer = viewer }
    @Received let viewer: Viewer
    let differentialValueCreationStamp = ProbeStamp.next()
}
