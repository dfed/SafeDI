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

/// The uncreated-alias walk's rule for an alias that keeps the label it retypes: a type's own declaration of an
/// alias's label does not count as a declaration of the label the alias's fulfilling expression reads, as inline's
/// `addAliasGenerator` already treats a label-keeping alias of a lazily instantiated instance. So a label-keeping
/// alias of an uncreated `onlyIfAvailable` alias is a reader of it, and a label-keeping alias that is itself uncreated
/// inherits the property whose absence leaves the chain's root uncreated. Beside it: a reader inside a nested seam,
/// which the nested seam's signature carries as the alias or receive it is; a reader that requires the alias, which is
/// rejected as an `onlyIfAvailable` reader is; and the spellings of each. Each cell sits beside the inline build of the
/// same graph.
struct SafeDIToolSeamLabelKeepingAliasTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A label-keeping alias of an uncreated alias

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenLabelKeepingAliasBeneathAliasRetypesIt(holder: Holder) async throws {
		// `Reader`'s alias keeps the label `authToken` of `Detail`'s uncreated alias and retypes it: its fulfilling expression
		// reads `Detail`'s alias, not `Reader`'s own declaration, which is not in scope in its own initializer.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.labelKeepingAlias], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		await assertThrowsError(diagnostics: { fixtures in
			let expected: [Holder: String] = [
				.nothing: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.token: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.authToken: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
			]
			return expected[holder] ?? ""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = nil
				                    #sourceLocation()
				                    func __safeDI_reader() -> Reader {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
				                        let authToken: (any Auth)? = authToken
				                        #sourceLocation()
				                        return Reader(authToken: authToken)
				                    }
				                    let reader: Reader = __safeDI_reader()
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(left: left)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    func __safeDI_reader() -> Reader {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
				                        let authToken: (any Auth)? = authToken
				                        #sourceLocation()
				                        return Reader(authToken: authToken)
				                    }
				                    let reader: Reader = __safeDI_reader()
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(left: left)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = nil
				                    #sourceLocation()
				                    func __safeDI_reader() -> Reader {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
				                        let authToken: (any Auth)? = authToken
				                        #sourceLocation()
				                        return Reader(authToken: authToken)
				                    }
				                    let reader: Reader = __safeDI_reader()
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(left: left)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrors_whenReaderBeneathLabelKeepingAliasOfUncreatedAliasReceivesIt() async throws {
		// `Sub`'s label-keeping alias of `Detail`'s uncreated alias is itself uncreated where `token` is, and `Reader` beneath
		// `Sub` reads it: both are reported, in source order, naming `token`, the chain's root.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let sub: Sub"], reader: [Self.existentialReceive], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (any Auth)?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			\(fixtures["Sub.swift"]):8:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Sub` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_sub() -> Sub {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 8)
			                        let authToken: (any Auth)? = authToken
			                        #sourceLocation()
			                        let reader = Reader(authToken: authToken)
			                        return Sub(authToken: authToken, reader: reader)
			                    }
			                    let sub: Sub = __safeDI_sub()
			                    return Detail(authToken: authToken, sub: sub)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrors_whenReaderBeneathLabelKeepingAliasOfAliasOfPropertyBeingBuiltReceivesIt() async throws {
		// The static form of the chain: both errors say `token` is still being built, and neither offers to make the alias required.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret"], left: nil, detail: [Self.alias, "@Instantiated let sub: Sub"], reader: [Self.existentialReceive], secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Sub.swift"]):8:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Sub` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is still being built; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 8)
			                    let authToken: (any Auth)? = authToken
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Sub(authToken: authToken, reader: reader)
			                }
			                let sub: Sub = __safeDI_sub()
			                return Detail(authToken: authToken, sub: sub)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_sub() -> Sub {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 8)
			                        let authToken: (any Auth)? = authToken
			                        #sourceLocation()
			                        let reader = Reader(authToken: authToken)
			                        return Sub(authToken: authToken, reader: reader)
			                    }
			                    let sub: Sub = __safeDI_sub()
			                    return Detail(authToken: authToken, sub: sub)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenErasedLabelKeepingAliasBeneathAliasRetypesIt() async throws {
		// An erased label-keeping alias reads the uncreated alias too; inline, which reads `Root`'s `authToken`, compiles.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.erasedLabelKeepingAlias], secretConformances: ", Auth", otherTypes: [Self.authProtocol, Self.anyAuth])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_reader() -> Reader {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
			                        let authToken: AnyAuth? = (authToken as Secret?).map { AnyAuth($0) }
			                        #sourceLocation()
			                        return Reader(authToken: authToken)
			                    }
			                    let reader: Reader = __safeDI_reader()
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOneUncreatedAliasError_whenLabelKeepingAliasIsReachedBeneathAliasAndBesideIt() async throws {
		// `Reader` is built under `Screen` directly, where `authToken` is a parameter that may be `nil`, and beneath `Detail`'s
		// alias: one error, from the path beneath the alias.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let reader: Reader", "@Instantiated let left: Left"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.labelKeepingAlias], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_reader() -> Reader {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
			                let authToken: (any Auth)? = authToken
			                #sourceLocation()
			                return Reader(authToken: authToken)
			            }
			            let reader: Reader = __safeDI_reader()
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_reader() -> Reader {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
			                        let authToken: (any Auth)? = authToken
			                        #sourceLocation()
			                        return Reader(authToken: authToken)
			                    }
			                    let reader: Reader = __safeDI_reader()
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(reader: reader, left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whereInlineReadsTheAliasAbove_whenLabelKeepingAliasSpellsUnwrappedFormBeneathAlias() async throws {
		// A label-keeping alias spelled `ofType: Secret.self` beneath `authToken: Secret?` reads that optional form, as an
		// `onlyIfAvailable` alias reads either form of its fulfilling property, so inline binds it from `Detail`'s alias. The
		// seam rejects the read of its uncreated alias.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret.self, onlyIfAvailable: true) let authToken: (any Auth)?"], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_reader() -> Reader {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
			                        let authToken: (any Auth)? = authToken
			                        #sourceLocation()
			                        return Reader(authToken: authToken)
			                    }
			                    let reader: Reader = __safeDI_reader()
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: A label-keeping alias of a parameter that may be nil

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenReaderBeneathLabelKeepingAliasOfPassThroughReceivesIt() async throws {
		// `Sub` keeps the label of the pass-through `authToken`, which may be `nil`, and `Reader` beneath reads it: the remedy
		// renames `Sub`'s alias before receiving `authToken` itself, since a reader of the renamed alias is this shape again,
		// and a receive or alias of `authToken` beneath the label-keeping alias is the hidden-label error.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], left: ["@Instantiated let sub: Sub"], detail: nil, reader: [Self.existentialReceive], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (any Auth)?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: Secret?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: Secret?` on `Reader` instead, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 8)
			                    let authToken: (any Auth)? = authToken
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Sub(authToken: authToken, reader: reader)
			                }
			                let sub: Sub = __safeDI_sub()
			                return Left(sub: sub)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenReaderBeneathErasedLabelKeepingAliasOfPassThroughReceivesIt() async throws {
		// `Root` holds an erased `authToken: AnyAuth`, which inline's `Reader` reads where the seam would pass `nil`: the
		// value the rejection prevents.
		let fixture = Self.fixture(rootHolds: ["@Instantiated(fulfilledByType: \"Secret\", erasedToConcreteExistential: true) let authToken: AnyAuth"], left: ["@Instantiated let sub: Sub"], detail: nil, reader: ["@Received(onlyIfAvailable: true) let authToken: AnyAuth?"], secretConformances: ", Auth", otherTypes: [Self.authProtocol, Self.anyAuth, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.erasedLabelKeepingAlias, "@Instantiated let reader: Reader"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: AnyAuth?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: Secret?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: Secret?` on `Reader` instead, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = AnyAuth(Secret())
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 8)
			                    let authToken: AnyAuth? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Sub(authToken: authToken, reader: reader)
			                }
			                let sub: Sub = __safeDI_sub()
			                return Left(sub: sub)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenReaderBeneathLabelKeepingAliasOfPropertyBeingBuiltReceivesIt() async throws {
		// `Sub` is built inside `authToken`, so its label-keeping alias is statically uncreated: the remedy renames the alias
		// and receives `authToken` itself, and does not offer to make the alias required.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], screen: ["@Instantiated let authToken: Secret"], left: nil, detail: nil, reader: [Self.existentialReceive], secret: ["@Instantiated let subBuilder: Instantiator<Sub>"], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (any Auth)?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: Secret?` is still being built; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: Secret?` on `Reader` instead.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_subBuilder() -> Sub {
			                #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 8)
			                let authToken: (any Auth)? = nil
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Sub(authToken: authToken, reader: reader)
			            }
			            let subBuilder = Instantiator<Sub>(__safeDI_subBuilder)
			            return Secret(subBuilder: subBuilder)
			        }
			        let token: Secret = __safeDI_token()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_authToken() -> Secret {
			                func __safeDI_subBuilder() -> Sub {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 8)
			                    let authToken: (any Auth)? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Sub(authToken: authToken, reader: reader)
			                }
			                let subBuilder = Instantiator<Sub>(__safeDI_subBuilder)
			                return Secret(subBuilder: subBuilder)
			            }
			            let authToken: Secret = __safeDI_authToken()
			            return Screen(authToken: authToken)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: Controls

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAlias_whenTypeBeneathAliasInstantiatesItsPropertyAndAliasesThatUnderAnotherLabel() async throws {
		// `Reader` instantiates `authToken` and aliases its own property as `bearer`: an alias with another label reads the
		// sibling the type declares, which the guard keeps for every alias that keeps no label.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: ["@Instantiated let authToken: Secret", "@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret.self, onlyIfAvailable: true) let bearer: Secret?"], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_D306FBD537400E08.self
			            return Screen(token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init(token: Secret?) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token
			                #sourceLocation()
			                func __safeDI_reader() -> Reader {
			                    let authToken = Secret()
			                    #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 9)
			                    let bearer: Secret? = authToken
			                    #sourceLocation()
			                    return Reader(authToken: authToken, bearer: bearer)
			                }
			                let reader: Reader = __safeDI_reader()
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_D306FBD537400E08 {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_reader() -> Reader {
			                        let authToken = Secret()
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 9)
			                        let bearer: Secret? = authToken
			                        #sourceLocation()
			                        return Reader(authToken: authToken, bearer: bearer)
			                    }
			                    let reader: Reader = __safeDI_reader()
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: The type-spelling axis

	@Test(arguments: SafeDIToolSeamUncreatedAliasTests.Spelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorSpellingRemedyType_whenReaderBeneathLabelKeepingAliasOfPassThroughIsSpelledAnyWay(spelling: SafeDIToolSeamUncreatedAliasTests.Spelling) async {
		// The remedy spells the pass-through's optional form through its type description, `X?` and never `X??`.
		let fixture = spelling.fixture(left: ["@Instantiated let sub: Sub"], detail: nil, reader: [spelling.anyReceive], otherTypes: [seamFixtureType(named: "Sub", isFinalClass: true, declarations: [spelling.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		await assertThrowsError(diagnostics: { fixtures in
			let expected: [SafeDIToolSeamUncreatedAliasTests.Spelling: String] = [
				.existential: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: (any Auth)?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: (any Auth)?` on `Reader` instead, or make the alias required.
				""",
				.closure: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: (() -> Void)?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: (() -> Void)?` on `Reader` instead, or make the alias required.
				""",
				.nested: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: Feature.Secret?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: Feature.Secret?` on `Reader` instead, or make the alias required.
				""",
				.nonFunctionTypealias: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: SecretID?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: SecretID?` on `Reader` instead, or make the alias required.
				""",
				.optionalOfType: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: Secret?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: Secret?` on `Reader` instead, or make the alias required.
				""",
				.sendableClosure: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: (@Sendable () -> Void)?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: (@Sendable () -> Void)?` on `Reader` instead, or make the alias required.
				""",
				.optionalClosure: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: (() -> Void)?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: (() -> Void)?` on `Reader` instead, or make the alias required.
				""",
				.tuple: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: (a: Int, b: String)?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: (a: Int, b: String)?` on `Reader` instead, or make the alias required.
				""",
				.generic: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Any?` beneath the `onlyIfAvailable` alias `authToken` that `Sub` declares, which is not created where `authToken: Box<Secret>?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Sub`, or `nil`, depending on what encloses it. Give `Sub`'s alias a label other than `authToken` and receive `@Received(onlyIfAvailable: true) let authToken: Box<Secret>?` on `Reader` instead, or make the alias required.
				""",
			]
			return expected[spelling] ?? ""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: A reader inside a nested seam

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorWithAliasText_whenNestedSeamsTypeAliasesUncreatedAlias(holder: Holder) async throws {
		// `Sub`, inside the nested seam `Inner`, aliases `Detail`'s uncreated alias: `Inner`'s parameter stands for that alias,
		// which its signature's receiver records, so the error is the alias one, as for the same tree with `Inner` inline.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias, "@Instantiated let inner: Inner"], reader: nil, secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let sub: Sub"]), seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"])])
		await assertThrowsError(diagnostics: { fixtures in
			let expected: [Holder: String] = [
				.nothing: """
				\(fixtures["Sub.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Sub` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.token: """
				\(fixtures["Sub.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Sub` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.authToken: """
				\(fixtures["Sub.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Sub` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
			]
			return expected[holder] ?? ""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = nil
				                    #sourceLocation()
				                    func __safeDI_inner() -> Inner {
				                        func __safeDI_sub() -> Sub {
				                            #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 7)
				                            let bearer: Secret? = authToken
				                            #sourceLocation()
				                            return Sub(bearer: bearer)
				                        }
				                        let sub: Sub = __safeDI_sub()
				                        return Inner(sub: sub)
				                    }
				                    let inner: Inner = __safeDI_inner()
				                    return Detail(authToken: authToken, inner: inner)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(left: left)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    func __safeDI_inner() -> Inner {
				                        func __safeDI_sub() -> Sub {
				                            #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 7)
				                            let bearer: Secret? = authToken
				                            #sourceLocation()
				                            return Sub(bearer: bearer)
				                        }
				                        let sub: Sub = __safeDI_sub()
				                        return Inner(sub: sub)
				                    }
				                    let inner: Inner = __safeDI_inner()
				                    return Detail(authToken: authToken, inner: inner)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(left: left)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = nil
				                    #sourceLocation()
				                    func __safeDI_inner() -> Inner {
				                        func __safeDI_sub() -> Sub {
				                            #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 7)
				                            let bearer: Secret? = authToken
				                            #sourceLocation()
				                            return Sub(bearer: bearer)
				                        }
				                        let sub: Sub = __safeDI_sub()
				                        return Inner(sub: sub)
				                    }
				                    let inner: Inner = __safeDI_inner()
				                    return Detail(authToken: authToken, inner: inner)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(left: left)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorWithAliasText_whenNestedSeamItselfAliasesUncreatedAlias() async throws {
		// The nested seam declares the alias of the alias itself: the alias text names `Inner`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let inner: Inner"], reader: nil, secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Inner.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Inner` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_inner() -> Inner {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Inner.swift"])", line: 7)
			                        let bearer: Secret? = authToken
			                        #sourceLocation()
			                        return Inner(bearer: bearer)
			                    }
			                    let inner: Inner = __safeDI_inner()
			                    return Detail(authToken: authToken, inner: inner)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: A reader that requires the alias

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenRequiredReaderBeneathAliasOfPassThroughReceivesIt() async throws {
		// A reader that requires the alias's property is rejected as an `onlyIfAvailable` reader is: the parameter stays
		// `T?`, received only if available, so no binding gives the reader inline's value, and the remedy is a required
		// alias typed as the reader receives it.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.requiredReceive], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = token
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
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
	mutating func generate_throwsChainError_whenRequiredAliasTypedNonOptionalIsRequiredAsOptionalBeneathIt() async {
		// The remedy mis-typed: a required alias typed `Secret` does not fulfill a reader requiring `Secret?`, the existing chain
		// error in both builds.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self) let authToken: Secret", "@Instantiated let reader: Reader"], reader: [Self.requiredReceive], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `authToken: Secret?` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Left -> Detail -> Reader. The non-optional `authToken: Secret` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
			\(fixtures["Reader.swift"]):7:5-7:14: fixit: @Received(onlyIfAvailable: true)
			\(fixtures["Reader.swift"]):7:5: error: @Received property `authToken: Secret?` is not @Instantiated or @Forwarded in chain: Screen -> Left -> Detail -> Reader. The non-optional `authToken: Secret` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
			\(fixtures["Reader.swift"]):7:5-7:14: fixit: @Received(onlyIfAvailable: true)
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `authToken: Secret?` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Left -> Detail -> Reader. The non-optional `authToken: Secret` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
			\(fixtures["Reader.swift"]):7:5-7:14: fixit: @Received(onlyIfAvailable: true)
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Across modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorInSeamsModule_whenLabelKeepingAliasAndItsDeclaringTypeAreInModuleSeamDependsOn(integration: MultiModuleIntegration) async {
		// `Detail` and `Reader` declared in `Core`, which `Feature` depends on.
		let files = Self.fixture(rootHolds: Holder.authToken.declarations, detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.labelKeepingAlias])
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Reader.swift", in: "Core", fixtures, integration)):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Reader.swift", in: "Core", fixtures, integration)):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `authToken`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `authToken` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `authToken` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.threeModules(files), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorWithAliasTextInSeamsModule_whenNestedSeamInAnotherModuleAliasesUncreatedAlias(integration: MultiModuleIntegration) async {
		// The nested seam's signature is computed by each module from the declarations in module info, so the receiver's
		// alias property is in memory only: the alias text is the same with `Inner` in another module.
		let files = Self.fixture(rootHolds: Holder.authToken.declarations, detail: [Self.alias, "@Instantiated let inner: Inner"], reader: nil, otherTypes: [Self.authProtocol, seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let sub: Sub"]), seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"])])
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Sub.swift", in: "Core", fixtures, integration)):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Sub` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Sub.swift", in: "Core", fixtures, integration)):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Sub` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.innerInCore(files), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	typealias Holder = SafeDIToolSeamUncreatedAliasTests.Holder
	private static let alias = "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?"
	private static let receive = "@Received(onlyIfAvailable: true) let authToken: Secret?"
	private static let requiredReceive = "@Received let authToken: Secret?"
	private static let existentialReceive = "@Received(onlyIfAvailable: true) let authToken: (any Auth)?"
	/// An alias that keeps the label `authToken` and retypes it to an existential `Secret` conforms to.
	private static let labelKeepingAlias = "@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let authToken: (any Auth)?"
	private static let erasedLabelKeepingAlias = "@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let authToken: AnyAuth?"
	private static let authProtocol = "public protocol Auth {}"
	private static let anyAuth = "public struct AnyAuth: Auth {\n    public init(_ auth: any Auth) {\n        self.auth = auth\n    }\n\n    public let auth: any Auth\n}"

	private static func fixture(
		rootHolds: [String] = [],
		rootBuilds: String = "@Instantiated let screen: Screen",
		screen: [String] = ["@Instantiated let left: Left"],
		left: [String]? = ["@Instantiated let detail: Detail"],
		detail: [String]? = [alias, "@Instantiated let reader: Reader"],
		reader: [String]? = [receive],
		secret: [String] = [],
		secretConformances: String = ", Auth",
		otherTypes: [String] = [authProtocol],
	) -> [String] {
		SafeDIToolSeamUncreatedAliasTests.fixture(rootHolds: rootHolds, rootBuilds: rootBuilds, screen: screen, left: left, detail: detail, reader: reader, secret: secret, secretConformances: secretConformances, otherTypes: otherTypes)
	}

	private static func twoModules(_ files: [String]) -> [ModuleFixture] {
		SafeDIToolSeamUncreatedAliasTests.twoModules(files)
	}

	private static func threeModules(_ files: [String]) -> [ModuleFixture] {
		SafeDIToolSeamUncreatedAliasTests.threeModules(files)
	}

	/// The path a diagnostic names `file` of `module` by under `integration`.
	private static func path(of file: String, in module: String, _ fixtures: [String: FixturePaths], _ integration: MultiModuleIntegration) -> String {
		SafeDIToolSeamUncreatedAliasTests.path(of: file, in: module, fixtures, integration)
	}

	/// `files` as `twoModules`, with `Inner`, `Sub`, and `Secret` in `Core`, which `Feature` depends on.
	private static func innerInCore(_ files: [String]) -> [ModuleFixture] {
		let coreTypes = files.filter { $0.contains("class Inner:") || $0.contains("class Sub:") || $0.contains("class Secret:") || $0.hasPrefix("public protocol Auth") }
		let featureTypes = files.dropFirst().filter { !coreTypes.contains($0) }
		return [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: coreTypes),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureTypes.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Core\nimport Feature\n\n" + files[0]], dependencies: ["Core", "Feature"]),
		]
	}
}
