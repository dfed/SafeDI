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

/// A receive inside a seam's tree whose label a declaration on its path declares with a property that does not
/// provide it is the hidden-label error, reported at the seam from its own chain, on every path and whatever any
/// caller holds: the generated initializer passes each dependency by label and is generated before any caller is
/// known, so nothing it takes reaches beneath such a declaration. Each cell sits beside the inline build of the same
/// graph.
struct SafeDIToolSeamHiddenReceiveTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: The seam's own property hidden beneath a declaration

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenOwnOnlyIfAvailablePropertyIsReceivedBeneathDeclarationOfItsLabelAndRootHoldsNothing() async throws {
		let fixture = Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received(onlyIfAvailable: true) let user: User?", rootHoldsUser: false)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// Inline, no caller provides `user`, so the receive is passed `nil`.
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                let user = Name()
			                let reader = Reader(user: nil)
			                return Left(user: user, reader: reader)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(user: nil, left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromSeamsChainOnce_whenOwnOnlyIfAvailablePropertyIsReceivedBeneathDeclarationOfItsLabelAndRootHoldsIt() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received(onlyIfAvailable: true) let user: User?", rootHoldsUser: true),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromRootOnly_whenOwnOnlyIfAvailablePropertyIsReceivedBeneathDeclarationAndRootHoldsItInline() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: inlineFixture(Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received(onlyIfAvailable: true) let user: User?", rootHoldsUser: true)),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnfulfillableErrorFromRoot_whenRequiredReceiveIsHiddenBeneathDeclarationAndRootHoldsNothing(seam: Bool) async {
		// The root's chain reports the receive unfulfillable first, with and without the seam.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Left -> Reader. Did you mean `user: Name`?
			\(fixtures["Reader.swift"]):7:25-7:29: fixit: Name
			"""
		}) {
			let fixture = Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received let user: User", rootHoldsUser: false)
			return try await executeSafeDIToolTest(swiftFileContent: seam ? fixture : inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenRequiredReceiveIsHiddenBeneathDeclarationInModuleWithNoRoot() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Array(Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received let user: User", rootHoldsUser: false).dropFirst()),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenOwnRequiredOptionalPropertyIsReceivedBeneathDeclarationOfItsLabelInModuleWithNoRoot() async {
		// The seam's own required `user: User?` is a parameter, which hides nothing: `Reader` beneath `Left`'s `user: Name`
		// is hidden from it, as from an only-if-available one.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Array(Self.ownPropertyFixture(own: "@Received let user: User?", reader: "@Received(onlyIfAvailable: true) let user: User?", rootHoldsUser: false).dropFirst()),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesDeclarationsValue_whenDeclarationOfLabelProvidesUnwrappedFormOfOwnOptionalProperty() async throws {
		let fixture = Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received(onlyIfAvailable: true) let user: User?", rootHoldsUser: false, leftDeclares: "@Instantiated let user: User")
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_0A0B087775B360DD.self
			            return Screen(user: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(user: User? = nil) {
			        func __safeDI_left() -> Left {
			            let user = User()
			            let reader = Reader(user: user)
			            return Left(user: user, reader: reader)
			        }
			        let left: Left = __safeDI_left()
			        self.init(user: user, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_0A0B087775B360DD {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                let user = User()
			                let reader = Reader(user: user)
			                return Left(user: user, reader: reader)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(user: nil, left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenOwnPropertyIsHiddenOnOnePathAndReceivedOnAnother() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received(onlyIfAvailable: true) let user: User?", rootHoldsUser: false, readerAlsoUnderRight: true),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [
		("(any Port)?", "public protocol Port {}"),
		("(() -> Void)?", ""),
		("Feature.Item?", "public enum Feature {\n    public final class Item {\n        public init() {}\n    }\n}"),
		("[Item]?", "public final class Item {\n    public init() {}\n}"),
		("UserID?", "public typealias UserID = String"),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenOwnPropertyOfEachSpellingIsReceivedBeneathDeclarationOfItsLabel(type: String, declarations: String) async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: \(type)` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: \(type)", reader: "@Received(onlyIfAvailable: true) let user: \(type)", rootHoldsUser: false) + (declarations.isEmpty ? [] : [declarations]),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorInSeamsModule_whenOwnPropertyIsReceivedBeneathDeclarationWhateverAnotherModuleHolds(integration: MultiModuleIntegration, appHoldsUser: Bool) async {
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let path = { (file: String) in
				switch integration {
				case .moduleInfo:
					fixtures["Feature"]![file]
				case .swiftPackagePlugin:
					NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: file)).path
				}
			}
			return """
			\(path("Reader.swift")):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(path("Left.swift")):8:5: note: `user: Name` is declared here
			"""
		}) {
			let files = Self.ownPropertyFixture(own: "@Received(onlyIfAvailable: true) let user: User?", reader: "@Received(onlyIfAvailable: true) let user: User?", rootHoldsUser: appHoldsUser)
			return try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Array(files.dropFirst())),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Feature\n\n" + files[0]], dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Aliases

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasToSeamsParameter_whenCallerHoldsFulfillingProperty() async throws {
		// `Detail`'s only-if-available alias keeps the label of `token: Secret`, which the seam takes as a parameter: the
		// alias is bound from the parameter, so `Detail` gets the caller's value, as inline.
		let fixture = Self.labelKeepingAliasFixture(rootHoldsToken: true)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_D306FBD537400E08.self
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(token: Secret? = nil) {
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			            let token: (any Auth)? = token
			            #sourceLocation()
			            return Detail(token: token)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_D306FBD537400E08 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
			                let token: (any Auth)? = token
			                #sourceLocation()
			                return Detail(token: token)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Screen(detail: detail)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasToSeamsParameter_whenCallerHoldsNothing() async throws {
		// The caller passes `nil`, which the alias binds, where inline does not create the alias and passes `nil`: the
		// same value.
		let fixture = Self.labelKeepingAliasFixture(rootHoldsToken: false)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_D306FBD537400E08.self
			            return Screen(token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(token: Secret? = nil) {
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			            let token: (any Auth)? = token
			            #sourceLocation()
			            return Detail(token: token)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_D306FBD537400E08 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_detail() -> Detail {
			                // Did not create `token: (any Auth)?` because `token: Secret` is unavailable.
			                return Detail(token: nil)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Screen(detail: detail)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasToSeamsRequiredParameter_whenAnotherReceiverRequiresFulfillingProperty() async throws {
		let fixture = Self.labelKeepingAliasFixture(rootHoldsToken: true, consumerRequiresToken: true)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_AC3B2DB59BEF585F.self
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(token: Secret) {
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			            let token: (any Auth)? = token
			            #sourceLocation()
			            return Detail(token: token)
			        }
			        let detail: Detail = __safeDI_detail()
			        let consumer = Consumer(token: token)
			        self.init(detail: detail, consumer: consumer)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_AC3B2DB59BEF585F {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
			                let token: (any Auth)? = token
			                #sourceLocation()
			                return Detail(token: token)
			            }
			            let detail: Detail = __safeDI_detail()
			            let consumer = Consumer(token: token)
			            return Screen(detail: detail, consumer: consumer)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsRenamedAliasToSeamsParameter_whenCallerHoldsFulfillingProperty() async throws {
		let fixture = Self.labelKeepingAliasFixture(rootHoldsToken: true, aliasLabel: "auth")
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_D306FBD537400E08.self
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(token: Secret? = nil) {
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			            let auth: (any Auth)? = token
			            #sourceLocation()
			            return Detail(auth: auth)
			        }
			        let detail: Detail = __safeDI_detail()
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_D306FBD537400E08 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
			                let auth: (any Auth)? = token
			                #sourceLocation()
			                return Detail(auth: auth)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Screen(detail: detail)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenAliasFulfillingPropertyIsHiddenOnOnePathAndCallerHoldsAliasProperty() async throws {
		// `Detail`'s alias of `token: Secret` is beneath `Left`'s `token: Token` on one path: the seam reports the hidden
		// receive from its own chain, where inline passes `Reader` the caller's `authToken` on both paths.
		let fixture = Self.aliasHiddenOnOnePathFixture(rootHolds: "authToken: Secret")
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):8:5: error: @Received property `token: Secret` is hidden in chain: Screen -> Left -> Detail. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                let token = Token()
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(token: token, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            func __safeDI_right() -> Right {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Right(detail: detail)
			            }
			            let right: Right = __safeDI_right()
			            return Screen(left: left, right: right)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenAliasFulfillingPropertyIsHiddenOnOnePathAndCallerHoldsFulfillingProperty(seam: Bool) async {
		// With `Root` holding `token: Secret`, the alias's receive is hidden with a provider above: the root's chain
		// reports it with or without the seam, and with the seam the seam's own chain reports it too.
		let fixture = Self.aliasHiddenOnOnePathFixture(rootHolds: "token: Secret")
		await assertThrowsError(diagnostics: { fixtures in
			seam
				? """
				\(fixtures["Detail.swift"]):8:5: error: @Received property `token: Secret` is hidden in chain: Screen -> Left -> Detail. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
				\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
				"""
				: """
				\(fixtures["Detail.swift"]):8:5: error: @Received property `token: Secret` is hidden in chain: Root -> Screen -> Left -> Detail. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
				\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
				"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: seam ? fixture : inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [nil, "authToken: Secret", "token: Secret"] as [String?])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorInSeamsModule_whenAliasFulfillingPropertyIsHiddenOnOnePathWhateverAnotherModuleHolds(integration: MultiModuleIntegration, appHolds: String?) async {
		// The seam's module rejects the hidden receive from the seam's own chain, whatever its callers hold.
		let files = Self.aliasHiddenOnOnePathFixture(rootHolds: appHolds)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let path = { (file: String) in
				switch integration {
				case .moduleInfo:
					fixtures["Feature"]![file]
				case .swiftPackagePlugin:
					NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: file)).path
				}
			}
			return """
			\(path("Detail.swift")):8:5: error: @Received property `token: Secret` is hidden in chain: Screen -> Left -> Detail. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
			\(path("Left.swift")):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Array(files.dropFirst())),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Feature\n\n" + files[0]], dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// How `Root` reaches the seam `Screen`: the property it declares, the type the root's chain names, and whether
	/// `Screen` fulfills `ScreenProtocol` or is erased by `AnyScreen`; `user` is received only if available unless
	/// `receiveIsRequired`.
	struct SeamHolding: Sendable, CustomTestStringConvertible {
		let name: String
		let rootProperty: String
		let chainType: String
		var fulfillsProtocol = false
		var isErased = false
		var receiveIsRequired = false

		var testDescription: String {
			name
		}

		static let all = [
			SeamHolding(name: "protocol it fulfills", rootProperty: "@Instantiated(fulfilledByType: \"Screen\") let screen: ScreenProtocol", chainType: "ScreenProtocol", fulfillsProtocol: true),
			SeamHolding(name: "protocol it fulfills, receive required", rootProperty: "@Instantiated(fulfilledByType: \"Screen\") let screen: ScreenProtocol", chainType: "ScreenProtocol", fulfillsProtocol: true, receiveIsRequired: true),
			SeamHolding(name: "erased constant", rootProperty: "@Instantiated(fulfilledByType: \"Screen\", erasedToConcreteExistential: true) let screen: AnyScreen", chainType: "AnyScreen", isErased: true),
			SeamHolding(name: "erased instantiator", rootProperty: "@Instantiated(fulfilledByType: \"Screen\", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<(), AnyScreen>", chainType: "ErasedInstantiator<(), AnyScreen>", isErased: true),
			SeamHolding(name: "instantiator", rootProperty: "@Instantiated let screenBuilder: Instantiator<Screen>", chainType: "Instantiator<Screen>"),
			SeamHolding(name: "lazily instantiated", rootProperty: "@Instantiated let screen: LazilyInstantiated<Screen>", chainType: "Screen"),
		]
	}

	@Test(arguments: SeamHolding.all)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromSeamsChainOnce_whenRootReachesSeamThroughProtocolErasureOrWrapper(holding: SeamHolding) async {
		// `Root` reaches `Screen` through a protocol, an erasure or a wrapper, so the root's chain names that type where
		// the seam's names `Screen`: the chains are matched by the types of their scopes, and the root's copy is dropped.
		// Built inline, the root's chain is the one reported.
		let receive = holding.receiveIsRequired ? "@Received let user: User" : "@Received(onlyIfAvailable: true) let user: User?"
		let receivedProperty = holding.receiveIsRequired ? "user: User" : "user: User?"
		for isSeam in [true, false] {
			// Appended rather than joined with `+` around ternaries: Swift 6.2 on Linux can time out type-checking a `+`
			// chain of arrays with ternaries; later Swift does not.
			var arguments = [String]()
			if isSeam {
				arguments.append("generateDependencyTree: true")
			}
			if holding.fulfillsProtocol {
				arguments.append("fulfillingAdditionalTypes: [ScreenProtocol.self]")
			}
			var files = [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", holding.rootProperty]),
				"""
				@Instantiable\(arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))")
				public struct Screen: Instantiable\(holding.fulfillsProtocol || holding.isErased ? ", ScreenProtocol" : "") {
				    public init(\(receivedProperty), left: Left) {
				        self.user = user
				        self.left = left
				    }

				    \(receive)
				    @Instantiated let left: Left
				}
				""",
				Self.left,
				seamFixtureType(named: "Reader", declarations: [receive]),
				Self.user,
				Self.name,
			]
			if holding.isErased {
				files.append(Self.anyScreen)
			}
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["Reader.swift"]):7:5: error: @Received property `\(receivedProperty)` is hidden in chain: \(isSeam ? "Screen" : "Root -> \(holding.chainType)") -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
				\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
				"""
			}) {
				try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsChainsThatReadAlikeOnce_whenTwoFulfilledByTypePropertiesOfOneTypeReachHiddenReceive() async {
		// `Root` holds two `ScreenProtocol` properties, one built by `Screen` and one by the plain `Other`: the chains through them read
		// alike. With no seam, the one error of today; with `Screen` a seam, in either order, the root's chain through `Other` keeps its
		// report beside the seam's own; with both seams, each seam's own and no root copy.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> ScreenProtocol -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated(fulfilledByType: \"Screen\") let screen: ScreenProtocol", "@Instantiated(fulfilledByType: \"Other\") let other: ScreenProtocol"]),
				"""
				@Instantiable
				public struct Screen: Instantiable, ScreenProtocol {
				    public init(user: User?, left: Left) {
				        self.user = user
				        self.left = left
				    }

				    @Received(onlyIfAvailable: true) let user: User?
				    @Instantiated let left: Left
				}
				""",
				"""
				@Instantiable
				public struct Other: Instantiable, ScreenProtocol {
				    public init(user: User?, left: Left) {
				        self.user = user
				        self.left = left
				    }

				    @Received(onlyIfAvailable: true) let user: User?
				    @Instantiated let left: Left
				}
				""",
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		for screenFirst in [true, false] {
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> ScreenProtocol -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
				\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
				\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
				\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
				"""
			}) {
				try await executeSafeDIToolTest(swiftFileContent: screenFirst ? [
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated(fulfilledByType: \"Screen\") let screen: ScreenProtocol", "@Instantiated(fulfilledByType: \"Other\") let other: ScreenProtocol"]),
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable, ScreenProtocol {
					    public init(user: User?, left: Left) {
					        self.user = user
					        self.left = left
					    }

					    @Received(onlyIfAvailable: true) let user: User?
					    @Instantiated let left: Left
					}
					""",
					"""
					@Instantiable
					public struct Other: Instantiable, ScreenProtocol {
					    public init(user: User?, left: Left) {
					        self.user = user
					        self.left = left
					    }

					    @Received(onlyIfAvailable: true) let user: User?
					    @Instantiated let left: Left
					}
					""",
					Self.left,
					seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
					Self.user,
					Self.name,
				] : [
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated(fulfilledByType: \"Other\") let other: ScreenProtocol", "@Instantiated(fulfilledByType: \"Screen\") let screen: ScreenProtocol"]),
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable, ScreenProtocol {
					    public init(user: User?, left: Left) {
					        self.user = user
					        self.left = left
					    }

					    @Received(onlyIfAvailable: true) let user: User?
					    @Instantiated let left: Left
					}
					""",
					"""
					@Instantiable
					public struct Other: Instantiable, ScreenProtocol {
					    public init(user: User?, left: Left) {
					        self.user = user
					        self.left = left
					    }

					    @Received(onlyIfAvailable: true) let user: User?
					    @Instantiated let left: Left
					}
					""",
					Self.left,
					seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
					Self.user,
					Self.name,
				], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Other -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated(fulfilledByType: \"Screen\") let screen: ScreenProtocol", "@Instantiated(fulfilledByType: \"Other\") let other: ScreenProtocol"]),
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable, ScreenProtocol {
				    public init(user: User?, left: Left) {
				        self.user = user
				        self.left = left
				    }

				    @Received(onlyIfAvailable: true) let user: User?
				    @Instantiated let left: Left
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Other: Instantiable, ScreenProtocol {
				    public init(user: User?, left: Left) {
				        self.user = user
				        self.left = left
				    }

				    @Received(onlyIfAvailable: true) let user: User?
				    @Instantiated let left: Left
				}
				""",
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromEachSeamsChain_whenSiblingSeamsReachHiddenReceiveAtDifferentDepths(panelFirst: Bool) async {
		// `Screen` reaches `Reader` beneath `Left`, and `Panel` beneath `Middle` and `Left`: each seam's own chain is reported, and the
		// root's chain through either is not, whichever is declared first. Inline reports the root's chain through each.
		let rootDeclarations = ["@Instantiated let user: User"] + (panelFirst ? ["@Instantiated let panel: Panel", "@Instantiated let screen: Screen"] : ["@Instantiated let screen: Screen", "@Instantiated let panel: Panel"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Panel -> Middle -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations),
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let middle: Middle"]),
				seamFixtureType(named: "Middle", declarations: ["@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Panel -> Middle -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations),
				seamFixtureType(named: "Screen", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Panel", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let middle: Middle"]),
				seamFixtureType(named: "Middle", declarations: ["@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromInnermostSeamsChain_whenNestedSeamsHoldHiddenReceive() async {
		// `Outer` calls `Inner`, whose tree holds the receive: `Inner`'s chain is reported once, and neither `Outer`'s nor the root's.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Inner -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let outer: Outer"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let inner: Inner"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Outer -> Inner -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let outer: Outer"]),
				seamFixtureType(named: "Outer", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let inner: Inner"]),
				seamFixtureType(named: "Inner", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromRootAndSeam_whenRootAlsoReachesHiddenReceiveWithoutSeam() async {
		// `Root` instantiates `Left` itself too: that chain passes through no seam, so it is reported beside the seam's own.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Screen", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromEachSeamsChain_whenSiblingSeamsReachHiddenReceiveAtSameDepth() async {
		// Two seams at one depth: each its own chain.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Panel -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen", "@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Panel -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen", "@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Screen", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Panel", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromEachSeamsChain_whenSeamReachesAnotherSeamAndHiddenReceiveDirectly() async {
		// `Panel` reaches `Screen` beneath `Middle` and holds `Left` itself: `Panel`'s own chain through its `Left`, and `Screen`'s.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Panel -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let middle: Middle", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Middle", declarations: ["@Instantiated let screen: Screen"]),
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Panel -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> Panel -> Middle -> Screen -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Panel", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let middle: Middle", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Middle", declarations: ["@Instantiated let screen: Screen"]),
				seamFixtureType(named: "Screen", declarations: ["@Received(onlyIfAvailable: true) let user: User?", "@Instantiated let left: Left"]),
				Self.left,
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromSeamsChain_whenSeamsShareInstantiatorCycle() async {
		// `X` and `Y` are seams on one instantiator cycle with `T`, which hides `user`, between them: each seam's own chain passes through
		// the other, and a rule dropping every chain through a reporting seam would leave the receive with no report at all. The match
		// is to a strictly shorter chain only, so `Y`'s chain, the shortest, is reported.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Y -> Instantiator<T> -> Instantiator<X> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let user: User", "@Instantiated let x: X"]),
				seamFixtureType(named: "X", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Y", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>"]),
				seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let user: Name", "@Instantiated let xBuilder: Instantiator<X>"]),
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> X -> Instantiator<Y> -> Instantiator<T> -> Instantiator<X> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let user: User", "@Instantiated let x: X"]),
				seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Y", isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>"]),
				seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let user: Name", "@Instantiated let xBuilder: Instantiator<X>"]),
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCallersHiddenError_whenCallerOnInstantiatorCycleHidesSeamsParameter() async {
		// `T` hides `user` above the seam `Z` and both hold `Reader`: the chain through `Z` that `T`'s declaration hides is the caller's
		// own error, which the seam's chain does not report, and the seam's own call site inside its tree is a chain of its own.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> T -> Instantiator<Z> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> T -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Z -> Instantiator<T> -> Instantiator<Z> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Z -> Instantiator<T> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let user: User", "@Instantiated let t: T"]),
				seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let user: Name", "@Instantiated let reader: Reader", "@Instantiated let zBuilder: Instantiator<Z>"]),
				seamFixtureType(named: "Z", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// Inline, the `Z` that `T`'s `zBuilder` builds again inside the cycle is a chain of its own too, as the seam's call site
		// inside its tree is: its `Reader` receives the `user` the `T` between declares.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> T -> Instantiator<Z> -> Instantiator<T> -> Instantiator<Z> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> T -> Instantiator<Z> -> Instantiator<T> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> T -> Instantiator<Z> -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User?` is hidden in chain: Root -> T -> Reader. `T` declares `user: Name` with the same label, so the types below `T` receive `user: Name` instead. Give `user: Name` on `T` a different label to fix.
			\(fixtures["T.swift"]):9:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let user: User", "@Instantiated let t: T"]),
				seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let user: Name", "@Instantiated let reader: Reader", "@Instantiated let zBuilder: Instantiator<Z>"]),
				seamFixtureType(named: "Z", isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
				Self.user,
				Self.name,
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	/// `Root` instantiates the seam `Screen`, and `user: User` when `rootHoldsUser`; `Screen` declares `own` and
	/// instantiates `Left` (and `Right`, when `readerAlsoUnderRight`); `Left` declares `leftDeclares` and instantiates
	/// `Reader`, which declares `reader`; `Right` instantiates `Reader` too.
	private static func ownPropertyFixture(own: String, reader: String, rootHoldsUser: Bool, leftDeclares: String = "@Instantiated let user: Name", readerAlsoUnderRight: Bool = false) -> [String] {
		var files = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(rootHoldsUser ? "user: User, " : "")screen: Screen) {
			        \(rootHoldsUser ? "self.user = user\n        " : "")self.screen = screen
			    }

			    \(rootHoldsUser ? "@Instantiated let user: User\n    " : "")@Instantiated let screen: Screen
			}
			""",
			seamFixtureType(named: "Screen", isSeam: true, declarations: [own, "@Instantiated let left: Left"] + (readerAlsoUnderRight ? ["@Instantiated let right: Right"] : [])),
			seamFixtureType(named: "Left", declarations: [leftDeclares, "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", declarations: [reader]),
			seamFixtureType(named: "User", declarations: []),
			seamFixtureType(named: "Name", declarations: []),
		]
		if readerAlsoUnderRight {
			files.append(seamFixtureType(named: "Right", declarations: ["@Instantiated let reader: Reader"]))
		}
		return files
	}

	/// `Root` instantiates the seam `Screen`, and `token: Secret` when `rootHoldsToken`; `Screen` instantiates `Detail`,
	/// and `Consumer`, which requires `token: Secret`, when `consumerRequiresToken`; `Detail` declares an only-if-available
	/// alias of `token: Secret` named `aliasLabel` of type `(any Auth)?`.
	private static func labelKeepingAliasFixture(rootHoldsToken: Bool, consumerRequiresToken: Bool = false, aliasLabel: String = "token") -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, declarations: (rootHoldsToken ? ["@Instantiated let token: Secret"] : []) + ["@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detail: Detail"] + (consumerRequiresToken ? ["@Instantiated let consumer: Consumer"] : [])),
			seamFixtureType(named: "Detail", declarations: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let \(aliasLabel): (any Auth)?"]),
			seamFixtureType(named: "Consumer", declarations: ["@Received let token: Secret"]),
			"public protocol Auth {}\n\n" + seamFixtureType(named: "Secret", declarations: [], conformances: ", Auth"),
		]
	}

	/// `Root` instantiates the seam `Screen`, and `rootHolds` when it is not `nil`; `Screen` instantiates `Left`, which
	/// declares `token: Token`, and `Right`; each instantiates `Detail`, which declares an only-if-available alias
	/// `authToken: Secret?` of `token: Secret` and instantiates `Reader`, which receives `authToken: Secret?` only if
	/// available.
	private static func aliasHiddenOnOnePathFixture(rootHolds: String?) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, declarations: (rootHolds.map { ["@Instantiated let \($0)"] } ?? []) + ["@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let left: Left", "@Instantiated let right: Right"]),
			seamFixtureType(named: "Left", declarations: ["@Instantiated let token: Token", "@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Right", declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let authToken: Secret?"]),
			seamFixtureType(named: "Token", declarations: []),
			seamFixtureType(named: "Secret", declarations: []),
		]
	}

	// MARK: The chains of rule H's dedupe

	private static let left = seamFixtureType(named: "Left", declarations: ["@Instantiated let user: Name", "@Instantiated let reader: Reader"])
	private static let user = seamFixtureType(named: "User", declarations: [])
	private static let name = seamFixtureType(named: "Name", declarations: [])
	private static let anyScreen = """
	public struct AnyScreen: ScreenProtocol {
	    public init(_ screen: any ScreenProtocol) {
	        self.screen = screen
	    }

	    public let screen: any ScreenProtocol
	}
	"""
}
