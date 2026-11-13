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

/// An `onlyIfAvailable` alias inside a seam's tree whose fulfilling property may be unavailable – a parameter of the
/// generated initializer that may be `nil`, a property still being built, or one generated later – is a `let` of its
/// label, bound from the parameter, or `nil`, exactly as inline binds it from the caller's nearest declaration of the
/// fulfilling property's label; its declaring type and every type beneath it read that `let`: a receive of the alias's
/// property, an alias of it, and a type beneath a declaration of the alias's property on the type that builds the
/// declaring type. Each cell sits beside the inline build of the same graph, and most compare the values both build.
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

	// MARK: A receive of an alias of a parameter

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReaderAliasBinding_whenReaderBeneathAliasOfPassThroughReceivesAliasProperty(holder: Holder) async throws {
		// `Detail`'s alias of the pass-through `token` is bound from it, `nil` where the caller holds no `token`, and `Reader`
		// reads the binding, in the seam as inline.
		let fixture = Self.fixture(rootHolds: holder.declarations)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                    let authToken: Secret? = nil
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
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReaderAliasBinding_whenSeamReceivesAliasLabelAsAnotherType() async throws {
		// The seam's own `authToken: Label?` is a declaration above the alias, which `Reader` beneath the alias does not read.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Received(onlyIfAvailable: true) let authToken: Label?", "@Instantiated let left: Left"], otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: [])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_665E9B76863CB227.self
			            return Screen(__safeDI_authToken: nil, __safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_authToken authToken: Label?, __safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(authToken: authToken, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_665E9B76863CB227 {}
			}
			""",
		])
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
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// Kept by hand: the seam corpus draws this shape in 2 graphs and reports its error in none (census at 3b12802a);
	// delete when the per-shape pin of graphs rejected with it reaches 3.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReaderSeamsOwnAliasBinding_whenReaderBeneathItReceivesAliasProperty() async throws {
		// The seam type's own alias of the pass-through `token` is bound from it, and `Reader` beneath reads the binding.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: [Self.alias, "@Instantiated let reader: Reader"], left: nil, detail: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let authToken: Secret? = token.instance
			        #sourceLocation()
			        let reader = Reader(authToken: authToken)
			        self.init(authToken: authToken, reader: reader)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 8)
			            let authToken: Secret? = nil
			            #sourceLocation()
			            let reader = Reader(authToken: authToken)
			            return Screen(authToken: authToken, reader: reader)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
		])
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: A receive of an alias beneath another declaration of its label

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReaderAliasBinding_whenTypeBuildingAliasesDeclaringTypeIsForwardedAliasProperty() async throws {
		// `Left` is forwarded `authToken: Secret`, and `Reader` beneath `Detail` reads `Detail`'s alias.
		let fixture = Self.fixture(screen: ["@Instantiated let leftBuilder: Instantiator<Left>"], left: ["@Forwarded let authToken: Secret", "@Instantiated let detail: Detail"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_leftBuilder(authToken: Secret) -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
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
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_leftBuilder(authToken: Secret) -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReaderAliasBinding_whenSeamRequiresWrapperOfAliasLabel() async throws {
		// The seam's own required `authToken: LazilyInstantiated<Secret>` is a declaration above the alias, which `Reader`
		// beneath the alias does not read.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: LazilyInstantiated<Secret>"], screen: ["@Received let authToken: LazilyInstantiated<Secret>", "@Instantiated let left: Left"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            Secret()
			        }
			        let authToken = LazilyInstantiated<Secret>(__safeDI_authToken)
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_2AD0C60B502D5EF5.self
			            return Screen(__safeDI_authToken: authToken, __safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_authToken authToken: LazilyInstantiated<Secret>, __safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(authToken: authToken, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_2AD0C60B502D5EF5 {}
			}
			""",
		])
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
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReaderAliasBinding_whenSeamRequiresAliasLabelAsAnotherType() async throws {
		// The seam's own required `authToken: Label` is a declaration above the alias, which `Reader` beneath the alias does
		// not read.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Label"], screen: ["@Received let authToken: Label", "@Instantiated let left: Left"], otherTypes: [seamFixtureType(named: "Label", isFinalClass: true, declarations: [])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Label()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_E4E24F2063DC5C68.self
			            return Screen(__safeDI_authToken: authToken, __safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_authToken authToken: Label, __safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(authToken: authToken, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_E4E24F2063DC5C68 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Label()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: A receive of an alias that is nil where it is declared

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasToNil_whenAliasFulfillingPropertyIsBeingBuilt() async throws {
		// `Detail` is built inside `token`, so its alias of `token` is `nil` there, and `Reader` reads that `nil`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret"], left: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
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
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
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
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
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
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasToNil_whenAliasFulfillingPropertyIsGeneratedLater() async throws {
		// `Secret` receives `a` only if available, so `token` is generated after `A`, which builds `Detail`: the alias is `nil`,
		// and `Reader` reads it.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret", "@Instantiated let a: A"], left: nil, secret: ["@Received(onlyIfAvailable: true) let a: A?"], otherTypes: [seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret(a: nil)
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
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return A(detail: detail)
			        }
			        let a: A = __safeDI_a()
			        let token = Secret(a: a)
			        self.init(token: token, a: a)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_CBF29CE484222325 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret(a: nil)
			        func __safeDI_screen() -> Screen {
			            func __safeDI_a() -> A {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromNearestDeclaration_whenAliasFulfillingPropertyIsBuiltBesideSeamsInstantiatedAliasProperty() async throws {
		// `Screen` instantiates `authToken` and `token`, each building `Detail`: its alias is `nil` inside `token`, which is
		// still being built, and bound from `token` inside `authToken`, and `Reader` reads it.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let authToken: Secret", "@Instantiated let token: Secret"], left: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
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
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			            return Secret(detailBuilder: detailBuilder)
			        }
			        let token: Secret = __safeDI_token()
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
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
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
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
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: An alias of an alias of a parameter

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasOfAlias_whenTypeBeneathAliasesDeclaringTypeAliasesIt() async throws {
		// `Reader`, beneath `Detail`, declares `bearer` of `Detail`'s alias, bound from its binding.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], reader: [Self.bearer])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                func __safeDI_reader() -> Reader {
			                    #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
			                    let bearer: Secret? = authToken
			                    #sourceLocation()
			                    return Reader(bearer: bearer)
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
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
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
			                        let bearer: Secret? = authToken
			                        #sourceLocation()
			                        return Reader(bearer: bearer)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: A declaration of the alias property beside the alias declaring type

	@Test(arguments: [.nothing, .token] as [Holder])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesDeclaringTypeItsAlias_whenTypeBuildingAliasesDeclaringTypeInstantiatesAliasProperty(holder: Holder) async throws {
		// `Left` instantiates `authToken`, and `Detail` is passed its own alias of the pass-through `token`.
		let fixture = Self.fixture(rootHolds: holder.declarations, left: ["@Instantiated let authToken: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Secret()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = nil
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsBothAliases_whenTypeBuildingAliasesDeclaringTypeAliasesPropertyBeingBuilt() async throws {
		// `Left`, built inside `other`, aliases `other` as `authToken`, `nil` there, beside `Detail`'s alias of the
		// pass-through `token`.
		let fixture = Self.fixture(screen: ["@Instantiated let other: Secret"], left: ["@Received(fulfilledByDependencyNamed: \"other\", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, secret: ["@Instantiated let left: Left"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_other() -> Secret {
			            func __safeDI_left() -> Left {
			                #sourceLocation(file: "\(output.fixtures["Left.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                    let authToken: Secret? = token.instance
			                    #sourceLocation()
			                    return Detail(authToken: authToken)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Secret(left: left)
			        }
			        let other: Secret = __safeDI_other()
			        self.init(other: other)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_other() -> Secret {
			                func __safeDI_left() -> Left {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Left.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    func __safeDI_detail() -> Detail {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
			                        let authToken: Secret? = nil
			                        #sourceLocation()
			                        return Detail(authToken: authToken)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(authToken: authToken, detail: detail)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasToNil_whenAliasOfPropertyBeingBuiltIsBuiltBesideAliasProperty() async throws {
		// `Detail`'s alias of `token`, built inside `token`, is `nil`, while `Left` instantiates `authToken: Secret` beside it.
		let fixture = Self.fixture(screen: ["@Instantiated let token: Secret"], left: ["@Instantiated let authToken: Secret", "@Instantiated let detail: Detail"], detail: [Self.alias], reader: nil, secret: ["@Instantiated let leftBuilder: Instantiator<Left>"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
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
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_leftBuilder() -> Left {
			                func __safeDI_authToken() -> Secret {
			                    let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			                    return Secret(leftBuilder: leftBuilder)
			                }
			                let authToken: Secret = __safeDI_authToken()
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    return Detail(authToken: authToken)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(authToken: authToken, detail: detail)
			            }
			            let leftBuilder = Instantiator<Left>(__safeDI_leftBuilder)
			            return Secret(leftBuilder: leftBuilder)
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
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
			                        let authToken: Secret? = nil
			                        #sourceLocation()
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesDeclaringTypeItsAlias_whenAliasPropertyIsExistentialAndBuilderInstantiatesItsUnwrappedForm() async throws {
		// `authToken: (any Auth)?` and `Left`'s `authToken: Auth` are one property's two forms, whatever the `any`, and
		// `Detail` is passed its own alias.
		let fixture = Self.fixture(left: ["@Instantiated(fulfilledByType: \"Secret\") let authToken: Auth", "@Instantiated let detail: Detail"], detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let authToken: (any Auth)?"], reader: nil, secretConformances: ", Auth", otherTypes: ["public protocol Auth {}"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            let authToken: Auth = Secret()
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                let authToken: (any Auth)? = token.instance
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
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                let authToken: Auth = Secret()
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
			                    let authToken: (any Auth)? = nil
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
			        self.init(screen: screen)
			    }
			}
			""",
		])
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: An alias only its declaring type reads

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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = nil
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_leftBuilder(authToken: Secret) -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_leftBuilder(authToken: Secret) -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_leftBuilder(authToken: Secret) -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = nil
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
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[holder])
	}

	// MARK: An alias whose fulfilling property is always available

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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token_)
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
				        let right = Right(token: token.instance)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token_)
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
				        let right = Right(token: token.instance)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token_)
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
				        let right = Right(token: token.instance)
				        self.init(left: left, right: right)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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

	// Kept by hand: the seam corpus judges one graph of this shape by value (census at 3b12802a); delete when the
	// per-shape accepted pin reaches 3.
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
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
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
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
			            return Screen(__safeDI_token: token)
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
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token token: Secret) {
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
			    /// Code you write and code SafeDI generates can both call this initializer.
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
			            _ = Screen.__safeDI_Screen_55AF83B7D12DE285.self
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret) {
			        let token = LazilyInstantiated<Secret>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret = token.instance
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
			    public enum __safeDI_Screen_55AF83B7D12DE285 {}
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
			            _ = Screen.__safeDI_Screen_55AF83B7D12DE285.self
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret) {
			        let token = LazilyInstantiated<Secret>(__safeDI_token)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let authToken: Secret = token.instance
			        #sourceLocation()
			        let reader = Reader(authToken: authToken)
			        self.init(authToken: authToken, reader: reader)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_55AF83B7D12DE285 {}
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

	// Kept by hand: the seam corpus judges one graph of this shape by value (census at 3b12802a); delete when the
	// per-shape accepted pin reaches 3.
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
			            _ = Screen.__safeDI_Screen_55AF83B7D12DE285.self
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret) {
			        let token = LazilyInstantiated<Secret>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret = token.instance
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
			    public enum __safeDI_Screen_55AF83B7D12DE285 {}
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

	// Kept by hand: the seam corpus judges one graph of this shape by value (census at 3b12802a); delete when the
	// per-shape accepted pin reaches 3.
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
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(token: nil)
			                return Detail(authToken: authToken, reader: reader)
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
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(token: nil)
			                return Detail(authToken: authToken, reader: reader)
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
			                #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = nil
			                #sourceLocation()
			                let reader = Reader(token: nil)
			                return Detail(authToken: authToken, reader: reader)
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
			                    let reader = Reader(token: nil)
			                    return Detail(authToken: authToken, reader: reader)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
				        let authToken: Secret? = token.instance
				        #sourceLocation()
				        let reader = Reader(token: token.instance)
				        self.init(authToken: authToken, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.token: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
				        let authToken: Secret? = token.instance
				        #sourceLocation()
				        let reader = Reader(token: token.instance)
				        self.init(authToken: authToken, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.authToken: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let authToken = Secret()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(authToken: authToken, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
				        let authToken: Secret? = token.instance
				        #sourceLocation()
				        let reader = Reader(token: token.instance)
				        self.init(authToken: authToken, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
				            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 8)
				            let authToken: Secret? = nil
				            #sourceLocation()
				            let reader = Reader(token: nil)
				            return Screen(authToken: authToken, reader: reader)
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
				            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 8)
				            let authToken: Secret? = nil
				            #sourceLocation()
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
			                _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			                return Screen(__safeDI_token: token)
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
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                let authToken: Secret? = token.instance
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
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
	mutating func generate_passesSeamItsOwnBinding_asInlinePassesItsOwnAliasForSeamsOwnAlias() async throws {
		// What was the Manual's second divergence: inline, `Screen`'s own alias is the nearest declaration of `authToken`, so
		// `Screen` is passed it, `nil`, rather than `Root`'s earlier `authToken`, as the seam binds it from its parameter,
		// which the caller passes `nil`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: [Self.alias, "@Instantiated let detail: Detail"], left: nil, detail: [], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let authToken: Secret? = token.instance
			        #sourceLocation()
			        let detail = Detail()
			        self.init(authToken: authToken, detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 8)
			            let authToken: Secret? = nil
			            #sourceLocation()
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

	// MARK: Two paths

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasOnEachPath_whenReaderIsBuiltOnTwoPaths() async throws {
		// `Detail`, and `Reader` beneath it, are built under `Left` and `Right`, and each `Detail` binds its alias from the
		// pass-through.
		let fixture = Self.fixture(screen: ["@Instantiated let left: Left", "@Instantiated let right: Right"], otherTypes: [seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(__safeDI_token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        func __safeDI_right() -> Right {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Right(detail: detail)
			        }
			        let right: Right = __safeDI_right()
			        self.init(left: left, right: right)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            func __safeDI_right() -> Right {
			                func __safeDI_detail() -> Detail {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                    let authToken: Secret? = nil
			                    #sourceLocation()
			                    let reader = Reader(authToken: authToken)
			                    return Detail(authToken: authToken, reader: reader)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: The type-spelling axis

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
				            _ = Screen.__safeDI_Screen_A421EFA52D1F7B52.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> (any Auth)?) {
				        let token = LazilyInstantiated<(any Auth)?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (any Auth)? = token.instance
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
				    public enum __safeDI_Screen_A421EFA52D1F7B52 {}
				}
				""",
			],
			.closure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_E4608EA1FD1D8D43.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> (() -> Void)?) {
				        let token = LazilyInstantiated<(() -> Void)?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (() -> Void)? = token.instance
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
				    public enum __safeDI_Screen_E4608EA1FD1D8D43 {}
				}
				""",
			],
			.nested: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_C31D1966139E727C.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Feature.Secret?) {
				        let token = LazilyInstantiated<Feature.Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Feature.Secret? = token.instance
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
				    public enum __safeDI_Screen_C31D1966139E727C {}
				}
				""",
			],
			.nonFunctionTypealias: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_E0C270908D9DAC29.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> SecretID?) {
				        let token = LazilyInstantiated<SecretID?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: SecretID? = token.instance
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
				    public enum __safeDI_Screen_E0C270908D9DAC29 {}
				}
				""",
			],
			.optionalOfType: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			.sendableClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_96D7A691E84399BD.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> (@Sendable () -> Void)?) {
				        let token = LazilyInstantiated<(@Sendable () -> Void)?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (@Sendable () -> Void)? = token.instance
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
				    public enum __safeDI_Screen_96D7A691E84399BD {}
				}
				""",
			],
			.optionalClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_E4608EA1FD1D8D43.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> (() -> Void)?) {
				        let token = LazilyInstantiated<(() -> Void)?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (() -> Void)? = token.instance
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
				    public enum __safeDI_Screen_E4608EA1FD1D8D43 {}
				}
				""",
			],
			.tuple: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_FE885FD9878453AC.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> (a: Int, b: String)?) {
				        let token = LazilyInstantiated<(a: Int, b: String)?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: (a: Int, b: String)? = token.instance
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
				    public enum __safeDI_Screen_FE885FD9878453AC {}
				}
				""",
			],
			.generic: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_56DA05D767AB07F1.self
				            return Screen(__safeDI_token: nil)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Box<Secret>?) {
				        let token = LazilyInstantiated<Box<Secret>?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
				                let authToken: Box<Secret>? = token.instance
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
				    public enum __safeDI_Screen_56DA05D767AB07F1 {}
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: (any Auth)? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: (() -> Void)? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Feature.Secret? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: SecretID? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Secret? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: (@Sendable () -> Void)? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: (() -> Void)? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: (a: Int, b: String)? = nil
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
				                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
				                    let authToken: Box<Secret>? = nil
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
	mutating func generate_passesReaderAliasBindingInSeamsModule_whateverAnotherModuleHolds(integration: MultiModuleIntegration, holder: Holder) async throws {
		// The seam's module binds `Detail`'s alias from the pass-through `token`, and `Reader` reads the binding, whatever
		// the caller's module holds.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.twoModules(Self.fixture(rootHolds: holder.declarations)), integration: integration, filesToDelete: &filesToDelete)
		let detailPath = try #require(output.modules["Feature"]).fixtures.compilerPath(of: "Detail.swift")
		#expect(try #require(output.modules["Feature"]).generatedFiles == [
			integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(detailPath)", line: 8)
			                let authToken: Secret? = token.instance
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
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReaderAliasBindingInSeamsModule_whenAliasesDeclaringTypeIsInModuleItDependsOn(integration: MultiModuleIntegration) async throws {
		// `Detail` and `Reader` are declared in `Core`, which `Feature` depends on: the seam's module binds the alias as
		// it does when it declares them.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.threeModules(Self.fixture(rootHolds: Holder.authToken.declarations)), integration: integration, filesToDelete: &filesToDelete)
		let detailPath = try #require(output.modules["Core"]).fixtures.compilerPath(of: "Detail.swift")
		#expect(try #require(output.modules["Feature"]).generatedFiles == [
			integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif

			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(detailPath)", line: 8)
			                let authToken: Secret? = token.instance
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
			    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
			}
			""",
		])
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"moduleInfo-nothing": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"moduleInfo-token": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"swiftPackagePlugin-authToken": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"swiftPackagePlugin-nothing": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"swiftPackagePlugin-token": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_token: token)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles["\(integration)-\(holder)"])
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"moduleInfo-nothing": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"moduleInfo-token": [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"swiftPackagePlugin-authToken": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"swiftPackagePlugin-nothing": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"swiftPackagePlugin-token": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            let authToken = Label()
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_token: token)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_token: nil)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles["\(integration)-\(holder)"])
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
				}
				""",
			],
			"swiftPackagePlugin": [
				"Screen+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(detailPath)", line: 7)
				                let authToken: Secret? = token.instance
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
				    public enum __safeDI_Screen_8763BEDE3E51EBC4 {}
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_token: token)
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
				            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles["\(integration)"])
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

	/// A spelling of the alias's fulfilling property: the pass-through `token`, which the seam takes as `T?`, received
	/// only if available.
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

	/// `files` as `twoModules`, with `Detail`, `Reader`, `Secret`, and `Auth` in `Core`, which `Feature` depends on.
	static func threeModules(_ files: [String]) -> [ModuleFixture] {
		let coreTypes = files.filter { $0.contains("class Detail:") || $0.contains("class Reader:") || $0.contains("class Secret:") || $0.hasPrefix("public protocol Auth") }
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
