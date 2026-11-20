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
import Testing
@testable import SafeDIToolTestSupport

/// The oracle that generated code calls only the functions and initializers only generated code calls
/// (`GraphFuzzerOracle.callsOfEntriesMeantForPeople(in:)`), never a generated `mock()` or a seam's plain initializer.
struct SafeDIToolGraphFuzzerGeneratedOnlyCallTests {
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsOfEntriesMeantForPeople_reportsCall_whenGeneratedCodeCallsGeneratedMock() {
		let findings = GraphFuzzerOracle.callsOfEntriesMeantForPeople(in: [
			"Feed/Screen+SafeDIMock.swift": Self.screenPublicMock,
			"App/Root+SafeDIMock.swift": Self.rootMock(screenCall: "Screen.mock(session: session, safeDIOverrides: safeDIOverrides.screen)"),
		])

		#expect(findings == [
			"`App/Root+SafeDIMock.swift` calls `Screen.mock(`, which code people write calls, not `Screen.__safeDI_mock(`: let screen = Screen.mock(session: session, safeDIOverrides: safeDIOverrides.screen)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsOfEntriesMeantForPeople_reportsCall_whenGeneratedMockTierCallsNarrowerGeneratedMock() {
		let findings = GraphFuzzerOracle.callsOfEntriesMeantForPeople(in: [
			"Feed/Service+SafeDIMock.swift": """
			extension Service {
			    public static func mock(
			        analytics: Analytics? = nil
			    ) -> Service {
			        Service.mock(analytics: analytics, session: nil)
			    }

			    package static func mock(
			        analytics: Analytics? = nil,
			        session: Session? = nil
			    ) -> Service {
			        Service.__safeDI_mock(analytics: analytics, session: session)
			    }
			}
			""",
		])

		#expect(findings == [
			"`Feed/Service+SafeDIMock.swift` calls `Service.mock(`, which code people write calls, not `Service.__safeDI_mock(`: Service.mock(analytics: analytics, session: nil)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsOfEntriesMeantForPeople_isEmpty_whenGeneratedCodeCallsGeneratedOnlyMock() {
		let findings = GraphFuzzerOracle.callsOfEntriesMeantForPeople(in: [
			"Feed/Screen+SafeDIMock.swift": Self.screenPublicMock,
			"App/Root+SafeDIMock.swift": Self.rootMock(screenCall: "Screen.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides.screen)"),
		])

		#expect(findings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsOfEntriesMeantForPeople_isEmpty_whenGeneratedCodeCallsHandWrittenMock() {
		// No generated file declares `Screen`'s `mock()`: a person wrote it, for generated code to call.
		let findings = GraphFuzzerOracle.callsOfEntriesMeantForPeople(in: [
			"App/Root+SafeDIMock.swift": Self.rootMock(screenCall: "Screen.mock(session: session)"),
		])

		#expect(findings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsOfEntriesMeantForPeople_reportsCall_whenGeneratedCodeCallsSeamPlainInitializer() {
		let findings = GraphFuzzerOracle.callsOfEntriesMeantForPeople(in: [
			"Feed/Feature+SafeDI.swift": Self.featureSeam,
			"App/Root+SafeDI.swift": "extension Root {\n    public convenience init() {\n        let feature = Feature(session: Session())\n        self.init(feature: feature)\n    }\n}",
		])

		#expect(findings == [
			"`App/Root+SafeDI.swift` calls `Feature`’s plain initializer, which code people write calls, not the one only generated code calls: let feature = Feature(session: Session())",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsOfEntriesMeantForPeople_isEmpty_whenGeneratedCodeCallsSeamGeneratedOnlyInitializer() {
		let findings = GraphFuzzerOracle.callsOfEntriesMeantForPeople(in: [
			"Feed/Feature+SafeDI.swift": Self.featureSeam,
			"App/Root+SafeDI.swift": "extension Root {\n    public convenience init() {\n        _ = Feature.__safeDI_Feature_8A1B.self\n        let feature = Feature(__safeDI_session: Session())\n        self.init(feature: feature)\n    }\n}",
		])

		#expect(findings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generatedCodeCallsEntryMeantForPeopleFailure_reportsFailure_whenAcceptedGraphCallsGeneratedMock() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"Feed/Screen+SafeDIMock.swift": Self.screenPublicMock,
			"App/Root+SafeDIMock.swift": Self.rootMock(screenCall: "Screen.mock(session: session)"),
		], warnings: [])
		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)

		#expect(runs.generatedCodeCallsEntryMeantForPeopleFailure?.kind == .generatedCodeCallsEntryMeantForPeople)
	}

	/// `Screen`'s public mock, whose `mock()` calls the function only generated code calls.
	private static let screenPublicMock = """
	extension Screen {
	    public static func mock(
	        session: LazilyInstantiated<Session>? = nil
	    ) -> Screen {
	        Screen.__safeDI_mock(session: session)
	    }

	    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
	    public static func __safeDI_mock(
	        session: LazilyInstantiated<Session>? = nil
	    ) -> Screen {
	        Screen(session: session ?? LazilyInstantiated { Session() })
	    }
	}
	"""

	/// A seam whose module generates a plain initializer beside the one only generated code calls.
	private static let featureSeam = """
	extension Feature {
	    public convenience init(session: Session) {
	        self.init(__safeDI_session: session)
	    }

	    public convenience init(__safeDI_session session: @autoclosure @escaping () -> Session) {
	        self.init(session: session())
	    }
	}

	extension Feature {
	    public enum __safeDI_Feature_8A1B {}
	}
	"""

	/// `Root`'s internal mock, which builds its `Screen` with `screenCall`.
	private static func rootMock(screenCall: String) -> String {
		"""
		extension Root {
		    static func mock() -> Root {
		        let session = LazilyInstantiated<Session> { Session() }
		        let screen = \(screenCall)
		        return Root(session: session, screen: screen)
		    }
		}
		"""
	}
}
