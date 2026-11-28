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

/// An internal mock root one of whose types is built where a label some receive only if available reads has a
/// declaration and where it has none, laid out from the node records of its world (`OnlyIfAvailableAnswers`): the type
/// is one variant, whose function every call shares.
struct SafeDIToolNodeRecordsMockOptionalParameterTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTypeInOneFunction_whenItIsBuiltBeforePromotedPropertyAndBeneathTypeThatReceivesIt() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		withKnownIssue("This line’s mock world has no LazilyInstantiated or only-if-available kind; the root keeps its tree’s mock.") {
			#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [[]])
			#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
			// `mock()` builds `badge` before `session`, which it promotes for `Settings`, and `Settings` builds `badge` after
			// it: both calls are of the one `__safeDI_badge`, as are the calls of what `Badge` builds.
			#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            badge: Badge.SafeDIMockConfiguration = .init(),
			            session: (() -> Session)? = nil,
			            detailBuilder: Detail.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                badge: badge,
			                session: session,
			                detailBuilder: detailBuilder
			            )
			        }

			        var badge: Badge.SafeDIMockConfiguration { __safeDI_storage.badge }
			        var session: (() -> Session)? { __safeDI_storage.session }
			        var detailBuilder: Detail.SafeDIMockConfiguration { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                badge: Badge.SafeDIMockConfiguration,
			                session: (() -> Session)?,
			                detailBuilder: Detail.SafeDIMockConfiguration
			            ) {
			                self.badge = badge
			                self.session = session
			                self.detailBuilder = detailBuilder
			            }

			            let badge: Badge.SafeDIMockConfiguration
			            let session: (() -> Session)?
			            let detailBuilder: Detail.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_badge(safeDIOverrides: Badge.SafeDIMockConfiguration) -> Badge {
			            let icon = if let safeDIBuilder = safeDIOverrides.icon { safeDIBuilder() } else { Icon() }
			            let formatter = LazilyInstantiated<Formatter> {
			                __safeDI_formatter(safeDIOverrides: safeDIOverrides.formatter)
			            }
			            let panelBuilder = Instantiator<Panel> {
			                __safeDI_panelBuilder(title: $0, safeDIOverrides: safeDIOverrides.panelBuilder)
			            }
			            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(icon, formatter, panelBuilder) } else { Badge(icon: icon, formatter: formatter, panelBuilder: panelBuilder) }
			        }
			        func __safeDI_formatter(safeDIOverrides: (() -> Formatter)?) -> Formatter {
			            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { Formatter() }
			        }
			        func __safeDI_panelBuilder(title: String, safeDIOverrides: ((String) -> Panel)?) -> Panel {
			            if let safeDIBuilder = safeDIOverrides { safeDIBuilder(title) } else { Panel(title: title) }
			        }
			        let badge: Badge = __safeDI_badge(safeDIOverrides: safeDIOverrides.badge)
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_settings(safeDIOverrides: Settings.SafeDIMockConfiguration) -> Settings {
			            let badge: Badge = __safeDI_badge(safeDIOverrides: safeDIOverrides.badge)
			            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(session, badge) } else { Settings(session: session, badge: badge) }
			        }
			        func __safeDI_detailBuilder(safeDIOverrides: Detail.SafeDIMockConfiguration) -> Detail {
			            let viewModel = if let safeDIBuilder = safeDIOverrides.viewModel { safeDIBuilder(session) } else { ViewModel(session: session) }
			            let settings: Settings = __safeDI_settings(safeDIOverrides: safeDIOverrides.settings)
			            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(viewModel, settings) } else { Detail(viewModel: viewModel, settings: settings) }
			        }
			        let detailBuilder = Instantiator<Detail> {
			            __safeDI_detailBuilder(safeDIOverrides: safeDIOverrides.detailBuilder)
			        }
			        return Root(badge: badge, detailBuilder: detailBuilder)
			    }
			}
			#endif
			""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeIsBuiltBeforePromotedPropertyAndBeneathTypeThatReceivesIt() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		withKnownIssue("This line’s mock world has no LazilyInstantiated or only-if-available kind; the root keeps its tree’s mock.") {
			#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		}
		func badge(_ place: String) -> String {
			".init(icon: { marked(Icon(), \"\(place).icon\") }, formatter: { marked(Formatter(), \"\(place).formatter\") }, panelBuilder: { marked(Panel(title: $0), \"\(place).panel\") }, { marked(Badge(icon: $0, formatter: $1, panelBuilder: $2), \"\(place)\") })"
		}
		let detail = ".init(viewModel: { marked(ViewModel(session: $0), \"viewModel\") }, settings: .init(badge: \(badge("settings.badge")), { marked(Settings(session: $0, badge: $1), \"settings\") }), { marked(Detail(viewModel: $0, settings: $1), \"detail\") })"
		let overridden = "Root.mock(safeDIOverrides: .init(badge: \(badge("badge")), session: { marked(Session(), \"session\") }, detailBuilder: \(detail)))"
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: ["Root.swift": Self.fixture], generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: ["Root.swift": Self.fixture], generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().badge.formatter.instance"),
				DifferentialValueProbe("Root.mock().badge.panelBuilder.instantiate(\"title\")"),
				DifferentialValueProbe("Root.mock().detailBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().detailBuilder.instantiate().settings.badge.formatter.instance"),
				DifferentialValueProbe("Root.mock().detailBuilder.instantiate().settings.badge.panelBuilder.instantiate(\"title\")"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden lazy", expression: "\(overridden).badge.formatter.instance"),
				DifferentialValueProbe(name: "overridden instantiator", expression: "\(overridden).badge.panelBuilder.instantiate(\"title\")"),
				DifferentialValueProbe(name: "overridden detail", expression: "\(overridden).detailBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden detail lazy", expression: "\(overridden).detailBuilder.instantiate().settings.badge.formatter.instance"),
				DifferentialValueProbe(name: "overridden detail instantiator", expression: "\(overridden).detailBuilder.instantiate().settings.badge.panelBuilder.instantiate(\"title\")"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read at each place: each marks a value its closure built.
		for marker in ["badge", "badge.icon", "badge.formatter", "badge.panel", "session", "detail", "viewModel", "settings", "settings.badge", "settings.badge.icon", "settings.badge.formatter", "settings.badge.panel"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root that builds `badge` and, through an `Instantiator`, a `Detail` whose `Settings` receives `session` and
	/// builds `badge` too. Nothing builds `session`, so `mock()` promotes it, and builds it after its own `badge`, which
	/// reads nothing of it. `ViewModel` receives `session` only if available, so the label is one whose declarations
	/// each call is read for. Each class carries a marker an override sets.
	private static let fixture = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(badge: Badge, detailBuilder: Instantiator<Detail>) {
	        self.badge = badge
	        self.detailBuilder = detailBuilder
	    }

	    @Instantiated let badge: Badge
	    @Instantiated let detailBuilder: Instantiator<Detail>
	}

	@Instantiable
	public final class Detail: Instantiable, Marked {
	    public init(viewModel: ViewModel, settings: Settings) {
	        self.viewModel = viewModel
	        self.settings = settings
	    }

	    @Instantiated let viewModel: ViewModel
	    @Instantiated let settings: Settings
	    public var marker = "built"
	}

	@Instantiable
	public final class ViewModel: Instantiable, Marked {
	    public init(session: Session?) {
	        self.session = session
	    }

	    @Received(onlyIfAvailable: true) let session: Session?
	    public var marker = "built"
	}

	@Instantiable
	public final class Settings: Instantiable, Marked {
	    public init(session: Session, badge: Badge) {
	        self.session = session
	        self.badge = badge
	    }

	    @Received let session: Session
	    @Instantiated let badge: Badge
	    public var marker = "built"
	}

	@Instantiable
	public final class Badge: Instantiable, Marked {
	    public init(icon: Icon, formatter: LazilyInstantiated<Formatter>, panelBuilder: Instantiator<Panel>) {
	        self.icon = icon
	        self.formatter = formatter
	        self.panelBuilder = panelBuilder
	    }

	    @Instantiated let icon: Icon
	    @Instantiated let formatter: LazilyInstantiated<Formatter>
	    @Instantiated let panelBuilder: Instantiator<Panel>
	    public var marker = "built"
	}

	@Instantiable
	public final class Icon: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable
	public final class Formatter: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable
	public final class Panel: Instantiable, Marked {
	    public init(title: String) {
	        self.title = title
	    }

	    @Forwarded let title: String
	    public var marker = "built"
	}

	@Instantiable
	public final class Session: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}
	"""

	/// What `body` returns with every internal mock root node records accept laid out from them, and the report of each
	/// mock root of the run, in the order of the roots' names.
	private static func layingOutMockRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports.sorted { $0.root < $1.root })
	}
}
