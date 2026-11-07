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

/// An `onlyIfAvailable` alias that keeps the label of its fulfilling property and only makes it optional – a redundant
/// spelling of `@Received(onlyIfAvailable: true)` – is not an alias of itself: a type's own declaration of the label is
/// not a declaration of the label the alias reads. The seam binds it from the parameter, as it binds any alias of a
/// parameter callers may leave `nil`, and rejects only the reads beneath it.
struct SafeDIToolSeamSelfAliasTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: An alias that keeps its fulfilling property's label and only makes it optional

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingOptionalAliasFromParameter_whenNothingReadsItAndCallerHoldsNothing() async throws {
		// `Detail`'s alias keeps the label `token` of its fulfilling property and only makes it optional: a type's own declaration of
		// the label is not a declaration of the label the alias reads, so the alias is not an alias of itself. With no reader it
		// is bound from the parameter; the caller holds nothing and passes `nil`, as inline does not create the alias.
		let fixture = Self.fixture(detail: [Self.selfAlias], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
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
			    public convenience init(token: Secret?) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                let token: Secret? = token
			                #sourceLocation()
			                return Detail(token: token)
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
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                    return Detail(token: nil)
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
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingOptionalAliasFromParameter_whenSeamItselfDeclaresIt() async throws {
		// The seam's own alias keeps the label of its pass-through.
		let fixture = Self.fixture(rootHolds: ["@Instantiated let token: Secret"], screen: [Self.selfAlias, "@Instantiated let left: Left"], detail: [], reader: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
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
			    public convenience init(token: Secret?) {
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let token: Secret? = token
			        #sourceLocation()
			        func __safeDI_left() -> Left {
			            let detail = Detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(token: token, left: left)
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
			    public convenience init() {
			        let token = Secret()
			        func __safeDI_screen() -> Screen {
			            #sourceLocation(file: "\(inlineOutput.fixtures["Screen.swift"])", line: 8)
			            let token: Secret? = token
			            #sourceLocation()
			            func __safeDI_left() -> Left {
			                let detail = Detail()
			                return Left(detail: detail)
			            }
			            let left: Left = __safeDI_left()
			            return Screen(token: token, left: left)
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
	mutating func generate_bindsLabelKeepingOptionalAliasFromParameter_whenAliasIsSpelledExistential() async throws {
		// The existential spelling: `auth: (any Auth)?` of `auth: any Auth`, equal under `==`, which ignores `any`.
		let fixture = Self.fixture(detail: [Self.existentialSelfAlias], reader: nil, secretConformances: ", Auth", otherTypes: [Self.authProtocol])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_9C2BE83E3D715C0F.self
			            return Screen(auth: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public convenience init(auth: (any Auth)?) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                let auth: (any Auth)? = auth
			                #sourceLocation()
			                return Detail(auth: auth)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_9C2BE83E3D715C0F {}
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
			                    // Did not create `auth: (any Auth)?` because `auth: any Auth` is unavailable.
			                    return Detail(auth: nil)
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
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLabelKeepingOptionalAliasFromParameter_whenFulfillingPropertyIsRequiredOptionalParameter() async throws {
		// `Right` requires `token: Secret?`, so the parameter is required and only its unwrapped form may be `nil`; the alias of that
		// form is bound from the parameter and read by nothing.
		let fixture = Self.fixture(rootBuilds: "@Instantiated let hostBuilder: Instantiator<Host>", left: ["@Instantiated let detail: Detail", "@Instantiated let right: Right"], detail: [Self.selfAlias], reader: nil, otherTypes: [Self.host, Self.right])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
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
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 7)
			                let token: Secret? = token
			                #sourceLocation()
			                return Detail(token: token)
			            }
			            let detail: Detail = __safeDI_detail()
			            let right = Right(token: token)
			            return Left(detail: detail, right: right)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
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
			        func __safeDI_hostBuilder(token: Secret?) -> Host {
			            func __safeDI_screen() -> Screen {
			                func __safeDI_left() -> Left {
			                    func __safeDI_detail() -> Detail {
			                        // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                        return Detail(token: nil)
			                    }
			                    let detail: Detail = __safeDI_detail()
			                    let right = Right(token: token)
			                    return Left(detail: detail, right: right)
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
	mutating func generate_bindsLabelKeepingOptionalAliasFromProperty_whenDeclaringTypeIsBuiltWhereItsFulfillingPropertyIsStillBeingBuilt() async throws {
		// The static twin: `Screen` instantiates `token`, whose builder builds `Detail`, where `token` is still being built. The alias
		// reads the enclosing declaration of `token`, which is unavailable there, in both builds alike.
		let fixture = Self.fixture(screen: ["@Instantiated let token: Secret"], left: nil, detail: [Self.selfAlias], reader: nil, secret: ["@Instantiated let detailBuilder: Instantiator<Detail>"])
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
			    public convenience init() {
			        func __safeDI_token() -> Secret {
			            func __safeDI_detailBuilder() -> Detail {
			                // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                return Detail(token: nil)
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
			        func __safeDI_screen() -> Screen {
			            func __safeDI_token() -> Secret {
			                func __safeDI_detailBuilder() -> Detail {
			                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                    return Detail(token: nil)
			                }
			                let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			                return Secret(detailBuilder: detailBuilder)
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
	mutating func generate_throwsUncreatedAliasErrorAtReaderOnly_whenReaderIsBeneathLabelKeepingOptionalAlias() async throws {
		// A reader beneath the alias reads it, which is error (1) at the reader: nothing is reported at the alias itself.
		let fixture = Self.fixture(detail: [Self.selfAlias, "@Instantiated let reader: Reader"], reader: ["@Received(onlyIfAvailable: true) let token: Secret?"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `token: Secret?` beneath the `onlyIfAvailable` alias `token` that `Detail` declares, which is not created where `token: Secret` is unavailable; built inline, `Reader` would then read whatever property named `token` is declared above `Detail`, or `nil`, depending on what encloses it. Give `Detail`'s alias a label other than `token` and receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead, or make the alias required.
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
			                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(token: nil)
			                    return Detail(token: nil, reader: reader)
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
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilForLabelKeepingOptionalAlias_whenFulfillingPropertyIsSiblingGeneratedLater() async throws {
		// `Left` instantiates `token` beside `detail`, and `Secret` receives `detail`, so `token` is generated after `Detail` is built:
		// the alias is not created, and `Detail` is passed `nil`, in both builds alike. `Left`'s `token` is the alias's own fulfilling
		// property, not a declaration of its label that inline would pass `Detail` in the alias's place.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated let token: Secret"], detail: [Self.selfAlias], reader: nil, secret: ["@Received let detail: Detail"])
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
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                return Detail(token: nil)
			            }
			            let detail: Detail = __safeDI_detail()
			            let token = Secret(detail: detail)
			            return Left(detail: detail, token: token)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
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
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                    return Detail(token: nil)
			                }
			                let detail: Detail = __safeDI_detail()
			                let token = Secret(detail: detail)
			                return Left(detail: detail, token: token)
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
	mutating func generate_passesNilForLabelKeepingExistentialAlias_whenFulfillingPropertyIsSiblingGeneratedLater() async throws {
		// The existential spelling: `auth: (any Auth)?` of `auth: any Auth`, which `Left` instantiates as `Secret` after `Detail`.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated(fulfilledByType: \"Secret\") let auth: any Auth"], detail: [Self.existentialSelfAlias], reader: nil, secret: ["@Received let detail: Detail"], secretConformances: ", Auth", otherTypes: [Self.authProtocol])
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
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                // Did not create `auth: (any Auth)?` because `auth: any Auth` is unavailable.
			                return Detail(auth: nil)
			            }
			            let detail: Detail = __safeDI_detail()
			            let auth: any Auth = Secret(detail: detail)
			            return Left(detail: detail, auth: auth)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
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
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `auth: (any Auth)?` because `auth: any Auth` is unavailable.
			                    return Detail(auth: nil)
			                }
			                let detail: Detail = __safeDI_detail()
			                let auth: any Auth = Secret(detail: detail)
			                return Left(detail: detail, auth: auth)
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
	mutating func generate_passesNilForLabelKeepingInstantiatorAlias_whenFulfillingPropertyIsSiblingGeneratedLater() async throws {
		// A label-keeping alias of `Left`'s `tokenBuilder: Instantiator<Secret>`, whose builder function is declared after `detail`.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated let tokenBuilder: Instantiator<Secret>"], detail: ["@Received(fulfilledByDependencyNamed: \"tokenBuilder\", ofType: Instantiator<Secret>.self, onlyIfAvailable: true) let tokenBuilder: Instantiator<Secret>?"], reader: nil, secret: ["@Received let detail: Detail"])
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
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                // Did not create `tokenBuilder: Instantiator<Secret>?` because `tokenBuilder: Instantiator<Secret>` is unavailable.
			                return Detail(tokenBuilder: nil)
			            }
			            let detail: Detail = __safeDI_detail()
			            func __safeDI_tokenBuilder() -> Secret {
			                Secret(detail: detail)
			            }
			            let tokenBuilder = Instantiator<Secret>(__safeDI_tokenBuilder)
			            return Left(detail: detail, tokenBuilder: tokenBuilder)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
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
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `tokenBuilder: Instantiator<Secret>?` because `tokenBuilder: Instantiator<Secret>` is unavailable.
			                    return Detail(tokenBuilder: nil)
			                }
			                let detail: Detail = __safeDI_detail()
			                func __safeDI_tokenBuilder() -> Secret {
			                    Secret(detail: detail)
			                }
			                let tokenBuilder = Instantiator<Secret>(__safeDI_tokenBuilder)
			                return Left(detail: detail, tokenBuilder: tokenBuilder)
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
	mutating func generate_passesNilForLabelKeepingLazilyInstantiatedAlias_whenFulfillingPropertyIsSiblingGeneratedLater() async throws {
		// A label-keeping alias of `Left`'s `token: LazilyInstantiated<Secret>`, generated after `detail`.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated let token: LazilyInstantiated<Secret>"], detail: ["@Received(fulfilledByDependencyNamed: \"token\", ofType: LazilyInstantiated<Secret>.self, onlyIfAvailable: true) let token: LazilyInstantiated<Secret>?"], reader: nil, secret: ["@Received let detail: Detail"])
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
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                // Did not create `token: LazilyInstantiated<Secret>?` because `token: LazilyInstantiated<Secret>` is unavailable.
			                return Detail(token: nil)
			            }
			            let detail: Detail = __safeDI_detail()
			            func __safeDI_token() -> Secret {
			                Secret(detail: detail)
			            }
			            let token = LazilyInstantiated<Secret>(__safeDI_token)
			            return Left(detail: detail, token: token)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
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
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `token: LazilyInstantiated<Secret>?` because `token: LazilyInstantiated<Secret>` is unavailable.
			                    return Detail(token: nil)
			                }
			                let detail: Detail = __safeDI_detail()
			                func __safeDI_token() -> Secret {
			                    Secret(detail: detail)
			                }
			                let token = LazilyInstantiated<Secret>(__safeDI_token)
			                return Left(detail: detail, token: token)
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
	mutating func generate_createsLabelKeepingOptionalAlias_whenFulfillingPropertyIsBuildersRequiredAliasOfSiblingGeneratedLater() async throws {
		// `Left`'s own required alias `token: Secret` of `secret`, generated after `detail`, is the alias's fulfilling property: the alias is
		// not created, and `Left` binds its alias after `secret`.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated let secret: Secret", "@Received(fulfilledByDependencyNamed: \"secret\", ofType: Secret.self) let token: Secret"], detail: [Self.selfAlias], reader: nil, secret: ["@Received let detail: Detail"])
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
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                return Detail(token: nil)
			            }
			            let detail: Detail = __safeDI_detail()
			            let secret = Secret(detail: detail)
			            #sourceLocation(file: "\(output.fixtures["Left.swift"])", line: 11)
			            let token: Secret = secret
			            #sourceLocation()
			            return Left(detail: detail, secret: secret, token: token)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
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
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                    return Detail(token: nil)
			                }
			                let detail: Detail = __safeDI_detail()
			                let secret = Secret(detail: detail)
			                #sourceLocation(file: "\(inlineOutput.fixtures["Left.swift"])", line: 11)
			                let token: Secret = secret
			                #sourceLocation()
			                return Left(detail: detail, secret: secret, token: token)
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
	mutating func generate_passesNilForLabelKeepingOptionalAlias_whenSeamItselfBuildsDeclaringTypeBesideFulfillingSiblingGeneratedLater() async throws {
		// The builder is the seam itself: `Left` is the seam, with no `Screen` above it.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let left: Left"]),
			seamFixtureType(named: "Left", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let detail: Detail", "@Instantiated let token: Secret"]),
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: [Self.selfAlias]),
			seamFixtureType(named: "Secret", isFinalClass: true, declarations: ["@Received let detail: Detail"]),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Left+SafeDI.swift": generatedFileHeader + """
			extension Left {
			    public convenience init() {
			        func __safeDI_detail() -> Detail {
			            // Did not create `token: Secret?` because `token: Secret` is unavailable.
			            return Detail(token: nil)
			        }
			        let detail: Detail = __safeDI_detail()
			        let token = Secret(detail: detail)
			        self.init(detail: detail, token: token)
			    }
			}

			extension Left {
			    public enum __safeDI_Left_CBF29CE484222325 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            _ = Left.__safeDI_Left_CBF29CE484222325.self
			            return Left()
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                return Detail(token: nil)
			            }
			            let detail: Detail = __safeDI_detail()
			            let token = Secret(detail: detail)
			            return Left(detail: detail, token: token)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsReaderErrorOnce_whenReaderReceivesLabelKeepingOptionalAliasWhoseFulfillingPropertyIsSiblingGeneratedLater() async throws {
		// A reader beneath the alias is rejected at the reader alone: `Left`'s `token` is the alias's own fulfilling property, not a
		// declaration of its label that would reach `Detail` in the alias's place. Inline, the reader is passed `nil`.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated let token: Secret"], detail: [Self.selfAlias, "@Instantiated let reader: Reader"], reader: ["@Received(onlyIfAvailable: true) let token: Secret?"], secret: ["@Received let detail: Detail"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Reader` receives `token: Secret?` beneath the `onlyIfAvailable` alias `token` that `Detail` declares, which is not created where `token: Secret` is generated later; built inline, `Reader` would then read whatever property named `token` is declared above `Detail`, or `nil`, depending on what encloses it. Give `Detail`'s alias a label other than `token` and receive `@Received(onlyIfAvailable: true) let token: Secret?` on `Reader` instead.
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
			                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                    let reader = Reader(token: nil)
			                    return Detail(token: nil, reader: reader)
			                }
			                let detail: Detail = __safeDI_detail()
			                let token = Secret(detail: detail)
			                return Left(detail: detail, token: token)
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilForLabelKeepingOptionalAliasAcrossModules_whenFulfillingPropertyIsSiblingGeneratedLater(integration: MultiModuleIntegration) async throws {
		// `Detail` and `Secret` in `Core`, `Left` and the seam in `Feature`, `Root` in `App`: the same bodies in each module's file.
		let fixture = Self.fixture(left: ["@Instantiated let detail: Detail", "@Instantiated let token: Secret"], detail: [Self.selfAlias], reader: nil, secret: ["@Received let detail: Detail"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamUncreatedAliasTests.threeModules(fixture), integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Screen {
				    public convenience init() {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                // Did not create `token: Secret?` because `token: Secret` is unavailable.
				                return Detail(token: nil)
				            }
				            let detail: Detail = __safeDI_detail()
				            let token = Secret(detail: detail)
				            return Left(detail: detail, token: token)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_CBF29CE484222325 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Screen {
				    public convenience init() {
				        func __safeDI_left() -> Left {
				            func __safeDI_detail() -> Detail {
				                // Did not create `token: Secret?` because `token: Secret` is unavailable.
				                return Detail(token: nil)
				            }
				            let detail: Detail = __safeDI_detail()
				            let token = Secret(detail: detail)
				            return Left(detail: detail, token: token)
				        }
				        let left: Left = __safeDI_left()
				        self.init(left: left)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_CBF29CE484222325 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen()
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_CBF29CE484222325.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen()
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		let expectedCoreFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: ["Core.swift": generatedFileHeader],
			.swiftPackagePlugin: [:],
		]
		#expect(try #require(output.modules["Core"]).generatedFiles == expectedCoreFiles[integration])
		if compileVerificationIsEnabled {
			#expect(try #require(output.compilation).modules.map(\.exitCode) == [0, 0, 0])
		}
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamUncreatedAliasTests.threeModules(inlineFixture(fixture)), integration: integration, filesToDelete: &filesToDelete)
		let expectedInlineFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif


				""",
			],
			.swiftPackagePlugin: [:],
		]
		#expect(try #require(inlineOutput.modules["Feature"]).generatedFiles == expectedInlineFeatureFiles[integration])
		let expectedInlineAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
				                    return Detail(token: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                let token = Secret(detail: detail)
				                return Left(detail: detail, token: token)
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
			.swiftPackagePlugin: [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            func __safeDI_left() -> Left {
				                func __safeDI_detail() -> Detail {
				                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
				                    return Detail(token: nil)
				                }
				                let detail: Detail = __safeDI_detail()
				                let token = Secret(detail: detail)
				                return Left(detail: detail, token: token)
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
		#expect(try #require(inlineOutput.modules["App"]).generatedFiles == expectedInlineAppFiles[integration])
		if compileVerificationIsEnabled {
			#expect(try #require(inlineOutput.compilation).modules.map(\.exitCode) == [0, 0, 0])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsAliasErrorAtAliasOfLabelKeepingOptionalAlias_whenCallerHoldsNothing() async throws {
		// `Detail` aliases its label-keeping alias as `bearer`: an alias of an alias that may not be created, reported at `bearer` alone, since
		// the label-keeping alias is no alias of itself. Inline, nothing provides `token`, so both are `nil`. The error is the one the fuzzer's
		// oracle must not take for an alias reading itself: it names the new alias's label, not the alias's own.
		let fixture = Self.fixture(detail: [Self.selfAlias, "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret?.self, onlyIfAvailable: true) let bearer: Secret?"], reader: nil)
		var thrownDiagnostics = ""
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):9:5: error: SafeDI cannot generate the dependency tree of `Screen`: `Detail` aliases `token: Secret?` as `bearer`, and `token` is an `onlyIfAvailable` alias that is not created where `token: Secret` is unavailable; built inline, `bearer` would then be created from whatever property named `token` is declared above `Detail`, or not at all, depending on what encloses it. Give `Detail`'s alias a label other than `token` and alias `token` as `bearer` with `onlyIfAvailable: true` instead, or make `token` required.
			"""
		}) {
			do {
				return try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			} catch let error as SafeDIToolTestError {
				thrownDiagnostics = "\(error.underlyingError)"
				throw error
			}
		}
		// The fuzzer's oracle for an alias rejected as an alias of itself keys on the generator's wording: false on this message, which
		// names another label, and true once the new alias is spelled under the alias's own label.
		let message = try #require(thrownDiagnostics.split(separator: "\n").first(where: { $0.contains(": error: ") }))
		#expect(!GraphFuzzerOracle.isUncreatedAliasErrorOfAliasReadingItself(message))
		#expect(GraphFuzzerOracle.isUncreatedAliasErrorOfAliasReadingItself(Substring(message.replacingOccurrences(of: "as `bearer`", with: "as `token`"))))
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            func __safeDI_left() -> Left {
			                func __safeDI_detail() -> Detail {
			                    // Did not create `token: Secret?` because `token: Secret` is unavailable.
			                    // Did not create `bearer: Secret?` because `token: Secret?` is unavailable.
			                    return Detail(token: nil, bearer: nil)
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
		])
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRequiredAliasOfLabelKeepingOptionalAliasIsDeclaredOnTheSameType(seam: Bool) async {
		// A required alias of the label-keeping alias: rejected by both builds, by main's own rule.
		let fixture = Self.fixture(detail: [Self.selfAlias, "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret?.self) let bearer: Secret?"], reader: nil)
		await assertThrowsError(diagnostics: { fixtures in
			// Both builds report production's error, so one text serves the seam and its inline twin.
			"""
			\(fixtures["Detail.swift"]):9:5: error: @Received property `token: Secret?` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Left -> Detail. `token: Secret?` is created by `Detail` only if `token: Secret` is available, and `token: Secret` is not @Instantiated or @Forwarded in chain. Did you mean to receive this property with `onlyIfAvailable: true`?
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: seam ? fixture : inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// An `onlyIfAvailable` alias that keeps the label of its fulfilling property and only makes it optional.
	private static let selfAlias = "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let token: Secret?"
	private static let existentialSelfAlias = "@Received(fulfilledByDependencyNamed: \"auth\", ofType: (any Auth).self, onlyIfAvailable: true) let auth: (any Auth)?"
	private static let authProtocol = "public protocol Auth {}"
	private static let host = seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let token: Secret?", "@Instantiated let screen: Screen"])
	private static let right = seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Received let token: Secret?"])

	private static func fixture(
		rootHolds: [String] = [],
		rootBuilds: String = "@Instantiated let screen: Screen",
		screen: [String] = ["@Instantiated let left: Left"],
		left: [String]? = ["@Instantiated let detail: Detail"],
		detail: [String]?,
		reader: [String]?,
		secret: [String] = [],
		secretConformances: String = "",
		otherTypes: [String] = [],
	) -> [String] {
		SafeDIToolSeamUncreatedAliasTests.fixture(rootHolds: rootHolds, rootBuilds: rootBuilds, screen: screen, left: left, detail: detail, reader: reader, secret: secret, secretConformances: secretConformances, otherTypes: otherTypes)
	}
}
