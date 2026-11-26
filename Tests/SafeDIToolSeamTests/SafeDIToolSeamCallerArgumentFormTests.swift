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

/// What a seam's call hands each fill that takes a value of the caller's scope as a parameter, where two fills of the call
/// take one label in different forms: each fill is handed the caller's declaration in the form that fill takes.
struct SafeDIToolSeamCallerArgumentFormTests: ~Copyable {
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
	mutating func generate_handsEachFillCallersValueInItsForm_whenCallerHoldsValueAndFillsTakeWrapperAndValue() async throws {
		// `Desk` binds `token` lazily above one of `Model`'s places and `Shelf` binds it plainly above one of `Panel`'s, so
		// `userService`'s fill takes the wrapper and `api`'s the value, each as a parameter the root dispatcher hands from
		// `Root`'s plain `token`: wrapped for the one, as itself for the other.
		try await expectApp(feature: Self.feature, app: Self.app(rootToken: "Token"), expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Office_Shelf_Scope() -> Office.__safeDI_ApiCarrier_Shelf<any Api> {
		            .init(panel: { values_token in __safeDI_apiBuilder_Office_Panel_Scope(token: values_token) })
		        }
		        func __safeDI_apiBuilder_Office_Panel_Scope(token: Token) -> Office.__safeDI_ApiCarrier_Panel<any Api> {
		            .init(api: {
		                let api: any Api = DefaultApi(token: token)
		                return api
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_4AC6D9478D1F32DF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Office() -> Office.__safeDI_ApiCarrier<any Api> {
		                .init(shelf: { values_desk, values_model in __safeDI_apiBuilder_Office_Shelf_Scope() }, panel: { values_desk, values_model, values_shelf in __safeDI_apiBuilder_Office_Panel_Scope(token: token) })
		            }
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
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
	mutating func generate_handsEachFillCallersValueInItsForm_whenCallerHoldsWrapperAndFillsTakeWrapperAndValue() async throws {
		// As above, with `Root` holding `token` lazily: the root dispatcher hands the wrapper to one fill and its instance to
		// the other.
		try await expectApp(feature: Self.feature, app: Self.app(rootToken: "LazilyInstantiated<Token>"), expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Office_Shelf_Scope() -> Office.__safeDI_ApiCarrier_Shelf<any Api> {
		            .init(panel: { values_token in __safeDI_apiBuilder_Office_Panel_Scope(token: values_token) })
		        }
		        func __safeDI_apiBuilder_Office_Panel_Scope(token: Token) -> Office.__safeDI_ApiCarrier_Panel<any Api> {
		            .init(api: {
		                let api: any Api = DefaultApi(token: token)
		                return api
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        func __safeDI_token() -> Token {
		            Token()
		        }
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_4AC6D9478D1F32DF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Office() -> Office.__safeDI_ApiCarrier<any Api> {
		                .init(shelf: { values_desk, values_model in __safeDI_apiBuilder_Office_Shelf_Scope() }, panel: { values_desk, values_model, values_shelf in __safeDI_apiBuilder_Office_Panel_Scope(token: token.instance) })
		            }
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token) })
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
	mutating func generate_handsEachFillCallersValueInItsForm_whenFillsTakeWrapperAndValueUnderSwiftPackagePlugin() async throws {
		try await expectApp(feature: Self.feature, app: Self.app(rootToken: "Token"), integration: .swiftPackagePlugin, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Office_Shelf_Scope() -> Office.__safeDI_ApiCarrier_Shelf<any Api> {
		            .init(panel: { values_token in __safeDI_apiBuilder_Office_Panel_Scope(token: values_token) })
		        }
		        func __safeDI_apiBuilder_Office_Panel_Scope(token: Token) -> Office.__safeDI_ApiCarrier_Panel<any Api> {
		            .init(api: {
		                let api: any Api = DefaultApi(token: token)
		                return api
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_4AC6D9478D1F32DF.self // If this line does not compile, add the SafeDI plugin to the target that declares Office.
		            func __safeDI_apiBuilder_Office() -> Office.__safeDI_ApiCarrier<any Api> {
		                .init(shelf: { values_desk, values_model in __safeDI_apiBuilder_Office_Shelf_Scope() }, panel: { values_desk, values_model, values_shelf in __safeDI_apiBuilder_Office_Panel_Scope(token: token) })
		            }
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
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
	mutating func generate_handsEachFillCallersValueInItsForm_whenTwoPlacesOfOneHoleTypeTakeWrapperAndValue() async throws {
		// One hole type, `UserService`, held by `Model` beneath `Desk`, which binds `token` lazily, and by `Bench` beneath
		// `Shelf`, which binds it plainly: the two places' fills, one per case, take `token` in different forms.
		let feature = [
			"public protocol UserService {}",
			seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Bench", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Desk", declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let model: Model"]),
			seamFixtureType(named: "Shelf", declarations: ["@Instantiated let token: Token", "@Instantiated let bench: Bench"]),
			seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let desk: Desk", "@Instantiated let model: Model", "@Instantiated let shelf: Shelf", "@Instantiated let bench: Bench"]),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let token: Token"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let office: Office"]),
		]
		try await expectApp(feature: feature, app: app, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Shelf_Scope() -> Office.__safeDI_UserServiceCarrier_Shelf<any UserService> {
		            .init(bench: { values_token in __safeDI_userServiceBuilder_Office_Bench_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Bench_Scope(token: Token) -> Office.__safeDI_UserServiceCarrier_Bench<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_E3AB70E00E078B7A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) }, shelf: { values_desk, values_model in __safeDI_userServiceBuilder_Office_Shelf_Scope() }, bench: { values_desk, values_model, values_shelf in __safeDI_userServiceBuilder_Office_Bench_Scope(token: token) })
		            }
		            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachFillCallersValueInItsForm_whenPlacesBeneathLevelBindingNothingTakeWrapperAndValue() async throws {
		// As the cell above, beneath `Wing`, which binds no `token`: `Wing`'s level function takes `token` once per form its
		// targets take, and hands each target its own.
		try await expectApp(feature: Self.wingFeature(deskToken: "LazilyInstantiated<Token>"), app: Self.wingApp(rootToken: "Token"), comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: LazilyInstantiated<Token>, token_Token: Token) -> Office.__safeDI_UserServiceCarrier_Wing<any UserService> {
		            .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token_LazilyInstantiated__Token) }, shelf: { values_desk, values_model in __safeDI_userServiceBuilder_Office_Shelf_Scope() }, bench: { values_desk, values_model, values_shelf in __safeDI_userServiceBuilder_Office_Bench_Scope(token: token_Token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Shelf_Scope() -> Office.__safeDI_UserServiceCarrier_Shelf<any UserService> {
		            .init(bench: { values_token in __safeDI_userServiceBuilder_Office_Bench_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Bench_Scope(token: Token) -> Office.__safeDI_UserServiceCarrier_Bench<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_683A32EED72C8BDB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(wing: __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: LazilyInstantiated<Token>({ token }), token_Token: token))
		            }
		            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachFillCallersValueInItsForm_whenCallerHoldsWrapperAndPlacesBeneathLevelBindingNothingTakeWrapperAndValue() async throws {
		try await expectApp(feature: Self.wingFeature(deskToken: "LazilyInstantiated<Token>"), app: Self.wingApp(rootToken: "LazilyInstantiated<Token>"), comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: LazilyInstantiated<Token>, token_Token: Token) -> Office.__safeDI_UserServiceCarrier_Wing<any UserService> {
		            .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token_LazilyInstantiated__Token) }, shelf: { values_desk, values_model in __safeDI_userServiceBuilder_Office_Shelf_Scope() }, bench: { values_desk, values_model, values_shelf in __safeDI_userServiceBuilder_Office_Bench_Scope(token: token_Token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Shelf_Scope() -> Office.__safeDI_UserServiceCarrier_Shelf<any UserService> {
		            .init(bench: { values_token in __safeDI_userServiceBuilder_Office_Bench_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Bench_Scope(token: Token) -> Office.__safeDI_UserServiceCarrier_Bench<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        func __safeDI_token() -> Token {
		            Token()
		        }
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_683A32EED72C8BDB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(wing: __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: token, token_Token: token.instance))
		            }
		            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachFillCallersValueInItsForm_whenPlacesBeneathLevelBindingNothingTakeSendableWrapperAndValue() async throws {
		try await expectApp(feature: Self.wingFeature(deskToken: "SendableLazilyInstantiated<Token>"), app: Self.wingApp(rootToken: "Token"), comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_userServiceBuilder_Office_Wing_Scope(token_SendableLazilyInstantiated__Token: SendableLazilyInstantiated<Token>, token_Token: Token) -> Office.__safeDI_UserServiceCarrier_Wing<any UserService> {
		            .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token_SendableLazilyInstantiated__Token) }, shelf: { values_desk, values_model in __safeDI_userServiceBuilder_Office_Shelf_Scope() }, bench: { values_desk, values_model, values_shelf in __safeDI_userServiceBuilder_Office_Bench_Scope(token: token_Token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: SendableLazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Shelf_Scope() -> Office.__safeDI_UserServiceCarrier_Shelf<any UserService> {
		            .init(bench: { values_token in __safeDI_userServiceBuilder_Office_Bench_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Bench_Scope(token: Token) -> Office.__safeDI_UserServiceCarrier_Bench<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_D7B91EB4BAA7E3D5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(wing: __safeDI_userServiceBuilder_Office_Wing_Scope(token_SendableLazilyInstantiated__Token: SendableLazilyInstantiated<Token>({ token }), token_Token: token))
		            }
		            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachFillCallersValueInItsForm_whenPlacesBeneathLevelBindingNothingReadOnlyIfAvailable() async throws {
		// The fills read `token` only if available, so `Model`'s takes the wrapper optionally and `Bench`'s the value.
		try await expectApp(feature: Self.wingFeature(deskToken: "LazilyInstantiated<Token>"), app: Self.wingApp(rootToken: "Token", reads: "@Received(onlyIfAvailable: true) let token: Token?"), comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token_Optional: LazilyInstantiated<Token>?, token_Token_Optional: Token?) -> Office.__safeDI_UserServiceCarrier_Wing<any UserService> {
		            .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token_LazilyInstantiated__Token_Optional) }, shelf: { values_desk, values_model in __safeDI_userServiceBuilder_Office_Shelf_Scope() }, bench: { values_desk, values_model, values_shelf in __safeDI_userServiceBuilder_Office_Bench_Scope(token: token_Token_Optional) })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token?.instance)
		                return userService
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Shelf_Scope() -> Office.__safeDI_UserServiceCarrier_Shelf<any UserService> {
		            .init(bench: { values_token in __safeDI_userServiceBuilder_Office_Bench_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Bench_Scope(token: Token?) -> Office.__safeDI_UserServiceCarrier_Bench<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_683A32EED72C8BDB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(wing: __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token_Optional: LazilyInstantiated<Token>({ token }), token_Token_Optional: token))
		            }
		            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachFillCallersValueInItsForm_whenPlacesBeneathLevelBindingNothingTakeWrapperAndValueUnderSwiftPackagePlugin() async throws {
		try await expectApp(feature: Self.wingFeature(deskToken: "LazilyInstantiated<Token>"), app: Self.wingApp(rootToken: "Token"), integration: .swiftPackagePlugin, comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: LazilyInstantiated<Token>, token_Token: Token) -> Office.__safeDI_UserServiceCarrier_Wing<any UserService> {
		            .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token_LazilyInstantiated__Token) }, shelf: { values_desk, values_model in __safeDI_userServiceBuilder_Office_Shelf_Scope() }, bench: { values_desk, values_model, values_shelf in __safeDI_userServiceBuilder_Office_Bench_Scope(token: token_Token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token.instance)
		                return userService
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Shelf_Scope() -> Office.__safeDI_UserServiceCarrier_Shelf<any UserService> {
		            .init(bench: { values_token in __safeDI_userServiceBuilder_Office_Bench_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Bench_Scope(token: Token) -> Office.__safeDI_UserServiceCarrier_Bench<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_683A32EED72C8BDB.self // If this line does not compile, add the SafeDI plugin to the target that declares Office.
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(wing: __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: LazilyInstantiated<Token>({ token }), token_Token: token))
		            }
		            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFormsOfOneLabelApartFromAnotherLabel_whenPlacesBeneathLevelBindingNothingTakeTwoFormsAndLabelSpelledLikeOne() async throws {
		// `Wing`'s level function names `token`'s forms by their types, and takes `token_Token`, which `Shelf` binds too,
		// under its label, which `Token`'s form would take, so that form takes `_` after it.
		let feature = Self.wingFeature(deskToken: "LazilyInstantiated<Token>", shelfDeclarations: ["@Instantiated let token_Token: Other"]) + [
			seamFixtureType(named: "Other", isFinalClass: true, declarations: [], conformances: ", Sendable"),
		]
		let app = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let token: Token", "@Received let token_Token: Other"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let token_Token: Other", "@Instantiated let office: Office"]),
		]
		try await expectApp(feature: feature, app: app, comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_userServiceBuilder_Office_Shelf_Scope() -> Office.__safeDI_UserServiceCarrier_Shelf<any UserService> {
		            .init(bench: { values_token_Token, values_token in __safeDI_userServiceBuilder_Office_Bench_Scope(token: values_token, token_Token: values_token_Token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Bench_Scope(token: Token, token_Token: Other) -> Office.__safeDI_UserServiceCarrier_Bench<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token, token_Token: token_Token)
		                return userService
		            })
		        }
		        let token = Token()
		        let token_Token = Other()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_470A60F47D757E41.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(wing: __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: LazilyInstantiated<Token>({ token }), token_Token_: token, token_Token: token_Token))
		            }
		            func __safeDI_userServiceBuilder_Office_Wing_Scope(token_LazilyInstantiated__Token: LazilyInstantiated<Token>, token_Token_: Token, token_Token: Other) -> Office.__safeDI_UserServiceCarrier_Wing<any UserService> {
		                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token_LazilyInstantiated__Token) }, shelf: { values_desk, values_model in __safeDI_userServiceBuilder_Office_Shelf_Scope() }, bench: { values_desk, values_model, values_shelf in __safeDI_userServiceBuilder_Office_Bench_Scope(token: token_Token_, token_Token: token_Token) })
		            }
		            func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		                .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		            }
		            func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		                .init(userService: {
		                    let userService: any UserService = DefaultUserService(token: token.instance, token_Token: token_Token)
		                    return userService
		                })
		            }
		            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(token: token, token_Token: token_Token, office: office)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsNilToFillReadingWrapperOnlyIfAvailable_whenCallerHoldsOnlyValueThatAnotherFillTakes() async throws {
		// `DefaultUserService` reads `token` as the wrapper only if available, which `Root` does not declare, so inline
		// builds it with `nil` on `Model`'s route outside `Desk`; `DefaultApi` takes `Root`'s value. Each fill is handed
		// what inline reads for it, never the other's.
		try await expectApp(feature: Self.lazyShelfFeature, app: Self.wrapperReadingApp(rootDeclarations: ["@Instantiated let token: Token", "@Instantiated let office: Office"]), comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Office_Shelf_Scope() -> Office.__safeDI_ApiCarrier_Shelf<any Api> {
		            .init(panel: { values_token in __safeDI_apiBuilder_Office_Panel_Scope(token: values_token) })
		        }
		        func __safeDI_apiBuilder_Office_Panel_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_ApiCarrier_Panel<any Api> {
		            .init(api: {
		                let api: any Api = DefaultApi(token: token.instance)
		                return api
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_ADA6ADCD860C9DDE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Office() -> Office.__safeDI_ApiCarrier<any Api> {
		                .init(shelf: { values_desk, values_model in __safeDI_apiBuilder_Office_Shelf_Scope() }, panel: { values_desk, values_model, values_shelf in __safeDI_apiBuilder_Office_Panel_Scope(token: LazilyInstantiated<Token>({ token })) })
		            }
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: nil) })
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
	mutating func generate_handsNilToFillReadingWrapperOnlyIfAvailable_whenCallerDeclaresValueThatAnotherFillTakesAfterSeam() async throws {
		try await expectApp(feature: Self.lazyShelfFeature, app: Self.wrapperReadingApp(rootDeclarations: ["@Instantiated let office: Office", "@Instantiated let token: Token"]), comparedWith: .inline, expected: """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Office_Shelf_Scope() -> Office.__safeDI_ApiCarrier_Shelf<any Api> {
		            .init(panel: { values_token in __safeDI_apiBuilder_Office_Panel_Scope(token: values_token) })
		        }
		        func __safeDI_apiBuilder_Office_Panel_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_ApiCarrier_Panel<any Api> {
		            .init(api: {
		                let api: any Api = DefaultApi(token: token.instance)
		                return api
		            })
		        }
		        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
		            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
		        }
		        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
		            .init(userService: {
		                let userService: any UserService = DefaultUserService(token: token)
		                return userService
		            })
		        }
		        let token = Token()
		        func __safeDI_office() -> Office {
		            _ = Office.__safeDI_Office_ADA6ADCD860C9DDE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Office() -> Office.__safeDI_ApiCarrier<any Api> {
		                .init(shelf: { values_desk, values_model in __safeDI_apiBuilder_Office_Shelf_Scope() }, panel: { values_desk, values_model, values_shelf in __safeDI_apiBuilder_Office_Panel_Scope(token: LazilyInstantiated<Token>({ token })) })
		            }
		            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
		                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: nil) })
		            }
		            return Office(__safeDI_apiBuilder: __safeDI_apiBuilder_Office(), __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
		        }
		        let office: Office = __safeDI_office()
		        self.init(office: office, token: token)
		    }
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What a cell's generated values are compared with: the same graph with every fulfilling declaration in `Feature`, or
	/// with no seam, so `App` builds `Office`'s tree inline.
	private enum KnownRight {
		case visibleBuild
		case inline
	}

	/// `Office`, a seam that builds `Wing`, which binds nothing and builds two places of `UserService`, each by itself and
	/// beneath a type that binds `token`: `Desk`, as `deskToken`, and `Shelf`, by value, after `shelfDeclarations`.
	private static func wingFeature(deskToken: String, shelfDeclarations: [String] = []) -> [String] {
		[
			"public protocol UserService {}",
			seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Bench", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Desk", declarations: ["@Instantiated let token: \(deskToken)", "@Instantiated let model: Model"]),
			seamFixtureType(named: "Shelf", declarations: shelfDeclarations + ["@Instantiated let token: Token", "@Instantiated let bench: Bench"]),
			seamFixtureType(named: "Wing", declarations: ["@Instantiated let desk: Desk", "@Instantiated let model: Model", "@Instantiated let shelf: Shelf", "@Instantiated let bench: Bench"]),
			seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let wing: Wing"]),
		]
	}

	/// `App`'s fulfiller of `UserService`, which `reads` `token`, and `Root`, which holds `token` as `rootToken` beside
	/// `Office`.
	private static func wingApp(rootToken: String, reads: String = "@Received let token: Token") -> [String] {
		[
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [reads]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: \(rootToken)", "@Instantiated let office: Office"]),
		]
	}

	/// `feature` with `Shelf` binding `token` lazily too.
	private static let lazyShelfFeature = featureFiles(shelfToken: "LazilyInstantiated<Token>")

	/// `App`'s fulfillers, `DefaultUserService` reading `token` as the wrapper only if available and `DefaultApi` requiring
	/// its value, and `Root`, with `rootDeclarations`.
	private static func wrapperReadingApp(rootDeclarations: [String]) -> [String] {
		[
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) let token: LazilyInstantiated<Token>?"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: ["@Received let token: Token"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations),
		]
	}

	/// `Office`, a seam whose holes `userService` and `api` are each built beneath a type that binds `token`, `Desk` lazily
	/// and `Shelf` plainly, and beneath none.
	private static let feature = featureFiles(shelfToken: "Token")

	/// `Office`, a seam whose holes `userService` and `api` are each built beneath a type that binds `token`, `Desk` lazily
	/// and `Shelf` as `shelfToken`, and beneath none.
	private static func featureFiles(shelfToken: String) -> [String] {
		[
			"public protocol UserService {}",
			"public protocol Api {}",
			seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
			seamFixtureType(named: "Desk", declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let model: Model"]),
			seamFixtureType(named: "Shelf", declarations: ["@Instantiated let token: \(shelfToken)", "@Instantiated let panel: Panel"]),
			seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let desk: Desk", "@Instantiated let model: Model", "@Instantiated let shelf: Shelf", "@Instantiated let panel: Panel"]),
		]
	}

	/// `App`'s fulfillers of `UserService` and `Api`, each receiving `token`, and `Root`, which holds `token` as
	/// `rootToken` beside `Office`, last.
	private static func app(rootToken: String) -> [String] {
		[
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let token: Token"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: ["@Received let token: Token"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: \(rootToken)", "@Instantiated let office: Office"]),
		]
	}

	/// Expects `App`'s generated file under `integration`, for `feature`'s seam called from `app`, to be `expected`, and the
	/// values it builds for `Root()` to equal those of the same graph built as `knownRight` says.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectApp(
		feature: [String],
		app: [String],
		integration: MultiModuleIntegration = .moduleInfo,
		comparedWith knownRight: KnownRight = .visibleBuild,
		expected: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		let generatedFileName = switch integration {
		case .moduleInfo: "App.swift"
		case .swiftPackagePlugin: "Root+SafeDI.swift"
		}
		let generated: String? = output.modules["App"]?.generatedFiles[generatedFileName]
		#expect(generated == generatedFileHeader + expected, sourceLocation: sourceLocation)
		guard compileVerificationIsEnabled else { return }
		let visibleModules = switch knownRight {
		case .visibleBuild: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + Array(app.dropLast()), app: Array(app.suffix(1)))
		case .inline: SafeDIToolSeamBuilderParameterTests.modules(feature: inlineFixture(feature), app: app)
		}
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
