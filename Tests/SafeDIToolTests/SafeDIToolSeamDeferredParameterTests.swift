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
@testable import SafeDITool

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
		    public init(user __safeDI_user: @autoclosure @escaping () -> User) {
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
		            return Screen(user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
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
		    public init(user __safeDI_user: @autoclosure @escaping () -> User?) {
		        let user = LazilyInstantiated<User?>(__safeDI_user)
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user.instance)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_EC87C7D62747BEAB {}
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
		            _ = Screen.__safeDI_Screen_EC87C7D62747BEAB.self
		            return Screen(user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
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
		    public init(user: Instantiator<User>) {
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
		    public init(user __safeDI_user: @autoclosure @escaping @Sendable () -> User) {
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
		            return Screen(user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
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
		    public init(user __safeDI_user_: @autoclosure @escaping () -> User) {
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
		    public init(default __safeDI_default: @autoclosure @escaping () -> User) {
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
		    public init(currentUser __safeDI_currentUser: @autoclosure @escaping () -> User?) {
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
		                return Screen(currentUser: currentUser)
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
		    public init(token __safeDI_token_: @autoclosure @escaping () -> Secret) {
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
		try expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
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
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: it declares `init(\(labels))` at line 7, which can be called with the argument labels of its generated initializer, `init(user:)`, which takes `user` as an `@autoclosure`. A call with those labels would resolve to the hand-written initializer or be ambiguous. Rename the hand-written initializer's argument labels, or remove it.
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
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamDeclaresByValueInitializerBesideOptionalParameter() async {
		// Beside `init(user: () -> User?)`, a hand-written `init(user: User)` takes every call from a caller holding a
		// `User`, so the seam's tree would silently not be built.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: it declares `init(user:)` at line 7, which can be called with the argument labels of its generated initializer, `init(user:)`, which takes `user` as an `@autoclosure`. A call with those labels would resolve to the hand-written initializer or be ambiguous. Rename the hand-written initializer's argument labels, or remove it.
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
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: it declares `init(user:)` at line 8, which can be called with the argument labels of its generated initializer, `init(user:)`. A call with those labels would resolve to the hand-written initializer or be ambiguous. Rename the hand-written initializer's argument labels, or remove it.
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
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
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
			let olderTargetErrors = try compileErrors(of: seamFiles, deploymentTarget: "14.0")
			#expect(olderTargetErrors.contains { $0.contains("'SendableLazilyInstantiated' is only available in macOS 15.0 or newer") }, "\(olderTargetErrors)")
			let newerTargetErrors = try compileErrors(of: seamFiles, deploymentTarget: "15.0")
			#expect(newerTargetErrors == [])
		}

		/// The errors `swiftc` reports for `files`, type-checked against the SafeDI module the test build produced for a
		/// macOS deployment target of `deploymentTarget` on this machine's architecture, as the verifier targets it.
		private mutating func compileErrors(of files: [String], deploymentTarget: String) throws -> [String] {
			let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
			let result = try runProcess(
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
}
