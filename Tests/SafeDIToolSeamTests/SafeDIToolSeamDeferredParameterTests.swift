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

/// How a seam's generated initializer takes a property its tree receives by value from outside it: as an
/// `@autoclosure`, held in a `LazilyInstantiated` under the property's label that the tree reads where it would read
/// the caller's value inline, so a `LazilyInstantiated` the caller holds is instantiated when the receiver inside the
/// seam is first built. A parameter a `@Sendable` function inside the tree reads is a `@Sendable` closure held in a
/// `SendableLazilyInstantiated`, and a caller that would hand it a wrapper that is not `Sendable` is reported, as the
/// capture is inline. A hand-written initializer a call with a tier's argument labels could reach is rejected.
struct SafeDIToolSeamDeferredParameterTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	/// `Root` holds `user` as `rootUser`'s spelling, and builds `Screen`, whose tree receives `user` in `Detail`, which
	/// `Screen` builds behind `screenBuilder`, and, when `constantReceiver` is set, in `Header`, a constant `Screen`
	/// builds.
	private static func fixture(
		rootUser: String,
		receive: String = "@Received let user: User",
		screenBuilder: String = "Instantiator<Detail>",
		constantReceiver: Bool = false,
		userConformances: String = ", Sendable",
		seam: Bool = true,
	) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: \(rootUser)", "@Instantiated let screen: Screen"]),
			seamFixtureType(
				named: "Screen",
				isSeam: seam,
				declarations: ["@Instantiated let detailBuilder: \(screenBuilder)"] + (constantReceiver ? ["@Instantiated let header: Header"] : []),
			),
			seamFixtureType(named: "Detail", declarations: [receive]),
			seamFixtureType(named: "Header", declarations: ["@Received let user: User"]),
			"""
			@Instantiable
			public final class User: Instantiable\(userConformances) {
			    public init() {}
			}
			""",
		]
	}

	// MARK: The deferral

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsMemoOnceForEveryReceiver_whenConstantAndBuilderReceiversReadPassThrough() async throws {
		// One memo, read where each receiver reads the label: by `Header`, built with `Screen`, and by `Detail`, built
		// behind the instantiator. Both read one instance, the caller's.
		let files = Self.fixture(rootUser: "LazilyInstantiated<User>", constantReceiver: true)
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping () -> User) {
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user.instance)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        let header = Header(user: user.instance)
		        self.init(detailBuilder: detailBuilder, header: header)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_08AA1A656B91D4BA {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_08AA1A656B91D4BA.self
		            return Screen(__safeDI_user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalAutoclosure_whenTreeReceivesPassThroughOnlyIfAvailable() async throws {
		// The parameter is `User?`, held in a `LazilyInstantiated<User?>`, whose instance the receiver reads; a caller
		// that holds the wrapper passes its instance, read when `Detail` is first built.
		let files = Self.fixture(rootUser: "LazilyInstantiated<User>", receive: "@Received(onlyIfAvailable: true) let user: User?")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping () -> User?) {
		        let user = LazilyInstantiated<User?>(__safeDI_user)
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user.instance)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_B61C3DC8DD996187 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_B61C3DC8DD996187.self
		            return Screen(__safeDI_user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesInstantiatorByValue_whenTreeReceivesInstantiatorPassThrough() async throws {
		// An instantiator is a value whose instantiation is deferred already: the caller hands the same reference as
		// inline, so the parameter is taken as declared.
		let files = Self.fixture(rootUser: "Instantiator<User>", receive: "@Received let user: Instantiator<User>")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_user user: Instantiator<User>) {
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_0C022EBEABB7BCBE {}
		}
		""")
	}

	// MARK: @Sendable

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableAutoclosure_whenSendableBuilderInsideTreeReadsPassThrough() async throws {
		// `Detail` is built inside a `@Sendable` builder function, which reads the parameter: the autoclosure is
		// `@Sendable` and held in a `SendableLazilyInstantiated`, as inline the builder captures the caller's
		// `SendableLazilyInstantiated`.
		let files = Self.fixture(rootUser: "SendableLazilyInstantiated<User>", screenBuilder: "SendableInstantiator<Detail>")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User) {
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        @Sendable func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user.instance)
		        }
		        let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_8EFCFC03F02E0CB8 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        @Sendable func __safeDI_user() -> User {
		            User()
		        }
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_8EFCFC03F02E0CB8.self
		            return Screen(__safeDI_user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenCallerHandsNonSendableWrappersInstanceToSendableParameter() async {
		// The seam's `@Sendable` parameter captures what the call passes, as the `@Sendable` builder inside the seam's
		// tree captures the caller's wrapper inline, which is reported with the same diagnostic.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: @Received property `user: User` cannot be received inside a `@Sendable` function in chain: Root -> Screen. `Screen`'s generated initializer takes `user` as a `@Sendable` closure, because a `@Sendable` function inside `Screen`'s tree reads it, and that closure cannot capture `user: LazilyInstantiated<User>` on `Root`, because `LazilyInstantiated<User>` is not `Sendable`. Declare `user` on `Root` as `SendableLazilyInstantiated<User>` to fix. A `SendableLazilyInstantiated` requires its instance type, `User`, to be `Sendable`.
			\(fixtures["Root.swift"]):8:5: note: `user: LazilyInstantiated<User>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixture(rootUser: "LazilyInstantiated<User>", screenBuilder: "SendableInstantiator<Detail>"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPlainAutoclosure_whenSendableBuilderReadsOnlyDeclarationInsideTree() async throws {
		// The `@Sendable` builder's tree instantiates its own `user`, which its `Detail` reads: only the plain builder's
		// `Detail` reads the parameter, so it is not `@Sendable`, and needs no `Sendable` user.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: LazilyInstantiated<User>", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let panelBuilder: SendableInstantiator<Panel>", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let user: User", "@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let user: User"]),
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_user __safeDI_user_: @autoclosure @escaping () -> User) {
		        let user = LazilyInstantiated<User>(__safeDI_user_)
		        @Sendable func __safeDI_panelBuilder() -> Panel {
		            let user = User()
		            let detail = Detail(user: user)
		            return Panel(user: user, detail: detail)
		        }
		        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user.instance)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(panelBuilder: panelBuilder, detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_08AA1A656B91D4BA {}
		}
		""")
	}

	// MARK: Spellings

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsKeywordLabelThroughEveryRead_whenPassThroughIsLabeledWithKeyword() async throws {
		// The label is spelled as an argument label at the parameter and the wider tier's call, and as an identifier at
		// the memo and its reads.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let `default`: User", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let `default`: User"]),
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_default: @autoclosure @escaping () -> User) {
		        let `default` = LazilyInstantiated<User>(__safeDI_default)
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(default: `default`.instance)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_04ECA07676FFFEB4 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsImplicitlyUnwrappedPassThroughAsOptional_whenTreeReceivesImplicitlyUnwrappedValue() async throws {
		// An autoclosure cannot return `User!`, nor a generic argument spell it: the autoclosure returns `User?`, whose
		// instance `Detail`'s `User!` argument accepts. The call passes the `User!` `Parent` binds.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let parentBuilder: Instantiator<Parent>"]),
			"""
			@Instantiable
			public struct Parent: Instantiable {
			    public init(user: User, currentUser: User!, screen: Screen) {
			        self.user = user
			        self.currentUser = currentUser
			        self.screen = screen
			    }

			    @Instantiated let user: User
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let currentUser: User!
			    @Instantiated let screen: Screen
			}
			""",
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let currentUser: User!"]),
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_currentUser: @autoclosure @escaping () -> User?) {
		        let currentUser = LazilyInstantiated<User?>(__safeDI_currentUser)
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(currentUser: currentUser.instance)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_397246C371CF5CDE {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_parentBuilder() -> Parent {
		            let user = User()
		            #sourceLocation(file: "\(output.fixtures["Parent.swift"])", line: 10)
		            let currentUser: User! = user
		            #sourceLocation()
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_397246C371CF5CDE.self
		                return Screen(__safeDI_currentUser: currentUser)
		            }
		            let screen: Screen = __safeDI_screen()
		            return Parent(user: user, currentUser: currentUser, screen: screen)
		        }
		        let parentBuilder = Instantiator<Parent>(__safeDI_parentBuilder)
		        self.init(parentBuilder: parentBuilder)
		    }
		}
		""")
	}

	// MARK: The seam's own label-keeping alias

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsOwnAliasFromAutoclosure_whenSeamRetypesPassThroughKeepingItsLabel() async throws {
		// The alias is the parameter's only reader and is bound where inline binds it, so it reads the autoclosure there
		// and no memo is declared beside it, which would redeclare its label.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Secret", "@Instantiated let screen: Screen"]),
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(token: any Auth, detailBuilder: Instantiator<Detail>) {
			        self.token = token
			        self.detailBuilder = detailBuilder
			    }

			    @Received(fulfilledByDependencyNamed: "token", ofType: Secret.self) let token: any Auth
			    @Instantiated let detailBuilder: Instantiator<Detail>
			}
			""",
			seamFixtureType(named: "Detail", declarations: ["@Received let token: any Auth"]),
			"""
			public protocol Auth: Sendable {}

			@Instantiable
			public final class Secret: Instantiable, Auth {
			    public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret) {
		        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
		        let token: any Auth = __safeDI_token_()
		        #sourceLocation()
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(token: token)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(token: token, detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_55AF83B7D12DE285 {}
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: Hand-written initializers

	@Test(arguments: [
		// The by-value twin of the generated initializer, a closure twin, and the existential, defaulted, generic and
		// `Any` twins, each of which takes the call from a caller holding a `User` beside an optional parameter or makes
		// it ambiguous.
		"init(user: User) {\n        self.init(detailBuilder: Instantiator { Detail(user: user) })\n    }",
		"init(user: @escaping () -> User) {\n        self.init(detailBuilder: Instantiator { Detail(user: user()) })\n    }",
		"init(user: any Sendable) {\n        self.init(detailBuilder: Instantiator { Detail(user: User()) })\n    }",
		"init(user: User, flag: Bool = false) {\n        self.init(detailBuilder: Instantiator { Detail(user: user) })\n    }",
		"init<T: Sendable>(user: T) {\n        self.init(detailBuilder: Instantiator { Detail(user: User()) })\n    }",
		"init(user: Any) {\n        self.init(detailBuilder: Instantiator { Detail(user: User()) })\n    }",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamDeclaresInitializerCallableWithGeneratedLabels(handWrittenInitializer: String) async {
		let labels = handWrittenInitializer.contains("flag:") ? "user:flag:" : "user:"
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: it declares `init(\(labels))`, which can be called with the argument labels of its generated initializer, `init(user:)`. Because the labels match, a call meant for one initializer can run the other instead, or the code can fail to compile. Rename this initializer’s argument labels; remove it; or, while code you write still calls it, remove `generatePlainDependencyTreeInitializers: true` from this module’s `#SafeDIConfiguration`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen"]),
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(detailBuilder: Instantiator<Detail>) {
					        self.detailBuilder = detailBuilder
					    }

					    public \(handWrittenInitializer)

					    @Instantiated let detailBuilder: Instantiator<Detail>
					}
					""",
					seamFixtureType(named: "Detail", declarations: ["@Received let user: User"]),
					"""
					@Instantiable
					public final class User: Instantiable, Sendable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamDeclaresByValueInitializerBesideOptionalParameter() async {
		// Beside `init(user: User?)`, a hand-written `init(user: User)` takes every call from a caller holding a
		// `User`, so the seam's tree would silently not be built.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: it declares `init(user:)`, which can be called with the argument labels of its generated initializer, `init(user:)`. Because the labels match, a call meant for one initializer can run the other instead, or the code can fail to compile. Rename this initializer’s argument labels; remove it; or, while code you write still calls it, remove `generatePlainDependencyTreeInitializers: true` from this module’s `#SafeDIConfiguration`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen"]),
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(detailBuilder: Instantiator<Detail>) {
					        self.detailBuilder = detailBuilder
					    }

					    public init(user: User) {
					        self.init(detailBuilder: Instantiator { Detail(user: user) })
					    }

					    @Instantiated let detailBuilder: Instantiator<Detail>
					}
					""",
					seamFixtureType(named: "Detail", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
					"""
					@Instantiable
					public final class User: Instantiable, Sendable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamDeclaresInitializerWithLabelsOfItsOwnReceives() async {
		// The generated initializer takes `user`, the seam's own receive, by value, so the error names no autoclosure.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):8:5: error: SafeDI cannot generate the dependency tree of `Screen`: it declares `init(user:)`, which can be called with the argument labels of its generated initializer, `init(user:)`. Because the labels match, a call meant for one initializer can run the other instead, or the code can fail to compile. Rename this initializer’s argument labels; remove it; or, while code you write still calls it, remove `generatePlainDependencyTreeInitializers: true` from this module’s `#SafeDIConfiguration`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen"]),
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(user: User, header: Header) {
					        self.user = user
					        self.header = header
					    }

					    public init(user: User) {
					        self.init(user: user, header: Header())
					    }

					    @Received let user: User
					    @Instantiated let header: Header
					}
					""",
					seamFixtureType(named: "Header", declarations: []),
					"""
					@Instantiable
					public final class User: Instantiable, Sendable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Nested seams

	/// `Root` holds `user` as `rootUser`'s spelling and builds `Screen`, a seam that builds `Inner`, a seam, as
	/// `innerHolder` – a constant or a wrapper of it – and `Inner` builds `Detail`, which receives `user`, behind
	/// `innerBuilder`.
	private static func nestedSeamsFixture(rootUser: String, innerHolder: String = "Inner", innerBuilder: String = "Instantiator<Detail>") -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: \(rootUser)", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let inner: \(innerHolder)"]),
			// `@unchecked`, as the fuzzer's mixed-wrapper graphs mark their types: a `SendableInstantiator` may build `Inner`.
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let detailBuilder: \(innerBuilder)"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Detail", declarations: ["@Received let user: User"]),
			userType,
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_defersThroughBothAutoclosures_whenOuterSeamPassesPassThroughToNestedSeamsDeferredParameter() async throws {
		// Cell 20: `Screen` holds `user` in a memo and hands `Inner` its instance as `Inner`'s autoclosure, which `Inner`
		// holds in a memo of its own: the caller's wrapper is read when `Detail` is first built, as inline.
		let files = Self.nestedSeamsFixture(rootUser: "LazilyInstantiated<User>")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping () -> User) {
			        let user = LazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_detailBuilder() -> Detail {
			            Detail(user: user.instance)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        self.init(detailBuilder: detailBuilder)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_08AA1A656B91D4BA {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_user() -> User {
			            User()
			        }
			        let user = LazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_08AA1A656B91D4BA.self
			            return Screen(__safeDI_user: user.instance)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(user: user, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping () -> User) {
			        let user = LazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_08AA1A656B91D4BA.self
			            return Inner(__safeDI_user: user.instance)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_08AA1A656B91D4BA {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableAutoclosure_whenNestedSeamTakesPassThroughSendable() async throws {
		// Cell 21: `Inner` reads `user` inside a `@Sendable` builder, so it takes a `@Sendable` closure, which captures
		// `Screen`'s memo: `Screen` takes `user` `@Sendable` too.
		let files = Self.nestedSeamsFixture(rootUser: "SendableLazilyInstantiated<User>", innerBuilder: "SendableInstantiator<Detail>")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User) {
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        @Sendable func __safeDI_detailBuilder() -> Detail {
			            Detail(user: user.instance)
			        }
			        let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
			        self.init(detailBuilder: detailBuilder)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_8EFCFC03F02E0CB8 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        @Sendable func __safeDI_user() -> User {
			            User()
			        }
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8EFCFC03F02E0CB8.self
			            return Screen(__safeDI_user: user.instance)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(user: user, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User) {
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_8EFCFC03F02E0CB8.self
			            return Inner(__safeDI_user: user.instance)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_8EFCFC03F02E0CB8 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableAutoclosure_whenOuterSeamCallsNestedSeamInsideSendableBuilder() async throws {
		// Cell 21b: `Inner` reads `user` behind a plain builder, so it takes a plain closure, but `Screen` calls `Inner`
		// inside a `@Sendable` builder, which reads `Screen`'s memo: `Screen` takes `user` `@Sendable`.
		let files = Self.nestedSeamsFixture(rootUser: "SendableLazilyInstantiated<User>", innerHolder: "SendableInstantiator<Inner>")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping () -> User) {
			        let user = LazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_detailBuilder() -> Detail {
			            Detail(user: user.instance)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        self.init(detailBuilder: detailBuilder)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_08AA1A656B91D4BA {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        @Sendable func __safeDI_user() -> User {
			            User()
			        }
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8EFCFC03F02E0CB8.self
			            return Screen(__safeDI_user: user.instance)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(user: user, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User) {
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        @Sendable func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_08AA1A656B91D4BA.self
			            return Inner(__safeDI_user: user.instance)
			        }
			        let inner = SendableInstantiator<Inner>(__safeDI_inner)
			        self.init(inner: inner)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_8EFCFC03F02E0CB8 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	/// `Root` builds `Outer`, a seam that holds `user` as a `LazilyInstantiated`, which is not `Sendable`, and builds
	/// `Screen`.
	private static let outerSeamHoldingNonSendableWrapper = [
		seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outer: Outer"]),
		seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let user: LazilyInstantiated<User>", "@Instantiated let screen: Screen"]),
	]

	/// `Screen`, a seam whose `Detail` reads `user` inside a `@Sendable` builder, and the types of its tree.
	private static let screenReadingInsideSendableBuilder = [
		seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detailBuilder: SendableInstantiator<Detail>"]),
		seamFixtureType(named: "Detail", declarations: ["@Received let user: User"]),
		userType,
	]

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenOuterSeamHandsNonSendableWrappersInstanceToNestedSeamsSendableParameter() async {
		// Cell 8b: the capture walk runs on `Outer`'s tree, as on a root's, so `Outer`'s call to `Screen` is reported.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: @Received property `user: User` cannot be received inside a `@Sendable` function in chain: Outer -> Screen. `Screen`'s generated initializer takes `user` as a `@Sendable` closure, because a `@Sendable` function inside `Screen`'s tree reads it, and that closure cannot capture `user: LazilyInstantiated<User>` on `Outer`, because `LazilyInstantiated<User>` is not `Sendable`. Declare `user` on `Outer` as `SendableLazilyInstantiated<User>` to fix. A `SendableLazilyInstantiated` requires its instance type, `User`, to be `Sendable`.
			\(fixtures["Outer.swift"]):8:5: note: `user: LazilyInstantiated<User>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.outerSeamHoldingNonSendableWrapper + Self.screenReadingInsideSendableBuilder, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenOuterSeamInAnotherModuleHandsNonSendableWrappersInstanceToSendableParameter(integration: MultiModuleIntegration) async {
		// Cell 8c: cell 8b's shape with `Screen` in `Feature` and `Outer` in `App`: `App` reads that `Screen` takes `user`
		// `@Sendable` from `Screen`'s declarations, under either flow.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			// Under the plugin, the paths are reported as the parse normalized them.
			func path(of fileName: String, inModule moduleName: String) -> String {
				switch integration {
				case .moduleInfo:
					fixtures[moduleName]![fileName]
				case .swiftPackagePlugin:
					NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
				}
			}
			return """
			\(path(of: "Screen.swift", inModule: "Feature")):1:1: error: @Received property `user: User` cannot be received inside a `@Sendable` function in chain: Outer -> Screen. `Screen`'s generated initializer takes `user` as a `@Sendable` closure, because a `@Sendable` function inside `Screen`'s tree reads it, and that closure cannot capture `user: LazilyInstantiated<User>` on `Outer`, because `LazilyInstantiated<User>` is not `Sendable`. Declare `user` on `Outer` as `SendableLazilyInstantiated<User>` to fix. A `SendableLazilyInstantiated` requires its instance type, `User`, to be `Sendable`.
			\(path(of: "Outer.swift", inModule: "App")):10:5: note: `user: LazilyInstantiated<User>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.screenReadingInsideSendableBuilder),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: Self.outerSeamHoldingNonSendableWrapper.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Holes

	/// Where `Inner`'s hole, `panel: any Panel`, sits for an outer seam's fill.
	enum PanelHole: CaseIterable, Sendable {
		/// `Inner` instantiates `panel: SendableLazilyInstantiated<any Panel>`, a hole that is a wrapper.
		case sendableLazilyInstantiated
		/// `Inner` instantiates `detailBuilder: SendableInstantiator<Detail>`, and `Detail` `panel: any Panel`, a hole
		/// built inside the `@Sendable` builder function.
		case beneathSendableInstantiator

		var featureTypes: [String] {
			switch self {
			case .sendableLazilyInstantiated:
				[seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panel: SendableLazilyInstantiated<any Panel>"])]
			case .beneathSendableInstantiator:
				[
					seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let detailBuilder: SendableInstantiator<Detail>"]),
					seamFixtureType(named: "Detail", declarations: ["@Instantiated let panel: any Panel"]),
				]
			}
		}

		/// The code `Feature` generates for `Inner`.
		var innerCode: String {
			switch self {
			case .sendableLazilyInstantiated:
				"""
				extension Inner {
				    @frozen public enum SafeDISendableScope_Panel {
				        case panel
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_panelSendableBuilder: @escaping @Sendable (SafeDISendableScope_Panel) -> any Panel) {
				        @Sendable func __safeDI_panel() -> any Panel {
				            __safeDI_panelSendableBuilder(.panel)
				        }
				        let panel = SendableLazilyInstantiated<any Panel>(__safeDI_panel)
				        self.init(panel: panel)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_3A7C0ADA472696EC {}
				}
				"""
			case .beneathSendableInstantiator:
				"""
				extension Inner {
				    @frozen public enum SafeDIScope_Panel {
				        @frozen public enum Detail_Scope {
				            case panel(panel_Values)

				            public struct panel_Values {}
				        }
				    }

				    @frozen public enum SafeDISendableScope_Panel {
				        case detailBuilder(SafeDIScope_Panel.Detail_Scope)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_panelSendableBuilder: @escaping @Sendable (SafeDISendableScope_Panel) -> any Panel) {
				        @Sendable func __safeDI_detailBuilder() -> Detail {
				            let panel: any Panel = __safeDI_panelSendableBuilder(.detailBuilder(.panel(SafeDIScope_Panel.Detail_Scope.panel_Values())))
				            return Detail(panel: panel)
				        }
				        let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
				        self.init(detailBuilder: detailBuilder)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_7CB480475496C1B0 {}
				}
				"""
			}
		}

		/// The fill `Outer`'s generated code declares for `Inner`'s builder, in the builder function of `inner`.
		var outerFill: String {
			switch self {
			case .sendableLazilyInstantiated:
				"""
				            @Sendable func __safeDI_panelSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Panel) -> any Panel {
				                switch scope {
				                case .panel:
				                    @Sendable func __safeDI_panel() -> DefaultPanel {
				                        DefaultPanel(user: user.instance)
				                    }
				                    return __safeDI_panel()
				                }
				            }
				            return Inner(__safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Inner)
				"""
			case .beneathSendableInstantiator:
				"""
				            @Sendable func __safeDI_panelSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_Panel) -> any Panel {
				                switch scope {
				                case let .detailBuilder(scope): return __safeDI_panelBuilder_Inner_Detail_Scope(scope)
				                }
				            }
				            @Sendable func __safeDI_panelBuilder_Inner_Detail_Scope(_ scope: Inner.SafeDIScope_Panel.Detail_Scope) -> any Panel {
				                switch scope {
				                case .panel:
				                    let panel: any Panel = DefaultPanel(user: user.instance)
				                    return panel
				                }
				            }
				            return Inner(__safeDI_panelSendableBuilder: __safeDI_panelSendableBuilder_Inner)
				"""
			}
		}

		/// The guard enum name `Inner`'s generated initializer declares.
		var innerGuard: String {
			switch self {
			case .sendableLazilyInstantiated: "__safeDI_Inner_3A7C0ADA472696EC"
			case .beneathSendableInstantiator: "__safeDI_Inner_7CB480475496C1B0"
			}
		}
	}

	/// `Feature` declares `Panel` and `Inner`, a seam whose tree builds `panel: any Panel` as `hole` says, a hole;
	/// `App` declares `DefaultPanel`, which fulfills `Panel` and receives `user`, `Outer`, a seam that builds `Inner`
	/// and fills its hole, and `Root`, which holds `user` as `rootUser`'s spelling.
	private static func outerFillModules(hole: PanelHole, rootUser: String) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(
			feature: ["public protocol Panel: Sendable {}", userType] + hole.featureTypes,
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultPanel", fulfilling: "Panel", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: \(rootUser)", "@Instantiated let outer: Outer"]),
			],
		)
	}

	@Test(arguments: PanelHole.allCases, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableAutoclosure_whenOuterSeamsSendableFillReadsPassThroughInnerSiteDoesNotCarry(hole: PanelHole, integration: MultiModuleIntegration) async throws {
		// Cell 8e: `Outer` fills `Inner`'s hole with `DefaultPanel`, which receives `user` from `Outer`'s caller, since
		// `Inner`'s site does not carry it. `DefaultPanel` is built in a `@Sendable` function of the fill, which reads
		// `Outer`'s memo, so `Outer` takes `user` as a `@Sendable` closure.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.outerFillModules(hole: hole, rootUser: "SendableLazilyInstantiated<User>"), integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: ["Inner": hole.innerCode]))
		#expect(output.modules["App"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Outer": """
			extension Outer {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User) {
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_inner() -> Inner {
			            _ = Inner.\(hole.innerGuard).self\(SafeDIToolSeamBuilderParameterTests.pluginComment(integration, seam: "Inner"))
			\(hole.outerFill)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_8EFCFC03F02E0CB8 {}
			}
			""",
			"Root": """
			extension Root {
			    public init() {
			        @Sendable func __safeDI_user() -> User {
			            User()
			        }
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_8EFCFC03F02E0CB8.self
			            return Outer(__safeDI_user: user.instance)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(user: user, outer: outer)
			    }
			}
			""",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenCallerHandsNonSendableWrappersInstanceToParameterOuterSeamsSendableFillReads() async {
		// Cell 8e's caller holding a `LazilyInstantiated`, which `Outer`'s `@Sendable` closure cannot capture: cell 8's error.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Outer.swift"]):3:1: error: @Received property `user: User` cannot be received inside a `@Sendable` function in chain: Root -> Outer. `Outer`'s generated initializer takes `user` as a `@Sendable` closure, because a `@Sendable` function inside `Outer`'s tree reads it, and that closure cannot capture `user: LazilyInstantiated<User>` on `Root`, because `LazilyInstantiated<User>` is not `Sendable`. Declare `user` on `Root` as `SendableLazilyInstantiated<User>` to fix. A `SendableLazilyInstantiated` requires its instance type, `User`, to be `Sendable`.
			\(fixtures["App"]!["Root.swift"]):10:5: note: `user: LazilyInstantiated<User>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.outerFillModules(hole: .sendableLazilyInstantiated, rootUser: "LazilyInstantiated<User>"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsHolesStructMemo_whenGeneratedAndHandWrittenFillsReadIt(integration: MultiModuleIntegration) async throws {
		// Cells 16 and 17: `Service` defers `token`, and hands the hole's struct the memo, whose field reads its instance.
		// `Root`'s generated fill reads `Root`'s own `token`, as inline, and `makeService(token:)`'s hand-written fill reads
		// the struct's field, which compiles as it did when the field held the value. `SafeDIToolSeamHoleLazyInputTests`
		// compares the values with the inline build's.
		let modules = SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol UserService {}",
				Self.tokenType,
				seamFixtureType(named: "Profile", declarations: ["@Received let token: Token", "@Instantiated let userService: any UserService"]),
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let token: Token"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let service: Service"]),
				"""
				public func makeService(token: Token) -> Service {
				    Service(token: token, userServiceBuilder: { scope in switch scope { case let .profileBuilder(values, .userService): DefaultUserService(token: values.token) } })
				}
				""",
			],
			featureConfiguration: plainDependencyTreeInitializersConfiguration,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"Service": """
			extension Service {
			    @frozen public enum SafeDIScope_UserService {
			        case profileBuilder(profileBuilder_Values, SafeDIScope_UserService.Profile_Scope)

			        public struct profileBuilder_Values {
			            public var token: Token { __safeDI_token.instance }
			            let __safeDI_token: LazilyInstantiated<Token>

			            init(token: LazilyInstantiated<Token>) {
			                __safeDI_token = token
			            }
			        }

			        @frozen public enum Profile_Scope {
			            case userService(userService_Values)

			            public struct userService_Values {}
			        }
			    }

			    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
			    public init(token: Token, userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
			        self.init(__safeDI_token: token, __safeDI_userServiceBuilder: userServiceBuilder)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// From code you write, call the initializer above instead.
			    public init(__safeDI_token: @autoclosure @escaping () -> Token, __safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        let __safeDI_userServiceValues_profileBuilder = SafeDIScope_UserService.profileBuilder_Values(token: token)
			        func __safeDI_profileBuilder() -> Profile {
			            let userService: any UserService = __safeDI_userServiceBuilder(.profileBuilder(__safeDI_userServiceValues_profileBuilder, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
			            return Profile(token: token.instance, userService: userService)
			        }
			        let profileBuilder = Instantiator<Profile>(__safeDI_profileBuilder)
			        self.init(profileBuilder: profileBuilder)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_DA263E0F696E2E8F {}
			}
			""",
		]))
		#expect(output.modules["App"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public init() {
			        func __safeDI_token() -> Token {
			            Token()
			        }
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_DA263E0F696E2E8F.self\(SafeDIToolSeamBuilderParameterTests.pluginComment(integration, seam: "Service"))
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .profileBuilder(_, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(token: token.instance)
			                    return userService
			                }
			            }
			            return Service(__safeDI_token: token.instance, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(token: token, service: service)
			    }
			}
			""",
		]))
	}

	// MARK: A lazy cycle that re-enters the seam

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesMemosInstanceToReenteredSeam_whenLazyCycleReentersSeamThatDefersPassThrough() async throws {
		// Cell 28: `T0`, inside `T3`'s tree, receives `token` and builds `T3` again: the re-entering call passes the memo's
		// instance, the nearest declaration of `token`, into the nested call's autoclosure.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Received let token: Token", "@Instantiated let t3Builder: Instantiator<T3>"]),
			Self.tokenType,
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_token() -> Token {
			            Token()
			        }
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        func __safeDI_t3Builder() -> T3 {
			            _ = T3.__safeDI_T3_F2F345803C710CE2.self
			            return T3(__safeDI_token: token.instance)
			        }
			        let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			        self.init(token: token, t3Builder: t3Builder)
			    }
			}
			""",
			"T3+SafeDI.swift": generatedFileHeader + """
			extension T3 {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Token) {
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        func __safeDI_t0Builder() -> T0 {
			            func __safeDI_t3Builder() -> T3 {
			                _ = T3.__safeDI_T3_F2F345803C710CE2.self
			                return T3(__safeDI_token: token.instance)
			            }
			            let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			            return T0(token: token.instance, t3Builder: t3Builder)
			        }
			        let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			        self.init(t0Builder: t0Builder)
			    }
			}

			extension T3 {
			    public enum __safeDI_T3_F2F345803C710CE2 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: Tiers and modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesDeferredParameterThroughWiderTier_whenPackageParameterIsOnlyIfAvailable(integration: MultiModuleIntegration) async throws {
		// Cell 29: `Service`'s `public` tier takes `title`, deferred, and calls the `package` tier with `__safeDI_title()`
		// and `nil` for `theme`, which it omits. `Mid`, in `Service`'s package, calls the `package` tier with the instances
		// of the wrappers it holds; `App`, in another package, calls the `public` tier.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				@Instantiable
				package final class Theme: Instantiable, Sendable {
				    package init() {}
				}
				""",
				Self.sendableType(named: "Title"),
				"""
				@Instantiable
				public struct Badge: Instantiable {
				    package init(theme: Theme?) {
				        self.theme = theme
				    }

				    @Received(onlyIfAvailable: true) package let theme: Theme?
				}
				""",
				seamFixtureType(named: "Header", declarations: ["@Received let title: Title"]),
				seamFixtureType(named: "Service", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let badgeBuilder: Instantiator<Badge>", "@Instantiated let headerBuilder: Instantiator<Header>"]),
			]),
			ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "MidRoot", isRoot: true, declarations: ["@Instantiated let theme: LazilyInstantiated<Theme>", "@Instantiated let title: LazilyInstantiated<Title>", "@Instantiated let service: Service"])
					.replacingOccurrences(of: "public init(theme", with: "package init(theme"),
			], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "AppRoot", isRoot: true, declarations: ["@Instantiated let title: LazilyInstantiated<Title>", "@Instantiated let service: Service"]),
			], dependencies: ["Feature"]),
		], integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"Service": """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_title: @autoclosure @escaping () -> Title) {
			        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> Title) {
			        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
			        let title = LazilyInstantiated<Title>(__safeDI_title)
			        func __safeDI_badgeBuilder() -> Badge {
			            Badge(theme: theme.instance)
			        }
			        let badgeBuilder = Instantiator<Badge>(__safeDI_badgeBuilder)
			        func __safeDI_headerBuilder() -> Header {
			            Header(title: title.instance)
			        }
			        let headerBuilder = Instantiator<Header>(__safeDI_headerBuilder)
			        self.init(badgeBuilder: badgeBuilder, headerBuilder: headerBuilder)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_9BAF4200A1BAA28B {}
			}
			""",
		]))
		#expect(output.modules["Mid"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "Mid", integration: integration, imports: ["Feature"], rootFiles: [
			"MidRoot": """
			extension MidRoot {
			    public init() {
			        func __safeDI_theme() -> Theme {
			            Theme()
			        }
			        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			        func __safeDI_title() -> Title {
			            Title()
			        }
			        let title = LazilyInstantiated<Title>(__safeDI_title)
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_9BAF4200A1BAA28B.self\(SafeDIToolSeamBuilderParameterTests.pluginComment(integration, seam: "Service"))
			            return Service(__safeDI_theme: theme.instance, __safeDI_title: title.instance)
			        }
			        let service: Service = __safeDI_service()
			        self.init(theme: theme, title: title, service: service)
			    }
			}
			""",
		]))
		#expect(output.modules["App"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"AppRoot": """
			extension AppRoot {
			    public init() {
			        func __safeDI_title() -> Title {
			            Title()
			        }
			        let title = LazilyInstantiated<Title>(__safeDI_title)
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_9BAF4200A1BAA28B.self\(SafeDIToolSeamBuilderParameterTests.pluginComment(integration, seam: "Service"))
			            return Service(__safeDI_title: title.instance)
			        }
			        let service: Service = __safeDI_service()
			        self.init(title: title, service: service)
			    }
			}
			""",
		]))
	}

	@Test(arguments: MultiModuleIntegration.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_agreesOnGuardAndSpellingAcrossModules_whenManualsScreenIsSplitAcrossModules(integration: MultiModuleIntegration, sendable: Bool) async throws {
		// Cell 32: the Manual's `Screen`, building `Cache` behind an instantiator – a `SendableInstantiator` when
		// `sendable` – in `Feature`, and `Root` in `App`. `Feature` and `App` compute one guard name and one spelling of
		// each deferred parameter, under either flow.
		let sendablePrefix = sendable ? "Sendable" : ""
		let sendableAttribute = sendable ? "@Sendable " : ""
		let guardName = sendable ? "__safeDI_Screen_E3C8CCA558CCA81B" : "__safeDI_Screen_3192EA1C03ABD98F"
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Received let user: User", "@Instantiated let cacheBuilder: \(sendablePrefix)Instantiator<Cache>"]),
				seamFixtureType(named: "Cache", declarations: ["@Received let database: Database", "@Received(onlyIfAvailable: true) let logger: Logger?"]),
				Self.userType,
				Self.sendableType(named: "Database"),
				Self.sendableType(named: "Logger"),
			]),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let database: \(sendablePrefix)LazilyInstantiated<Database>", "@Instantiated let screen: Screen"]),
			], dependencies: ["Feature"]),
		], integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"Screen": """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_user user: User, __safeDI_database: @autoclosure @escaping \(sendableAttribute)() -> Database, __safeDI_logger: @autoclosure @escaping \(sendableAttribute)() -> Logger?) {
			        let database = \(sendablePrefix)LazilyInstantiated<Database>(__safeDI_database)
			        let logger = \(sendablePrefix)LazilyInstantiated<Logger?>(__safeDI_logger)
			        \(sendableAttribute)func __safeDI_cacheBuilder() -> Cache {
			            Cache(database: database.instance, logger: logger.instance)
			        }
			        let cacheBuilder = \(sendablePrefix)Instantiator<Cache>(__safeDI_cacheBuilder)
			        self.init(user: user, cacheBuilder: cacheBuilder)
			    }
			}

			extension Screen {
			    public enum \(guardName) {}
			}
			""",
		]))
		#expect(output.modules["App"]?.generatedFiles == SafeDIToolSeamBuilderParameterTests.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public init() {
			        let user = User()
			        \(sendableAttribute)func __safeDI_database() -> Database {
			            Database()
			        }
			        let database = \(sendablePrefix)LazilyInstantiated<Database>(__safeDI_database)
			        func __safeDI_screen() -> Screen {
			            _ = Screen.\(guardName).self\(SafeDIToolSeamBuilderParameterTests.pluginComment(integration, seam: "Screen"))
			            return Screen(__safeDI_user: user, __safeDI_database: database.instance, __safeDI_logger: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(user: user, database: database, screen: screen)
			    }
			}
			""",
		]))
	}

	// MARK: The seam's own aliases of a pass-through

	/// `callers`, by default `Root`, which holds `token` as a `LazilyInstantiated` and builds `Screen`, a seam that
	/// declares `alias` and builds `Detail`, which declares `detailReceive`, behind an instantiator.
	private static func ownAliasFixture(alias: String, aliasType: String, detailReceive: String, callers: [String] = [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: LazilyInstantiated<Secret>", "@Instantiated let screen: Screen"])]) -> [String] {
		let aliasLabel = String(alias[alias.range(of: " let ")!.upperBound...].prefix { $0 != ":" })
		return callers + [
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(\(aliasLabel): \(aliasType), detailBuilder: Instantiator<Detail>) {
			        self.\(aliasLabel) = \(aliasLabel)
			        self.detailBuilder = detailBuilder
			    }

			    \(alias)
			    @Instantiated let detailBuilder: Instantiator<Detail>
			}
			""",
			seamFixtureType(named: "Detail", declarations: [detailReceive]),
			"""
			public protocol Auth: Sendable {}

			public struct AnyAuth: Auth {
			    public init(_ auth: any Auth) {
			        self.auth = auth
			    }

			    public let auth: any Auth
			}

			@Instantiable
			public final class Secret: Instantiable, Auth {
			    public init() {}
			}
			""",
		]
	}

	/// The code `Root` generates when it holds `token` as a `LazilyInstantiated` and builds `Screen`, whose guard enum is
	/// `guardName`.
	private static func rootPassingTokenInstance(toScreenGuardedBy guardName: String) -> String {
		generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_token() -> Secret {
		            Secret()
		        }
		        let token = LazilyInstantiated<Secret>(__safeDI_token)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.\(guardName).self
		            return Screen(__safeDI_token: token.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(token: token, screen: screen)
		    }
		}
		"""
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsMemoOnceInOwnAlias_whenSeamsOwnAliasIsPassThroughsOnlyReader() async throws {
		// Cell 37: `Screen`'s own alias `auth` of `token` is the only reader of `token`; it is bound in `Screen`'s
		// initializer, as inline, reading the memo once. `Root` is warned that `Screen`, created with it, reads the
		// instance, as inline.
		let files = Self.ownAliasFixture(alias: #"@Received(fulfilledByDependencyNamed: "token", ofType: Secret.self) let auth: any Auth"#, aliasType: "any Auth", detailReceive: "@Received let auth: any Auth")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": Self.rootPassingTokenInstance(toScreenGuardedBy: "__safeDI_Screen_55AF83B7D12DE285"),
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token: @autoclosure @escaping () -> Secret) {
			        let token = LazilyInstantiated<Secret>(__safeDI_token)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let auth: any Auth = token.instance
			        #sourceLocation()
			        func __safeDI_detailBuilder() -> Detail {
			            Detail(auth: auth)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        self.init(auth: auth, detailBuilder: detailBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_55AF83B7D12DE285 {}
			}
			""",
		])
		#expect(output.warnings.map(\.formatted) == ["\(output.fixtures["Root.swift"]):8:5: warning: @Instantiated property `token: LazilyInstantiated<Secret>` is instantiated whenever `Root` is created: `Screen` is created with `Root` and receives the instance as `auth: any Auth`. To instantiate it lazily, receive `token: LazilyInstantiated<Secret>` on `Screen`."])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsOwnErasedAliasFromAutoclosure_whenSeamErasesPassThroughKeepingItsLabel() async throws {
		// Cell 38c: the erased label-keeping alias wraps what the autoclosure returns; no memo is declared.
		let files = Self.ownAliasFixture(alias: #"@Received(fulfilledByDependencyNamed: "token", ofType: Secret.self, erasedToConcreteExistential: true) let token: AnyAuth"#, aliasType: "AnyAuth", detailReceive: "@Received let token: AnyAuth")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": Self.rootPassingTokenInstance(toScreenGuardedBy: "__safeDI_Screen_55AF83B7D12DE285"),
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret) {
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let token: AnyAuth = AnyAuth(__safeDI_token_())
			        #sourceLocation()
			        func __safeDI_detailBuilder() -> Detail {
			            Detail(token: token)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        self.init(token: token, detailBuilder: detailBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_55AF83B7D12DE285 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsOwnAliasFromOptionalAutoclosure_whenSeamRetypesRequiredOptionalPassThroughKeepingItsLabel() async throws {
		// Cell 38d: a required label-keeping retype of `token: Secret?`, which `Holder` forwards, reads the autoclosure
		// where it is bound; no memo is declared. The comparator does not traverse an instantiator with forwarded
		// properties, so the values are not compared.
		let files = Self.ownAliasFixture(
			alias: #"@Received(fulfilledByDependencyNamed: "token", ofType: Secret?.self) let token: (any Auth)?"#,
			aliasType: "(any Auth)?",
			detailReceive: "@Received let token: (any Auth)?",
			callers: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let holderBuilder: Instantiator<Holder>"]),
				seamFixtureType(named: "Holder", declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"]),
			],
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_holderBuilder(token: Secret?) -> Holder {
			            func __safeDI_screen() -> Screen {
			                _ = Screen.__safeDI_Screen_C10331417AC12746.self
			                return Screen(__safeDI_token: token)
			            }
			            let screen: Screen = __safeDI_screen()
			            return Holder(token: token, screen: screen)
			        }
			        let holderBuilder = Instantiator<Holder> {
			            __safeDI_holderBuilder(token: $0)
			        }
			        self.init(holderBuilder: holderBuilder)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret?) {
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let token: (any Auth)? = __safeDI_token_()
			        #sourceLocation()
			        func __safeDI_detailBuilder() -> Detail {
			            Detail(token: token)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        self.init(token: token, detailBuilder: detailBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_C10331417AC12746 {}
			}
			""",
		])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsOwnOnlyIfAvailableAliasFromAutoclosure_whenCallerHoldsWrapper(erased: Bool) async throws {
		// Cell 38e: the seam's own `onlyIfAvailable` label-keeping alias, plain or erased, is bound from the parameter,
		// which provides its form, so it is never `nil` at the seam's root; the directive locates it as before.
		let alias = erased
			? #"@Received(fulfilledByDependencyNamed: "token", ofType: Secret?.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let token: AnyAuth?"#
			: #"@Received(fulfilledByDependencyNamed: "token", ofType: Secret?.self, onlyIfAvailable: true) let token: (any Auth)?"#
		let aliasType = erased ? "AnyAuth?" : "(any Auth)?"
		let files = Self.ownAliasFixture(alias: alias, aliasType: aliasType, detailReceive: "@Received(onlyIfAvailable: true) let token: \(aliasType)")
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let binding = erased ? "(__safeDI_token_() as Secret?).map { AnyAuth($0) }" : "__safeDI_token_()"
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": Self.rootPassingTokenInstance(toScreenGuardedBy: "__safeDI_Screen_8763BEDE3E51EBC4"),
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret?) {
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let token: \(aliasType) = \(binding)
			        #sourceLocation()
			        func __safeDI_detailBuilder() -> Detail {
			            Detail(token: token)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        self.init(token: token, detailBuilder: detailBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: Deployment targets

	#if os(macOS)
		@Test
		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		mutating func generatedSeam_requiresMacOS15_whenSendableBuilderInsideTreeReadsPassThrough() async throws {
			// A `SendableLazilyInstantiated` is available from macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2, so a
			// seam whose tree reads a pass-through inside a `@Sendable` builder compiles only in a module that deploys there.
			guard compileVerificationIsEnabled else { return }
			let files = Self.fixture(rootUser: "SendableLazilyInstantiated<User>", screenBuilder: "SendableInstantiator<Detail>")
			let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			let seamFiles = (files.dropFirst() + [try #require(output.dependencyTreeFiles["Screen+SafeDI.swift"])]).map { "import SafeDI\n\n\($0)" }
			let olderTargetErrors = try await compileErrors(of: seamFiles, deploymentTarget: "14.0")
			#expect(olderTargetErrors.contains { $0.contains("'SendableLazilyInstantiated' is only available in macOS 15.0 or newer") }, "\(olderTargetErrors)")
			let newerTargetErrors = try await compileErrors(of: seamFiles, deploymentTarget: "15.0")
			#expect(newerTargetErrors == [])
		}

		/// The errors `swiftc` reports for `files`, type-checked against the SafeDI module the test build produced for a
		/// macOS deployment target of `deploymentTarget` on this machine's architecture, as the verifier targets it.
		private mutating func compileErrors(of files: [String], deploymentTarget: String) async throws -> [String] {
			let directory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			filesToDelete.append(directory)
			let filePaths = try files.enumerated().map { index, content in
				let fileURL = directory.appendingPathComponent("File\(index).swift")
				try content.write(to: fileURL, atomically: true, encoding: .utf8)
				return fileURL.path
			}
			let artifacts = try #require(SafeDIBuildArtifactLocator.locate())
			#if arch(arm64)
				let architecture = "arm64"
			#else
				let architecture = "x86_64"
			#endif
			let result = try await runProcess(
				swiftCompilerCommand.executable,
				arguments: swiftCompilerCommand.arguments + [
					"-typecheck",
					"-swift-version", "6",
					"-parse-as-library",
					"-target", "\(architecture)-apple-macos\(deploymentTarget)",
					"-I", artifacts.swiftModuleSearchPath.path,
					"-load-plugin-executable", "\(artifacts.safeDIMacrosToolPath.path)#SafeDIMacros",
				] + filePaths,
			)
			return result.stderr.split(separator: "\n").map(String.init).filter { $0.contains("error:") }
		}
	#endif

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Token`, a `Sendable` `@Instantiable` final class.
	private static let tokenType = sendableType(named: "Token")

	/// `User`, a `Sendable` `@Instantiable` final class.
	private static let userType = sendableType(named: "User")

	/// A public `Sendable` `@Instantiable` final class named `name`.
	private static func sendableType(named name: String) -> String {
		"""
		@Instantiable
		public final class \(name): Instantiable, Sendable {
		    public init() {}
		}
		"""
	}
}
