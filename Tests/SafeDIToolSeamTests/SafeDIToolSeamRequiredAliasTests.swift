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

/// A type inside a seam's tree that requires an `onlyIfAvailable` alias of a pass-through: inline, the caller builds the
/// alias's fulfilling property before the branch that builds the receiver, so the alias is bound from it. The seam's
/// signature carries that requirement on the pass-through (`SeamSignature.Parameter.requiredThroughAlias`), which stays
/// optional and received only if available, so the caller orders the property it passes before the seam exactly as
/// inline orders it before the receiver's branch, and reports the same cycle where it cannot. Each cell sits beside the
/// inline build of the same graph.
struct SafeDIToolSeamRequiredAliasTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: The caller orders the pass-through first

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsPassThroughBeforeSeam_whenTypeInSeamsTreeRequiresAliasOfIt() async throws {
		// `Root` declares `screen` before `token`, and `Child`, beneath `Detail`'s alias of `token`, requires the alias: the
		// caller builds `token` first, as inline builds it before `screen`'s branch.
		let fixture = Self.fixture()
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_576B94BF87A52B20.self
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen, token: token)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token?) {
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			            let authToken: Token? = token.instance
			            #sourceLocation()
			            let child = Child(authToken: authToken)
			            return Detail(authToken: authToken, child: child)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_576B94BF87A52B20 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                let authToken: Token? = token
			                #sourceLocation()
			                let child = Child(authToken: authToken)
			                return Detail(authToken: authToken, child: child)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Screen(detail: detail)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen, token: token)
			    }
			}
			""",
		])
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToPassThroughReceivingSeamOnlyIfAvailable_whenTypeInSeamsTreeRequiresAliasOfIt() async throws {
		// `Token` receives `screen` only if available, so the caller builds `token` first and passes it `nil` for `screen`,
		// as inline does.
		let fixture = Self.fixture(token: ["@Received(onlyIfAvailable: true) let screen: Screen?"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Token(screen: nil)
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_576B94BF87A52B20.self
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen, token: token)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token?) {
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			            let authToken: Token? = token.instance
			            #sourceLocation()
			            let child = Child(authToken: authToken)
			            return Detail(authToken: authToken, child: child)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_576B94BF87A52B20 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Token(screen: nil)
			        func __safeDI_screen() -> Screen {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                let authToken: Token? = token
			                #sourceLocation()
			                let child = Child(authToken: authToken)
			                return Detail(authToken: authToken, child: child)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Screen(detail: detail)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen, token: token)
			    }
			}
			""",
		])
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDependencyCycleError_whenPassThroughRequiresSeamWhoseTreeRequiresAliasOfIt() async {
		// `Token` requires `screen`, which must be built after `token`: the caller reports the cycle inline reports.
		let fixture = Self.fixture(token: ["@Received let screen: Screen"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Token.swift"]):7:5: error: Dependency cycle: `Screen` -> `Detail` -> `Token?` -> `Token` -> `Screen`. `Token` receives `screen: Screen`, which is still being built when `Token` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			\(fixtures["Screen.swift"]):1:1: note: `Screen` is part of the cycle
			\(fixtures["Detail.swift"]):1:1: note: `Detail` is part of the cycle
			\(fixtures["Token.swift"]):1:1: note: `Token` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Token.swift"]):7:5: error: Dependency cycle: `Screen` -> `Detail` -> `Token?` -> `Token` -> `Screen`. `Token` receives `screen: Screen`, which is still being built when `Token` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			\(fixtures["Screen.swift"]):1:1: note: `Screen` is part of the cycle
			\(fixtures["Detail.swift"]):1:1: note: `Detail` is part of the cycle
			\(fixtures["Token.swift"]):1:1: note: `Token` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsInstantiatorPassedToSeam_whenInstantiatorPassThroughReceivesInstantiatorOfSeamWhoseTreeRequiresAliasOfIt() async throws {
		// `Root` builds `tokenBuilder` and `screenBuilder`, and `Token` requires `screenBuilder`. `Screen`'s tree requires
		// `tokenBuilder` through `Detail`'s `onlyIfAvailable` alias, so the two instantiators receive each other: a loop of
		// instantiators, whose functions rebind each other. The seam's caller passes `Screen` the rebinding by name, as the
		// tree built inline reads it.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let tokenBuilder: Instantiator<Token>", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Screen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "tokenBuilder", ofType: Instantiator<Token>.self, onlyIfAvailable: true) let authTokenBuilder: Instantiator<Token>?"#, "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let authTokenBuilder: Instantiator<Token>?"]),
			seamFixtureType(named: "Token", isFinalClass: true, declarations: ["@Received let screenBuilder: Instantiator<Screen>"]),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_tokenBuilder() -> Token {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Token(screenBuilder: screenBuilder)
			        }
			        let tokenBuilder = Instantiator<Token>(__safeDI_tokenBuilder)
			        func __safeDI_screenBuilder() -> Screen {
			            let tokenBuilder = Instantiator<Token>(__safeDI_tokenBuilder)
			            _ = Screen.__safeDI_Screen_82F2BAC6DACDC4D9.self
			            return Screen(__safeDI_tokenBuilder: tokenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        self.init(tokenBuilder: tokenBuilder, screenBuilder: screenBuilder)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_tokenBuilder tokenBuilder: Instantiator<Token>?) {
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			            let authTokenBuilder: Instantiator<Token>? = tokenBuilder
			            #sourceLocation()
			            let child = Child(authTokenBuilder: authTokenBuilder)
			            return Detail(authTokenBuilder: authTokenBuilder, child: child)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_82F2BAC6DACDC4D9 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_tokenBuilder() -> Token {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Token(screenBuilder: screenBuilder)
			        }
			        let tokenBuilder = Instantiator<Token>(__safeDI_tokenBuilder)
			        func __safeDI_screenBuilder() -> Screen {
			            let tokenBuilder = Instantiator<Token>(__safeDI_tokenBuilder)
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                let authTokenBuilder: Instantiator<Token>? = tokenBuilder
			                #sourceLocation()
			                let child = Child(authTokenBuilder: authTokenBuilder)
			                return Detail(authTokenBuilder: authTokenBuilder, child: child)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Screen(detail: detail)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        self.init(tokenBuilder: tokenBuilder, screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesRequirementThroughOuterSeam_whenNestedSeamsTypeRequiresAliasOfPassThrough() async throws {
		// `Detail` is inside `Inner`, a seam inside `Screen`: `Inner`'s pass-through `token` carries the requirement,
		// so `Screen`'s does too, and the caller builds `token` first.
		let fixture = Self.fixture(screen: ["@Instantiated let inner: Inner"], otherTypes: [seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let detail: Detail"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token?) {
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			            let authToken: Token? = token.instance
			            #sourceLocation()
			            let child = Child(authToken: authToken)
			            return Detail(authToken: authToken, child: child)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_576B94BF87A52B20 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_576B94BF87A52B20.self
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen, token: token)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token?) {
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_576B94BF87A52B20.self
			            return Inner(__safeDI_token: token.instance)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_576B94BF87A52B20 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_inner() -> Inner {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Token? = token
			                    #sourceLocation()
			                    let child = Child(authToken: authToken)
			                    return Detail(authToken: authToken, child: child)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Inner(detail: detail)
			            }
			            let inner: Inner = __safeDI_inner()
			            return Screen(inner: inner)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen, token: token)
			    }
			}
			""",
		])
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: Across modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsPassThroughBeforeSeamInCallersModule_whenTypeInSeamsTreeRequiresAliasOfIt(integration: MultiModuleIntegration) async throws {
		// The caller's module reads the requirement from the seam's signature, under both flows: one guard, and `token`
		// built before `screen`.
		let fixture = Self.fixture()
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Array(fixture.dropFirst())),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Feature\n\n" + fixture[0]], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let detailPath = try #require(output.modules["Feature"]).fixtures.compilerPath(of: "Detail.swift")
		#expect(try #require(output.modules["Feature"]).generatedFiles == [
			integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token?) {
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(detailPath)", line: 8)
			            let authToken: Token? = token.instance
			            #sourceLocation()
			            let child = Child(authToken: authToken)
			            return Detail(authToken: authToken, child: child)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_576B94BF87A52B20 {}
			}
			""",
		])
		#expect(try #require(output.modules["App"]).generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_576B94BF87A52B20.self\(integration.seamCallComment(type: "Screen", declaringModule: "Feature"))
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen, token: token)
			    }
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let alias = "@Received(fulfilledByDependencyNamed: \"token\", ofType: Token.self, onlyIfAvailable: true) let authToken: Token?"

	/// `Root` instantiates the seam `Screen`, then `Token`; `Screen` declares `screen`, by default instantiating `Detail`,
	/// which declares the only-if-available alias `authToken` of the pass-through `token` and instantiates `Child`, which
	/// requires `authToken`. `Token` declares `token`, and `otherTypes` follow.
	private static func fixture(screen: [String] = ["@Instantiated let detail: Detail"], token: [String] = [], otherTypes: [String] = []) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let screen: Screen", "@Instantiated let token: Token"]),
			seamFixtureType(named: "Screen", isSeam: true, isFinalClass: true, declarations: screen),
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: [alias, "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received let authToken: Token?"]),
			seamFixtureType(named: "Token", isFinalClass: true, declarations: token),
		] + otherTypes
	}
}
