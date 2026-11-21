// The implementations of the seams’ holes, which hand-written calls pass to the seams’ builders.
import Core
import Feature
import Feed
import SafeDI

/// “Adopting SafeDI in a large codebase”: the app’s implementation of `Feed`’s `FeedService`.
@Instantiable(fulfillingAdditionalTypes: [FeedService.self])
final class AppFeedService: FeedService, Instantiable {
	init(session: Session) {
		self.session = session
	}

	func refresh() async {}

	@Received private let session: Session
}

/// “Generating a dependency tree per module”: `DefaultUploader`, whose `UploadJob`s receive `exportService`.
final class DefaultUploader: Uploader {
	init(jobBuilder: Instantiator<UploadJob>) {
		self.jobBuilder = jobBuilder
	}

	private let jobBuilder: Instantiator<UploadJob>
}

@Instantiable
final class UploadJob: Instantiable {
	init(exportService: ExportService) {
		self.exportService = exportService
	}

	@Received private let exportService: ExportService
}

final class DefaultProfileStore: ProfileStore {
	init() {}
}

final class AppMaker: Maker {
	init(name: String) {
		self.name = name
	}

	private let name: String
}

final class AppReporter: Reporter {
	init() {}
}
