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

/// The remedy of the error for a wrapper that is not `Sendable` captured by a `@Sendable` builder function names every
/// declaration of the wrapper that reaches the receiver, in source order, so that following it clears every error at
/// that receive rather than moving the error to the next declaration. Each remedy is then applied, and the remedied
/// graph generates and compiles.
struct SafeDIToolCodeGenerationSendableCaptureRemedyTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Several roots declare the wrapper

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_namesEveryDeclarationInSourceOrder_whenThreeRootsDeclareErasedInstantiatorThatSendableBuilderReceiverCaptures() async {
		// The roots are declared in `A.swift`, `B.swift` and `C.swift` in the order `Root2`, `Root0`, `Root1`, so a
		// list in name order would differ from the source order the remedy names them in.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: ErasedInstantiator<(), AnyChild>` cannot be received inside a `@Sendable` function in chain: Root0 -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Root0` in a `@Sendable` function, which cannot capture `childBuilder: ErasedInstantiator<(), AnyChild>` on `Root0`, because `ErasedInstantiator<(), AnyChild>` is not `Sendable`. Declare `childBuilder` on `Root2`, `Root0`, and `Root1`, and this property, as `SendableErasedInstantiator<(), AnyChild>` to fix. `SendableErasedInstantiator<(), AnyChild>` builds `AnyChild` in a `@Sendable` function, so what the tree of `AnyChild` receives from outside that function must be `Sendable` too.
				\(fixtures["B.swift"]):7:5: note: `childBuilder: ErasedInstantiator<(), AnyChild>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: ErasedInstantiator<(), AnyChild>` cannot be received inside a `@Sendable` function in chain: Root1 -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Root1` in a `@Sendable` function, which cannot capture `childBuilder: ErasedInstantiator<(), AnyChild>` on `Root1`, because `ErasedInstantiator<(), AnyChild>` is not `Sendable`. Declare `childBuilder` on `Root2`, `Root0`, and `Root1`, and this property, as `SendableErasedInstantiator<(), AnyChild>` to fix. `SendableErasedInstantiator<(), AnyChild>` builds `AnyChild` in a `@Sendable` function, so what the tree of `AnyChild` receives from outside that function must be `Sendable` too.
				\(fixtures["C.swift"]):7:5: note: `childBuilder: ErasedInstantiator<(), AnyChild>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: ErasedInstantiator<(), AnyChild>` cannot be received inside a `@Sendable` function in chain: Root2 -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Root2` in a `@Sendable` function, which cannot capture `childBuilder: ErasedInstantiator<(), AnyChild>` on `Root2`, because `ErasedInstantiator<(), AnyChild>` is not `Sendable`. Declare `childBuilder` on `Root2`, `Root0`, and `Root1`, and this property, as `SendableErasedInstantiator<(), AnyChild>` to fix. `SendableErasedInstantiator<(), AnyChild>` builds `AnyChild` in a `@Sendable` function, so what the tree of `AnyChild` receives from outside that function must be `Sendable` too.
				\(fixtures["A.swift"]):7:5: note: `childBuilder: ErasedInstantiator<(), AnyChild>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init() {}
					}

					public final class AnyChild {
					    public init(_ child: Child) {}
					}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(childBuilder: ErasedInstantiator<(), AnyChild>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let childBuilder: ErasedInstantiator<(), AnyChild>
					}
					""",
				],
				swiftFileContentByFilePath: [
					"A.swift": """
					@Instantiable(isRoot: true)
					public final class Root2: Instantiable {
					    public init(childBuilder: ErasedInstantiator<(), AnyChild>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<(), AnyChild>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"B.swift": """
					@Instantiable(isRoot: true)
					public final class Root0: Instantiable {
					    public init(childBuilder: ErasedInstantiator<(), AnyChild>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<(), AnyChild>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"C.swift": """
					@Instantiable(isRoot: true)
					public final class Root1: Instantiable {
					    public init(childBuilder: ErasedInstantiator<(), AnyChild>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<(), AnyChild>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
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
	mutating func run_generatesCode_whenThreeRootsDeclareSendableErasedInstantiatorThatSendableBuilderReceiverReceives() async throws {
		// The remedy above, applied: every declaration it names, and the receive, are `SendableErasedInstantiator`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}

				public final class AnyChild {
				    public init(_ child: Child) {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(childBuilder: SendableErasedInstantiator<(), AnyChild>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let childBuilder: SendableErasedInstantiator<(), AnyChild>
				}
				""",
			],
			swiftFileContentByFilePath: [
				"A.swift": """
				@Instantiable(isRoot: true)
				public final class Root2: Instantiable {
				    public init(childBuilder: SendableErasedInstantiator<(), AnyChild>, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: SendableErasedInstantiator<(), AnyChild>
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"B.swift": """
				@Instantiable(isRoot: true)
				public final class Root0: Instantiable {
				    public init(childBuilder: SendableErasedInstantiator<(), AnyChild>, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: SendableErasedInstantiator<(), AnyChild>
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"C.swift": """
				@Instantiable(isRoot: true)
				public final class Root1: Instantiable {
				    public init(childBuilder: SendableErasedInstantiator<(), AnyChild>, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: SendableErasedInstantiator<(), AnyChild>
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"A+SafeDI.swift": generatedFileHeader + """
			extension Root2 {
			    public convenience init() {
			        @Sendable func __safeDI_childBuilder() -> Child {
			            Child()
			        }
			        let childBuilder = SendableErasedInstantiator<(), AnyChild> {
			            AnyChild(__safeDI_childBuilder())
			        }
			        @Sendable func __safeDI_settingsBuilder() -> Settings {
			            Settings(childBuilder: childBuilder)
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        self.init(childBuilder: childBuilder, settingsBuilder: settingsBuilder)
			    }
			}
			""",
			"B+SafeDI.swift": generatedFileHeader + """
			extension Root0 {
			    public convenience init() {
			        @Sendable func __safeDI_childBuilder() -> Child {
			            Child()
			        }
			        let childBuilder = SendableErasedInstantiator<(), AnyChild> {
			            AnyChild(__safeDI_childBuilder())
			        }
			        @Sendable func __safeDI_settingsBuilder() -> Settings {
			            Settings(childBuilder: childBuilder)
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        self.init(childBuilder: childBuilder, settingsBuilder: settingsBuilder)
			    }
			}
			""",
			"C+SafeDI.swift": generatedFileHeader + """
			extension Root1 {
			    public convenience init() {
			        @Sendable func __safeDI_childBuilder() -> Child {
			            Child()
			        }
			        let childBuilder = SendableErasedInstantiator<(), AnyChild> {
			            AnyChild(__safeDI_childBuilder())
			        }
			        @Sendable func __safeDI_settingsBuilder() -> Settings {
			            Settings(childBuilder: childBuilder)
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        self.init(childBuilder: childBuilder, settingsBuilder: settingsBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_namesBothDeclarations_whenTwoRootsDeclareLazilyInstantiatedPropertyWhoseInstanceSendableBuilderReceiverReceives() async {
		// The receiver takes the instance, so the remedy changes only the declarations, not the receive.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `analytics: Analytics` cannot be received inside a `@Sendable` function in chain: Root0 -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Root0` in a `@Sendable` function, which cannot capture `analytics: LazilyInstantiated<Analytics>` on `Root0`, because `LazilyInstantiated<Analytics>` is not `Sendable`. Declare `analytics` on `Root0` and `Root1` as `SendableLazilyInstantiated<Analytics>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Analytics`, to be `Sendable`.
				\(fixtures["Root0.swift"]):7:5: note: `analytics: LazilyInstantiated<Analytics>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `analytics: Analytics` cannot be received inside a `@Sendable` function in chain: Root1 -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Root1` in a `@Sendable` function, which cannot capture `analytics: LazilyInstantiated<Analytics>` on `Root1`, because `LazilyInstantiated<Analytics>` is not `Sendable`. Declare `analytics` on `Root0` and `Root1` as `SendableLazilyInstantiated<Analytics>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Analytics`, to be `Sendable`.
				\(fixtures["Root1.swift"]):7:5: note: `analytics: LazilyInstantiated<Analytics>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root0: Instantiable {
					    public init(analytics: LazilyInstantiated<Analytics>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let analytics: LazilyInstantiated<Analytics>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable(isRoot: true)
					public final class Root1: Instantiable {
					    public init(analytics: LazilyInstantiated<Analytics>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let analytics: LazilyInstantiated<Analytics>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class Analytics: Instantiable, Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(analytics: Analytics) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let analytics: Analytics
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
	mutating func run_generatesCode_whenTwoRootsDeclareSendableLazilyInstantiatedPropertyWhoseInstanceSendableBuilderReceiverReceives() async throws {
		// The remedy above, applied: both declarations it names are `SendableLazilyInstantiated`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root0: Instantiable {
				    public init(analytics: SendableLazilyInstantiated<Analytics>, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let analytics: SendableLazilyInstantiated<Analytics>
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class Root1: Instantiable {
				    public init(analytics: SendableLazilyInstantiated<Analytics>, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let analytics: SendableLazilyInstantiated<Analytics>
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"""
				@Instantiable
				public final class Analytics: Instantiable, Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(analytics: Analytics) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let analytics: Analytics
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root0+SafeDI.swift": generatedFileHeader + """
			extension Root0 {
			    public convenience init() {
			        @Sendable func __safeDI_analytics() -> Analytics {
			            Analytics()
			        }
			        let analytics = SendableLazilyInstantiated<Analytics>(__safeDI_analytics)
			        @Sendable func __safeDI_settingsBuilder() -> Settings {
			            Settings(analytics: analytics.instance)
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        self.init(analytics: analytics, settingsBuilder: settingsBuilder)
			    }
			}
			""",
			"Root1+SafeDI.swift": generatedFileHeader + """
			extension Root1 {
			    public convenience init() {
			        @Sendable func __safeDI_analytics() -> Analytics {
			            Analytics()
			        }
			        let analytics = SendableLazilyInstantiated<Analytics>(__safeDI_analytics)
			        @Sendable func __safeDI_settingsBuilder() -> Settings {
			            Settings(analytics: analytics.instance)
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        self.init(analytics: analytics, settingsBuilder: settingsBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Tests – Several types in one root's tree declare the wrapper

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_namesBothDeclarations_whenSiblingsInOneTreeDeclareInstantiatorThatSendableBuilderReceiverCaptures() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> ScreenA -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `ScreenA` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `ScreenA`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `ScreenA` and `ScreenB`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["ScreenA.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> ScreenB -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `ScreenB` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `ScreenB`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `ScreenA` and `ScreenB`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["ScreenB.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(screenA: ScreenA, screenB: ScreenB) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let screenA: ScreenA
					    @Instantiated let screenB: ScreenB
					}
					""",
					"""
					@Instantiable
					public final class ScreenA: Instantiable {
					    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let childBuilder: Instantiator<Child>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class ScreenB: Instantiable {
					    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let childBuilder: Instantiator<Child>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(childBuilder: Instantiator<Child>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let childBuilder: Instantiator<Child>
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
	mutating func run_generatesCode_whenSiblingsInOneTreeDeclareSendableInstantiatorThatSendableBuilderReceiverReceives() async throws {
		// The remedy above, applied: both declarations it names, and the receive, are `SendableInstantiator`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(screenA: ScreenA, screenB: ScreenB) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let screenA: ScreenA
				    @Instantiated let screenB: ScreenB
				}
				""",
				"""
				@Instantiable
				public final class ScreenA: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let childBuilder: SendableInstantiator<Child>
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"""
				@Instantiable
				public final class ScreenB: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let childBuilder: SendableInstantiator<Child>
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let childBuilder: SendableInstantiator<Child>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenA() -> ScreenA {
			            @Sendable func __safeDI_childBuilder() -> Child {
			                Child()
			            }
			            let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			            @Sendable func __safeDI_settingsBuilder() -> Settings {
			                Settings(childBuilder: childBuilder)
			            }
			            let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			            return ScreenA(childBuilder: childBuilder, settingsBuilder: settingsBuilder)
			        }
			        let screenA: ScreenA = __safeDI_screenA()
			        func __safeDI_screenB() -> ScreenB {
			            @Sendable func __safeDI_childBuilder() -> Child {
			                Child()
			            }
			            let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			            @Sendable func __safeDI_settingsBuilder() -> Settings {
			                Settings(childBuilder: childBuilder)
			            }
			            let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			            return ScreenB(childBuilder: childBuilder, settingsBuilder: settingsBuilder)
			        }
			        let screenB: ScreenB = __safeDI_screenB()
			        self.init(screenA: screenA, screenB: screenB)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_namesDeclarationOnce_whenTwoSendableBuildersInOneTreeCaptureOneDeclaration() async {
		// Two chains reach the receive, each capturing the one declaration on `Root`, which the remedy names once.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> ScreenA -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `ScreenA` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `Root`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `Root`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> ScreenB -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `ScreenB` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `Root`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `Root`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(childBuilder: Instantiator<Child>, screenA: ScreenA, screenB: ScreenB) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let childBuilder: Instantiator<Child>
					    @Instantiated let screenA: ScreenA
					    @Instantiated let screenB: ScreenB
					}
					""",
					"""
					@Instantiable
					public final class ScreenA: Instantiable {
					    public init(settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class ScreenB: Instantiable {
					    public init(settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(childBuilder: Instantiator<Child>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let childBuilder: Instantiator<Child>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – The tree receives the wrapper from outside it

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesOnlyTypeThatDeclaresWrapper_whenAnotherMockRootReceivesWrapperFromOutsideItsTree() async {
		// `Root`'s mock captures the `analytics` `Root` forwards, and `Screen`'s mock the one its tree receives from
		// outside it, both at `Settings`. The remedy that names a declaration names `Root` alone, since changing it and
		// the receive leaves `Screen`'s mock receiving a `Sendable` wrapper too; the other keeps its words.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `analytics: LazilyInstantiated<Analytics>` cannot be received inside a `@Sendable` function in chain: Root -> Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `analytics: LazilyInstantiated<Analytics>` on `Root`, because `LazilyInstantiated<Analytics>` is not `Sendable`. Declare `analytics` on `Root`, and this property, as `SendableLazilyInstantiated<Analytics>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Analytics`, to be `Sendable`.
				\(fixtures["Root.swift"]):7:5: note: `analytics: LazilyInstantiated<Analytics>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `analytics: LazilyInstantiated<Analytics>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `analytics: LazilyInstantiated<Analytics>`, which the tree of `Screen` receives from outside it, because `LazilyInstantiated<Analytics>` is not `Sendable`. Declare `analytics` as `SendableLazilyInstantiated<Analytics>` where it is declared and where it is received as `LazilyInstantiated<Analytics>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Analytics`, to be `Sendable`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    public init(analytics: LazilyInstantiated<Analytics>, screen: Screen) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let analytics: LazilyInstantiated<Analytics>
					    @Instantiated let screen: Screen
					}

					public protocol Analytics: Sendable {}
					""",
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(analytics: LazilyInstantiated<Analytics>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let analytics: LazilyInstantiated<Analytics>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	private var filesToDelete: [URL]
}
