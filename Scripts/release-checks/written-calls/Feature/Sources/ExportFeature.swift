// From the manual’s “Generating a dependency tree per module”: a seam whose hole’s builder takes nothing.
import SafeDI

public final class ExportService {
	public init() {}
}

public protocol Uploader {}

@Instantiable(generateDependencyTree: true)
public final class ExportFeature: Instantiable {
	public init(exportService: ExportService, uploader: any Uploader) {
		self.exportService = exportService
		self.uploader = uploader
	}

	@Received private let exportService: ExportService
	@Instantiated private let uploader: any Uploader
}
