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

/// An `onlyIfAvailable` alias inside a seam's tree that may not be created – bound from a parameter of the generated
/// initializer that may be `nil`, judged against the closest declaration of its fulfilling property on the path, or
/// not created on a path – is bound from its fulfilling property, or not created, exactly as inline builds it, and its
/// declaring type is passed what inline passes it. Inline, anything else that reads the alias's label where the alias
/// is not created reads whatever declaration of the label encloses the alias, which depends on what encloses the seam,
/// so the seam rejects every such read: a receive of the alias's property in its declaring type's tree, an alias of it
/// on that type or beneath, and, but for the seam type's own aliases, a declaration of the alias's property on the type
/// that builds the declaring type. Each cell sits beside the inline build of the same graph.
struct SafeDIToolSeamUncreatedAliasTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A receive of an uncreated alias

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenReaderBeneathAliasOfPassThroughReceivesAliasProperty(holder: Holder) async throws {
		// `Detail`'s alias of the pass-through `token` is not created inline where `token` is unavailable, and `Reader`
		// then reads whatever `authToken` encloses `Detail`: the seam reports it, whatever the caller holds.
		let fixture = Self.fixture(rootHolds: holder.declarations)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			"""
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    let reader = Reader(authToken: nil)
				                    return Detail(authToken: nil, reader: reader)
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
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: nil, reader: reader)
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
	mutating func generate_throwsUncreatedAliasError_whenAnotherTypeReceivesAliasLabelAsAnotherType() async throws {
		// `Client`'s receive of `authToken: String?` makes the seam take a parameter of that label, which inline is no
		// declaration: `Reader` reads the caller's `authToken: Secret` where `Detail`'s alias is not created.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let left: Left", "@Instantiated let client: Client"], otherTypes: [seamFixtureType(named: "Client", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: String?"])])
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
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            let client = Client(authToken: nil)
			            return Screen(left: left, client: client)
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
	mutating func generate_throwsUncreatedAliasError_whenOptionalWrapperOfAliasLabelIsReceivedBesideTheAlias() async throws {
		// `Consumer`'s receive of `authToken: LazilyInstantiated<Secret>?` makes the seam take a parameter of that label,
		// which inline is no declaration: `Reader` reads the caller's `authToken: Secret` where the alias is not created.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let left: Left", "@Instantiated let consumer: Consumer"], otherTypes: [seamFixtureType(named: "Consumer", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: LazilyInstantiated<Secret>?"])])
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
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            let consumer = Consumer(authToken: nil)
			            return Screen(left: left, consumer: consumer)
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
	mutating func generate_throwsUncreatedAliasError_whenSeamReceivesAliasLabelAsAnotherType() async throws {
		// The seam's own `authToken: Label?` is a parameter inline does not have: `Reader` reads the caller's
		// `authToken: Secret` where `Detail`'s alias is not created.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Received(onlyIfAvailable: true) let authToken: Label?", "@Instantiated let left: Left"], otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: [])])
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
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(authToken: nil, left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: A receive of an uncreated alias beneath another declaration of its label

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenSeamReceivesAliasPropertyOnlyIfAvailable(holder: Holder) async throws {
		// The seam's own `authToken: Secret?` is a declaration above the alias, which nothing about the verdict depends on:
		// `Reader`'s closest declaration of the label is the alias.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: [Self.receive, "@Instantiated let left: Left"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			"""
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    let reader = Reader(authToken: nil)
				                    return Detail(authToken: nil, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: nil, left: left)
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
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: nil, left: left)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: nil, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: authToken, left: left)
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

	@Test(arguments: [.nothing, .token] as [Holder])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrors_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasProperty(holder: Holder) async throws {
		// `Left` instantiates `authToken: Secret` and builds `Detail`: `Reader` reads `Left`'s inline where the alias is not
		// created, and so is `Detail` passed it.
		let fixture = Self.fixture(rootHolds: holder.declarations, left: ["@Instantiated let authToken: Secret", "@Instantiated let detail: Detail"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):8:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			"""
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
				                let authToken = Secret()
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                let authToken = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenSeamInstantiatesAliasPropertyAboveTypeBuildingAliasesDeclaringType() async throws {
		// `Screen` instantiates `authToken: Secret` two levels above `Detail`: `Reader` reads it inline where the alias is not
		// created.
		let fixture = Self.fixture(screen: ["@Instantiated let authToken: Secret", "@Instantiated let left: Left"])
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
			        func __safeDI_screen() -> Screen {
			            let authToken = Secret()
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(authToken: authToken, left: left)
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
	mutating func generate_throwsUncreatedAliasError_whenTypeBuildingAliasesDeclaringTypeIsForwardedAliasProperty() async throws {
		// `Left` is forwarded `authToken: Secret`: `Reader` reads it inline where the alias is not created.
		let fixture = Self.fixture(screen: ["@Instantiated let leftBuilder: Instantiator<Left>"], left: ["@Forwarded let authToken: Secret", "@Instantiated let detail: Detail"])
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
			        func __safeDI_screen() -> Screen {
			            func __safeDI_leftBuilder(authToken: Secret) -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let leftBuilder = Instantiator<Left> {
			                __safeDI_leftBuilder(authToken: $0)
			            }
			            return Screen(leftBuilder: leftBuilder)
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
	mutating func generate_throwsUncreatedAliasError_whenSeamRequiresWrapperOfAliasLabel() async throws {
		// The seam's own required `authToken: LazilyInstantiated<Secret>` is a declaration above the alias, which nothing about
		// the verdict depends on.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: LazilyInstantiated<Secret>"], screen: ["@Received let authToken: LazilyInstantiated<Secret>", "@Instantiated let left: Left"])
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
			        func __safeDI_authToken() -> Secret {
			            Secret()
			        }
			        let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(authToken: authToken, left: left)
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
	mutating func generate_throwsUncreatedAliasError_whenSeamRequiresAliasLabelAsAnotherType() async throws {
		// The seam's own required `authToken: Label` is a declaration above the alias, which nothing about the verdict
		// depends on.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Label"], screen: ["@Received let authToken: Label", "@Instantiated let left: Left"], otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: [])])
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
			        let authToken = Label()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(authToken: authToken, left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: A receive of an uncreated alias beneath a declaration of its label that does not provide it

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasLabelAsAnotherType() async throws {
		// `Left` instantiates `authToken: Label`, which inline `Reader` would read where the alias is not created – code that
		// does not compile once a caller's `authToken: Secret` provides the alias's property.
		let fixture = Self.fixture(screen: ["@Instantiated let left: Left", "@Instantiated let client: Client"], left: ["@Instantiated let authToken: Label", "@Instantiated let detail: Detail"], otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: []), seamFixtureType(named: "Client", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: Secret?"])])
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
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                let authToken = Label()
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            let client = Client(authToken: nil)
			            return Screen(left: left, client: client)
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
	mutating func generate_throwsUncreatedAliasError_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasLabelAsAnotherTypeBeneathAliasProperty() async throws {
		// `Screen` instantiates `authToken: Secret` and `Left` `authToken: Label`: with the caller's `token`, inline creates the
		// alias; without it, `Reader` would read `Left`'s `Label`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], screen: ["@Instantiated let authToken: Secret", "@Instantiated let left: Left"], left: ["@Instantiated let authToken: Label", "@Instantiated let detail: Detail"], otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: [])])
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
			            let authToken = Secret()
			            func __safeDI_left() -> Left {
			                let authToken = Label()
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = token
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(authToken: authToken, left: left)
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
	mutating func generate_throwsUncreatedAliasError_whenTypeBuildingAliasesDeclaringTypeLazilyInstantiatesAliasLabel() async throws {
		// `Left` lazily instantiates `authToken`, whose instance never stands in for the uncreated alias inline.
		let fixture = Self.fixture(screen: ["@Instantiated let left: Left", "@Instantiated let client: Client"], left: ["@Instantiated let authToken: LazilyInstantiated<Secret>", "@Instantiated let detail: Detail"], otherTypes: [seamFixtureType(named: "Client", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: Secret?"])])
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
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_authToken() -> Secret {
			                    Secret()
			                }
			                let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            let client = Client(authToken: nil)
			            return Screen(left: left, client: client)
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
	mutating func generate_throwsUncreatedAliasError_whenTypeBuildingAliasesDeclaringTypeInstantiatesInstantiatorOfAliasLabel() async throws {
		// `Left` instantiates an `Instantiator` under the alias's label, which inline is no declaration of its property.
		let fixture = Self.fixture(screen: ["@Instantiated let left: Left", "@Instantiated let client: Client"], left: ["@Instantiated let authToken: Instantiator<Secret>", "@Instantiated let detail: Detail"], otherTypes: [seamFixtureType(named: "Client", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: Secret?"])])
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
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_authToken() -> Secret {
			                    Secret()
			                }
			                let authToken = Instantiator<Secret>(__safeDI_authToken)
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            let client = Client(authToken: nil)
			            return Screen(left: left, client: client)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: A receive of an alias that is not created where it is declared

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsBeingBuilt() async throws {
		// `Detail` is built inside `token`, so its alias of `token` is never created there, and `Reader` reads the caller's
		// `authToken` inline.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret"], left: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is still being built; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
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
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                let reader = Reader(authToken: nil)
			                return Detail(authToken: nil, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsBeingBuiltAndSeamReceivesAliasProperty() async throws {
		// The seam's own `authToken: Secret?` changes nothing: `Reader`'s closest declaration of the label is the alias.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: [Self.receive, "@Instantiated let token: Secret"], left: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is still being built; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
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
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                let reader = Reader(authToken: nil)
			                return Detail(authToken: nil, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            return Screen(authToken: authToken, token: token)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsGeneratedLater() async throws {
		// `Secret` receives `a` only if available, so `token` is generated after `A`, which builds `Detail`: the alias is not
		// created, and `Reader` reads the caller's `authToken` inline.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret", "@Instantiated let a: A"], left: nil, secret: ["@Received(onlyIfAvailable: true) let a: A?"], otherTypes: [seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is generated later; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret(a: nil)
			        func __safeDI_screen() -> Screen {
			            func __safeDI_a() -> A {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return A(detail: detail)
			            }
			            let a: A = __safeDI_a()
			            let token = Secret(a: a)
			            return Screen(token: token, a: a)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsGeneratedLaterAndSeamReceivesAliasProperty() async throws {
		// The seam's own `authToken: Secret?` changes nothing: `Reader`'s closest declaration of the label is the alias.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: [Self.receive, "@Instantiated let token: Secret", "@Instantiated let a: A"], left: nil, secret: ["@Received(onlyIfAvailable: true) let a: A?"], otherTypes: [seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is generated later; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret(a: nil)
			        func __safeDI_screen() -> Screen {
			            func __safeDI_a() -> A {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return A(detail: detail)
			            }
			            let a: A = __safeDI_a()
			            let token = Secret(a: a)
			            return Screen(authToken: authToken, token: token, a: a)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsBeingBuiltAndAnotherTypeReceivesAliasLabelAsAnotherType() async throws {
		// `Client`'s `authToken: String?` makes the seam take a parameter inline does not have.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret", "@Instantiated let client: Client"], left: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"], otherTypes: [seamFixtureType(named: "Client", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: String?"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is still being built; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
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
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                let reader = Reader(authToken: nil)
			                return Detail(authToken: nil, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            let client = Client(authToken: nil)
			            return Screen(token: token, client: client)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsBeingBuiltBeneathDeclarationOfAliasLabelAsAnotherType() async throws {
		// `Left`, built inside `token`, instantiates `authToken: Label`, which inline `Reader` reads once something provides the
		// alias's property.
		let fixture = Self.fixture(screen: ["@Instantiated let token: Secret", "@Instantiated let client: Client"], left: ["@Instantiated let authToken: Label", "@Instantiated let detail: Detail"], secret: ["@Instantiated let leftBuilder: Instantiator<Left>"], otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: []), seamFixtureType(named: "Client", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: Secret?"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is still being built; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_leftBuilder() -> Left {
			                    let authToken = Label()
			                    func __safeDI_detail() -> Detail {
			                        // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                        let reader = Reader(authToken: nil)
			                        return Detail(authToken: nil, reader: reader)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(authToken: authToken, detail: detail)
			                }
			                let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			                return Secret(leftBuilder: leftBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            let client = Client(authToken: nil)
			            return Screen(token: token, client: client)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsBeingBuiltBeneathLazilyInstantiatedAliasLabel() async throws {
		// `Left`, built inside `token`, lazily instantiates `authToken`, whose instance never stands in for the alias inline.
		let fixture = Self.fixture(screen: ["@Instantiated let token: Secret", "@Instantiated let client: Client"], left: ["@Instantiated let authToken: LazilyInstantiated<Secret>", "@Instantiated let detail: Detail"], secret: ["@Instantiated let leftBuilder: Instantiator<Left>"], otherTypes: [seamFixtureType(named: "Client", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let authToken: Secret?"])])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is still being built; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_leftBuilder() -> Left {
			                    func __safeDI_authToken() -> Secret {
			                        let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			                        return Secret(leftBuilder: leftBuilder)
			                    }
			                    let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
			                    func __safeDI_detail() -> Detail {
			                        // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                        let reader = Reader(authToken: nil)
			                        return Detail(authToken: nil, reader: reader)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(authToken: authToken, detail: detail)
			                }
			                let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			                return Secret(leftBuilder: leftBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            let client = Client(authToken: nil)
			            return Screen(token: token, client: client)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasFulfillingPropertyIsBuiltBesideSeamsInstantiatedAliasProperty() async throws {
		// `Screen` instantiates `authToken` and `token`, each building `Detail`: the alias is never created, and `Reader` reads
		// `Screen`'s `authToken` inline where it is not being built.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let authToken: Secret", "@Instantiated let token: Secret"], left: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is still being built; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
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
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                let reader = Reader(authToken: nil)
			                return Detail(authToken: nil, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            func __safeDI_authToken() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = token
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
			            }
			            let authToken: Secret = __safeDI_authToken()
			            return Screen(authToken: authToken, token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: A receive of an uncreated alias inside a builder, a nested seam, or the seam itself

	@Test(arguments: ["Instantiator", "SendableInstantiator", "LazilyInstantiated"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenReaderBeneathAliasIsBuiltInsideWrapper(wrapper: String) async throws {
		// `Reader` built inside a builder function still reads the alias's label.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let readerBuilder: \(wrapper)<Reader>"], sendable: wrapper.hasPrefix("Sendable"))
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedInlineOutput: [String: [String: String]] = [
			"Instantiator": [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    func __safeDI_readerBuilder() -> Reader {
				                        Reader(authToken: authToken)
				                    }
				                    let readerBuilder = Instantiator<Reader>(__safeDI_readerBuilder)
				                    return Detail(authToken: nil, readerBuilder: readerBuilder)
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
			"SendableInstantiator": [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    @Sendable func __safeDI_readerBuilder() -> Reader {
				                        Reader(authToken: authToken)
				                    }
				                    let readerBuilder = SendableInstantiator<Reader>(__safeDI_readerBuilder)
				                    return Detail(authToken: nil, readerBuilder: readerBuilder)
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
			"LazilyInstantiated": [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    func __safeDI_readerBuilder() -> Reader {
				                        Reader(authToken: authToken)
				                    }
				                    let readerBuilder = LazilyInstantiated<Reader>(__safeDI_readerBuilder)
				                    return Detail(authToken: nil, readerBuilder: readerBuilder)
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
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[wrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenNestedSeamPassesAliasPropertyBeneathAlias() async throws {
		// `Panel`, a seam inside `Screen`'s tree, takes `authToken` as a parameter beneath `Detail`'s alias, standing for
		// `Panel`'s `Reader`, which inline reads the caller's `authToken` where the alias is not created.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let panel: Panel"], otherTypes: [seamFixtureType(named: "Panel", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let reader: Reader"])])
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
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    func __safeDI_panel() -> Panel {
			                        let reader = Reader(authToken: authToken)
			                        return Panel(reader: reader)
			                    }
			                    let panel: Panel = __safeDI_panel()
			                    return Detail(authToken: nil, panel: panel)
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
	mutating func generate_throwsUncreatedAliasError_whenReaderBeneathSeamsOwnAliasReceivesAliasProperty() async throws {
		// The seam type's own alias is not created inline where `token` is unavailable, and `Reader` beneath reads the
		// caller's `authToken`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: [Self.alias, "@Instantiated let reader: Reader"], left: nil, detail: nil)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Screen` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Screen`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
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
			            // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			            let reader = Reader(authToken: authToken)
			            return Screen(authToken: authToken, reader: reader)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: An alias of an uncreated alias

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenAliasesDeclaringTypeAliasesItOnlyIfAvailable(holder: Holder) async throws {
		// `bearer`, `Detail`'s alias of its own uncreated alias, is created inline from whatever `authToken` encloses `Detail`.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias, Self.bearer], reader: nil)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    // Did not create `bearer: Secret?` because `authToken: Secret?` is unavailable.
				                    return Detail(authToken: nil, bearer: nil)
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 9)
				                    let bearer: Secret? = authToken
				                    #sourceLocation()
				                    return Detail(authToken: authToken, bearer: bearer)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 9)
				                    let bearer: Secret? = authToken
				                    #sourceLocation()
				                    return Detail(authToken: nil, bearer: bearer)
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

	@Test(arguments: [.token, .authToken] as [Holder])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenAliasesDeclaringTypeAliasesItRequired(holder: Holder) async throws {
		// A required `bearer` of the uncreated alias reads it the same way. A caller that holds neither property has no inline
		// build: inline requires `authToken` of it.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias, "@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self) let bearer: Secret?"], reader: nil)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedInlineOutput: [Holder: [String: String]] = [
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 9)
				                    let bearer: Secret? = authToken
				                    #sourceLocation()
				                    return Detail(authToken: authToken, bearer: bearer)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 9)
				                    let bearer: Secret? = authToken
				                    #sourceLocation()
				                    return Detail(authToken: nil, bearer: bearer)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenSeamAliasesItsOwnAliasOnlyIfAvailable(holder: Holder) async throws {
		// The chain on the seam type itself: `bearer` reads `Screen`'s own alias, which its callers cannot change.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: [Self.alias, Self.bearer, "@Instantiated let left: Left"], left: [], detail: nil, reader: nil)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):10:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Screen` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Screen`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
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
				            // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				            // Did not create `bearer: Secret?` because `authToken: Secret?` is unavailable.
				            let left = Left()
				            return Screen(authToken: nil, bearer: nil, left: left)
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
				            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 9)
				            let authToken: Secret? = token
				            #sourceLocation()
				            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 10)
				            let bearer: Secret? = authToken
				            #sourceLocation()
				            let left = Left()
				            return Screen(authToken: authToken, bearer: bearer, left: left)
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
				            // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 10)
				            let bearer: Secret? = authToken
				            #sourceLocation()
				            let left = Left()
				            return Screen(authToken: authToken, bearer: bearer, left: left)
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
	mutating func generate_throwsUncreatedAliasError_whenAliasesDeclaringTypeAliasesAliasOfPropertyBeingBuilt() async throws {
		// Built inside `token`, `Detail` creates neither alias, while inline `bearer` is created from the caller's `authToken`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret"], left: nil, detail: [Self.alias, Self.bearer], reader: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Secret` is still being built; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead.
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
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                // Did not create `bearer: Secret?` because `authToken: Secret?` is unavailable.
			                return Detail(authToken: nil, bearer: nil)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 9)
			                    let bearer: Secret? = authToken
			                    #sourceLocation()
			                    return Detail(authToken: nil, bearer: bearer)
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
	mutating func generate_throwsUncreatedAliasError_whenTypeBeneathAliasesDeclaringTypeAliasesIt() async throws {
		// `Reader`, beneath `Detail`, declares `bearer` of `Detail`'s uncreated alias.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], reader: [Self.bearer])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
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
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    func __safeDI_reader() -> Reader {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
			                        let bearer: Secret? = authToken
			                        #sourceLocation()
			                        return Reader(bearer: bearer)
			                    }
			                    let reader: Reader = __safeDI_reader()
			                    return Detail(authToken: nil, reader: reader)
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
	mutating func generate_throwsUncreatedAliasErrors_whenReaderBeneathAliasOfUncreatedAliasReceivesIt() async throws {
		// `bearer` reads `authToken`, and `Reader` reads `bearer`, an alias of an alias that may not be created.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, Self.bearer, "@Instantiated let reader: Reader"], reader: ["@Received(onlyIfAvailable: true) let bearer: Secret?"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):10:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `bearer: Secret?` beneath the `onlyIfAvailable` alias `bearer` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `bearer` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
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
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 10)
			                    let bearer: Secret? = authToken
			                    #sourceLocation()
			                    let reader = Reader(bearer: bearer)
			                    return Detail(authToken: nil, bearer: bearer, reader: reader)
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

	// MARK: A declaration of the alias property beside the alias declaring type

	@Test(arguments: [.nothing, .token] as [Holder])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSamePropertyError_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasProperty(holder: Holder) async throws {
		// Nothing reads the alias, but inline `Left` passes `Detail` its own `authToken` where the alias is not created.
		let fixture = Self.fixture(rootHolds: holder.declarations, left: ["@Instantiated let authToken: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			"""
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
				                let authToken = Secret()
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                let authToken = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSamePropertyError_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasPropertyAfterIt() async throws {
		// Declared after `detail`, `Left`'s `authToken` is generated after it, and inline passes `Detail` `nil`: rejected as
		// label reuse beside the alias.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated let authToken: Secret"], detail: [Self.alias], reader: nil)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    return Detail(authToken: nil)
			                }
			                let detail: Detail = __safeDI_detail()
			                let authToken = Secret()
			                return Left(detail: detail, authToken: authToken)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
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
	mutating func generate_throwsSamePropertyError_whenTypeBuildingAliasesDeclaringTypeGeneratesAliasPropertyLater() async throws {
		// `Secret` receives `detail` only if available, so `Left`'s `authToken` is generated after `detail`.
		let fixture = Self.fixture(left: ["@Instantiated let authToken: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, secret: ["@Received(onlyIfAvailable: true) let detail: Detail?"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    return Detail(authToken: nil)
			                }
			                let detail: Detail = __safeDI_detail()
			                let authToken = Secret(detail: detail)
			                return Left(authToken: authToken, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	@Test(arguments: [.nothing, .other] as [Holder])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSamePropertyError_whenTypeBuildingAliasesDeclaringTypeAliasesAnotherParameterAsAliasProperty(holder: Holder) async throws {
		// `Left`'s own alias `authToken` of `other`, created where the caller holds `other`, is what inline passes `Detail`.
		let fixture = Self.fixture(rootHolds: holder.declarations, left: ["@Received(fulfilledByDependencyNamed: \"other\", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			"""
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
				                // Did not create `authToken: Secret?` because `other: Secret` is unavailable.
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: nil, detail: detail)
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
			.other: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let other = Secret()
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                #sourceLocation(file: "\(inlineOutput.fixtures["Left.swift"])", line: 8)
				                let authToken: Secret? = other
				                #sourceLocation()
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(left: left)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(other: other, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
	}

	@Test(arguments: [.nothing, .token] as [Holder])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSamePropertyError_whenAliasesDeclaringTypeBuildsTypeDeclaringTheSameAlias(holder: Holder) async throws {
		// `Reader`, built by `Detail`, declares its own alias `authToken` of `token`: `Detail` declares the alias's property.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: ["@Instantiated let detail: Detail"], left: nil, reader: [Self.alias])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Reader` declares is not created where `token: Secret` is unavailable, and `Detail`, which builds `Reader`, also declares `authToken: Secret?`; built inline, `Reader` is then passed `Detail`'s `authToken` when `Detail` builds it first. Give the alias a label `Detail` does not declare, or make the alias required.
			"""
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
				            func __safeDI_detail() -> Detail {
				                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                func __safeDI_reader() -> Reader {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Reader(authToken: nil)
				                }
				                let reader: Reader = __safeDI_reader()
				                return Detail(authToken: nil, reader: reader)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Screen(detail: detail)
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
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                func __safeDI_reader() -> Reader {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Reader.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Reader(authToken: authToken)
				                }
				                let reader: Reader = __safeDI_reader()
				                return Detail(authToken: authToken, reader: reader)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Screen(detail: detail)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSamePropertyError_whenAliasesDeclaringTypeBuildsTypeDeclaringTheSameAliasOfPropertyBeingBuilt() async throws {
		// Both aliases are not created where `token` is being built.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret"], left: ["@Instantiated let detail: Detail"], reader: [Self.alias], secret: ["@Instantiated let leftBuilder: Instantiator<Left>"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Reader` declares is not created where `token: Secret` is still being built, and `Detail`, which builds `Reader`, also declares `authToken: Secret?`; built inline, `Reader` is then passed `Detail`'s `authToken` when `Detail` builds it first. Give the alias a label `Detail` does not declare.
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
			            func __safeDI_leftBuilder() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    func __safeDI_reader() -> Reader {
			                        // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                        return Reader(authToken: nil)
			                    }
			                    let reader: Reader = __safeDI_reader()
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			            return Secret(leftBuilder: leftBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_leftBuilder() -> Left {
			                    func __safeDI_detail() -> Detail {
			                        // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                        func __safeDI_reader() -> Reader {
			                            // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                            return Reader(authToken: authToken)
			                        }
			                        let reader: Reader = __safeDI_reader()
			                        return Detail(authToken: nil, reader: reader)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(detail: detail)
			                }
			                let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			                return Secret(leftBuilder: leftBuilder)
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
	mutating func generate_throwsSamePropertyError_whenTypeBuildingAliasesDeclaringTypeAliasesPropertyBeingBuilt() async throws {
		// `Left`, built inside `other`, aliases `other` as `authToken`, which is not created there, beside `Detail`'s alias of
		// the pass-through `token`.
		let fixture = Self.fixture(screen: ["@Instantiated let other: Secret"], left: ["@Received(fulfilledByDependencyNamed: \"other\", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, secret: ["@Instantiated let left: Left"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_other() -> Secret {
			                func __safeDI_left() -> Left {
			                    // Did not create `authToken: Secret?` because `other: Secret` is unavailable.
			                    func __safeDI_detail() -> Detail {
			                        // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                        return Detail(authToken: nil)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(authToken: nil, detail: detail)
			                }
			                let left: Left = __safeDI_left()
			                return Secret(left: left)
			            }
			            let other: Secret = __safeDI_other()
			            return Screen(other: other)
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
	mutating func generate_throwsSamePropertyError_whenAliasOfPropertyBeingBuiltIsBuiltBesideAliasProperty() async throws {
		// `Detail`'s alias of `token`, built inside `token`, is not created, and `Left` instantiates `authToken: Secret`.
		let fixture = Self.fixture(screen: ["@Instantiated let token: Secret"], left: ["@Instantiated let authToken: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, secret: ["@Instantiated let leftBuilder: Instantiator<Left>"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is still being built, and `Left`, which builds `Detail`, also declares `authToken: Secret`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_leftBuilder() -> Left {
			                    func __safeDI_authToken() -> Secret {
			                        let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			                        return Secret(leftBuilder: leftBuilder)
			                    }
			                    let authToken: Secret = __safeDI_authToken()
			                    func __safeDI_detail() -> Detail {
			                        // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                        return Detail(authToken: authToken)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(authToken: authToken, detail: detail)
			                }
			                let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			                return Secret(leftBuilder: leftBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            return Screen(token: token)
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
	mutating func generate_throwsSamePropertyError_whenAliasPropertyIsExistentialAndBuilderInstantiatesItsUnwrappedForm() async throws {
		// `authToken: (any Auth)?` and `Left`'s `authToken: Auth` are one property's two forms, whatever the `any`.
		let fixture = Self.fixture(left: ["@Instantiated(fulfilledByType: \"Secret\") let authToken: Auth", "@Instantiated let detail: Detail"], detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let authToken: (any Auth)?"], reader: nil, secretConformances: ", Auth", otherTypes: ["public protocol Auth {}"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: (any Auth)?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Auth`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                let authToken: Auth = Secret()
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: (any Auth)?` because `token: Secret` is unavailable.
			                    return Detail(authToken: authToken)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(left: left)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: Accepted: an uncreated alias only its declaring type reads

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameterAndPassesBinding_whenOnlyAliasesDeclaringTypeReadsIt(holder: Holder) async throws {
		// The canonical alias: bound from the pass-through as an optional value, its declaring type passed the binding.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenTypeBuildingAliasesDeclaringTypeReceivesAliasLabel(holder: Holder) async throws {
		// `Left` receives `authToken` only if available and builds `Detail`, whose alias nothing reads: a receive declares nothing.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: ["@Instantiated let left: Left", "@Instantiated let client: Client"], left: [Self.receive, "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, otherTypes: [seamFixtureType(named: "Client", isFinalClass: true, declarations: [Self.receive])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_7277EBA46FA456D9.self
				            return Screen(authToken: nil, token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(authToken: Secret? = nil, token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let client = Client(authToken: authToken)
				        self.init(left: left, client: client)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_7277EBA46FA456D9 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_7277EBA46FA456D9.self
				            return Screen(authToken: nil, token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(authToken: Secret? = nil, token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let client = Client(authToken: authToken)
				        self.init(left: left, client: client)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_7277EBA46FA456D9 {}
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_7277EBA46FA456D9.self
				            return Screen(authToken: authToken, token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(authToken: Secret? = nil, token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let client = Client(authToken: authToken)
				        self.init(left: left, client: client)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_7277EBA46FA456D9 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: nil, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let client = Client(authToken: nil)
				            return Screen(left: left, client: client)
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: nil, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let client = Client(authToken: nil)
				            return Screen(left: left, client: client)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let client = Client(authToken: authToken)
				            return Screen(left: left, client: client)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasLabelAsAnotherType(holder: Holder) async throws {
		// `Left`'s `authToken: Label` declares another property than the alias's, which inline never passes `Detail`.
		let fixture = Self.fixture(rootHolds: holder.declarations, left: ["@Instantiated let authToken: Label", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: [])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                let authToken = Label()
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                let authToken = Label()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                let authToken = Label()
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasLabelAsInstantiator(holder: Holder) async throws {
		// `Left`'s `authToken: Instantiator<Secret>` declares another property than the alias's, which inline never passes `Detail`.
		let fixture = Self.fixture(rootHolds: holder.declarations, left: ["@Instantiated let authToken: Instantiator<Secret>", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, otherTypes: [])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_authToken() -> Secret {
				                Secret()
				            }
				            let authToken = Instantiator<Secret>(__safeDI_authToken)
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_authToken() -> Secret {
				                Secret()
				            }
				            let authToken = Instantiator<Secret>(__safeDI_authToken)
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_authToken() -> Secret {
				                Secret()
				            }
				            let authToken = Instantiator<Secret>(__safeDI_authToken)
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_authToken() -> Secret {
				                    Secret()
				                }
				                let authToken = Instantiator<Secret>(__safeDI_authToken)
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                func __safeDI_authToken() -> Secret {
				                    Secret()
				                }
				                let authToken = Instantiator<Secret>(__safeDI_authToken)
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                func __safeDI_authToken() -> Secret {
				                    Secret()
				                }
				                let authToken = Instantiator<Secret>(__safeDI_authToken)
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasLabelAsLazilyInstantiatedWrapper(holder: Holder) async throws {
		// `Left`'s `authToken: LazilyInstantiated<Secret>` declares another property than the alias's, which inline never passes `Detail`.
		let fixture = Self.fixture(rootHolds: holder.declarations, left: ["@Instantiated let authToken: LazilyInstantiated<Secret>", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, otherTypes: [])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_authToken() -> Secret {
				                Secret()
				            }
				            let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_authToken() -> Secret {
				                Secret()
				            }
				            let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_authToken() -> Secret {
				                Secret()
				            }
				            let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_authToken() -> Secret {
				                    Secret()
				                }
				                let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                func __safeDI_authToken() -> Secret {
				                    Secret()
				                }
				                let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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
				                func __safeDI_authToken() -> Secret {
				                    Secret()
				                }
				                let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenSeamInstantiatesAliasPropertyAboveTypeBuildingAliasesDeclaringType(holder: Holder) async throws {
		// `Screen`'s `authToken` is two levels above `Detail`, which inline is passed `nil` where the alias is not created.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: ["@Instantiated let authToken: Secret", "@Instantiated let left: Left"], detail: [Self.alias], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        let authToken = Secret()
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(authToken: authToken, left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        let authToken = Secret()
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(authToken: authToken, left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        let authToken = Secret()
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(authToken: authToken, left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            let authToken = Secret()
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: authToken, left: left)
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
				            let authToken = Secret()
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: authToken, left: left)
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
				            let authToken = Secret()
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: authToken, left: left)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenTypeBuildingAliasesDeclaringTypeIsForwardedAliasProperty(holder: Holder) async throws {
		// A forwarded `authToken` is no child of `Left`, so inline passes `Detail` `nil` where the alias is not created.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: ["@Instantiated let leftBuilder: Instantiator<Left>"], left: ["@Forwarded let authToken: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_leftBuilder(authToken: Secret) -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let leftBuilder = Instantiator<Left> {
				            __safeDI_leftBuilder(authToken: $0)
				        }
				        self.init(leftBuilder: leftBuilder)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_leftBuilder(authToken: Secret) -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let leftBuilder = Instantiator<Left> {
				            __safeDI_leftBuilder(authToken: $0)
				        }
				        self.init(leftBuilder: leftBuilder)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_leftBuilder(authToken: Secret) -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let leftBuilder = Instantiator<Left> {
				            __safeDI_leftBuilder(authToken: $0)
				        }
				        self.init(leftBuilder: leftBuilder)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_leftBuilder(authToken: Secret) -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
				            }
				            let leftBuilder = Instantiator<Left> {
				                __safeDI_leftBuilder(authToken: $0)
				            }
				            return Screen(leftBuilder: leftBuilder)
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
				            func __safeDI_leftBuilder(authToken: Secret) -> Left {
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
				            }
				            let leftBuilder = Instantiator<Left> {
				                __safeDI_leftBuilder(authToken: $0)
				            }
				            return Screen(leftBuilder: leftBuilder)
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
				            func __safeDI_leftBuilder(authToken: Secret) -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(authToken: authToken, detail: detail)
				            }
				            let leftBuilder = Instantiator<Left> {
				                __safeDI_leftBuilder(authToken: $0)
				            }
				            return Screen(leftBuilder: leftBuilder)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenSeamReceivesAliasPropertyOnlyIfAvailable(holder: Holder) async throws {
		// The seam's own `authToken: Secret?` is a parameter nothing beneath the alias reads.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: [Self.receive, "@Instantiated let left: Left"], detail: [Self.alias], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_7277EBA46FA456D9.self
				            return Screen(authToken: nil, token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(authToken: Secret? = nil, token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(authToken: authToken, left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_7277EBA46FA456D9 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_7277EBA46FA456D9.self
				            return Screen(authToken: nil, token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(authToken: Secret? = nil, token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(authToken: authToken, left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_7277EBA46FA456D9 {}
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_7277EBA46FA456D9.self
				            return Screen(authToken: authToken, token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(authToken: Secret? = nil, token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(authToken: authToken, left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_7277EBA46FA456D9 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: nil, left: left)
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: nil, left: left)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            return Screen(authToken: authToken, left: left)
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
	mutating func generate_leavesAliasUncreated_whenAliasFulfillingPropertyIsBeingBuiltAndNothingReadsIt() async throws {
		// Not created where `token` is being built, and read by nothing but `Detail`, which is passed `nil` both ways.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let authToken: Secret", "@Instantiated let token: Secret"], left: nil, detail: [Self.alias], reader: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                return Detail(authToken: nil)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_CBF29CE484222325.self
			            return Screen()
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                return Detail(authToken: nil)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let token: Secret = __safeDI_token()
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                let authToken: Secret? = token
			                #sourceLocation()
			                return Detail(authToken: authToken)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        self.init(authToken: authToken, token: token)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_CBF29CE484222325 {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                return Detail(authToken: nil)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    return Detail(authToken: nil)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
			            }
			            let token: Secret = __safeDI_token()
			            func __safeDI_authToken() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
			                    let authToken: Secret? = token
			                    #sourceLocation()
			                    return Detail(authToken: authToken)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
			            }
			            let authToken: Secret = __safeDI_authToken()
			            return Screen(authToken: authToken, token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: Accepted: an alias that is always created

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAlias_whenTypeOnPathInstantiatesAliasFulfillingProperty(holder: Holder) async throws {
		// `Left` instantiates `token`, the closest declaration of the alias's fulfilling property on that path, so the alias is
		// created there, and `Reader` reads it, while `Right` takes the seam's `token` parameter.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: ["@Instantiated let left: Left", "@Instantiated let right: Right"], left: ["@Instantiated let token: Secret", "@Instantiated let detail: Detail"], otherTypes: [seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let token: Secret?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let token = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Detail(authToken: authToken, reader: reader)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let right = Right(token: token)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let token = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Detail(authToken: authToken, reader: reader)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let right = Right(token: token)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let token = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Detail(authToken: authToken, reader: reader)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let right = Right(token: token)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                let token = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(token: token, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let right = Right(token: nil)
				            return Screen(left: left, right: right)
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
				                let token = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(token: token, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let right = Right(token: token)
				            return Screen(left: left, right: right)
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
				                let token = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    let reader = Reader(authToken: authToken)
				                    return Detail(authToken: authToken, reader: reader)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(token: token, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let right = Right(token: nil)
				            return Screen(left: left, right: right)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAlias_whenTypeOnPathInstantiatesAliasFulfillingPropertyAndNothingReadsIt(holder: Holder) async throws {
		// As above, with nothing beneath the alias.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: ["@Instantiated let left: Left", "@Instantiated let right: Right"], left: ["@Instantiated let token: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, otherTypes: [seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let token: Secret?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let token = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let right = Right(token: token)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let token = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let right = Right(token: token)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let token = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        let right = Right(token: token)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                let token = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(token: token, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let right = Right(token: nil)
				            return Screen(left: left, right: right)
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
				                let token = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(token: token, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let right = Right(token: token)
				            return Screen(left: left, right: right)
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
				                let token = Secret()
				                func __safeDI_detail() -> Detail {
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken)
				                }
				                let detail: Detail = __safeDI_detail()
				                return Left(token: token, detail: detail)
				            }
				            let left: Left = __safeDI_left()
				            let right = Right(token: nil)
				            return Screen(left: left, right: right)
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
	mutating func generate_readsNearerDeclaration_whenTypeBetweenAliasAndReaderInstantiatesAliasProperty() async throws {
		// `Mid` instantiates `authToken: Secret` between the alias and `Reader`, which reads `Mid`'s both ways.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let mid: Mid"], otherTypes: [seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let authToken: Secret", "@Instantiated let reader: Reader"])])
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
			    public convenience init(token: Secret? = nil) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token
			                #sourceLocation()
			                func __safeDI_mid() -> Mid {
			                    let authToken = Secret()
			                    let reader = Reader(authToken: authToken)
			                    return Mid(authToken: authToken, reader: reader)
			                }
			                let mid: Mid = __safeDI_mid()
			                return Detail(authToken: authToken, mid: mid)
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
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    func __safeDI_mid() -> Mid {
			                        let authToken = Secret()
			                        let reader = Reader(authToken: authToken)
			                        return Mid(authToken: authToken, reader: reader)
			                    }
			                    let mid: Mid = __safeDI_mid()
			                    return Detail(authToken: nil, mid: mid)
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
	mutating func generate_createsAlias_whenAnotherReceiverRequiresAliasFulfillingProperty() async throws {
		// `Other` requires `token`, so the seam takes it as a required parameter, and the alias is always created.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], screen: ["@Instantiated let left: Left", "@Instantiated let other: Other"], otherTypes: [seamFixtureType(named: "Other", isFinalClass: true, declarations: ["@Received let token: Secret"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
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
			    public convenience init(token: Secret) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        let other = Other(token: token)
			        self.init(left: left, other: other)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_AC3B2DB59BEF585F {}
			}
			""",
		])
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
			            let other = Other(token: token)
			            return Screen(left: left, other: other)
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
	mutating func generate_createsAlias_whenSeamIsForwardedAliasFulfillingProperty() async throws {
		// The seam's own `@Forwarded let token: Secret` is a parameter that is never `nil`.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let screenBuilder: Instantiator<Screen>", screen: ["@Forwarded let token: Secret", "@Instantiated let left: Left"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder(token: Secret) -> Screen {
			            _ = Screen.__safeDI_Screen_AC3B2DB59BEF585F.self
			            return Screen(token: token)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(token: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init(token: Secret) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(token: token, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_AC3B2DB59BEF585F {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder(token: Secret) -> Screen {
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
			            return Screen(token: token, left: left)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(token: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAlias_whenTypeOnPathIsForwardedAliasFulfillingProperty() async throws {
		// `Left`, built through an instantiator, is forwarded `token`, the closest declaration of the alias's fulfilling property.
		let fixture = Self.fixture(screen: ["@Instantiated let leftBuilder: Instantiator<Left>"], left: ["@Forwarded let token: Secret", "@Instantiated let detail: Detail"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_CBF29CE484222325.self
			            return Screen()
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init() {
			        func __safeDI_leftBuilder(token: Secret) -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(token: token, detail: detail)
			        }
			        let leftBuilder = Instantiator<Left> {
			            __safeDI_leftBuilder(token: $0)
			        }
			        self.init(leftBuilder: leftBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_CBF29CE484222325 {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_leftBuilder(token: Secret) -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = token
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(token: token, detail: detail)
			            }
			            let leftBuilder = Instantiator<Left> {
			                __safeDI_leftBuilder(token: $0)
			            }
			            return Screen(leftBuilder: leftBuilder)
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
	mutating func generate_createsRequiredAlias_whenReaderBeneathRequiresIt() async throws {
		// A required alias of the pass-through makes `token` a required parameter: the parameter is the property before
		// the rename.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self) let authToken: Secret", "@Instantiated let reader: Reader"], reader: ["@Received let authToken: Secret"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
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
			    public convenience init(token: Secret) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret = token
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
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
			    public enum __safeDI_Screen_AC3B2DB59BEF585F {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret = token
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
	mutating func generate_createsRequiredAlias_whenSeamDeclaresItAndReaderBeneathRequiresIt() async throws {
		// The same on the seam type itself.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], screen: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self) let authToken: Secret", "@Instantiated let reader: Reader"], left: nil, detail: nil, reader: ["@Received let authToken: Secret"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
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
			    public convenience init(token: Secret) {
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let authToken: Secret = token
			        #sourceLocation()
			        let reader = Reader(authToken: authToken)
			        self.init(authToken: authToken, reader: reader)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_AC3B2DB59BEF585F {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 8)
			            let authToken: Secret = token
			            #sourceLocation()
			            let reader = Reader(authToken: authToken)
			            return Screen(authToken: authToken, reader: reader)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: The remedies

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesFulfillingProperty_whenReaderReceivesAliasFulfillingPropertyInstead(holder: Holder) async throws {
		// The first remedy: `Reader` receives `token` itself only if available.
		let fixture = Self.fixture(rootHolds: holder.declarations, reader: ["@Received(onlyIfAvailable: true) let token: Secret?"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                let reader = Reader(token: token)
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
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                let reader = Reader(token: token)
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
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                let reader = Reader(token: token)
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
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    let reader = Reader(token: nil)
				                    return Detail(authToken: nil, reader: reader)
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
				                    let reader = Reader(token: token)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    let reader = Reader(token: nil)
				                    return Detail(authToken: nil, reader: reader)
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
	mutating func generate_createsAlias_whenAliasIsMadeRequired() async throws {
		// The second remedy: the alias is required, so `token` is a required parameter and `Reader` reads the alias.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self) let authToken: Secret", "@Instantiated let reader: Reader"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
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
			    public convenience init(token: Secret) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret = token
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
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
			    public enum __safeDI_Screen_AC3B2DB59BEF585F {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret = token
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
	mutating func generate_passesNil_whenReaderBeneathAliasOfPropertyBeingBuiltReceivesFulfillingPropertyInstead() async throws {
		// The first remedy where `token` is being built: `Reader` is passed `nil` both ways.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret"], left: nil, reader: ["@Received(onlyIfAvailable: true) let token: Secret?"], secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                let reader = Reader(token: nil)
			                return Detail(authToken: nil, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_CBF29CE484222325.self
			            return Screen()
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                let reader = Reader(token: nil)
			                return Detail(authToken: nil, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let token: Secret = __safeDI_token()
			        self.init(token: token)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_CBF29CE484222325 {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                let reader = Reader(token: nil)
			                return Detail(authToken: nil, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(token: nil)
			                    return Detail(authToken: nil, reader: reader)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesFulfillingProperty_whenReaderBeneathSeamsOwnAliasReceivesFulfillingPropertyInstead(holder: Holder) async throws {
		// The first remedy beneath the seam type's own alias.
		let fixture = Self.fixture(rootHolds: holder.declarations, screen: [Self.alias, "@Instantiated let reader: Reader"], left: nil, detail: nil, reader: ["@Received(onlyIfAvailable: true) let token: Secret?"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
				        let authToken: Secret? = token
				        #sourceLocation()
				        let reader = Reader(token: token)
				        self.init(authToken: authToken, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
				        let authToken: Secret? = token
				        #sourceLocation()
				        let reader = Reader(token: token)
				        self.init(authToken: authToken, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
				        let authToken: Secret? = token
				        #sourceLocation()
				        let reader = Reader(token: token)
				        self.init(authToken: authToken, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				            let reader = Reader(token: nil)
				            return Screen(authToken: nil, reader: reader)
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
				            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 8)
				            let authToken: Secret? = token
				            #sourceLocation()
				            let reader = Reader(token: token)
				            return Screen(authToken: authToken, reader: reader)
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
				            // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				            let reader = Reader(token: nil)
				            return Screen(authToken: authToken, reader: reader)
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

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsBothAliasesFromParameter_whenSecondAliasAliasesFulfillingPropertyInstead(holder: Holder) async throws {
		// The remedy for an alias of an uncreated alias: `bearer` aliases `token` only if available.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias, "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let bearer: Secret?"], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 9)
				                let bearer: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken, bearer: bearer)
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
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 9)
				                let bearer: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken, bearer: bearer)
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
			],
			.authToken: [
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token
				                #sourceLocation()
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 9)
				                let bearer: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken, bearer: bearer)
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
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
		let expectedInlineOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    // Did not create `bearer: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil, bearer: nil)
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 9)
				                    let bearer: Secret? = token
				                    #sourceLocation()
				                    return Detail(authToken: authToken, bearer: bearer)
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
				                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
				                    // Did not create `bearer: Secret?` because `token: Secret` is unavailable.
				                    return Detail(authToken: nil, bearer: nil)
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

	// MARK: The divergences the Manual states

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesCallersOptionalValueToAliasesDeclaringType_whereInlineDoesNotCreateTheAlias() async throws {
		// The Manual's first divergence: a caller holding only `token: Secret?` passes it, and the alias the seam binds from it
		// reaches `Detail`, where inline creates no alias of `token: Secret` and passes `nil`.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", detail: [Self.alias], reader: nil, otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                _ = Screen.__safeDI_Screen_D306FBD537400E08.self
			                return Screen(token: token)
			            }
			            let screen: Screen = __safeDI_screen()
			            return Host(token: token, screen: screen)
			        }
			        let hostBuilder = Instantiator<Host> {
			            __safeDI_hostBuilder(token: $0)
			        }
			        self.init(hostBuilder: hostBuilder)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init(token: Secret? = nil) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                let authToken: Secret? = token
			                #sourceLocation()
			                return Detail(authToken: authToken)
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
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                func __safeDI_left() -> Left {
			                    func __safeDI_detail() -> Detail {
			                        // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                        return Detail(authToken: nil)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(detail: detail)
			                }
			                let left: Left = __safeDI_left()
			                return Screen(left: left)
			            }
			            let screen: Screen = __safeDI_screen()
			            return Host(token: token, screen: screen)
			        }
			        let hostBuilder = Instantiator<Host> {
			            __safeDI_hostBuilder(token: $0)
			        }
			        self.init(hostBuilder: hostBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesSeamItsOwnBinding_whereInlinePassesCallersEarlierSiblingForSeamsOwnAlias() async throws {
		// The Manual's second divergence: inline, `Root`'s earlier `authToken` is passed to the seam in place of its own
		// uncreated alias; the seam's own alias is bound from its parameter, which the caller passes `nil`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: [Self.alias, "@Instantiated let detail: Detail"], left: nil, detail: [], reader: nil)
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
			    public convenience init(token: Secret? = nil) {
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let authToken: Secret? = token
			        #sourceLocation()
			        let detail = Detail()
			        self.init(authToken: authToken, detail: detail)
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
			            // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			            let detail = Detail()
			            return Screen(authToken: authToken, detail: detail)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
	}

	// MARK: Determinism

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOneUncreatedAliasError_whenReaderIsBuiltOnTwoPaths() async throws {
		// `Detail`, and `Reader` beneath it, are built under `Left` and `Right`: `Reader` is reported once.
		let fixture = Self.fixture(screen: ["@Instantiated let left: Left", "@Instantiated let right: Right"], otherTypes: [seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"])])
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
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            func __safeDI_right() -> Right {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `authToken: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(authToken: nil)
			                    return Detail(authToken: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Right(detail: detail)
			            }
			            let right: Right = __safeDI_right()
			            return Screen(left: left, right: right)
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
	mutating func generate_namesFirstDeclaredPath_whenReaderIsBuiltBeneathTwoAliasesUnderAnyTypeNames() async {
		// `Reader` is built beneath an uncreated alias on each of two paths, `Screen`'s first-declared child's first: the
		// error names the path met first in declaration order, whatever the six types are named.
		let names = ["Bravo", "Echo", "Alpha", "Foxtrot", "Delta", "Charlie"]
		for rotation in 0..<12 {
			let rotated = Array(names[(rotation % 6)...] + names[..<(rotation % 6)])
			let permutation = rotation < 6 ? rotated : rotated.reversed()
			let (screen, first, second, firstDetail, secondDetail, reader) = (permutation[0], permutation[1], permutation[2], permutation[3], permutation[4], permutation[5])
			let fixture = [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: \(screen)"]),
				seamFixtureType(named: screen, isSeam: true, declarations: ["@Instantiated let first: \(first)", "@Instantiated let second: \(second)"]),
				seamFixtureType(named: first, declarations: ["@Instantiated let detail: \(firstDetail)"]),
				seamFixtureType(named: second, declarations: ["@Instantiated let detail: \(secondDetail)"]),
				seamFixtureType(named: firstDetail, declarations: [Self.alias, "@Instantiated let reader: \(reader)"]),
				seamFixtureType(named: secondDetail, declarations: [Self.alias, "@Instantiated let reader: \(reader)"]),
				seamFixtureType(named: reader, declarations: [Self.receive]),
				seamFixtureType(named: "Secret", declarations: []),
			]
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["\(reader).swift"]):7:5: error: SafeDI cannot generate the dependency tree of `\(screen)`: `\(reader)` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `\(firstDetail)` declares, which is not created where `token: Secret` is unavailable; built inline, `\(reader)` would then read whatever property named `authToken` is declared above `\(firstDetail)`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `\(reader)` instead, or make the alias required.
				"""
			}) {
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
	}

	// MARK: The type-spelling axis

	@Test(arguments: Spelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorSpellingRemedyType_whenAliasPropertyIsSpelledAnyWay(spelling: Spelling) async {
		// The remedy spells the fulfilling property's optional form through its type description: `(any Auth)?`,
		// `(() -> Void)?`, `Feature.Secret?`, `SecretID?`, `Secret?` – not `Secret??` – for `ofType: Secret?.self`, and
		// `(@Sendable () -> Void)?`, `(() -> Void)?` for the optional closure, `(a: Int, b: String)?`, and `Box<Secret>?`.
		await assertThrowsError(diagnostics: { fixtures in
			let expected: [Spelling: String] = [
				.existential: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (any Auth)?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: any Auth` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: (any Auth)?` on `Reader` instead, or make the alias required.
				""",
				.closure: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (() -> Void)?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: () -> Void` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: (() -> Void)?` on `Reader` instead, or make the alias required.
				""",
				.nested: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Feature.Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Feature.Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Feature.Secret?` on `Reader` instead, or make the alias required.
				""",
				.nonFunctionTypealias: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: SecretID?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: SecretID` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: SecretID?` on `Reader` instead, or make the alias required.
				""",
				.optionalOfType: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
				""",
				.sendableClosure: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (@Sendable () -> Void)?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: @Sendable () -> Void` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: (@Sendable () -> Void)?` on `Reader` instead, or make the alias required.
				""",
				.optionalClosure: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (() -> Void)?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: (() -> Void)?` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: (() -> Void)?` on `Reader` instead, or make the alias required.
				""",
				.tuple: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: (a: Int, b: String)?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: (a: Int, b: String)` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: (a: Int, b: String)?` on `Reader` instead, or make the alias required.
				""",
				.generic: """
				\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Box<Secret>?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Box<Secret>` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Box<Secret>?` on `Reader` instead, or make the alias required.
				""",
			]
			return expected[spelling] ?? ""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: spelling.fixture(detail: [spelling.alias, "@Instantiated let reader: Reader"], reader: [spelling.receive]), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: Spelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasError_whenAliasOfAliasIsSpelledAnyWay(spelling: Spelling) async {
		await assertThrowsError(diagnostics: { fixtures in
			let expected: [Spelling: String] = [
				.existential: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: (any Auth)?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: any Auth` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.closure: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: (() -> Void)?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: () -> Void` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.nested: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Feature.Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Feature.Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.nonFunctionTypealias: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: SecretID?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: SecretID` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.optionalOfType: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Secret?` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.sendableClosure: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: (@Sendable () -> Void)?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: @Sendable () -> Void` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.optionalClosure: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: (() -> Void)?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: (() -> Void)?` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.tuple: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: (a: Int, b: String)?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: (a: Int, b: String)` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
				.generic: """
				\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Box<Secret>?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Box<Secret>` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
				""",
			]
			return expected[spelling] ?? ""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: spelling.fixture(detail: [spelling.alias, spelling.bearer], reader: nil), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: Spelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSamePropertyError_whenSiblingAliasPropertyIsSpelledAnyWay(spelling: Spelling) async {
		await assertThrowsError(diagnostics: { fixtures in
			let expected: [Spelling: String] = [
				.existential: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: (any Auth)?` that `Detail` declares is not created where `token: any Auth` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: (any Auth)?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.closure: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: (() -> Void)?` that `Detail` declares is not created where `token: () -> Void` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: (() -> Void)?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.nested: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Feature.Secret?` that `Detail` declares is not created where `token: Feature.Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Feature.Secret?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.nonFunctionTypealias: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: SecretID?` that `Detail` declares is not created where `token: SecretID` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: SecretID?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.optionalOfType: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret?` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.sendableClosure: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: (@Sendable () -> Void)?` that `Detail` declares is not created where `token: @Sendable () -> Void` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: (@Sendable () -> Void)?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.optionalClosure: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: (() -> Void)?` that `Detail` declares is not created where `token: (() -> Void)?` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: (() -> Void)?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.tuple: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: (a: Int, b: String)?` that `Detail` declares is not created where `token: (a: Int, b: String)` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: (a: Int, b: String)?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
				.generic: """
				\(fixtures["Detail.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Box<Secret>?` that `Detail` declares is not created where `token: Box<Secret>` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Box<Secret>?`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
				""",
			]
			return expected[spelling] ?? ""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: spelling.fixture(left: [spelling.siblingAlias, "@Instantiated let detail: Detail"], detail: [spelling.alias], reader: nil), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: Spelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenAliasIsSpelledAnyWay(spelling: Spelling) async throws {
		let fixture = spelling.fixture(detail: [spelling.alias], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Spelling: [String: String]] = [
			.existential: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_2B72C0D922CD6E2A.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: (any Auth)? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (any Auth)? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_2B72C0D922CD6E2A {}
				}
				""",
			],
			.closure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D0C1971522FE69A9.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: (() -> Void)? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (() -> Void)? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D0C1971522FE69A9 {}
				}
				""",
			],
			.nested: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_4D4CEA4E424D94E0.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Feature.Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Feature.Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_4D4CEA4E424D94E0 {}
				}
				""",
			],
			.nonFunctionTypealias: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_DE48F91F10B71AD3.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: SecretID? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: SecretID? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_DE48F91F10B71AD3 {}
				}
				""",
			],
			.optionalOfType: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
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
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			.sendableClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_2A974997353A33F7.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: (@Sendable () -> Void)? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (@Sendable () -> Void)? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_2A974997353A33F7 {}
				}
				""",
			],
			.optionalClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D0C1971522FE69A9.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: (() -> Void)? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (() -> Void)? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D0C1971522FE69A9 {}
				}
				""",
			],
			.tuple: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_CF6EE32C08F6AC90.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: (a: Int, b: String)? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (a: Int, b: String)? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_CF6EE32C08F6AC90 {}
				}
				""",
			],
			.generic: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_4A6C7C62A36072DB.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Box<Secret>? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Box<Secret>? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_4A6C7C62A36072DB {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[spelling])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedInlineOutput: [Spelling: [String: String]] = [
			.existential: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: (any Auth)?` because `token: any Auth` is unavailable.
				                    return Detail(authToken: nil)
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
			.closure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: (() -> Void)?` because `token: () -> Void` is unavailable.
				                    return Detail(authToken: nil)
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
			.nested: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Feature.Secret?` because `token: Feature.Secret` is unavailable.
				                    return Detail(authToken: nil)
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
			.nonFunctionTypealias: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: SecretID?` because `token: SecretID` is unavailable.
				                    return Detail(authToken: nil)
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
			.optionalOfType: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Secret?` because `token: Secret?` is unavailable.
				                    return Detail(authToken: nil)
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
			.sendableClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: (@Sendable () -> Void)?` because `token: @Sendable () -> Void` is unavailable.
				                    return Detail(authToken: nil)
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
			.optionalClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: (() -> Void)?` because `token: (() -> Void)?` is unavailable.
				                    return Detail(authToken: nil)
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
			.tuple: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: (a: Int, b: String)?` because `token: (a: Int, b: String)` is unavailable.
				                    return Detail(authToken: nil)
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
			.generic: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `authToken: Box<Secret>?` because `token: Box<Secret>` is unavailable.
				                    return Detail(authToken: nil)
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
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[spelling])
	}

	// MARK: Across modules

	@Test(arguments: MultiModuleIntegration.allCases, Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorInSeamsModule_whateverAnotherModuleHolds(integration: MultiModuleIntegration, holder: Holder) async {
		let files = Self.fixture(rootHolds: holder.declarations)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.twoModules(files), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorInSeamsModule_whenAliasesDeclaringTypeIsInModuleItDependsOn(integration: MultiModuleIntegration) async {
		let files = Self.fixture(rootHolds: Holder.authToken.declarations)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Reader.swift", in: "Core", fixtures, integration)):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `authToken: Secret?` beneath the `onlyIfAvailable` alias `authToken` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `authToken` is declared above `Detail`, or `nil`, depending on what encloses it. Receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.threeModules(files), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUncreatedAliasErrorInSeamsModule_whenAliasesDeclaringTypeAliasesItAndAnotherModuleHoldsItsLabel(integration: MultiModuleIntegration) async {
		let files = Self.fixture(rootHolds: Holder.authToken.declarations, detail: [Self.alias, Self.bearer], reader: nil)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `authToken: Secret?` as `bearer`, and `authToken` is an `onlyIfAvailable` alias that is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `authToken` is declared above `Detail`, or not at all, depending on what encloses it. Alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `authToken` required.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.twoModules(files), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSamePropertyErrorInSeamsModule_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasProperty(integration: MultiModuleIntegration) async {
		let files = Self.fixture(rootHolds: Holder.token.declarations, left: ["@Instantiated let authToken: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: the `onlyIfAvailable` alias `authToken: Secret?` that `Detail` declares is not created where `token: Secret` is unavailable, and `Left`, which builds `Detail`, also declares `authToken: Secret`; built inline, `Detail` is then passed `Left`'s `authToken` when `Left` builds it first. Give the alias a label `Left` does not declare, or make the alias required.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.twoModules(files), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameterAcrossModules_whenOnlyAliasesDeclaringTypeReadsIt(integration: MultiModuleIntegration, holder: Holder) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoModules(Self.fixture(rootHolds: holder.declarations, detail: [Self.alias], reader: nil)),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let detailPath = try #require(output.modules["Feature"]).fixtures.compilerPath(of: "Detail.swift")
		let expectedFeatureFiles: [String: [String: String]] = [
			"moduleInfo-authToken": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			"moduleInfo-nothing": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			"moduleInfo-token": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			"swiftPackagePlugin-authToken": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			"swiftPackagePlugin-nothing": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			"swiftPackagePlugin-token": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles["\(integration)-\(holder)"])
		let expectedAppFiles: [String: [String: String]] = [
			"moduleInfo-authToken": [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

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
			],
			"moduleInfo-nothing": [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
			"moduleInfo-token": [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
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
			],
			"swiftPackagePlugin-authToken": [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
			],
			"swiftPackagePlugin-nothing": [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
			"swiftPackagePlugin-token": [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles["\(integration)-\(holder)"])
		if compileVerificationIsEnabled {
			#expect(try #require(output.compilation).modules.map(\.exitCode) == [0, 0])
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameterAcrossModules_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasLabelAsAnotherType(integration: MultiModuleIntegration, holder: Holder) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoModules(Self.fixture(rootHolds: holder.declarations, left: ["@Instantiated let authToken: Label", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, otherTypes: [seamFixtureType(named: "Label", declarations: [])])),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let detailPath = try #require(output.modules["Feature"]).fixtures.compilerPath(of: "Detail.swift")
		let expectedFeatureFiles: [String: [String: String]] = [
			"moduleInfo-authToken": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			"moduleInfo-nothing": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			"moduleInfo-token": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			"swiftPackagePlugin-authToken": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			"swiftPackagePlugin-nothing": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
			"swiftPackagePlugin-token": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(authToken: authToken, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_D306FBD537400E08 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles["\(integration)-\(holder)"])
		let expectedAppFiles: [String: [String: String]] = [
			"moduleInfo-authToken": [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

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
			],
			"moduleInfo-nothing": [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
			"moduleInfo-token": [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
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
			],
			"swiftPackagePlugin-authToken": [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
			],
			"swiftPackagePlugin-nothing": [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
			"swiftPackagePlugin-token": [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles["\(integration)-\(holder)"])
		if compileVerificationIsEnabled {
			#expect(try #require(output.compilation).modules.map(\.exitCode) == [0, 0])
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameterAcrossThreeModules_whenAliasesDeclaringTypeIsInModuleItDependsOn(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.threeModules(Self.fixture(rootHolds: Holder.token.declarations, detail: [Self.alias], reader: nil)),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let detailPath = try #require(output.modules["Core"]).fixtures.compilerPath(of: "Detail.swift")
		let expectedFeatureFiles: [String: [String: String]] = [
			"moduleInfo": [
				"Feature.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
			"swiftPackagePlugin": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Screen {
				    public convenience init(token: Secret? = nil) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token
				                #sourceLocation()
				                return Detail(authToken: authToken)
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
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles["\(integration)"])
		let expectedAppFiles: [String: [String: String]] = [
			"moduleInfo": [
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
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
			],
			"swiftPackagePlugin": [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_D306FBD537400E08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles["\(integration)"])
		if compileVerificationIsEnabled {
			#expect(try #require(output.compilation).modules.map(\.exitCode) == [0, 0, 0])
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What the caller, `Root`, holds above the seam.
	enum Holder: String, CaseIterable, CustomTestStringConvertible {
		case nothing
		case token
		case authToken
		case other

		static let allCases: [Holder] = [.nothing, .token, .authToken]

		var declarations: [String] {
			switch self {
			case .nothing:
				[]
			case .token:
				["@Instantiated let token: Secret"]
			case .authToken:
				["@Instantiated let authToken: Secret"]
			case .other:
				["@Instantiated let other: Secret"]
			}
		}

		var testDescription: String {
			rawValue
		}
	}

	/// A spelling of the alias's fulfilling property: the pass-through `token`, which the seam takes as `T? = nil`.
	enum Spelling: String, CaseIterable, CustomTestStringConvertible {
		/// `token: any Auth`.
		case existential
		/// `token: () -> Void`.
		case closure
		/// `token: Feature.Secret`.
		case nested
		/// `token: SecretID`, a typealias of `String`.
		case nonFunctionTypealias
		/// `token: Secret?`, aliased with `ofType: Secret?.self`.
		case optionalOfType
		/// `token: @Sendable () -> Void`.
		case sendableClosure
		/// `token: (() -> Void)?`, aliased with `ofType: (() -> Void)?.self`.
		case optionalClosure
		/// `token: (a: Int, b: String)`.
		case tuple
		/// `token: Box<Secret>`.
		case generic

		/// The fulfilling property's type as `ofType:` spells it.
		var fulfillingType: String {
			switch self {
			case .existential:
				"(any Auth)"
			case .closure:
				"(() -> Void)"
			case .nested:
				"Feature.Secret"
			case .nonFunctionTypealias:
				"SecretID"
			case .optionalOfType:
				"Secret?"
			case .sendableClosure:
				"(@Sendable () -> Void)"
			case .optionalClosure:
				"(() -> Void)?"
			case .tuple:
				"(a: Int, b: String)"
			case .generic:
				"Box<Secret>"
			}
		}

		/// The alias's own type.
		var aliasType: String {
			switch self {
			case .existential:
				"(any Auth)?"
			case .closure:
				"(() -> Void)?"
			case .nested:
				"Feature.Secret?"
			case .nonFunctionTypealias:
				"SecretID?"
			case .optionalOfType:
				"Secret?"
			case .sendableClosure:
				"(@Sendable () -> Void)?"
			case .optionalClosure:
				"(() -> Void)?"
			case .tuple:
				"(a: Int, b: String)?"
			case .generic:
				"Box<Secret>?"
			}
		}

		/// An alias on a type beneath the seam that keeps the label of the pass-through `authToken`, which may be `nil`, and
		/// retypes it to `Any?`, which every spelling converts to.
		var labelKeepingAlias: String {
			"@Received(fulfilledByDependencyNamed: \"authToken\", ofType: \(aliasType).self, onlyIfAvailable: true) let authToken: Any?"
		}

		/// A receive of the label-keeping alias's property.
		var anyReceive: String {
			"@Received(onlyIfAvailable: true) let authToken: Any?"
		}

		var alias: String {
			"@Received(fulfilledByDependencyNamed: \"token\", ofType: \(fulfillingType).self, onlyIfAvailable: true) let authToken: \(aliasType)"
		}

		var receive: String {
			"@Received(onlyIfAvailable: true) let authToken: \(aliasType)"
		}

		var bearer: String {
			"@Received(fulfilledByDependencyNamed: \"authToken\", ofType: \(aliasType).self, onlyIfAvailable: true) let bearer: \(aliasType)"
		}

		/// An alias of the alias's property on the type that builds the alias's declaring type, of another pass-through.
		var siblingAlias: String {
			"@Received(fulfilledByDependencyNamed: \"other\", ofType: \(fulfillingType).self, onlyIfAvailable: true) let authToken: \(aliasType)"
		}

		var testDescription: String {
			rawValue
		}

		/// `SafeDIToolSeamUncreatedAliasTests.fixture` with this spelling's types declared.
		func fixture(left: [String] = ["@Instantiated let detail: Detail"], detail: [String]?, reader: [String]?, otherTypes: [String] = []) -> [String] {
			let declarations = switch self {
			case .existential:
				"public protocol Auth {}"
			case .closure, .optionalOfType, .sendableClosure, .optionalClosure, .tuple:
				""
			case .nested:
				"public enum Feature {\n    public struct Secret {\n        public init() {}\n    }\n}"
			case .nonFunctionTypealias:
				"public typealias SecretID = String"
			case .generic:
				"public final class Box<Value> {\n    public init(_ value: Value) {\n        self.value = value\n    }\n\n    public let value: Value\n}"
			}
			return SafeDIToolSeamUncreatedAliasTests.fixture(left: left, detail: detail, reader: reader, otherTypes: (declarations.isEmpty ? [] : [declarations]) + otherTypes)
		}
	}

	private static let alias = "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?"
	private static let receive = "@Received(onlyIfAvailable: true) let authToken: Secret?"
	private static let bearer = "@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"

	/// `Root` holds `rootHolds` and builds the seam `Screen` with `rootBuilds`; `Screen` declares `screen` – by default it
	/// instantiates `Left`, which instantiates `Detail`, which declares the only-if-available alias `authToken` of the
	/// pass-through `token` and instantiates `Reader`, which receives `authToken` only if available. A type whose
	/// declarations are `nil` is left out; `Secret` declares `secret` and conforms to `secretConformances`, and
	/// `otherTypes` follow. With `sendable`, every type conforms to `Sendable`.
	static func fixture(
		rootHolds: [String] = [],
		rootBuilds: String = "@Instantiated let screen: Screen",
		screen: [String] = ["@Instantiated let left: Left"],
		left: [String]? = ["@Instantiated let detail: Detail"],
		detail: [String]? = [alias, "@Instantiated let reader: Reader"],
		reader: [String]? = [receive],
		secret: [String] = [],
		secretConformances: String = "",
		otherTypes: [String] = [],
		sendable: Bool = false,
	) -> [String] {
		let conformances = sendable ? ", Sendable" : ""
		// Final classes, so that a type can hold one that holds it.
		let types: [String?] = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootHolds + [rootBuilds], conformances: conformances),
			seamFixtureType(named: "Screen", isSeam: true, isFinalClass: true, declarations: screen, conformances: conformances),
			left.map { seamFixtureType(named: "Left", isFinalClass: true, declarations: $0, conformances: conformances) },
			detail.map { seamFixtureType(named: "Detail", isFinalClass: true, declarations: $0, conformances: conformances) },
			reader.map { seamFixtureType(named: "Reader", isFinalClass: true, declarations: $0, conformances: conformances) },
			seamFixtureType(named: "Secret", isFinalClass: true, declarations: secret, conformances: secretConformances + conformances),
		]
		return types.compactMap(\.self) + otherTypes
	}

	/// `files`, `Root`'s first, as `Feature`, which declares the seam, and `App`, which declares `Root`.
	static func twoModules(_ files: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Array(files.dropFirst())),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Feature\n\n" + files[0]], dependencies: ["Feature"]),
		]
	}

	/// `files` as `twoModules`, with `Detail`, `Reader`, and `Secret` in `Core`, which `Feature` depends on.
	static func threeModules(_ files: [String]) -> [ModuleFixture] {
		let coreTypes = files.filter { $0.contains("class Detail:") || $0.contains("class Reader:") || $0.contains("class Secret:") }
		let featureTypes = files.dropFirst().filter { !coreTypes.contains($0) }
		return [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: coreTypes),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureTypes.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Core\nimport Feature\n\n" + files[0]], dependencies: ["Core", "Feature"]),
		]
	}

	/// The path a diagnostic names `file` of `module` by under `integration`.
	static func path(of file: String, in module: String, _ fixtures: [String: FixturePaths], _ integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[module]![file]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[module]!.compilerPath(of: file)).path
		}
	}
}
