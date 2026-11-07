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

/// An `onlyIfAvailable` alias inside a seam of a parameter of optional type – a pass-through received only if
/// available, the seam's own `onlyIfAvailable` receive, a required pass-through `x: X?`, the seam's own required
/// `@Received let x: X?`, or its own `@Forwarded let x: X?` – reads that optional form whichever form it spells, as
/// inline reads the caller's nearest declaration, so the alias is bound from the parameter and is `nil` where it is.
/// Each cell sits beside the inline build of the same graph.
struct SafeDIToolSeamRequiredOptionalParameterTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: An alias of exactly a required optional parameter

	@Test(arguments: ReaderKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsExactFormAlias_whenSeamsOwnRequiredReceiveIsOptional(reader: ReaderKind) async throws {
		// The seam's own required `token: Secret?` is a value every caller passes, so `Detail`'s alias of exactly `token: Secret?`
		// is always created, whatever reads it; the initializer takes `token: Secret?` with no default.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", screen: ["@Received let token: Secret?", "@Instantiated let left: Left"], detail: reader.detail, reader: reader.declarations, otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [ReaderKind: [String: String]] = [
			.onlyIfAvailable: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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
				    public convenience init(token: Secret?) {
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
				    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
				}
				""",
			],
			.required: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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
				    public convenience init(token: Secret?) {
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
				    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
				}
				""",
			],
			.none: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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
				    public convenience init(token: Secret?) {
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
				        self.init(token: token, left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[reader])
		let expectedInlineOutput: [ReaderKind: [String: String]] = [
			.onlyIfAvailable: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
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
				                return Screen(token: token, left: left)
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
			],
			.required: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
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
				                return Screen(token: token, left: left)
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
			],
			.none: [
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
				                return Screen(token: token, left: left)
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
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[reader])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsExactFormAlias_whenRequiredPassThroughIsOptionalWrapper() async throws {
		// The wrapper spelling: `Left` requires `token: LazilyInstantiated<Secret>?`, which `Detail` aliases exactly.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", left: ["@Received let token: LazilyInstantiated<Secret>?", "@Instantiated let detail: Detail"], detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: LazilyInstantiated<Secret>?.self, onlyIfAvailable: true) let authToken: LazilyInstantiated<Secret>?", "@Instantiated let reader: Reader"], reader: ["@Received(onlyIfAvailable: true) let authToken: LazilyInstantiated<Secret>?"], otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: LazilyInstantiated<Secret>?", "@Instantiated let screen: Screen"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: LazilyInstantiated<Secret>?) -> Host {
			            func __safeDI_screen() -> Screen {
			                _ = Screen.__safeDI_Screen_83396009A30E2AFD.self
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
			    public convenience init(token: LazilyInstantiated<Secret>?) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			                let authToken: LazilyInstantiated<Secret>? = token
			                #sourceLocation()
			                let reader = Reader(authToken: authToken)
			                return Detail(authToken: authToken, reader: reader)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(token: token, detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_83396009A30E2AFD {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: LazilyInstantiated<Secret>?) -> Host {
			            func __safeDI_screen() -> Screen {
			                func __safeDI_left() -> Left {
			                    func __safeDI_detail() -> Detail {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
			                        let authToken: LazilyInstantiated<Secret>? = token
			                        #sourceLocation()
			                        let reader = Reader(authToken: authToken)
			                        return Detail(authToken: authToken, reader: reader)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    return Left(token: token, detail: detail)
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

	@Test(arguments: OptionalSpelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsExactFormAlias_whenSeamsOwnRequiredReceiveIsOptionalAndSpelledAnyWay(spelling: OptionalSpelling) async throws {
		// The type-spelling axis: an existential, a closure, a nested type, a typealias, a generic, and a tuple.
		let fixture = spelling.fixture()
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [OptionalSpelling: [String: String]] = [
			.existential: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: (any Auth)?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_8393C47C1ED4CB60.self
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
				    public convenience init(token: (any Auth)?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: (any Auth)? = token
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
				    public enum __safeDI_Screen_8393C47C1ED4CB60 {}
				}
				""",
			],
			.closure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: (() -> Void)?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4D3D1774B4EA6EAD.self
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
				    public convenience init(token: (() -> Void)?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: (() -> Void)? = token
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
				    public enum __safeDI_Screen_4D3D1774B4EA6EAD {}
				}
				""",
			],
			.nested: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Feature.Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_66B781B70ABE6816.self
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
				    public convenience init(token: Feature.Secret?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Feature.Secret? = token
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
				    public enum __safeDI_Screen_66B781B70ABE6816 {}
				}
				""",
			],
			.nonFunctionTypealias: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: SecretID?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_36BABAB4386A75F7.self
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
				    public convenience init(token: SecretID?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: SecretID? = token
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
				    public enum __safeDI_Screen_36BABAB4386A75F7 {}
				}
				""",
			],
			.generic: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Box<Secret>?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_397522097A4AC22F.self
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
				    public convenience init(token: Box<Secret>?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: Box<Secret>? = token
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
				    public enum __safeDI_Screen_397522097A4AC22F {}
				}
				""",
			],
			.tuple: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: (a: Int, b: String)?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_CF352213058C3AC6.self
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
				    public convenience init(token: (a: Int, b: String)?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
				                let authToken: (a: Int, b: String)? = token
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
				    public enum __safeDI_Screen_CF352213058C3AC6 {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[spelling])
		let expectedInlineOutput: [OptionalSpelling: [String: String]] = [
			.existential: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: (any Auth)?) -> Host {
				            func __safeDI_screen() -> Screen {
				                func __safeDI_left() -> Left {
				                    func __safeDI_detail() -> Detail {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                        let authToken: (any Auth)? = token
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
			],
			.closure: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: (() -> Void)?) -> Host {
				            func __safeDI_screen() -> Screen {
				                func __safeDI_left() -> Left {
				                    func __safeDI_detail() -> Detail {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                        let authToken: (() -> Void)? = token
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
			],
			.nested: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Feature.Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                func __safeDI_left() -> Left {
				                    func __safeDI_detail() -> Detail {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                        let authToken: Feature.Secret? = token
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
			],
			.nonFunctionTypealias: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: SecretID?) -> Host {
				            func __safeDI_screen() -> Screen {
				                func __safeDI_left() -> Left {
				                    func __safeDI_detail() -> Detail {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                        let authToken: SecretID? = token
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
			],
			.generic: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Box<Secret>?) -> Host {
				            func __safeDI_screen() -> Screen {
				                func __safeDI_left() -> Left {
				                    func __safeDI_detail() -> Detail {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                        let authToken: Box<Secret>? = token
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
			],
			.tuple: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: (a: Int, b: String)?) -> Host {
				            func __safeDI_screen() -> Screen {
				                func __safeDI_left() -> Left {
				                    func __safeDI_detail() -> Detail {
				                        #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 8)
				                        let authToken: (a: Int, b: String)? = token
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
			],
		]
		#expect(inlineOutput.dependencyTreeFiles == expectedInlineOutput[spelling])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsExactFormAlias_whenNestedSeamsOwnRequiredReceiveIsOptional() async throws {
		// `Inner`, a seam inside `Screen`'s tree, takes the required `token: Secret?` its own tree requires; `Detail`'s alias of
		// exactly that form is always created.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", screen: ["@Received let token: Secret?", "@Instantiated let inner: Inner"], left: ["@Received let token: Secret?", "@Instantiated let detail: Detail"], detail: [Self.exactFormAlias, "@Instantiated let reader: Reader"], otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"]), seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let left: Left"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    public convenience init(token __safeDI_token: @autoclosure @escaping () -> Secret?) {
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
			            return Left(token: token.instance, detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_C10331417AC12746 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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
			    public convenience init(token: Secret?) {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_C10331417AC12746.self
			            return Inner(token: token)
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(token: token, inner: inner)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
			}
			""",
		])
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                func __safeDI_inner() -> Inner {
			                    func __safeDI_left() -> Left {
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
			                    return Inner(left: left)
			                }
			                let inner: Inner = __safeDI_inner()
			                return Screen(token: token, inner: inner)
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

	// MARK: An alias of a parameter that may be nil

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasOfUnwrappedFormFromSeamsOwnOptionalForwardedProperty_asInlineDoes() async throws {
		// An `onlyIfAvailable` alias of `token: Secret` reads the seam's own forwarded `token: Secret?`, its optional form,
		// as an `onlyIfAvailable` alias reads either form of its fulfilling property: the seam and inline bind it alike.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let screenBuilder: Instantiator<Screen>", screen: ["@Forwarded let token: Secret?", "@Instantiated let left: Left"], detail: [Self.alias, "@Instantiated let reader: Reader"], reader: [Self.receive])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder(token: Secret?) -> Screen {
			            _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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
			    public convenience init(token: Secret?) {
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
			    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder(token: Secret?) -> Screen {
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
	mutating func generate_bindsAliasFromNearestAlias_whenOnlyIfAvailableAliasOfParameterDefaultingToNilIsClosestDeclarationOfRequiredOptionalParameter() async throws {
		// `Left`'s `onlyIfAvailable` alias `token: Secret?` of the `= nil` parameter `other` is the closest declaration of `token`
		// above `Detail`'s exact-form alias, which is bound from it.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", screen: ["@Instantiated let right: Right", "@Instantiated let left: Left"], left: ["@Received(fulfilledByDependencyNamed: \"other\", ofType: Secret.self, onlyIfAvailable: true) let token: Secret?", "@Instantiated let detail: Detail"], detail: [Self.exactFormAlias, "@Instantiated let reader: Reader"], reader: [Self.receive], otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"]), seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Received let token: Secret?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                _ = Screen.__safeDI_Screen_20E046F5ABDBDA7E.self
			                return Screen(other: nil, token: token)
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
			    public convenience init(other __safeDI_other: @autoclosure @escaping () -> Secret?, token __safeDI_token_: @autoclosure @escaping () -> Secret?) {
			        let other = LazilyInstantiated<Secret?>(__safeDI_other)
			        let token = LazilyInstantiated<Secret?>(__safeDI_token_)
			        let right = Right(token: token.instance)
			        func __safeDI_left() -> Left {
			            #sourceLocation(file: "\(output.fixtures["Left.swift"])", line: 8)
			            let token: Secret? = other.instance
			            #sourceLocation()
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
			        self.init(right: right, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_20E046F5ABDBDA7E {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                let right = Right(token: token)
			                func __safeDI_left() -> Left {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Left.swift"])", line: 8)
			                    let token: Secret? = nil
			                    #sourceLocation()
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
			                return Screen(right: right, left: left)
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
		try expectSeamBuildsInlineValues(of: fixture, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	// MARK: An erased alias of a parameter that may be nil

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_mapsErasedAliasOverOptionalParameterOnce_whenAliasSpellsOptionalForm() async throws {
		// An erased `onlyIfAvailable` alias spelled `ofType: Secret?.self` of a `= nil` pass-through maps over the parameter as
		// `Secret?`, never `Secret??`, and compiles. Inline, the alias is declared optional, so it maps over the root's
		// non-optional `token` too.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], left: ["@Instantiated let sub: Sub"], detail: nil, reader: nil, secretConformances: ", Auth", otherTypes: [Self.authProtocol, Self.anyAuth, seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret?.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let authToken: AnyAuth?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init(token __safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_sub() -> Sub {
			                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 7)
			                let authToken: AnyAuth? = (token.instance as Secret?).map { AnyAuth($0) }
			                #sourceLocation()
			                return Sub(authToken: authToken)
			            }
			            let sub: Sub = __safeDI_sub()
			            return Left(sub: sub)
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
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 7)
			                    let authToken: AnyAuth? = (token as Secret?).map { AnyAuth($0) }
			                    #sourceLocation()
			                    return Sub(authToken: authToken)
			                }
			                let sub: Sub = __safeDI_sub()
			                return Left(sub: sub)
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
	mutating func generate_mapsErasedAliasOverOptionalParameterOnce_whenAliasSpellsUnwrappedForm() async throws {
		// The control: spelled `ofType: Secret.self`, the alias maps over `token as Secret?`, as before.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], left: ["@Instantiated let sub: Sub"], detail: nil, reader: nil, secretConformances: ", Auth", otherTypes: [Self.authProtocol, Self.anyAuth, seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let authToken: AnyAuth?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_8763BEDE3E51EBC4.self
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init(token __safeDI_token: @autoclosure @escaping () -> Secret?) {
			        let token = LazilyInstantiated<Secret?>(__safeDI_token)
			        func __safeDI_left() -> Left {
			            func __safeDI_sub() -> Sub {
			                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 7)
			                let authToken: AnyAuth? = (token.instance as Secret?).map { AnyAuth($0) }
			                #sourceLocation()
			                return Sub(authToken: authToken)
			            }
			            let sub: Sub = __safeDI_sub()
			            return Left(sub: sub)
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
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_sub() -> Sub {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 7)
			                    let authToken: AnyAuth? = AnyAuth(token)
			                    #sourceLocation()
			                    return Sub(authToken: authToken)
			                }
			                let sub: Sub = __safeDI_sub()
			                return Left(sub: sub)
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
	mutating func generate_wrapsErasedExactFormAliasOfRequiredOptionalParameterInExistential_whereInlineDoesToo() async throws {
		// An erased alias of exactly a required `token: Secret?` is always created, and is declared optional, so both builds map
		// the wrapper over the optional `token`, which compiles.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", screen: ["@Received let token: Secret?", "@Instantiated let left: Left"], left: ["@Instantiated let sub: Sub"], detail: nil, reader: nil, secretConformances: ", Auth", otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"]), Self.authProtocol, Self.anyAuth, seamFixtureType(named: "Sub", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret?.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let authToken: AnyAuth?"])])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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
			    public convenience init(token: Secret?) {
			        func __safeDI_left() -> Left {
			            func __safeDI_sub() -> Sub {
			                #sourceLocation(file: "\(output.fixtures["Sub.swift"])", line: 7)
			                let authToken: AnyAuth? = (token as Secret?).map { AnyAuth($0) }
			                #sourceLocation()
			                return Sub(authToken: authToken)
			            }
			            let sub: Sub = __safeDI_sub()
			            return Left(sub: sub)
			        }
			        let left: Left = __safeDI_left()
			        self.init(token: token, left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
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
			                    func __safeDI_sub() -> Sub {
			                        #sourceLocation(file: "\(inlineOutput.fixtures["Sub.swift"])", line: 7)
			                        let authToken: AnyAuth? = (token as Secret?).map { AnyAuth($0) }
			                        #sourceLocation()
			                        return Sub(authToken: authToken)
			                    }
			                    let sub: Sub = __safeDI_sub()
			                    return Left(sub: sub)
			                }
			                let left: Left = __safeDI_left()
			                return Screen(token: token, left: left)
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

	// MARK: Across modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsExactFormAliasAcrossModules_whenSeamsOwnRequiredReceiveIsOptional(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.twoModules(Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", screen: ["@Received let token: Secret?", "@Instantiated let left: Left"], detail: [Self.exactFormAlias, "@Instantiated let reader: Reader"], reader: [Self.receive], otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"])])), integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(try #require(output.modules["Feature"]).fixtures.compilerPath(of: "Detail.swift"))", line: 8)
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
				    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret?) {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(try #require(output.modules["Feature"]).fixtures.compilerPath(of: "Detail.swift"))", line: 8)
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
				    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			],
			.swiftPackagePlugin: [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
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
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		if compileVerificationIsEnabled {
			#expect(try #require(output.compilation).modules.map(\.exitCode) == [0, 0])
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsExactFormAliasAcrossModules_whenNestedSeamInAnotherModuleTakesRequiredOptionalParameter(integration: MultiModuleIntegration) async throws {
		// `Inner`, its tree and `Secret` in `Core`; `Screen`, `Host` and `Root` in `Feature`: `Screen` reads `Inner`'s signature,
		// whose required `token: Secret?` comes back required, and `Inner` creates the exact-form alias as it does in one module.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", screen: ["@Received let token: Secret?", "@Instantiated let inner: Inner"], left: ["@Received let token: Secret?", "@Instantiated let detail: Detail"], detail: [Self.exactFormAlias, "@Instantiated let reader: Reader"], otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"]), seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let left: Left"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.innerInCore(fixture), integration: integration, filesToDelete: &filesToDelete)
		let expectedCoreFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Core.swift": generatedFileHeader + """
				extension Inner {
				    public convenience init(token __safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(try #require(output.modules["Core"]).fixtures.compilerPath(of: "Detail.swift"))", line: 8)
				                let authToken: Secret? = token.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Detail(authToken: authToken, reader: reader)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token.instance, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_C10331417AC12746 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Inner+SafeDI.swift": generatedFileHeader + """
				extension Inner {
				    public convenience init(token __safeDI_token: @autoclosure @escaping () -> Secret?) {
				        let token = LazilyInstantiated<Secret?>(__safeDI_token)
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                #sourceLocation(file: "\(try #require(output.modules["Core"]).fixtures.compilerPath(of: "Detail.swift"))", line: 8)
				                let authToken: Secret? = token.instance
				                #sourceLocation()
				                let reader = Reader(authToken: authToken)
				                return Detail(authToken: authToken, reader: reader)
				            }
				            let detail: Detail = __safeDI_detail()
				            return Left(token: token.instance, detail: detail)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Inner {
				    public enum __safeDI_Inner_C10331417AC12746 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Core"]).generatedFiles == expectedCoreFiles[integration])
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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

				extension Screen {
				    public convenience init(token: Secret?) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_C10331417AC12746.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Inner(token: token)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(token: token, inner: inner)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_hostBuilder(token: Secret?) -> Host {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_4BDBF64A8A90FDCE.self
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
				#if canImport(Core)
				import Core
				#endif

				extension Screen {
				    public convenience init(token: Secret?) {
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_C10331417AC12746.self // If this line does not compile, add the SafeDI plugin to the target that declares Inner.
				            return Inner(token: token)
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(token: token, inner: inner)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_4BDBF64A8A90FDCE {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		if compileVerificationIsEnabled {
			#expect(try #require(output.compilation).modules.map(\.exitCode) == [0, 0])
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	typealias Holder = SafeDIToolSeamUncreatedAliasTests.Holder
	private static let alias = "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?"
	private static let exactFormAlias = "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret?.self, onlyIfAvailable: true) let authToken: Secret?"
	private static let receive = "@Received(onlyIfAvailable: true) let authToken: Secret?"
	private static let authProtocol = "public protocol Auth {}"
	private static let anyAuth = "public struct AnyAuth: Auth {\n    public init(_ auth: any Auth) {\n        self.auth = auth\n    }\n\n    public let auth: any Auth\n}"

	/// What reads the alias beneath its declaring type.
	enum ReaderKind: String, CaseIterable, CustomTestStringConvertible {
		case onlyIfAvailable
		case required
		case none

		var testDescription: String {
			rawValue
		}

		/// `Detail`'s declarations: the exact-form alias and, with a reader, `reader`.
		var detail: [String] {
			self == .none ? [exactFormAlias] : [exactFormAlias, "@Instantiated let reader: Reader"]
		}

		/// `Reader`'s declarations, or `nil` for no `Reader`.
		var declarations: [String]? {
			switch self {
			case .onlyIfAvailable:
				[receive]
			case .required:
				["@Received let authToken: Secret?"]
			case .none:
				nil
			}
		}
	}

	/// A spelling of the seam's own required optional receive `token: T?`, aliased with `ofType: T?.self`.
	enum OptionalSpelling: String, CaseIterable, CustomTestStringConvertible {
		/// `token: (any Auth)?`.
		case existential
		/// `token: (() -> Void)?`.
		case closure
		/// `token: Feature.Secret?`.
		case nested
		/// `token: SecretID?`, a typealias of `String`.
		case nonFunctionTypealias
		/// `token: Box<Secret>?`.
		case generic
		/// `token: (a: Int, b: String)?`.
		case tuple

		var testDescription: String {
			rawValue
		}

		/// The non-optional type, spelled to take `?`.
		var type: String {
			switch self {
			case .existential:
				"(any Auth)"
			case .closure:
				"(() -> Void)"
			case .nested:
				"Feature.Secret"
			case .nonFunctionTypealias:
				"SecretID"
			case .generic:
				"Box<Secret>"
			case .tuple:
				"(a: Int, b: String)"
			}
		}

		private var declarations: [String] {
			switch self {
			case .existential:
				["public protocol Auth {}"]
			case .closure, .tuple:
				[]
			case .nested:
				["public enum Feature {\n    public struct Secret {\n        public init() {}\n    }\n}"]
			case .nonFunctionTypealias:
				["public typealias SecretID = String"]
			case .generic:
				["public final class Box<Value> {\n    public init(_ value: Value) {\n        self.value = value\n    }\n\n    public let value: Value\n}"]
			}
		}

		/// `Root` builds `Host`, which forwards `token: T?` and instantiates the seam, whose own required receive `token: T?`
		/// `Detail` aliases exactly, and `Reader` receives the alias only if available.
		func fixture() -> [String] {
			SafeDIToolSeamRequiredOptionalParameterTests.fixture(
				rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>",
				screen: ["@Received let token: \(type)?", "@Instantiated let left: Left"],
				detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: \(type)?.self, onlyIfAvailable: true) let authToken: \(type)?", "@Instantiated let reader: Reader"],
				reader: ["@Received(onlyIfAvailable: true) let authToken: \(type)?"],
				otherTypes: [seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: \(type)?", "@Instantiated let screen: Screen"])] + declarations,
			)
		}
	}

	private static func fixture(
		rootHolds: [String] = [],
		rootBuilds: String = "@Instantiated let screen: Screen",
		screen: [String] = ["@Instantiated let left: Left"],
		left: [String]? = ["@Instantiated let detail: Detail"],
		detail: [String]? = [exactFormAlias, "@Instantiated let reader: Reader"],
		reader: [String]? = [receive],
		secret: [String] = [],
		secretConformances: String = "",
		otherTypes: [String] = [],
	) -> [String] {
		SafeDIToolSeamUncreatedAliasTests.fixture(rootHolds: rootHolds, rootBuilds: rootBuilds, screen: screen, left: left, detail: detail, reader: reader, secret: secret, secretConformances: secretConformances, otherTypes: otherTypes)
	}

	/// `files` with `Inner`, `Left`, `Detail`, `Reader`, and `Secret` in `Core`, which `Feature`, holding the rest, depends on.
	private static func innerInCore(_ files: [String]) -> [ModuleFixture] {
		let coreTypes = files.filter { file in ["Inner", "Left", "Detail", "Reader", "Secret"].contains { file.contains("class \($0):") } }
		return [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: coreTypes),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: files.filter { !coreTypes.contains($0) }.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
		]
	}

	private static func twoModules(_ files: [String]) -> [ModuleFixture] {
		SafeDIToolSeamUncreatedAliasTests.twoModules(files)
	}
}
