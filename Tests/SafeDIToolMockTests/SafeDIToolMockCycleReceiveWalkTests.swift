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

/// A mock root binds every value its tree receives from above it, wherever in the tree the receive is. In a graph of
/// screens that open one another, the walk that finds those values reaches a screen again through another path, and
/// must not reuse what an earlier, unfinished walk of it found: here `Screen7` is walked first beneath `Screen4`, before
/// `Screen4`'s walk has found that `Screen6`, beneath `Screen2`, receives `context`, and again as `Screen0`'s own child.
struct SafeDIToolMockCycleReceiveWalkTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesItsOverrideToTheScreenBuiltAgain_whenTheScreenReceivesItOnlyIfAvailableThroughACycleWalkedEarlier() async throws {
		// `Screen0` → `Screen7` → `Screen4` → `Screen2` → `Screen6` declares no `context`, so `Screen6` reads the one the mock
		// root binds. A mock that judged `Screen7`'s tree by the walk of it beneath `Screen4` passed `Screen7`'s builder
		// function `nil`, and the binding went unread.
		let fixture = Self.screens(screen6ReceivesContext: "@Received(onlyIfAvailable: true) let context: Context?")
			+ [
				"""
				public func screen6ReceivesTheOverride() -> String {
				    let context = Context()
				    let screen6 = Screen0.mock(safeDIOverrides: .init(context: context))
				        .screen7Builder.instantiate()
				        .screen4Builder.instantiate()
				        .screen2Builder.instantiate()
				        .screen6Builder.instantiate()
				    return "\\(screen6.context === context)"
				}
				""",
			]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: fixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles["Screen0+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen0 {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen5Builder: Screen5.SafeDIMockConfiguration = .init(),
		            screen7Builder: Screen7.SafeDIMockConfiguration = .init(),
		            context: Context? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen5Builder: screen5Builder,
		                screen7Builder: screen7Builder
		            )
		            self.context = context
		        }

		        var screen5Builder: Screen5.SafeDIMockConfiguration { __safeDI_storage.screen5Builder }
		        var screen7Builder: Screen7.SafeDIMockConfiguration { __safeDI_storage.screen7Builder }
		        let context: Context?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen5Builder: Screen5.SafeDIMockConfiguration,
		                screen7Builder: Screen7.SafeDIMockConfiguration
		            ) {
		                self.screen5Builder = screen5Builder
		                self.screen7Builder = screen7Builder
		            }

		            let screen5Builder: Screen5.SafeDIMockConfiguration
		            let screen7Builder: Screen7.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen0 {
		        let context: Context? = safeDIOverrides.context
		        func __safeDI_screen5Builder() -> Screen5 {
		            let context = if let safeDIBuilder = safeDIOverrides.screen5Builder.context { safeDIBuilder() } else { Context() }
		            func __safeDI_screen3Builder() -> Screen3 {
		                func __safeDI_screen6Builder() -> Screen6 {
		                    func __safeDI_screen4Builder() -> Screen4 {
		                        func __safeDI_screen2Builder() -> Screen2 {
		                            let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                            return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.screen4Builder.screen2Builder.safeDIBuilder { safeDIBuilder(screen6Builder) } else { Screen2(screen6Builder: screen6Builder) }
		                        }
		                        let screen2Builder = Instantiator<Screen2>(__safeDI_screen2Builder)
		                        func __safeDI_screen7Builder() -> Screen7 {
		                            func __safeDI_screen0Builder() -> Screen0 {
		                                let screen5Builder = Instantiator<Screen5>(__safeDI_screen5Builder)
		                                let screen7Builder = Instantiator<Screen7>(__safeDI_screen7Builder)
		                                return Screen0(screen5Builder: screen5Builder, screen7Builder: screen7Builder)
		                            }
		                            let screen0Builder = Instantiator<Screen0>(__safeDI_screen0Builder)
		                            let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                            return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.screen4Builder.screen7Builder.safeDIBuilder { safeDIBuilder(screen0Builder, screen4Builder) } else { Screen7(screen0Builder: screen0Builder, screen4Builder: screen4Builder) }
		                        }
		                        let screen7Builder = Instantiator<Screen7>(__safeDI_screen7Builder)
		                        return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.screen4Builder.safeDIBuilder { safeDIBuilder(screen2Builder, screen7Builder) } else { Screen4(screen2Builder: screen2Builder, screen7Builder: screen7Builder) }
		                    }
		                    let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                    return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.safeDIBuilder { safeDIBuilder(context, screen4Builder) } else { Screen6(context: context, screen4Builder: screen4Builder) }
		                }
		                let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.safeDIBuilder { safeDIBuilder(screen6Builder) } else { Screen3(screen6Builder: screen6Builder) }
		            }
		            let screen3Builder = Instantiator<Screen3>(__safeDI_screen3Builder)
		            return if let safeDIBuilder = safeDIOverrides.screen5Builder.safeDIBuilder { safeDIBuilder(context, screen3Builder) } else { Screen5(context: context, screen3Builder: screen3Builder) }
		        }
		        let screen5Builder = Instantiator<Screen5>(__safeDI_screen5Builder)
		        func __safeDI_screen7Builder(context: Context?) -> Screen7 {
		            func __safeDI_screen0Builder() -> Screen0 {
		                func __safeDI_screen5Builder() -> Screen5 {
		                    let context = Context()
		                    func __safeDI_screen3Builder() -> Screen3 {
		                        func __safeDI_screen6Builder() -> Screen6 {
		                            func __safeDI_screen4Builder() -> Screen4 {
		                                func __safeDI_screen2Builder() -> Screen2 {
		                                    let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                                    return Screen2(screen6Builder: screen6Builder)
		                                }
		                                let screen2Builder = Instantiator<Screen2>(__safeDI_screen2Builder)
		                                let screen7Builder = Instantiator<Screen7> {
		                                    __safeDI_screen7Builder(context: context)
		                                }
		                                return Screen4(screen2Builder: screen2Builder, screen7Builder: screen7Builder)
		                            }
		                            let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                            return Screen6(context: context, screen4Builder: screen4Builder)
		                        }
		                        let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                        return Screen3(screen6Builder: screen6Builder)
		                    }
		                    let screen3Builder = Instantiator<Screen3>(__safeDI_screen3Builder)
		                    return Screen5(context: context, screen3Builder: screen3Builder)
		                }
		                let screen5Builder = Instantiator<Screen5>(__safeDI_screen5Builder)
		                let screen7Builder = Instantiator<Screen7> {
		                    __safeDI_screen7Builder(context: context)
		                }
		                return Screen0(screen5Builder: screen5Builder, screen7Builder: screen7Builder)
		            }
		            let screen0Builder = Instantiator<Screen0>(__safeDI_screen0Builder)
		            func __safeDI_screen4Builder() -> Screen4 {
		                func __safeDI_screen2Builder() -> Screen2 {
		                    func __safeDI_screen6Builder() -> Screen6 {
		                        let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                        return Screen6(context: context, screen4Builder: screen4Builder)
		                    }
		                    let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                    return Screen2(screen6Builder: screen6Builder)
		                }
		                let screen2Builder = Instantiator<Screen2>(__safeDI_screen2Builder)
		                let screen7Builder = Instantiator<Screen7> {
		                    __safeDI_screen7Builder(context: context)
		                }
		                return Screen4(screen2Builder: screen2Builder, screen7Builder: screen7Builder)
		            }
		            let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		            return if let safeDIBuilder = safeDIOverrides.screen7Builder.safeDIBuilder { safeDIBuilder(screen0Builder, screen4Builder) } else { Screen7(screen0Builder: screen0Builder, screen4Builder: screen4Builder) }
		        }
		        let screen7Builder = Instantiator<Screen7> {
		            __safeDI_screen7Builder(context: context)
		        }
		        return Screen0(screen5Builder: screen5Builder, screen7Builder: screen7Builder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen0 {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            screen5Builder: Screen5.SafeDIMockConfiguration = .init(),
		            screen7Builder: Screen7.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen5Builder: screen5Builder,
		                screen7Builder: screen7Builder,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var screen5Builder: Screen5.SafeDIMockConfiguration { __safeDI_storage.screen5Builder }
		        var screen7Builder: Screen7.SafeDIMockConfiguration { __safeDI_storage.screen7Builder }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen5Builder: Screen5.SafeDIMockConfiguration,
		                screen7Builder: Screen7.SafeDIMockConfiguration,
		                safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)?
		            ) {
		                self.screen5Builder = screen5Builder
		                self.screen7Builder = screen7Builder
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let screen5Builder: Screen5.SafeDIMockConfiguration
		            let screen7Builder: Screen7.SafeDIMockConfiguration
		            let safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)?
		        }
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen0+SafeDIMock.swift"] ?? "")")
		let fixtureFiles = Dictionary(uniqueKeysWithValues: fixture.enumerated().map { ("File\($0.offset).swift", $0.element) })
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			probes: [DifferentialValueProbe("screen6ReceivesTheOverride()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == "probe screen6ReceivesTheOverride()\nString \"true\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheValueAsAnOverride_whenAScreenRequiresItThroughACycleWalkedEarlier() async throws {
		// The mock builds a value its tree requires as an override, as it builds one a child requires outside a cycle. A
		// mock that judged `Screen7`'s tree by the walk of it beneath `Screen4` took `context` as a parameter instead.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.screens(screen6ReceivesContext: "@Received let context: Context"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles["Screen0+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen0 {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen5Builder: Screen5.SafeDIMockConfiguration = .init(),
		            context: (() -> Context)? = nil,
		            screen7Builder: Screen7.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen5Builder: screen5Builder,
		                context: context,
		                screen7Builder: screen7Builder
		            )
		        }

		        var screen5Builder: Screen5.SafeDIMockConfiguration { __safeDI_storage.screen5Builder }
		        var context: (() -> Context)? { __safeDI_storage.context }
		        var screen7Builder: Screen7.SafeDIMockConfiguration { __safeDI_storage.screen7Builder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen5Builder: Screen5.SafeDIMockConfiguration,
		                context: (() -> Context)?,
		                screen7Builder: Screen7.SafeDIMockConfiguration
		            ) {
		                self.screen5Builder = screen5Builder
		                self.context = context
		                self.screen7Builder = screen7Builder
		            }

		            let screen5Builder: Screen5.SafeDIMockConfiguration
		            let context: (() -> Context)?
		            let screen7Builder: Screen7.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen0 {
		        func __safeDI_screen5Builder() -> Screen5 {
		            let context = if let safeDIBuilder = safeDIOverrides.screen5Builder.context { safeDIBuilder() } else { Context() }
		            func __safeDI_screen3Builder() -> Screen3 {
		                func __safeDI_screen6Builder() -> Screen6 {
		                    func __safeDI_screen4Builder() -> Screen4 {
		                        func __safeDI_screen2Builder() -> Screen2 {
		                            let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                            return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.screen4Builder.screen2Builder.safeDIBuilder { safeDIBuilder(screen6Builder) } else { Screen2(screen6Builder: screen6Builder) }
		                        }
		                        let screen2Builder = Instantiator<Screen2>(__safeDI_screen2Builder)
		                        func __safeDI_screen7Builder() -> Screen7 {
		                            func __safeDI_screen0Builder() -> Screen0 {
		                                let screen5Builder = Instantiator<Screen5>(__safeDI_screen5Builder)
		                                let screen7Builder = Instantiator<Screen7>(__safeDI_screen7Builder)
		                                return Screen0(screen5Builder: screen5Builder, screen7Builder: screen7Builder)
		                            }
		                            let screen0Builder = Instantiator<Screen0>(__safeDI_screen0Builder)
		                            let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                            return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.screen4Builder.screen7Builder.safeDIBuilder { safeDIBuilder(screen0Builder, screen4Builder) } else { Screen7(screen0Builder: screen0Builder, screen4Builder: screen4Builder) }
		                        }
		                        let screen7Builder = Instantiator<Screen7>(__safeDI_screen7Builder)
		                        return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.screen4Builder.safeDIBuilder { safeDIBuilder(screen2Builder, screen7Builder) } else { Screen4(screen2Builder: screen2Builder, screen7Builder: screen7Builder) }
		                    }
		                    let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                    return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.screen6Builder.safeDIBuilder { safeDIBuilder(context, screen4Builder) } else { Screen6(context: context, screen4Builder: screen4Builder) }
		                }
		                let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                return if let safeDIBuilder = safeDIOverrides.screen5Builder.screen3Builder.safeDIBuilder { safeDIBuilder(screen6Builder) } else { Screen3(screen6Builder: screen6Builder) }
		            }
		            let screen3Builder = Instantiator<Screen3>(__safeDI_screen3Builder)
		            return if let safeDIBuilder = safeDIOverrides.screen5Builder.safeDIBuilder { safeDIBuilder(context, screen3Builder) } else { Screen5(context: context, screen3Builder: screen3Builder) }
		        }
		        let screen5Builder = Instantiator<Screen5>(__safeDI_screen5Builder)
		        let context = if let safeDIBuilder = safeDIOverrides.context { safeDIBuilder() } else { Context() }
		        func __safeDI_screen7Builder(context: Context) -> Screen7 {
		            func __safeDI_screen0Builder() -> Screen0 {
		                func __safeDI_screen5Builder() -> Screen5 {
		                    let context = Context()
		                    func __safeDI_screen3Builder() -> Screen3 {
		                        func __safeDI_screen6Builder() -> Screen6 {
		                            func __safeDI_screen4Builder() -> Screen4 {
		                                func __safeDI_screen2Builder() -> Screen2 {
		                                    let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                                    return Screen2(screen6Builder: screen6Builder)
		                                }
		                                let screen2Builder = Instantiator<Screen2>(__safeDI_screen2Builder)
		                                let screen7Builder = Instantiator<Screen7> {
		                                    __safeDI_screen7Builder(context: context)
		                                }
		                                return Screen4(screen2Builder: screen2Builder, screen7Builder: screen7Builder)
		                            }
		                            let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                            return Screen6(context: context, screen4Builder: screen4Builder)
		                        }
		                        let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                        return Screen3(screen6Builder: screen6Builder)
		                    }
		                    let screen3Builder = Instantiator<Screen3>(__safeDI_screen3Builder)
		                    return Screen5(context: context, screen3Builder: screen3Builder)
		                }
		                let screen5Builder = Instantiator<Screen5>(__safeDI_screen5Builder)
		                let screen7Builder = Instantiator<Screen7> {
		                    __safeDI_screen7Builder(context: context)
		                }
		                return Screen0(screen5Builder: screen5Builder, screen7Builder: screen7Builder)
		            }
		            let screen0Builder = Instantiator<Screen0>(__safeDI_screen0Builder)
		            func __safeDI_screen4Builder() -> Screen4 {
		                func __safeDI_screen2Builder() -> Screen2 {
		                    func __safeDI_screen6Builder() -> Screen6 {
		                        let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		                        return Screen6(context: context, screen4Builder: screen4Builder)
		                    }
		                    let screen6Builder = Instantiator<Screen6>(__safeDI_screen6Builder)
		                    return Screen2(screen6Builder: screen6Builder)
		                }
		                let screen2Builder = Instantiator<Screen2>(__safeDI_screen2Builder)
		                let screen7Builder = Instantiator<Screen7> {
		                    __safeDI_screen7Builder(context: context)
		                }
		                return Screen4(screen2Builder: screen2Builder, screen7Builder: screen7Builder)
		            }
		            let screen4Builder = Instantiator<Screen4>(__safeDI_screen4Builder)
		            return if let safeDIBuilder = safeDIOverrides.screen7Builder.safeDIBuilder { safeDIBuilder(screen0Builder, screen4Builder) } else { Screen7(screen0Builder: screen0Builder, screen4Builder: screen4Builder) }
		        }
		        let screen7Builder = Instantiator<Screen7> {
		            __safeDI_screen7Builder(context: context)
		        }
		        return Screen0(screen5Builder: screen5Builder, screen7Builder: screen7Builder)
		    }
		}
		#endif

		#if DEBUG
		extension Screen0 {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            screen5Builder: Screen5.SafeDIMockConfiguration = .init(),
		            screen7Builder: Screen7.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen5Builder: screen5Builder,
		                screen7Builder: screen7Builder,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var screen5Builder: Screen5.SafeDIMockConfiguration { __safeDI_storage.screen5Builder }
		        var screen7Builder: Screen7.SafeDIMockConfiguration { __safeDI_storage.screen7Builder }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen5Builder: Screen5.SafeDIMockConfiguration,
		                screen7Builder: Screen7.SafeDIMockConfiguration,
		                safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)?
		            ) {
		                self.screen5Builder = screen5Builder
		                self.screen7Builder = screen7Builder
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let screen5Builder: Screen5.SafeDIMockConfiguration
		            let screen7Builder: Screen7.SafeDIMockConfiguration
		            let safeDIBuilder: ((Instantiator<Screen5>, Instantiator<Screen7>) -> Screen0)?
		        }
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen0+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The screens: `Screen0`, which generates its mock, opens `Screen5`, which declares `context`, and `Screen7`; the
	/// screens beneath open one another, and `Screen6` receives `context` with `screen6ReceivesContext`.
	private static func screens(screen6ReceivesContext: String) -> [String] {
		[
			screen("Screen0", attributes: "(generateMock: true)", "@Instantiated let screen5Builder: Instantiator<Screen5>", "@Instantiated let screen7Builder: Instantiator<Screen7>"),
			screen("Screen2", "@Instantiated let screen6Builder: Instantiator<Screen6>"),
			screen("Screen3", "@Instantiated let screen6Builder: Instantiator<Screen6>"),
			screen("Screen4", "@Instantiated let screen2Builder: Instantiator<Screen2>", "@Instantiated let screen7Builder: Instantiator<Screen7>"),
			screen("Screen5", "@Instantiated let context: Context", "@Instantiated let screen3Builder: Instantiator<Screen3>"),
			screen("Screen6", screen6ReceivesContext, "@Instantiated let screen4Builder: Instantiator<Screen4>"),
			screen("Screen7", "@Instantiated let screen0Builder: Instantiator<Screen0>", "@Instantiated let screen4Builder: Instantiator<Screen4>"),
			"""
			@Instantiable
			public final class Context: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	/// A screen declaring `declarations`, each `<attribute> let <label>: <type>`, with an initializer that takes them all.
	private static func screen(_ name: String, attributes: String = "", _ declarations: String...) -> String {
		let parsed = declarations.map { declaration in
			let afterLet = declaration.components(separatedBy: " let ")[1]
			let parts = afterLet.components(separatedBy: ": ")
			return (label: parts[0], type: parts[1])
		}
		var lines = ["@Instantiable\(attributes)", "public final class \(name): Instantiable {"]
		lines.append("    public init(" + parsed.map { "\($0.label): \($0.type)" }.joined(separator: ", ") + ") {")
		lines += parsed.map { "        self.\($0.label) = \($0.label)" }
		lines += ["    }", ""]
		lines += declarations.map { "    \($0)" }
		lines.append("}")
		return lines.joined(separator: "\n")
	}
}
