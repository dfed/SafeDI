// Types whose generated mocks or initializers take the parameter shapes the manual documents one by one.
import Core
import SafeDI

/// “The `mockOnly` parameter”: a forwarded type with a hand-written mock, which a flat `mock()` parameter defaults to.
@Instantiable(mockOnly: true)
public final class AppConfiguration {
	public init(environment: String) {
		self.environment = environment
	}

	public static func mock() -> AppConfiguration {
		AppConfiguration(environment: "mock")
	}

	public let environment: String
}

@Instantiable(generateMock: true)
public struct ConfiguredView: Instantiable {
	public init(configuration: AppConfiguration) {
		self.configuration = configuration
	}

	@Forwarded private let configuration: AppConfiguration
}

/// “Conditionally receiving dependencies” and “Dependency kinds in the generated mock”: an entry typed as optional.
@Instantiable(generateMock: true)
public struct GuestFeedView: Instantiable {
	public init(user: User?) {
		self.user = user
	}

	@Received(onlyIfAvailable: true) private let user: User?
}

/// “LazilyInstantiated” and “Dependency kinds in the generated mock”: a lazily instantiated dependency’s entry.
@Instantiable
public final class ReportService: Instantiable {
	public init() {}
}

@Instantiable(generateMock: true)
public final class ReportScreen: Instantiable {
	public init(reportService: LazilyInstantiated<ReportService>) {
		self.reportService = reportService
	}

	@Instantiated private let reportService: LazilyInstantiated<ReportService>
}

/// “Dependency kinds in the generated mock”: a dependency instantiated only if available that a declaration fulfills.
public protocol ReportAnalytics {}

@Instantiable(fulfillingAdditionalTypes: [ReportAnalytics.self])
public final class DefaultReportAnalytics: ReportAnalytics, Instantiable {
	public init() {}
}

@Instantiable(generateMock: true)
public final class ReportSummaryScreen: Instantiable {
	public init(analytics: (any ReportAnalytics)?) {
		self.analytics = analytics
	}

	@Instantiated(onlyIfAvailable: true) private let analytics: (any ReportAnalytics)?
}

/// “Overriding dependencies”: a labeled default-valued `@autoclosure` parameter. (The manual names the type `Service`.)
@Instantiable(generateMock: true)
public final class Retrier: Instantiable {
	public init(retries: @autoclosure () -> Int = 3) {
		self.retries = retries()
	}

	private let retries: Int
}

/// “Attributes for generated declarations”: a mock bound to the main actor.
@Instantiable(mockAttributes: "@MainActor", generateMock: true)
public final class MyPresenter: Instantiable {
	@MainActor public init() {}
}

/// “Attributes for generated declarations”: a root whose generated `init()` is bound to the main actor.
@Instantiable
public final class Presenter: Instantiable {
	@MainActor public init() {}
}

@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
public final class MainRoot: Instantiable {
	public init(presenter: Presenter) {
		self.presenter = presenter
	}

	@Instantiated private let presenter: Presenter
}

/// “Dependency kinds in the generated mock”, under “Names”: two flat parameters that share a label.
@Instantiable(generateMock: true)
public struct ItemsView: Instantiable {
	public init(first: FirstList, second: SecondList) {
		self.first = first
		self.second = second
	}

	@Instantiated private let first: FirstList
	@Instantiated private let second: SecondList
}

@Instantiable
public struct FirstList: Instantiable {
	public init(items: [String]) {
		self.items = items
	}

	@Received private let items: [String]
}

@Instantiable
public struct SecondList: Instantiable {
	public init(items: Set<String>) {
		self.items = items
	}

	@Received private let items: Set<String>
}

/// “Hand-written mocks”: a generated `mock()` that calls through to the method `customMockName` names.
@Instantiable(generateMock: true, customMockName: "customMock")
public struct NetworkClient: Instantiable {
	public init(logger: Logger) {
		self.logger = logger
	}

	@Instantiated let logger: Logger

	public static func customMock(logger: Logger = Logger()) -> NetworkClient {
		NetworkClient(logger: logger)
	}
}

/// “Overriding dependencies”: beneath a `Sendable` wrapper, a dependency the mock cannot build is a `@Sendable`
/// autoclosure parameter, to which a caller still writes a value.
public final class RemoteService: Sendable {
	public init() {}
}

@Instantiable
public final class Worker: Instantiable {
	public nonisolated init(remote: RemoteService) {
		self.remote = remote
	}

	@Received private let remote: RemoteService
}

@Instantiable(generateMock: true)
public final class SyncRoot: Instantiable {
	public init(workerBuilder: SendableInstantiator<Worker>) {
		self.workerBuilder = workerBuilder
	}

	@Instantiated private let workerBuilder: SendableInstantiator<Worker>
}
