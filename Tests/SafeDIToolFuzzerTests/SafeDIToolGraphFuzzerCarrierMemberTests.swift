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

/// The `carrier.member` check: generated code stores or passes a seam's carrier, never a closure member of it apart
/// from it (`GraphFuzzerCarrierMembers.membersReadApart(in:)`).
struct SafeDIToolGraphFuzzerCarrierMemberTests {
	@Test
	func membersReadApart_isEmpty_whenEveryMemberReadIsCalled() {
		let files = ["Feed/Home+SafeDI.swift": Self.home(body: """
		        let screen = __safeDI_apiBuilder.screen(__safeDI_Values1(theme: theme))
		        let api: any Api = screen.api()
		        self.init(theme: theme, api: api, screen: screen)
		"""), "Feed/Home+SafeDICarrier.swift": Self.carriers]

		#expect(GraphFuzzerCarrierMembers.membersReadApart(in: files) == [])
		#expect(GraphFuzzerCarrierMembers.judgedReadCount(in: files) == 2)
	}

	@Test
	func membersReadApart_reportsRead_whenMemberIsBoundApartFromItsCarrier() {
		let files = ["Feed/Home+SafeDI.swift": Self.home(body: """
		        let screenMember = __safeDI_apiBuilder.screen
		        let screen = screenMember(__safeDI_Values1(theme: theme))
		        self.init(theme: theme, api: screen.api(), screen: screen)
		"""), "Feed/Home+SafeDICarrier.swift": Self.carriers]

		#expect(GraphFuzzerCarrierMembers.membersReadApart(in: files) == [
			"`Feed/Home+SafeDI.swift` line 3: `__safeDI_apiBuilder.screen` is read apart from its carrier: let screenMember = __safeDI_apiBuilder.screen",
		])
	}

	@Test
	func membersReadApart_reportsRead_whenMemberOfCarrierAMemberReturnedIsPassedAsArgument() {
		let files = ["Feed/Home+SafeDI.swift": Self.home(body: """
		        let screen = __safeDI_apiBuilder.screen(__safeDI_Values1(theme: theme))
		        self.init(theme: theme, api: Self.build(screen.api), screen: screen)
		"""), "Feed/Home+SafeDICarrier.swift": Self.carriers]

		#expect(GraphFuzzerCarrierMembers.membersReadApart(in: files) == [
			"`Feed/Home+SafeDI.swift` line 4: `screen.api` is read apart from its carrier: self.init(theme: theme, api: Self.build(screen.api), screen: screen)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func carrierMemberReadApartFailure_reportsFailure_whenAcceptedGraphBindsMemberApart() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["Feed/Home+SafeDI.swift": Self.home(body: """
		        let screenMember = __safeDI_apiBuilder.screen
		        self.init(theme: theme, api: screenMember(__safeDI_Values1(theme: theme)).api(), screen: nil)
		"""), "Feed/Home+SafeDICarrier.swift": Self.carriers], warnings: [])
		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)

		#expect(runs.carrierMemberReadApartFailure?.kind == .carrierMemberReadApart)
	}

	/// A seam's initializer only generated code calls, taking the carrier of `Api`, around `body`.
	private static func home(body: String) -> String {
		"""
		extension Home {
		    public convenience init(__safeDI_theme theme: Theme, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		\(body)
		    }
		}
		"""
	}

	/// The carriers of `Home`'s hole type `Api`: the root's, whose member builds `Screen`'s level carrier, and that level's.
	private static let carriers = """
	extension Home {
	    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
	        public let screen: (__safeDI_Values1) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

	        public init(screen: @escaping (__safeDI_Values1) -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
	            self.screen = screen
	        }
	    }

	    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
	        public let api: () -> __safeDI_Built

	        public init(api: @escaping () -> __safeDI_Built) {
	            self.api = api
	        }
	    }
	}
	"""
}
