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

import Testing
@testable import SafeDIToolTestSupport

/// The query oracle's reading of generated code (`GraphFuzzerQuerySupplies(generatedFiles:kindsByLabelByType:)`), which
/// resolves each received argument of each construction as Swift scopes names.
struct SafeDIToolGraphFuzzerQuerySupplyTests {
	@Test
	func generatedCodeSupplies_followParameterToEveryCall_whenLazyCycleCallsBuilderFunctionFromTwoScopes() {
		let supplies = GraphFuzzerQuerySupplies(generatedFiles: ["App+SafeDI.swift": Self.lazyCycleCode], kindsByLabelByType: Self.lazyCycleKinds)

		#expect(supplies.unreadable.isEmpty)
		#expect(supplies.valuesByReceive == [
			"Screen.currentSession": ["App.session", "Step.session"],
			"Screen.session": ["App.session", "Step.session"],
		])
	}

	@Test
	func generatedCodeSupplies_readNil_whenCallPassesNil() {
		let code = Self.lazyCycleCode.replacingOccurrences(of: "        let screenBuilder = Instantiator<Screen> {\n            __safeDI_screenBuilder(session: session)", with: "        let screenBuilder = Instantiator<Screen> {\n            __safeDI_screenBuilder(session: nil)")

		let supplies = GraphFuzzerQuerySupplies(generatedFiles: ["App+SafeDI.swift": code], kindsByLabelByType: Self.lazyCycleKinds)

		#expect(supplies.valuesByReceive["Screen.session"] == ["nil", "Step.session"])
	}

	@Test
	func differences_listReceive_whenExportNamesAnotherSupplier() throws {
		let generated = GraphFuzzerQuerySupplies(generatedFiles: ["App+SafeDI.swift": Self.lazyCycleCode], kindsByLabelByType: Self.lazyCycleKinds)
		let exported = try #require(try GraphFuzzerQuerySupplies(exportedJSON: """
		{
		  "completeness" : "trees",
		  "declarations" : [
		    { "id" : "M.App", "typeName" : "App", "dependencies" : [] },
		    { "id" : "M.Step", "typeName" : "Step", "dependencies" : [] },
		    { "id" : "M.Screen", "typeName" : "Screen", "dependencies" : [
		      { "source" : "received", "label" : "session", "provenance" : [ { "source" : "declaration", "declaredBy" : "M.App", "label" : "session" } ] },
		      { "source" : "received", "label" : "currentSession", "aliasOf" : { "label" : "session" }, "provenance" : [
		        { "source" : "declaration", "declaredBy" : "M.App", "label" : "session" },
		        { "source" : "nil", "reason" : { "kind" : "noProvidingDeclaration", "message" : "" } }
		      ] }
		    ] }
		  ]
		}
		"""))

		#expect(exported.differences(from: generated) == [
			#"Screen.currentSession: ["App.session", "nil"] against ["App.session", "Step.session"]"#,
			#"Screen.session: ["App.session"] against ["App.session", "Step.session"]"#,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func problems_reportMark_whenExportMarksDependencyInstantiatedOnlyIfAvailable() throws {
		// With dependencies instantiated only if available marked too, no graph of the first 2,500 base corpus seeds or the
		// first 1,000 seam corpus seeds fails, so the marks oracle's check of such a mark is shown to fire here, on an
		// export written by hand.
		let marks = try GraphFuzzerUnfulfilledDependencies(exportedJSON: """
		{
		  "completeness" : "partialTrees",
		  "declarations" : [
		    { "id" : "M.Root", "typeName" : "Root", "dependencies" : [
		      { "source" : "instantiated", "label" : "service", "plainType" : "Service", "isUnfulfilled" : true, "filePath" : "/fixture/File0.swift", "line" : 5 },
		      { "source" : "instantiated", "label" : "optionalService", "plainType" : "Service", "isOnlyIfAvailable" : true, "isUnfulfilled" : true, "filePath" : "/fixture/File0.swift", "line" : 6 }
		    ] }
		  ]
		}
		""")

		#expect(marks.problems(
			generateErrorLocations: ["File0.swift:5", "File0.swift:6"],
			errorLocationsWithMissingTypesDeclared: nil,
			fixture: GraphFuzzerFixture(seed: 1, swiftFileContent: []),
		) == ["The export marks the dependency at File0.swift:6 unfulfilled, which is instantiated only if available and so is `nil`."])
	}

	@Test
	func kindsByLabelByType_namesEachKind_whenExportListsEverySourceAndLifetime() throws {
		let kinds = try GraphFuzzerQuerySupplies.kindsByLabelByType(exportedJSON: """
		{
		  "declarations" : [
		    { "typeName" : "Screen", "dependencies" : [
		      { "source" : "instantiated", "lifetime" : "eager", "label" : "model" },
		      { "source" : "instantiated", "lifetime" : "lazy", "label" : "cache" },
		      { "source" : "instantiated", "lifetime" : "builder", "label" : "stepBuilder" },
		      { "source" : "instantiated", "lifetime" : "eager", "label" : "analytics", "isOnlyIfAvailable" : true },
		      { "source" : "forwarded", "label" : "id" },
		      { "source" : "received", "label" : "session" },
		      { "source" : "received", "label" : "currentSession", "aliasOf" : { "label" : "session" } }
		    ] }
		  ]
		}
		""")

		#expect(kinds == ["Screen": [
			"model": "instantiated",
			"cache": "lazy",
			"stepBuilder": "builder",
			"analytics": "absent",
			"id": "forwarded",
			"session": "received",
			"currentSession": "alias",
		]])
	}

	private static let lazyCycleKinds = [
		"App": ["session": "instantiated", "screenBuilder": "builder"],
		"Screen": ["session": "received", "currentSession": "alias", "stepBuilder": "builder"],
		"Step": ["session": "instantiated", "screenBuilder": "builder"],
		"Session": [String: String](),
	]

	private static let lazyCycleCode = """
	extension App {
	    public convenience init() {
	        let session = Session()
	        func __safeDI_screenBuilder(session: Session) -> Screen {
	            let currentSession: Session = session
	            func __safeDI_stepBuilder() -> Step {
	                let session = Session()
	                let screenBuilder = Instantiator<Screen> {
	                    __safeDI_screenBuilder(session: session)
	                }
	                return Step(session: session, screenBuilder: screenBuilder)
	            }
	            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
	            return Screen(session: session, currentSession: currentSession, stepBuilder: stepBuilder)
	        }
	        let screenBuilder = Instantiator<Screen> {
	            __safeDI_screenBuilder(session: session)
	        }
	        self.init(session: session, screenBuilder: screenBuilder)
	    }
	}

	#if DEBUG
	extension Screen {
	    static func mock(session: Session) -> Screen {
	        Screen(session: Session(), currentSession: session, stepBuilder: Instantiator<Step> { fatalError() })
	    }
	}
	#endif
	"""
}
