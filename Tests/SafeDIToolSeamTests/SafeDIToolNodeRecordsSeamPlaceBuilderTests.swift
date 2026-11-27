// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The internal mock of a type that generates its dependency tree, laid out from node records where it takes a builder for
/// the places it builds: the type that instantiates a place binds it from the builder at the top of its function, and the
/// mocked type's own place is bound before the nodes, as the mock's walk writes them.
struct SafeDIToolNodeRecordsSeamPlaceBuilderTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: SeamPlaceBuilderCell.laidOut)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenSeamsOwnMockBindsPlacesFromBuilder(cell: SeamPlaceBuilderCell) async throws {
		let modules = cell.modules
		let walkOutput = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter { $0.isMockRoot && $0.root == "Service" }.map(\.refusal) == [nil])
		#expect(reports.filter { $0.isMockRoot && $0.root == "Service" }.map(\.isLaidOutFromNodeRecords) == [true])
		if let expectedMock = cell.mockDifferingFromWalks {
			// Differences 1 and 2 of the laid out text: each function is declared once in the root's body and handed its overrides.
			let mock = try Self.mock(of: #require(output.modules["Feature"]?.generatedFiles["Feature.swift"]))
			#expect(mock == expectedMock, "Unexpected mock \(mock)")
		} else {
			#expect(output.modules["Feature"]?.generatedFiles == walkOutput.modules["Feature"]?.generatedFiles)
		}
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: walkOutput, modules: modules),
			probes: [
				DifferentialValueProbe("plainProbe()"),
				DifferentialValueProbe(name: "overridden root", expression: "overriddenProbe()"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every builder and override was read: each marks the value it set.
		for marker in cell.markers {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test(arguments: SeamPlaceBuilderCell.walked)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTheWalksText_whenRecordsDoNotServeBuildersPlace(cell: SeamPlaceBuilderCell) async throws {
		let modules = cell.modules
		let walkOutput = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		// A place built inside a `@Sendable` function, and a place the mocked type holds in a wrapper beside a node, keep
		// the refusal, so the walk writes the mock.
		#expect(reports.filter { $0.isMockRoot && $0.root == "Service" }.map(\.isLaidOutFromNodeRecords) == [false])
		#expect(reports.filter { $0.isMockRoot && $0.root == "Service" }.map { $0.everyRefusal.contains("uncoveredDependency") } == [true])
		#expect(output.modules["Feature"]?.generatedFiles == walkOutput.modules["Feature"]?.generatedFiles)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The text of `Service.mock()` in `generatedFile`, from its declaration to its closing brace.
	private static func mock(of generatedFile: String) throws -> String {
		let start = try #require(generatedFile.range(of: "    static func mock("))
		let end = try #require(generatedFile.range(of: "\n    }\n", range: start.upperBound..<generatedFile.endIndex))
		return String(generatedFile[start.lowerBound..<end.upperBound])
	}

	/// Runs `body` with mock roots laid out from node records, and returns what it returns with every root's report.
	private static func layingOutMockRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports)
	}
}

/// A seam `Service` that generates its own mock and holds places of `UserService`, with what its laid out mock is.
struct SeamPlaceBuilderCell: CustomTestStringConvertible, Sendable {
	/// What the cell tests.
	let testDescription: String
	/// The properties `Service` declares.
	let serviceDeclarations: [String]
	/// The call of `Service.mock` that sets every builder and override, each marking the value it returns; empty for a cell
	/// that runs no probe.
	let overriddenCall: String
	/// What each probe returns beside the `Service` it builds, named `service`.
	var reads = [String]()
	/// The markers the overridden probe's values hold.
	var markers = [String]()
	/// `mock()` as it is laid out, where its text is not the walk's.
	var mockDifferingFromWalks: String?

	/// Module `Feature`, which declares the cell's `Service` and the types it builds.
	var modules: [ModuleFixture] {
		let parameters = serviceDeclarations.map { declaration in
			declaration.split(separator: " ").drop { !$0.hasSuffix(":") || $0.hasPrefix("@") }.joined(separator: " ")
		}
		let labels = parameters.map { $0.prefix { $0 != ":" } }
		let returned = (["service"] + reads).joined(separator: ", ")
		return [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				Self.types,
				"""
				import SafeDI

				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Service: Instantiable {
				    public init(\(parameters.joined(separator: ", "))) {
				\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
				    }

				\(serviceDeclarations.map { "    \($0)" }.joined(separator: "\n"))
				}
				""",
			] + (overriddenCall.isEmpty ? [] : [
				"""
				func plainProbe() -> [Any] {
				    let service = Service.mock(otherServiceBuilder: { LiveOtherService() }, userServiceBuilder: { LiveUserService() })
				    return [\(returned)]
				}

				func overriddenProbe() -> [Any] {
				    let service = \(overriddenCall)
				    return [\(returned)]
				}
				""".replacingOccurrences(of: "otherServiceBuilder: { LiveOtherService() }, ", with: overriddenCall.contains("otherServiceBuilder") ? "otherServiceBuilder: { LiveOtherService() }, " : ""),
			])),
		]
	}

	/// The cells whose mock is laid out from node records.
	static let laidOut: [SeamPlaceBuilderCell] = [
		SeamPlaceBuilderCell(
			testDescription: "two siblings instantiate the place under one label beside the mocked type's own place",
			serviceDeclarations: ["@Instantiated public let userService: any UserService", "@Instantiated public let settings: Settings", "@Instantiated public let account: Account"],
			overriddenCall: "Service.mock(userServiceBuilder: { marked(LiveUserService(), \"place\") }, safeDIOverrides: .init(settings: { marked(Settings(service: $0), \"settings\") }, account: { marked(Account(service: $0), \"account\") }))",
			markers: ["place", "settings", "account"],
		),
		SeamPlaceBuilderCell(
			testDescription: "a node receives the mocked type's own place",
			serviceDeclarations: ["@Instantiated public let userService: any UserService", "@Instantiated public let reader: Reader"],
			overriddenCall: "Service.mock(userServiceBuilder: { marked(LiveUserService(), \"place\") }, safeDIOverrides: .init(reader: { marked(Reader(userService: $0), \"reader\") }))",
			markers: ["place", "reader"],
		),
		SeamPlaceBuilderCell(
			testDescription: "the mocked type holds its only place lazily",
			serviceDeclarations: ["@Instantiated public let userService: LazilyInstantiated<any UserService>"],
			overriddenCall: "Service.mock(userServiceBuilder: { marked(LiveUserService(), \"place\") })",
			reads: ["service.userService.instance"],
			markers: ["place"],
		),
		SeamPlaceBuilderCell(
			testDescription: "the place is beneath an instantiator",
			serviceDeclarations: ["@Instantiated public let profileBuilder: Instantiator<Profile>"],
			overriddenCall: "Service.mock(userServiceBuilder: { marked(LiveUserService(), \"place\") }, safeDIOverrides: .init(profileBuilder: { marked(Profile(userService: $0), \"profile\") }))",
			reads: ["service.profileBuilder.instantiate()", "service.profileBuilder.instantiate()"],
			markers: ["place", "profile"],
		),
		SeamPlaceBuilderCell(
			testDescription: "two types instantiate places of two hole types under one label",
			serviceDeclarations: ["@Instantiated public let settings: Settings", "@Instantiated public let ledger: Ledger"],
			overriddenCall: "Service.mock(otherServiceBuilder: { marked(LiveOtherService(), \"other\") }, userServiceBuilder: { marked(LiveUserService(), \"place\") }, safeDIOverrides: .init(settings: { marked(Settings(service: $0), \"settings\") }, ledger: { marked(Ledger(service: $0), \"ledger\") }))",
			markers: ["other", "place", "settings", "ledger"],
		),
		SeamPlaceBuilderCell(
			testDescription: "the type that instantiates the place declares a property labeled like the builder",
			serviceDeclarations: ["@Instantiated public let badge: Badge"],
			overriddenCall: "Service.mock(userServiceBuilder: { marked(LiveUserService(), \"place\") }, safeDIOverrides: .init(badge: .init(userServiceBuilder: { marked(Analytics(), \"analytics\") }, { marked(Badge(userService: $0, userServiceBuilder: $1), \"badge\") })))",
			reads: ["service.badge.userServiceBuilder.instantiate()"],
			markers: ["place", "analytics", "badge"],
			mockDifferingFromWalks: """
			    static func mock(
			        userServiceBuilder: @escaping () -> any UserService,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_userServiceBuilder_ = userServiceBuilder
			        func __safeDI_userServiceBuilder(safeDIOverrides: (() -> Analytics)?) -> Analytics {
			            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { Analytics() }
			        }
			        func __safeDI_badge(safeDIOverrides: Badge.SafeDIMockConfiguration) -> Badge {
			            let userService: any UserService = __safeDI_userServiceBuilder_()
			            let userServiceBuilder = Instantiator<Analytics> {
			                __safeDI_userServiceBuilder(safeDIOverrides: safeDIOverrides.userServiceBuilder)
			            }
			            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(userService, userServiceBuilder) } else { Badge(userService: userService, userServiceBuilder: userServiceBuilder) }
			        }
			        let badge: Badge = __safeDI_badge(safeDIOverrides: safeDIOverrides.badge)
			        return Service(badge: badge)
			    }

			""",
		),
	]

	/// The cells whose mock the walk still writes.
	static let walked: [SeamPlaceBuilderCell] = [
		SeamPlaceBuilderCell(
			testDescription: "the place is beneath a `@Sendable` instantiator",
			serviceDeclarations: ["@Instantiated public let profileBuilder: SendableInstantiator<SendableProfile>"],
			overriddenCall: "",
		),
		SeamPlaceBuilderCell(
			testDescription: "the mocked type holds a place lazily beside a node",
			serviceDeclarations: ["@Instantiated public let userService: LazilyInstantiated<any UserService>", "@Instantiated public let settings: Settings"],
			overriddenCall: "",
		),
	]

	/// The types every cell's module declares.
	private static let types = """
	import SafeDI

	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}

	public protocol UserService: AnyObject {}

	public protocol OtherService: AnyObject {}

	public final class LiveUserService: UserService, Marked, @unchecked Sendable {
	    public init() {}

	    public var marker = "built"
	}

	public final class LiveOtherService: OtherService, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable
	public final class Analytics: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable
	public final class Profile: Instantiable, Marked {
	    public init(userService: any UserService) {
	        self.userService = userService
	    }

	    @Instantiated public let userService: any UserService
	    public var marker = "built"
	}

	@Instantiable
	public final class SendableProfile: Instantiable, @unchecked Sendable {
	    public init(userService: any UserService) {
	        self.userService = userService
	    }

	    @Instantiated public let userService: any UserService
	}

	@Instantiable
	public final class Settings: Instantiable, Marked {
	    public init(service: any UserService) {
	        self.service = service
	    }

	    @Instantiated public let service: any UserService
	    public var marker = "built"
	}

	@Instantiable
	public final class Account: Instantiable, Marked {
	    public init(service: any UserService) {
	        self.service = service
	    }

	    @Instantiated public let service: any UserService
	    public var marker = "built"
	}

	@Instantiable
	public final class Ledger: Instantiable, Marked {
	    public init(service: any OtherService) {
	        self.service = service
	    }

	    @Instantiated public let service: any OtherService
	    public var marker = "built"
	}

	@Instantiable
	public final class Reader: Instantiable, Marked {
	    public init(userService: any UserService) {
	        self.userService = userService
	    }

	    @Received public let userService: any UserService
	    public var marker = "built"
	}

	@Instantiable
	public final class Badge: Instantiable, Marked {
	    public init(userService: any UserService, userServiceBuilder: Instantiator<Analytics>) {
	        self.userService = userService
	        self.userServiceBuilder = userServiceBuilder
	    }

	    @Instantiated public let userService: any UserService
	    @Instantiated public let userServiceBuilder: Instantiator<Analytics>
	    public var marker = "built"
	}
	"""
}
