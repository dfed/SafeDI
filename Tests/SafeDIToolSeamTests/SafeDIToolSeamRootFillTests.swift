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

/// A fill of a call of another module's seam that captures nothing of the call, binding only what its dispatcher hands
/// it, is declared once, at the top of the root that holds the call, however many paths reach it
/// (`ScopeGenerator.fillRootFunction`, `RootFunctionHoisting`). A fill that reads a value of the caller stays in each call.
/// Every cell compiles.
struct SafeDIToolSeamRootFillTests: ~Copyable {
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

	/// `Last` holds `screenBuilder`, a hole only `App` can fill, with `AppScreen`, which opens `Last` again: the fill
	/// re-enters its call, so it is a function of its own. The root opens `Last` and `AppScreen`, so the fill is reached on
	/// two paths, and the root declares it once, at its top.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillOnceAtTheRootsTop_whenFillReentersItsCallOnTwoPaths() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(readingToken: false), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		            return __safeDI_fillBody_A9A9FB6A5ED20C19(service: service)
		        }
		        func __safeDI_fillBody_A9A9FB6A5ED20C19(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		            func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                func __safeDI_lastBuilder(id: Int) -> Last {
		                    _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                    return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                }
		                let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                    AnyScreen(__safeDI_lastBuilder(id: $0))
		                }
		                return AppScreen(id: id, service: service, lastBuilder: lastBuilder)
		            }
		            return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		        }
		        func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		            .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		        }
		        let service = Service()
		        func __safeDI_lastBuilder(id: Int) -> Last {
		            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		        }
		        let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_lastBuilder(id: $0))
		        }
		        func __safeDI_screenBuilder(id: Int) -> AppScreen {
		            func __safeDI_lastBuilder(id: Int) -> Last {
		                _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		            }
		            let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                AnyScreen(__safeDI_lastBuilder(id: $0))
		            }
		            return AppScreen(id: id, service: service, lastBuilder: lastBuilder)
		        }
		        let screenBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_screenBuilder(id: $0))
		        }
		        self.init(service: service, lastBuilder: lastBuilder, screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	/// The same shape, but `AppScreen` receives `token`, which only the root declares: the fill reads the caller's `token`,
	/// so each call declares it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillInEachCall_whenFillThatReentersItsCallReadsCallersValue() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(readingToken: true), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        let token = Token()
		        func __safeDI_lastBuilder(id: Int) -> Last {
		            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		                func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                    func __safeDI_lastBuilder(id: Int) -> Last {
		                        _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                    }
		                    let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                        AnyScreen(__safeDI_lastBuilder(id: $0))
		                    }
		                    return AppScreen(id: id, service: service, lastBuilder: lastBuilder, token: token)
		                }
		                return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		            }
		            func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		                .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		            }
		            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		        }
		        let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_lastBuilder(id: $0))
		        }
		        func __safeDI_screenBuilder(id: Int) -> AppScreen {
		            func __safeDI_lastBuilder(id: Int) -> Last {
		                _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		                    func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                        func __safeDI_lastBuilder(id: Int) -> Last {
		                            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                        }
		                        let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                            AnyScreen(__safeDI_lastBuilder(id: $0))
		                        }
		                        return AppScreen(id: id, service: service, lastBuilder: lastBuilder, token: token)
		                    }
		                    return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		                }
		                func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		                    .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		                }
		                return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		            }
		            let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                AnyScreen(__safeDI_lastBuilder(id: $0))
		            }
		            return AppScreen(id: id, service: service, lastBuilder: lastBuilder, token: token)
		        }
		        let screenBuilder = ErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_screenBuilder(id: $0))
		        }
		        self.init(service: service, lastBuilder: lastBuilder, screenBuilder: screenBuilder, token: token)
		    }
		}
		""")
	}

	/// The root opens `Last` only in a `SendableErasedInstantiator`, whose `@Sendable` builder function declares `Last`'s
	/// fill, which is plain: the root cannot declare it at its top, where the `@Sendable` function would call a plain one, so
	/// the fill stays in the call.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillInItsCall_whenCallIsInsideSendableFunctionAndFillIsPlain() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(readingToken: false, opensLastInSendableWrapperOnly: true), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        @Sendable nonisolated func __safeDI_lastBuilder(id: Int) -> Last {
		            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		                func __safeDI_fillBody_A9A9FB6A5ED20C19(service: Service) -> ErasedInstantiator<Int, AnyScreen>.Builder {
		                    func __safeDI_screenBuilder(id: Int) -> AppScreen {
		                        func __safeDI_lastBuilder(id: Int) -> Last {
		                            _ = Last.__safeDI_Last_64640399A387E1E1.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		                        }
		                        let lastBuilder = ErasedInstantiator<Int, AnyScreen> {
		                            AnyScreen(__safeDI_lastBuilder(id: $0))
		                        }
		                        return AppScreen(id: id, service: service, lastBuilder: lastBuilder)
		                    }
		                    return { forwarded in AnyScreen(__safeDI_screenBuilder(id: forwarded)) }
		                }
		                return __safeDI_fillBody_A9A9FB6A5ED20C19(service: service)
		            }
		            func __safeDI_appScreen_AnyScreenBuilder_Last() -> Last.__safeDI_AppScreen_AnyScreenCarrier<AnyScreen> {
		                .init(screenBuilder: { values_id, values_service in __safeDI_appScreen_AnyScreenBuilder_Last_screenBuilder(service: values_service) })
		            }
		            return Last(__safeDI_id: id, __safeDI_service: service, __safeDI_appScreen_AnyScreenBuilder: __safeDI_appScreen_AnyScreenBuilder_Last())
		        }
		        let lastBuilder = SendableErasedInstantiator<Int, AnyScreen> {
		            AnyScreen(__safeDI_lastBuilder(id: $0))
		        }
		        self.init(service: service, lastBuilder: lastBuilder)
		    }
		}
		""")
	}

	// MARK: Fixtures

	/// `Last`, a seam whose `screenBuilder` only `App` can fill, and `App`, whose `AppScreen` fills it and opens `Last`
	/// again, and whose root opens both. Where `readingToken`, `AppScreen` receives `token`, which only the root declares.
	/// Where `opensLastInSendableWrapperOnly`, the root opens only `Last`, in a `SendableErasedInstantiator`.
	private static func screenModules(readingToken: Bool, opensLastInSendableWrapperOnly: Bool = false) -> [ModuleFixture] {
		let tokenParameter = readingToken ? ", token: Token" : ""
		let tokenAssignment = readingToken ? "; self.token = token" : ""
		let appScreenToken = readingToken ? "\n    @Received let token: Token" : ""
		let rootToken = readingToken ? "\n    @Instantiated let token: Token" : ""
		let root = opensLastInSendableWrapperOnly ? """
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(service: Service, lastBuilder: SendableErasedInstantiator<Int, AnyScreen>) {
		        self.service = service; self.lastBuilder = lastBuilder
		    }
		    @Instantiated let service: Service
		    @Instantiated(fulfilledByType: "Last", erasedToConcreteExistential: true) let lastBuilder: SendableErasedInstantiator<Int, AnyScreen>
		}
		""" : """
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(service: Service, lastBuilder: ErasedInstantiator<Int, AnyScreen>, screenBuilder: ErasedInstantiator<Int, AnyScreen>\(tokenParameter)) {
		        self.service = service; self.lastBuilder = lastBuilder; self.screenBuilder = screenBuilder\(tokenAssignment)
		    }
		    @Instantiated let service: Service
		    @Instantiated(fulfilledByType: "Last", erasedToConcreteExistential: true) let lastBuilder: ErasedInstantiator<Int, AnyScreen>
		    @Instantiated(fulfilledByType: "AppScreen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<Int, AnyScreen>\(rootToken)
		}
		"""
		return [
			ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
			import SafeDI

			public final class AnyScreen {
			    public init(_ screen: AnyObject) { self.screen = screen }
			    public let screen: AnyObject
			}

			@Instantiable
			public final class Service: Instantiable, Sendable {
			    public init() {}
			}

			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}

			@Instantiable(generateDependencyTree: true)
			public final class Last: Instantiable {
			    public init(id: Int, service: Service, screenBuilder: ErasedInstantiator<Int, AnyScreen>) {
			        self.id = id; self.service = service; self.screenBuilder = screenBuilder
			    }
			    @Forwarded let id: Int
			    @Received let service: Service
			    @Instantiated(fulfilledByType: "AppScreen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<Int, AnyScreen>
			}
			"""]),
			ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
			import Seam
			import SafeDI

			@Instantiable
			public final class AppScreen: Instantiable {
			    public init(id: Int, service: Service, lastBuilder: ErasedInstantiator<Int, AnyScreen>\(tokenParameter)) {
			        self.id = id; self.service = service; self.lastBuilder = lastBuilder\(tokenAssignment)
			    }
			    @Forwarded let id: Int
			    @Received let service: Service
			    @Instantiated(fulfilledByType: "Last", erasedToConcreteExistential: true) let lastBuilder: ErasedInstantiator<Int, AnyScreen>\(appScreenToken)
			}


			\(root)
			"""], dependencies: ["Seam"]),
		]
	}

	private var filesToDelete: [URL]
}
