// From the manual’s “Generating a dependency tree per module”: a seam that receives a value and instantiates a type
// that receives one value and another only if available.
import Core
import SafeDI

@Instantiable(generateDependencyTree: true)
public struct Screen: Instantiable {
	public init(user: User, cache: Cache) {
		self.user = user
		self.cache = cache
	}

	@Received private let user: User
	@Instantiated private let cache: Cache
}

@Instantiable
public struct Cache: Instantiable {
	public init(database: Database, logger: Logger?) {
		self.database = database
		self.logger = logger
	}

	@Received private let database: Database
	@Received(onlyIfAvailable: true) private let logger: Logger?
}
