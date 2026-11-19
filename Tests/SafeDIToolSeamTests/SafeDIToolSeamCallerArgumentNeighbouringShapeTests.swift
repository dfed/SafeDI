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

/// What a call hands a value its fills read of the caller's scope, where two fills of the call read one label in
/// different forms and only one takes it from the call: that fill is handed the caller's declaration in the form it takes
/// (`ArgumentSource.preferredCallerArgument(among:)`).
struct SafeDIToolSeamCallerArgumentNeighbouringShapeTests: ~Copyable {
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
	mutating func generate_wrapsCallersTokenForUserServicesFill_whenApisFillCapturesCallersToken() async throws {
		// `Desk` binds `token` lazily above `Model`'s place, so `userService`'s fill takes the wrapper, which the root
		// dispatcher wraps of `Root`'s plain `token`. `Panel`'s only route binds no `token`, so `api`'s fill reads `Root`'s
		// own, which it captures.
		let feature = [
			"public protocol UserService {}",
			"public protocol Api {}",
			seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
			seamFixtureType(named: "Desk", declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let model: Model"]),
			seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let desk: Desk", "@Instantiated let model: Model", "@Instantiated let panel: Panel"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let token: Token"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: ["@Received let token: Token"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let office: Office"]),
		]
		try await expectApp(feature: feature, app: app, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_BE2826E04FD0676E.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Office() -> Office.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(panel: { _ in __safeDI_apiBuilder_Office_Panel_Scope() })
		            }
		            func __safeDI_apiBuilder_Office_Panel_Scope() -> Office.SafeDIScope_Api.Panel_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = DefaultApi(token: token)
		                    return api
		                })
		            }
		            func __safeDI_userServiceBuilder_Office() -> Office.SafeDIScope_UserService.__safeDI_Builder<any UserService> {
		                .init(desk: { _ in __safeDI_userServiceBuilder_Office_Desk_Scope() }, model: { _ in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
		            }
		            func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.SafeDIScope_UserService.Desk_Scope.__safeDI_Builder<any UserService> {
		                .init(model: { values in __safeDI_userServiceBuilder_Office_Model_Scope(token: values.token) })
		            }
		            func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.SafeDIScope_UserService.Model_Scope.__safeDI_Builder<any UserService> {
		                .init(userService: { _ in
		                    let userService: any UserService = DefaultUserService(token: token.instance)
		                    return userService
		                })
		            }
		            return Office(__safeDI_apiBuilder: __safeDI_apiBuilder_Office(), __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCallersTokenForUserServicesFill_whenApisFillTakesTokenFromShelf() async throws {
		// `api`'s fill takes `token` by value, which `Shelf` passes on `Panel`'s only route, and `userService`'s takes the
		// wrapper, which the root dispatcher wraps of `Root`'s `token`.
		let feature = [
			"public protocol UserService {}",
			"public protocol Api {}",
			seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
			seamFixtureType(named: "Desk", declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let model: Model"]),
			seamFixtureType(named: "Shelf", declarations: ["@Instantiated let token: Token", "@Instantiated let panel: Panel"]),
			seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let desk: Desk", "@Instantiated let model: Model", "@Instantiated let shelf: Shelf"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let token: Token"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: ["@Received let token: Token"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let office: Office"]),
		]
		try await expectApp(feature: feature, app: app, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_8C350C040CB8FBDD.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Office() -> Office.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(shelf: { _ in __safeDI_apiBuilder_Office_Shelf_Scope() })
		            }
		            func __safeDI_apiBuilder_Office_Shelf_Scope() -> Office.SafeDIScope_Api.Shelf_Scope.__safeDI_Builder<any Api> {
		                .init(panel: { values in __safeDI_apiBuilder_Office_Panel_Scope(token: values.token) })
		            }
		            func __safeDI_apiBuilder_Office_Panel_Scope(token: Token) -> Office.SafeDIScope_Api.Panel_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = DefaultApi(token: token)
		                    return api
		                })
		            }
		            func __safeDI_userServiceBuilder_Office() -> Office.SafeDIScope_UserService.__safeDI_Builder<any UserService> {
		                .init(desk: { _ in __safeDI_userServiceBuilder_Office_Desk_Scope() }, model: { _ in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
		            }
		            func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.SafeDIScope_UserService.Desk_Scope.__safeDI_Builder<any UserService> {
		                .init(model: { values in __safeDI_userServiceBuilder_Office_Model_Scope(token: values.token) })
		            }
		            func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.SafeDIScope_UserService.Model_Scope.__safeDI_Builder<any UserService> {
		                .init(userService: { _ in
		                    let userService: any UserService = DefaultUserService(token: token.instance)
		                    return userService
		                })
		            }
		            return Office(__safeDI_apiBuilder: __safeDI_apiBuilder_Office(), __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let moduleInfoComment = "If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."

	/// Expects `App`'s generated file, for `feature`'s seam called from `app`, to be `expected`, and the values it builds for
	/// `Root()` to equal those of the same graph with every fulfilling declaration in `Feature`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectApp(feature: [String], app: [String], expected: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let generated: String? = output.modules["App"]?.generatedFiles["App.swift"]
		let expectedFile: String = generatedFileHeader + expected
		#expect(generated == expectedFile, sourceLocation: sourceLocation)
		guard compileVerificationIsEnabled else { return }
		let visibleModules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Array(app.dropLast()), app: Array(app.suffix(1)))
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
