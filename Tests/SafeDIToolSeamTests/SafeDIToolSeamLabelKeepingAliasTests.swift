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

/// An alias that keeps the label it retypes: a type's own declaration of an alias's label does not count as a
/// declaration of the label the alias's fulfilling expression reads, as inline's `addAliasGenerator` already treats a
/// label-keeping alias of a lazily instantiated instance. So a label-keeping alias beneath an `onlyIfAvailable` alias
/// of a seam's parameter is bound from that alias, and `nil` where it is. Beside it: a reader inside a nested seam,
/// which the nested seam's signature carries as the alias or receive it is; a reader that requires the alias; and the
/// spellings of each. Each cell sits beside the inline build of the same graph.
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

	// MARK: A label-keeping alias of an alias of a parameter

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasFromAlias_whenItRetypesAliasAboveIt(holder: Holder) async throws {
		// `Reader`'s alias keeps the label `authToken` of `Detail`'s alias and retypes it: its fulfilling expression reads
		// `Detail`'s alias, not `Reader`'s own declaration, which is not in scope in its own initializer.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.labelKeepingAlias], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
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
				                func __safeDI_reader() -> Reader {
				                    #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
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
				                func __safeDI_reader() -> Reader {
				                    #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
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
				                func __safeDI_reader() -> Reader {
				                    #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasFromAlias_whenReaderBeneathLabelKeepingAliasOfAliasReceivesIt() async throws {
		// `Sub`'s label-keeping alias of `Detail`'s alias is bound from it, and `Reader` beneath `Sub` reads `Sub`'s binding.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let sub: Sub"], reader: [Self.existentialReceive], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
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
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsChainToNil_whenReaderBeneathLabelKeepingAliasOfAliasOfPropertyBeingBuiltReceivesIt() async throws {
		// The static form of the chain: `token` is still being built, so both aliases are `nil`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let token: Secret"], left: nil, detail: [Self.alias, "@Instantiated let sub: Sub"], reader: [Self.existentialReceive], secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
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
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
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
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsErasedLabelKeepingAliasFromAlias_whenItRetypesAliasAboveIt() async throws {
		// An erased label-keeping alias beneath `Detail`'s alias maps that alias's binding, in the seam as inline.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.erasedLabelKeepingAlias], secretConformances: ", Auth", otherTypes: [Self.authProtocol, Self.anyAuth])
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasFromNearestDeclaration_whenItIsReachedBeneathAliasAndBesideIt() async throws {
		// `Reader` is built under `Screen` directly, where `authToken` is the seam's parameter, and beneath `Detail`'s alias,
		// which it reads there.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], screen: ["@Instantiated let reader: Reader", "@Instantiated let left: Left"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.labelKeepingAlias], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_E9BA667A7B6A8A1B.self
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
			    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> Secret?, __safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken_)
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_reader() -> Reader {
			            #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
			            let authToken: (any Auth)? = authToken.instance
			            #sourceLocation()
			            return Reader(authToken: authToken)
			        }
			        let reader: Reader = __safeDI_reader()
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                func __safeDI_reader() -> Reader {
			                    #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
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
			        self.init(reader: reader, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_E9BA667A7B6A8A1B {}
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasFromAliasAbove_whenItSpellsUnwrappedFormBeneathAlias() async throws {
		// A label-keeping alias spelled `ofType: Secret.self` beneath `authToken: Secret?` reads that optional form, as an
		// `onlyIfAvailable` alias reads either form of its fulfilling property, so it is bound from `Detail`'s alias, in the seam
		// as inline.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret.self, onlyIfAvailable: true) let authToken: (any Auth)?"], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_063E11C337D62C73.self
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
			    public convenience init(__safeDI_authToken authToken: Secret?, __safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                func __safeDI_reader() -> Reader {
			                    #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
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
			        self.init(left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_063E11C337D62C73 {}
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: A label-keeping alias of a parameter that may be nil

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasFromParameter_whenReaderBeneathReceivesIt() async throws {
		// `Sub` keeps the label of the pass-through `authToken`, which may be `nil`, and `Reader` beneath reads `Sub`'s binding.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], left: ["@Instantiated let sub: Sub"], detail: nil, reader: [Self.existentialReceive], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_A9C51D76FF594AA6.self
			            return Screen(__safeDI_authToken: authToken)
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
			    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> Secret?) {
			        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken_)
			        func __safeDI_left() -> Left {
			            func __safeDI_sub() -> Sub {
			                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
			                let authToken: (any Auth)? = authToken.instance
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Sub(authToken: authToken, reader: reader)
			            }
			            let sub: Sub = __safeDI_sub()
			            return Left(sub: sub)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_A9C51D76FF594AA6 {}
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsErasedLabelKeepingAliasFromParameter_whenReaderBeneathReceivesIt() async throws {
		// `Sub`'s erased label-keeping alias maps the pass-through `authToken`, which the caller passes `Root`'s `authToken`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated(fulfilledByType: \"Secret\", erasedToConcreteExistential: true) let authToken: AnyAuth"], left: ["@Instantiated let sub: Sub"], detail: nil, reader: ["@Received(onlyIfAvailable: true) let authToken: AnyAuth?"], secretConformances: ", Auth", otherTypes: [Self.authProtocol, Self.anyAuth, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.erasedLabelKeepingAlias, "@Instantiated let reader: Reader"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let authToken = AnyAuth(Secret())
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_A9C51D76FF594AA6.self
			            return Screen(__safeDI_authToken: nil)
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
			    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> Secret?) {
			        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken_)
			        func __safeDI_left() -> Left {
			            func __safeDI_sub() -> Sub {
			                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
			                let authToken: AnyAuth? = (authToken.instance as Secret?).map { AnyAuth($0) }
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Sub(authToken: authToken, reader: reader)
			            }
			            let sub: Sub = __safeDI_sub()
			            return Left(sub: sub)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_A9C51D76FF594AA6 {}
			}
			""",
		])
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingAliasToNil_whenReaderBeneathAliasOfPropertyBeingBuiltReceivesIt() async throws {
		// `Sub` is built inside `authToken`, so its label-keeping alias is `nil`, and `Reader` beneath reads that `nil`.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], screen: ["@Instantiated let authToken: Secret"], left: nil, detail: nil, reader: [Self.existentialReceive], secret: ["@Instantiated let subBuilder: Instantiator<Sub>"], secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Sub", isFinalClass: true, declarations: [Self.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_subBuilder() -> Sub {
			                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
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
			            _ = Screen.__safeDI_Screen_CBF29CE484222325.self
			            return Screen()
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_authToken() -> Secret {
			            func __safeDI_subBuilder() -> Sub {
			                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
			                let authToken: (any Auth)? = nil
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Sub(authToken: authToken, reader: reader)
			            }
			            let subBuilder = Instantiator<Sub>(__safeDI_subBuilder)
			            return Secret(subBuilder: subBuilder)
			        }
			        let authToken: Secret = __safeDI_authToken()
			        self.init(authToken: authToken)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
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
	mutating func generate_bindsLabelKeepingAliasFromParameter_whenReaderBeneathItIsSpelledAnyWay(spelling: SafeDIToolSeamUncreatedAliasTests.Spelling) async throws {
		// The label-keeping alias retypes the pass-through `authToken`, which may be `nil`, to `Any?` from every spelling.
		let fixture = spelling.fixture(left: ["@Instantiated let sub: Sub"], detail: nil, reader: [spelling.anyReceive], otherTypes: [seamFixtureType(named: "Sub", isFinalClass: true, declarations: [spelling.labelKeepingAlias, "@Instantiated let reader: Reader"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [SafeDIToolSeamUncreatedAliasTests.Spelling: [String: String]] = [
			.existential: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_3D514124C70F64F0.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> (any Auth)?) {
				        let authToken = LazilyInstantiated<(any Auth)?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_3D514124C70F64F0 {}
				}
				""",
			],
			.closure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_F4CB39382F5CBD25.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> (() -> Void)?) {
				        let authToken = LazilyInstantiated<(() -> Void)?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_F4CB39382F5CBD25 {}
				}
				""",
			],
			.nested: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_1433A402386E2672.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> Feature.Secret?) {
				        let authToken = LazilyInstantiated<Feature.Secret?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_1433A402386E2672 {}
				}
				""",
			],
			.nonFunctionTypealias: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_355BAF235B541B43.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> SecretID?) {
				        let authToken = LazilyInstantiated<SecretID?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_355BAF235B541B43 {}
				}
				""",
			],
			.optionalOfType: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_A9C51D76FF594AA6.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> Secret?) {
				        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_A9C51D76FF594AA6 {}
				}
				""",
			],
			.sendableClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_864A9D5FFC636A83.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> (@Sendable () -> Void)?) {
				        let authToken = LazilyInstantiated<(@Sendable () -> Void)?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_864A9D5FFC636A83 {}
				}
				""",
			],
			.optionalClosure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_F4CB39382F5CBD25.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> (() -> Void)?) {
				        let authToken = LazilyInstantiated<(() -> Void)?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_F4CB39382F5CBD25 {}
				}
				""",
			],
			.tuple: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_301BB3464139FD7E.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> (a: Int, b: String)?) {
				        let authToken = LazilyInstantiated<(a: Int, b: String)?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_301BB3464139FD7E {}
				}
				""",
			],
			.generic: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_AD12AEFF533729F3.self
				            return Screen(__safeDI_authToken: nil)
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
				    public convenience init(__safeDI_authToken __safeDI_authToken_: @autoclosure @escaping () -> Box<Secret>?) {
				        let authToken = LazilyInstantiated<Box<Secret>?>(__safeDI_authToken_)
				        func __safeDI_left() -> Left {
				            func __safeDI_sub() -> Sub {
				                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 8)
				                let authToken: Any? = authToken.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Sub(authToken: authToken, reader: reader)
				            }
				            let sub: Sub = __safeDI_sub()
				            return Left(sub: sub)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_AD12AEFF533729F3 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[spelling])
	}

	// MARK: A reader inside a nested seam

	@Test(arguments: Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasOfAliasFromParameter_whenNestedSeamsTypeAliasesIt(holder: Holder) async throws {
		// `Sub`, inside the nested seam `Inner`, aliases `Detail`'s alias: `Inner`'s parameter stands for that alias, and its
		// caller passes it the alias's binding, as for the same tree with `Inner` inline.
		let fixture = Self.fixture(rootHolds: holder.declarations, detail: [Self.alias, "@Instantiated let inner: Inner"], reader: nil, secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let sub: Sub"]), seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [Holder: [String: String]] = [
			.nothing: [
				"Inner+SafeDI.swift": generatedFileHeader + """
				extension Inner {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_authToken: @autoclosure @escaping () -> Secret?) {
				        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken)
				        func __safeDI_sub() -> Sub {
				            #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 7)
				            let bearer: Secret? = authToken.instance
				            #sourceLocation()
				            return Sub(bearer: bearer)
				        }
				        let sub: Sub = __safeDI_sub()
				        self.init(sub: sub)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_A9C51D76FF594AA6 {}
				}
				""",
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
				                func __safeDI_inner() -> Inner {
				                    _ = Inner.__safeDI_Inner_A9C51D76FF594AA6.self
				                    return Inner(__safeDI_authToken: authToken)
				                }
				                let inner: Inner = __safeDI_inner()
				                return Detail(authToken: authToken, inner: inner)
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
				"Inner+SafeDI.swift": generatedFileHeader + """
				extension Inner {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_authToken: @autoclosure @escaping () -> Secret?) {
				        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken)
				        func __safeDI_sub() -> Sub {
				            #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 7)
				            let bearer: Secret? = authToken.instance
				            #sourceLocation()
				            return Sub(bearer: bearer)
				        }
				        let sub: Sub = __safeDI_sub()
				        self.init(sub: sub)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_A9C51D76FF594AA6 {}
				}
				""",
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
				                func __safeDI_inner() -> Inner {
				                    _ = Inner.__safeDI_Inner_A9C51D76FF594AA6.self
				                    return Inner(__safeDI_authToken: authToken)
				                }
				                let inner: Inner = __safeDI_inner()
				                return Detail(authToken: authToken, inner: inner)
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
				"Inner+SafeDI.swift": generatedFileHeader + """
				extension Inner {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_authToken: @autoclosure @escaping () -> Secret?) {
				        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken)
				        func __safeDI_sub() -> Sub {
				            #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 7)
				            let bearer: Secret? = authToken.instance
				            #sourceLocation()
				            return Sub(bearer: bearer)
				        }
				        let sub: Sub = __safeDI_sub()
				        self.init(sub: sub)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_A9C51D76FF594AA6 {}
				}
				""",
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
				                func __safeDI_inner() -> Inner {
				                    _ = Inner.__safeDI_Inner_A9C51D76FF594AA6.self
				                    return Inner(__safeDI_authToken: authToken)
				                }
				                let inner: Inner = __safeDI_inner()
				                return Detail(authToken: authToken, inner: inner)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasOfAliasFromParameter_whenNestedSeamItselfAliasesIt() async throws {
		// The nested seam declares the alias of the alias itself, and its caller passes it the alias's binding.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let authToken: Secret"], detail: [Self.alias, "@Instantiated let inner: Inner"], reader: nil, secretConformances: ", Auth", otherTypes: [Self.authProtocol, seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_authToken: @autoclosure @escaping () -> Secret?) {
			        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken)
			        #sourceLocation(file: "\(output.fixtures["Inner.swift"])", line: 7)
			        let bearer: Secret? = authToken.instance
			        #sourceLocation()
			        self.init(bearer: bearer)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_A9C51D76FF594AA6 {}
			}
			""",
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
			                func __safeDI_inner() -> Inner {
			                    _ = Inner.__safeDI_Inner_A9C51D76FF594AA6.self
			                    return Inner(__safeDI_authToken: authToken)
			                }
			                let inner: Inner = __safeDI_inner()
			                return Detail(authToken: authToken, inner: inner)
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: A reader that requires the alias

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesAliasBindingToRequiredReader_whenReaderBeneathAliasOfPassThroughReceivesIt() async throws {
		// A reader that requires the alias's property is passed the alias's binding, `nil` where the parameter is.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.requiredReceive], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_2731EA611E5B250D.self
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
			    public enum __safeDI_Screen_2731EA611E5B250D {}
			}
			""",
		])
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
		try await expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
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
	mutating func generate_bindsLabelKeepingAliasFromAliasInSeamsModule_whenItAndItsDeclaringTypeAreInModuleSeamDependsOn(integration: MultiModuleIntegration) async throws {
		// `Detail` and `Reader` are declared in `Core`, which `Feature` depends on: `Reader`'s label-keeping alias is bound
		// from `Detail`'s alias as it is when `Feature` declares them.
		let files = Self.fixture(rootHolds: Holder.authToken.declarations, detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.labelKeepingAlias])
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.threeModules(files), integration: integration, filesToDelete: &filesToDelete)
		let detailPath = try #require(output.modules["Core"]).fixtures.compilerPath(of: "Detail.swift")
		let readerPath = try #require(output.modules["Core"]).fixtures.compilerPath(of: "Reader.swift")
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
			                func __safeDI_reader() -> Reader {
			                    #sourceLocation(file: "\(readerPath)", line: 7)
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
	mutating func generate_bindsAliasOfAliasInSeamsModule_whenNestedSeamInAnotherModuleAliasesIt(integration: MultiModuleIntegration) async throws {
		// The nested seam `Inner`, in `Core`, takes `Sub`'s alias of `Detail`'s alias as a parameter, which `Feature`
		// passes the alias's binding.
		let files = Self.fixture(rootHolds: Holder.authToken.declarations, detail: [Self.alias, "@Instantiated let inner: Inner"], reader: nil, otherTypes: [Self.authProtocol, seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let sub: Sub"]), seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"authToken\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.innerInCore(files), integration: integration, filesToDelete: &filesToDelete)
		let subPath = try #require(output.modules["Core"]).fixtures.compilerPath(of: "Sub.swift")
		#expect(try #require(output.modules["Core"]).generatedFiles == [
			integration == .moduleInfo ? "Core.swift" : "Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public convenience init(__safeDI_authToken: @autoclosure @escaping () -> Secret?) {
			        let authToken = LazilyInstantiated<Secret?>(__safeDI_authToken)
			        func __safeDI_sub() -> Sub {
			            #sourceLocation(file: "\(subPath)", line: 7)
			            let bearer: Secret? = authToken.instance
			            #sourceLocation()
			            return Sub(bearer: bearer)
			        }
			        let sub: Sub = __safeDI_sub()
			        self.init(sub: sub)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_A9C51D76FF594AA6 {}
			}
			""",
		])
		let detailPath = try #require(output.modules["Feature"]).fixtures.compilerPath(of: "Detail.swift")
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
			                #sourceLocation(file: "\(detailPath)", line: 10)
			                let authToken: Secret? = token.instance
			                #sourceLocation()
			                func __safeDI_inner() -> Inner {
			                    _ = Inner.__safeDI_Inner_A9C51D76FF594AA6.self\(integration.seamCallComment(type: "Inner", declaringModule: "Core"))
			                    return Inner(__safeDI_authToken: authToken)
			                }
			                let inner: Inner = __safeDI_inner()
			                return Detail(authToken: authToken, inner: inner)
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
