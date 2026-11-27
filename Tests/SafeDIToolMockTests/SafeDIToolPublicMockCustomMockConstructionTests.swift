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

/// A public mock builds a type with its hand-written mock through a construction function in the type's extension
/// (`__safeDI_mock`), which every public mock of the module shares, so it returns what the hand-written mock returns,
/// whatever type the property it builds is declared as: an eraser wraps its result, and a protocol or an existential
/// property takes it as it is.
struct SafeDIToolPublicMockCustomMockConstructionTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsCustomMocksTypeFromConstructionFunction_whenAnotherModulesPublicMockErasesTypeBuiltWithCustomMock(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": Self.featureTypes]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["T8.swift": Self.publicT8ErasingT0], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let generatedFiles = try #require(output.modules["Other"]).generatedFiles
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension T0 {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            t3: (() -> T3)? = nil,
			            analytics: (() -> Analytics)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                t3: t3,
			                analytics: analytics
			            )
			        }

			        public var t3: (() -> T3)? { __safeDI_storage.t3 }
			        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                t3: (() -> T3)?,
			                analytics: (() -> Analytics)?
			            ) {
			                self.t3 = t3
			                self.analytics = analytics
			            }

			            let t3: (() -> T3)?
			            let analytics: (() -> Analytics)?
			        }
			    }

			    public static func mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T0 {
			        T0.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T0 {
			        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder() } else { T3() }
			        func __safeDI_analytics() -> Analytics {
			            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        }
			        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
			        return T0.customMock(t3: t3, analytics: analytics)
			    }
			}

			extension T0 {
			    public enum __safeDI_T0_mock_E6F54C5E4AC4B0CA {}
			}
			#endif
			"""])
			#expect(generatedFiles == ["Other.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension T8 {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil,
			            anyT0: __safeDI_Other_T0_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                analytics: analytics,
			                anyT0: anyT0
			            )
			        }

			        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
			        public var anyT0: __safeDI_Other_T0_MockConfiguration { __safeDI_storage.anyT0 }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                analytics: (() -> Analytics)?,
			                anyT0: __safeDI_Other_T0_MockConfiguration
			            ) {
			                self.analytics = analytics
			                self.anyT0 = anyT0
			            }

			            let analytics: (() -> Analytics)?
			            let anyT0: __safeDI_Other_T0_MockConfiguration
			        }
			    }

			    public static func mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T8 {
			        T8.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T8 {
			        func __safeDI_analytics() -> Analytics {
			            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        }
			        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
			        func __safeDI_anyT0() -> AnyT0 {
			            let t3 = if let safeDIBuilder = safeDIOverrides.anyT0.t3 { safeDIBuilder() } else { T3() }
			            return AnyT0(T0.__safeDI_mock(t3: t3, analytics: analytics, safeDIBuilder: safeDIOverrides.anyT0.safeDIBuilder))
			        }
			        let anyT0: AnyT0 = __safeDI_anyT0()
			        return T8(anyT0: anyT0, analytics: analytics)
			    }
			}

			extension T8 {
			    public enum __safeDI_T8_mock_E6F54C5E4AC4B0CA {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `T0` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_T0_MockConfiguration {
			    public init(
			        t3: (() -> T3)? = nil,
			        _ safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            t3: t3,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var t3: (() -> T3)? { __safeDI_storage.t3 }
			    /// Overrides how `T0` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            t3: (() -> T3)?,
			            safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
			        ) {
			            self.t3 = t3
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let t3: (() -> T3)?
			        let safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
			    }
			}

			extension T0 {
			    static func __safeDI_mock(t3: T3, analytics: LazilyInstantiated<Analytics>, safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?) -> T0 {
			        if let safeDIBuilder { safeDIBuilder(t3, analytics) } else { T0.customMock(t3: t3, analytics: analytics) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension T0 {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            t3: (() -> T3)? = nil,
				            analytics: (() -> Analytics)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                t3: t3,
				                analytics: analytics
				            )
				        }

				        public var t3: (() -> T3)? { __safeDI_storage.t3 }
				        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                t3: (() -> T3)?,
				                analytics: (() -> Analytics)?
				            ) {
				                self.t3 = t3
				                self.analytics = analytics
				            }

				            let t3: (() -> T3)?
				            let analytics: (() -> Analytics)?
				        }
				    }

				    public static func mock(
				        analytics: LazilyInstantiated<Analytics>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> T0 {
				        T0.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        analytics: LazilyInstantiated<Analytics>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> T0 {
				        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder() } else { T3() }
				        func __safeDI_analytics() -> Analytics {
				            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
				        }
				        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
				        return T0.customMock(t3: t3, analytics: analytics)
				    }
				}

				extension T0 {
				    public enum __safeDI_T0_mock_E6F54C5E4AC4B0CA {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
			])
			#expect(generatedFiles == [
				"T8+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension T8 {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            analytics: (() -> Analytics)? = nil,
				            anyT0: __safeDI_Other_T0_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                analytics: analytics,
				                anyT0: anyT0
				            )
				        }

				        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
				        public var anyT0: __safeDI_Other_T0_MockConfiguration { __safeDI_storage.anyT0 }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                analytics: (() -> Analytics)?,
				                anyT0: __safeDI_Other_T0_MockConfiguration
				            ) {
				                self.analytics = analytics
				                self.anyT0 = anyT0
				            }

				            let analytics: (() -> Analytics)?
				            let anyT0: __safeDI_Other_T0_MockConfiguration
				        }
				    }

				    public static func mock(
				        analytics: LazilyInstantiated<Analytics>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> T8 {
				        T8.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        analytics: LazilyInstantiated<Analytics>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> T8 {
				        func __safeDI_analytics() -> Analytics {
				            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
				        }
				        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
				        func __safeDI_anyT0() -> AnyT0 {
				            let t3 = if let safeDIBuilder = safeDIOverrides.anyT0.t3 { safeDIBuilder() } else { T3() }
				            return AnyT0(T0.__safeDI_mock(t3: t3, analytics: analytics, safeDIBuilder: safeDIOverrides.anyT0.safeDIBuilder))
				        }
				        let anyT0: AnyT0 = __safeDI_anyT0()
				        return T8(anyT0: anyT0, analytics: analytics)
				    }
				}

				extension T8 {
				    public enum __safeDI_T8_mock_E6F54C5E4AC4B0CA {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				/// Configuration for how `T0` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_T0_MockConfiguration {
				    public init(
				        t3: (() -> T3)? = nil,
				        _ safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            t3: t3,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var t3: (() -> T3)? { __safeDI_storage.t3 }
				    /// Overrides how `T0` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            t3: (() -> T3)?,
				            safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
				        ) {
				            self.t3 = t3
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let t3: (() -> T3)?
				        let safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
				    }
				}

				extension T0 {
				    static func __safeDI_mock(t3: T3, analytics: LazilyInstantiated<Analytics>, safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?) -> T0 {
				        if let safeDIBuilder { safeDIBuilder(t3, analytics) } else { T0.customMock(t3: t3, analytics: analytics) }
				    }
				}
				#endif

				""",
			])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsCustomMocksTypeFromConstructionFunction_whenOwnModulesPublicMockErasesTypeBuiltWithCustomMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: [
				"Types.swift": Self.featureTypes,
				"T8.swift": """
				import SafeDI

				@Instantiable(generateMock: .public)
				public final class T8: Instantiable {
					public init(anyT0: AnyT0, analytics: LazilyInstantiated<Analytics>) {
						self.anyT0 = anyT0
						self.analytics = analytics
					}

					@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0: AnyT0
					@Received let analytics: LazilyInstantiated<Analytics>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Types+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension T0 {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            t3: (() -> T3)? = nil,
			            analytics: (() -> Analytics)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                t3: t3,
			                analytics: analytics
			            )
			        }

			        public var t3: (() -> T3)? { __safeDI_storage.t3 }
			        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                t3: (() -> T3)?,
			                analytics: (() -> Analytics)?
			            ) {
			                self.t3 = t3
			                self.analytics = analytics
			            }

			            let t3: (() -> T3)?
			            let analytics: (() -> Analytics)?
			        }
			    }

			    public static func mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T0 {
			        T0.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T0 {
			        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder() } else { T3() }
			        func __safeDI_analytics() -> Analytics {
			            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        }
			        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
			        return T0.customMock(t3: t3, analytics: analytics)
			    }
			}

			extension T0 {
			    public enum __safeDI_T0_mock_E6F54C5E4AC4B0CA {}
			}
			#endif
			""",
			"T8+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension T8 {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil,
			            anyT0: __safeDI_T0_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                analytics: analytics,
			                anyT0: anyT0
			            )
			        }

			        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
			        public var anyT0: __safeDI_T0_MockConfiguration { __safeDI_storage.anyT0 }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                analytics: (() -> Analytics)?,
			                anyT0: __safeDI_T0_MockConfiguration
			            ) {
			                self.analytics = analytics
			                self.anyT0 = anyT0
			            }

			            let analytics: (() -> Analytics)?
			            let anyT0: __safeDI_T0_MockConfiguration
			        }
			    }

			    public static func mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T8 {
			        T8.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analytics: LazilyInstantiated<Analytics>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> T8 {
			        func __safeDI_analytics() -> Analytics {
			            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        }
			        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
			        func __safeDI_anyT0() -> AnyT0 {
			            let t3 = if let safeDIBuilder = safeDIOverrides.anyT0.t3 { safeDIBuilder() } else { T3() }
			            return AnyT0(T0.__safeDI_mock(t3: t3, analytics: analytics, safeDIBuilder: safeDIOverrides.anyT0.safeDIBuilder))
			        }
			        let anyT0: AnyT0 = __safeDI_anyT0()
			        return T8(anyT0: anyT0, analytics: analytics)
			    }
			}

			extension T8 {
			    public enum __safeDI_T8_mock_E6F54C5E4AC4B0CA {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			/// Configuration for how `T0` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_T0_MockConfiguration {
			    public init(
			        t3: (() -> T3)? = nil,
			        _ safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            t3: t3,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var t3: (() -> T3)? { __safeDI_storage.t3 }
			    /// Overrides how `T0` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            t3: (() -> T3)?,
			            safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
			        ) {
			            self.t3 = t3
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let t3: (() -> T3)?
			        let safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
			    }
			}

			extension T0 {
			    static func __safeDI_mock(t3: T3, analytics: LazilyInstantiated<Analytics>, safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?) -> T0 {
			        if let safeDIBuilder { safeDIBuilder(t3, analytics) } else { T0.customMock(t3: t3, analytics: analytics) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsCustomMocksTypeFromConstructionFunction_whenAnotherModulesPublicMockBuildsTypeThroughErasedInstantiator() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": Self.featureTypes]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["T8.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: .public)
				public final class T8: Instantiable {
					public init(anyT0Builder: ErasedInstantiator<(), AnyT0>, analytics: LazilyInstantiated<Analytics>) {
						self.anyT0Builder = anyT0Builder
						self.analytics = analytics
					}

					@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0Builder: ErasedInstantiator<(), AnyT0>
					@Received let analytics: LazilyInstantiated<Analytics>
				}
				"""], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T0 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            t3: (() -> T3)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t3: t3,
		                analytics: analytics
		            )
		        }

		        public var t3: (() -> T3)? { __safeDI_storage.t3 }
		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t3: (() -> T3)?,
		                analytics: (() -> Analytics)?
		            ) {
		                self.t3 = t3
		                self.analytics = analytics
		            }

		            let t3: (() -> T3)?
		            let analytics: (() -> Analytics)?
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        T0.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder() } else { T3() }
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        return T0.customMock(t3: t3, analytics: analytics)
		    }
		}

		extension T0 {
		    public enum __safeDI_T0_mock_E6F54C5E4AC4B0CA {}
		}
		#endif
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T8 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            anyT0Builder: __safeDI_Other_T0_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                analytics: analytics,
		                anyT0Builder: anyT0Builder
		            )
		        }

		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
		        public var anyT0Builder: __safeDI_Other_T0_MockConfiguration { __safeDI_storage.anyT0Builder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                analytics: (() -> Analytics)?,
		                anyT0Builder: __safeDI_Other_T0_MockConfiguration
		            ) {
		                self.analytics = analytics
		                self.anyT0Builder = anyT0Builder
		            }

		            let analytics: (() -> Analytics)?
		            let anyT0Builder: __safeDI_Other_T0_MockConfiguration
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        T8.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        func __safeDI_anyT0Builder() -> AnyT0 {
		            let t3 = if let safeDIBuilder = safeDIOverrides.anyT0Builder.t3 { safeDIBuilder() } else { T3() }
		            return AnyT0(T0.__safeDI_mock(t3: t3, analytics: analytics, safeDIBuilder: safeDIOverrides.anyT0Builder.safeDIBuilder))
		        }
		        let anyT0Builder = ErasedInstantiator<(), AnyT0>(__safeDI_anyT0Builder)
		        return T8(anyT0Builder: anyT0Builder, analytics: analytics)
		    }
		}

		extension T8 {
		    public enum __safeDI_T8_mock_E6F54C5E4AC4B0CA {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `T0` is constructed within the public mock trees of module `Other`.
		nonisolated public struct __safeDI_Other_T0_MockConfiguration {
		    public init(
		        t3: (() -> T3)? = nil,
		        _ safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            t3: t3,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var t3: (() -> T3)? { __safeDI_storage.t3 }
		    /// Overrides how `T0` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            t3: (() -> T3)?,
		            safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		        ) {
		            self.t3 = t3
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let t3: (() -> T3)?
		        let safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		    }
		}

		extension T0 {
		    static func __safeDI_mock(t3: T3, analytics: LazilyInstantiated<Analytics>, safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?) -> T0 {
		        if let safeDIBuilder { safeDIBuilder(t3, analytics) } else { T0.customMock(t3: t3, analytics: analytics) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesConstructionFunctionReturningCustomMocksType_whenPublicMockBuildingTypeAsExistentialSortsBeforeOneBuildingItAsItself() async throws {
		// `T8`, first in type order, builds `T0` as `any T0Protocol`, and `T9` as `T0`: the one construction function the
		// module's public mocks share returns `T0`, which both take.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": Self.featureTypes]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["T8.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: .public)
				public final class T8: Instantiable {
					public init(t0: any T0Protocol, analytics: LazilyInstantiated<Analytics>) {
						self.t0 = t0
						self.analytics = analytics
					}

					@Instantiated(fulfilledByType: "T0") let t0: any T0Protocol
					@Received let analytics: LazilyInstantiated<Analytics>
				}

				@Instantiable(generateMock: .public)
				public final class T9: Instantiable {
					public init(t0: T0, analytics: LazilyInstantiated<Analytics>) {
						self.t0 = t0
						self.analytics = analytics
					}

					@Instantiated let t0: T0
					@Received let analytics: LazilyInstantiated<Analytics>
				}
				"""], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T0 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            t3: (() -> T3)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t3: t3,
		                analytics: analytics
		            )
		        }

		        public var t3: (() -> T3)? { __safeDI_storage.t3 }
		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t3: (() -> T3)?,
		                analytics: (() -> Analytics)?
		            ) {
		                self.t3 = t3
		                self.analytics = analytics
		            }

		            let t3: (() -> T3)?
		            let analytics: (() -> Analytics)?
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        T0.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder() } else { T3() }
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        return T0.customMock(t3: t3, analytics: analytics)
		    }
		}

		extension T0 {
		    public enum __safeDI_T0_mock_E6F54C5E4AC4B0CA {}
		}
		#endif
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T8 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            t0: __safeDI_Other_T0_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                analytics: analytics,
		                t0: t0
		            )
		        }

		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
		        public var t0: __safeDI_Other_T0_MockConfiguration { __safeDI_storage.t0 }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                analytics: (() -> Analytics)?,
		                t0: __safeDI_Other_T0_MockConfiguration
		            ) {
		                self.analytics = analytics
		                self.t0 = t0
		            }

		            let analytics: (() -> Analytics)?
		            let t0: __safeDI_Other_T0_MockConfiguration
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        T8.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        func __safeDI_t0() -> any T0Protocol {
		            let t3 = if let safeDIBuilder = safeDIOverrides.t0.t3 { safeDIBuilder() } else { T3() }
		            return T0.__safeDI_mock(t3: t3, analytics: analytics, safeDIBuilder: safeDIOverrides.t0.safeDIBuilder)
		        }
		        let t0: any T0Protocol = __safeDI_t0()
		        return T8(t0: t0, analytics: analytics)
		    }
		}

		extension T8 {
		    public enum __safeDI_T8_mock_E6F54C5E4AC4B0CA {}
		}
		#endif

		#if DEBUG
		extension T9 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            t0: __safeDI_Other_T0_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                analytics: analytics,
		                t0: t0
		            )
		        }

		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
		        public var t0: __safeDI_Other_T0_MockConfiguration { __safeDI_storage.t0 }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                analytics: (() -> Analytics)?,
		                t0: __safeDI_Other_T0_MockConfiguration
		            ) {
		                self.analytics = analytics
		                self.t0 = t0
		            }

		            let analytics: (() -> Analytics)?
		            let t0: __safeDI_Other_T0_MockConfiguration
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T9 {
		        T9.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T9 {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        func __safeDI_t0() -> T0 {
		            let t3 = if let safeDIBuilder = safeDIOverrides.t0.t3 { safeDIBuilder() } else { T3() }
		            return T0.__safeDI_mock(t3: t3, analytics: analytics, safeDIBuilder: safeDIOverrides.t0.safeDIBuilder)
		        }
		        let t0: T0 = __safeDI_t0()
		        return T9(t0: t0, analytics: analytics)
		    }
		}

		extension T9 {
		    public enum __safeDI_T9_mock_E6F54C5E4AC4B0CA {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `T0` is constructed within the public mock trees of module `Other`.
		nonisolated public struct __safeDI_Other_T0_MockConfiguration {
		    public init(
		        t3: (() -> T3)? = nil,
		        _ safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            t3: t3,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var t3: (() -> T3)? { __safeDI_storage.t3 }
		    /// Overrides how `T0` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            t3: (() -> T3)?,
		            safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		        ) {
		            self.t3 = t3
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let t3: (() -> T3)?
		        let safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		    }
		}

		extension T0 {
		    static func __safeDI_mock(t3: T3, analytics: LazilyInstantiated<Analytics>, safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?) -> T0 {
		        if let safeDIBuilder { safeDIBuilder(t3, analytics) } else { T0.customMock(t3: t3, analytics: analytics) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCustomMockInEraser_whenAnotherModulesInternalMockErasesTypeBuiltWithCustomMock() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": Self.featureTypes]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["T8.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: true)
				public final class T8: Instantiable {
					public init(anyT0: AnyT0, analytics: LazilyInstantiated<Analytics>) {
						self.anyT0 = anyT0
						self.analytics = analytics
					}

					@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0: AnyT0
					@Received let analytics: LazilyInstantiated<Analytics>
				}
				"""], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T0 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            t3: (() -> T3)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t3: t3,
		                analytics: analytics
		            )
		        }

		        public var t3: (() -> T3)? { __safeDI_storage.t3 }
		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t3: (() -> T3)?,
		                analytics: (() -> Analytics)?
		            ) {
		                self.t3 = t3
		                self.analytics = analytics
		            }

		            let t3: (() -> T3)?
		            let analytics: (() -> Analytics)?
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        T0.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder() } else { T3() }
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        return T0.customMock(t3: t3, analytics: analytics)
		    }
		}

		extension T0 {
		    public enum __safeDI_T0_mock_E6F54C5E4AC4B0CA {}
		}
		#endif
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T8 {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            anyT0: T0.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                analytics: analytics,
		                anyT0: anyT0
		            )
		        }

		        var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
		        var anyT0: T0.SafeDIMockConfiguration { __safeDI_storage.anyT0 }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                analytics: (() -> Analytics)?,
		                anyT0: T0.SafeDIMockConfiguration
		            ) {
		                self.analytics = analytics
		                self.anyT0 = anyT0
		            }

		            let analytics: (() -> Analytics)?
		            let anyT0: T0.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        func __safeDI_anyT0() -> AnyT0 {
		            let t3 = if let safeDIBuilder = safeDIOverrides.anyT0.t3 { safeDIBuilder() } else { T3() }
		            return if let safeDIBuilder = safeDIOverrides.anyT0.safeDIBuilder { AnyT0(safeDIBuilder(t3, analytics)) } else { AnyT0(T0.customMock(t3: t3, analytics: analytics)) }
		        }
		        let anyT0: AnyT0 = __safeDI_anyT0()
		        return T8(anyT0: anyT0, analytics: analytics)
		    }
		}
		#endif

		#if DEBUG
		extension T0 {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            t3: (() -> T3)? = nil,
		            _ safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t3: t3,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var t3: (() -> T3)? { __safeDI_storage.t3 }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t3: (() -> T3)?,
		                safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		            ) {
		                self.t3 = t3
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let t3: (() -> T3)?
		            let safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsTypeFromInitializerConstructionFunction_whenAnotherModulesPublicMockErasesTypeWithoutCustomMock() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
				import SafeDI

				public protocol T0Protocol {}

				extension T0: T0Protocol {}

				public struct AnyT0: T0Protocol {
					public init(_ value: any T0Protocol) {
						self.value = value
					}

					public let value: any T0Protocol
				}

				@Instantiable
				public final class Analytics: Instantiable {
					public init() {}
				}

				@Instantiable
				public final class T3: Instantiable {
					public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class T0: Instantiable {
					public init(t3: T3, analytics: LazilyInstantiated<Analytics>) {
						self.t3 = t3
						self.analytics = analytics
					}

					@Instantiated let t3: T3
					@Received let analytics: LazilyInstantiated<Analytics>

				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["T8.swift": Self.publicT8ErasingT0], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T0 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            t3: (() -> T3)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t3: t3,
		                analytics: analytics
		            )
		        }

		        public var t3: (() -> T3)? { __safeDI_storage.t3 }
		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t3: (() -> T3)?,
		                analytics: (() -> Analytics)?
		            ) {
		                self.t3 = t3
		                self.analytics = analytics
		            }

		            let t3: (() -> T3)?
		            let analytics: (() -> Analytics)?
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        T0.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T0 {
		        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder() } else { T3() }
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        return T0(t3: t3, analytics: analytics)
		    }
		}

		extension T0 {
		    public enum __safeDI_T0_mock_E6F54C5E4AC4B0CA {}
		}
		#endif
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T8 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            anyT0: __safeDI_Other_T0_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                analytics: analytics,
		                anyT0: anyT0
		            )
		        }

		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
		        public var anyT0: __safeDI_Other_T0_MockConfiguration { __safeDI_storage.anyT0 }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                analytics: (() -> Analytics)?,
		                anyT0: __safeDI_Other_T0_MockConfiguration
		            ) {
		                self.analytics = analytics
		                self.anyT0 = anyT0
		            }

		            let analytics: (() -> Analytics)?
		            let anyT0: __safeDI_Other_T0_MockConfiguration
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        T8.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        func __safeDI_anyT0() -> AnyT0 {
		            let t3 = if let safeDIBuilder = safeDIOverrides.anyT0.t3 { safeDIBuilder() } else { T3() }
		            return AnyT0(T0.__safeDI_init(t3: t3, analytics: analytics, safeDIBuilder: safeDIOverrides.anyT0.safeDIBuilder))
		        }
		        let anyT0: AnyT0 = __safeDI_anyT0()
		        return T8(anyT0: anyT0, analytics: analytics)
		    }
		}

		extension T8 {
		    public enum __safeDI_T8_mock_E6F54C5E4AC4B0CA {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `T0` is constructed within the public mock trees of module `Other`.
		nonisolated public struct __safeDI_Other_T0_MockConfiguration {
		    public init(
		        t3: (() -> T3)? = nil,
		        _ safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            t3: t3,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var t3: (() -> T3)? { __safeDI_storage.t3 }
		    /// Overrides how `T0` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            t3: (() -> T3)?,
		            safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		        ) {
		            self.t3 = t3
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let t3: (() -> T3)?
		        let safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?
		    }
		}

		extension T0 {
		    static func __safeDI_init(t3: T3, analytics: LazilyInstantiated<Analytics>, safeDIBuilder: ((T3, LazilyInstantiated<Analytics>) -> T0)?) -> T0 {
		        if let safeDIBuilder { safeDIBuilder(t3, analytics) } else { T0(t3: t3, analytics: analytics) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsProtocolCustomMockReturnsFromConstructionFunction_whenAnotherModulesPublicMockHoldsTypeAsThatProtocol() async throws {
		// `ConcreteService`'s `mockOnly` mock returns `ServiceProtocol`, which the type fulfills: the construction function
		// returns `ServiceProtocol`, which both the property of that type and the `ErasedInstantiator` building it take.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["ConcreteService.swift": """
				import SafeDI

				public protocol ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				public final class ConcreteService: ServiceProtocol, Instantiable {
					public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
				extension ConcreteService {
					public static func mock(name: String = "mock") -> ServiceProtocol {
						ConcreteService()
					}
				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["T8.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: .public)
				public final class T8: Instantiable {
					public init(service: ServiceProtocol, serviceBuilder: ErasedInstantiator<(), ServiceProtocol>) {
						self.service = service
						self.serviceBuilder = serviceBuilder
					}

					@Instantiated let service: ServiceProtocol
					@Instantiated(fulfilledByType: "ConcreteService") let serviceBuilder: ErasedInstantiator<(), ServiceProtocol>
				}
				"""], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T8 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            service: __safeDI_Other_ConcreteService_MockConfiguration = .init(),
		            serviceBuilder: __safeDI_Other_ConcreteService_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                service: service,
		                serviceBuilder: serviceBuilder
		            )
		        }

		        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }
		        public var serviceBuilder: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.serviceBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                service: __safeDI_Other_ConcreteService_MockConfiguration,
		                serviceBuilder: __safeDI_Other_ConcreteService_MockConfiguration
		            ) {
		                self.service = service
		                self.serviceBuilder = serviceBuilder
		            }

		            let service: __safeDI_Other_ConcreteService_MockConfiguration
		            let serviceBuilder: __safeDI_Other_ConcreteService_MockConfiguration
		        }
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        T8.__safeDI_mock(safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        func __safeDI_service() -> ServiceProtocol {
		            return ConcreteService.__safeDI_mock(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
		        }
		        let service: ServiceProtocol = __safeDI_service()
		        func __safeDI_serviceBuilder() -> ServiceProtocol {
		            ConcreteService.__safeDI_mock(name: safeDIOverrides.serviceBuilder.name, safeDIBuilder: safeDIOverrides.serviceBuilder.safeDIBuilder)
		        }
		        let serviceBuilder = ErasedInstantiator<(), ServiceProtocol>(__safeDI_serviceBuilder)
		        return T8(service: service, serviceBuilder: serviceBuilder)
		    }
		}

		extension T8 {
		    public enum __safeDI_T8_mock_51799E6AA5E7B634 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Other`.
		nonisolated public struct __safeDI_Other_ConcreteService_MockConfiguration {
		    public init(
		        name: String? = nil,
		        _ safeDIBuilder: ((String) -> ConcreteService)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            name: name,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// `nil` keeps the default of `ConcreteService`’s `name`.
		    public var name: String? { __safeDI_storage.name }
		    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((String) -> ConcreteService)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            name: String?,
		            safeDIBuilder: ((String) -> ConcreteService)?
		        ) {
		            self.name = name
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let name: String?
		        let safeDIBuilder: ((String) -> ConcreteService)?
		    }
		}

		extension ConcreteService {
		    static func __safeDI_mock(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ServiceProtocol {
		        let name = name ?? ("mock")
		        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService.mock(name: name) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsCustomMocksTypeFromConstructionFunction_whenAnotherModulesPublicMockErasesTypeWhoseCustomMockIsMockOnly() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
				import SafeDI

				public protocol T0Protocol {}

				extension T0: T0Protocol {}

				public struct AnyT0: T0Protocol {
					public init(_ value: any T0Protocol) {
						self.value = value
					}

					public let value: any T0Protocol
				}

				@Instantiable
				public final class Analytics: Instantiable {
					public init() {}
				}

				@Instantiable
				public final class T3: Instantiable {
					public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class T0: Instantiable {
					init(t3: T3, analytics: LazilyInstantiated<Analytics>) {
						self.t3 = t3
						self.analytics = analytics
					}

					@Instantiated let t3: T3
					@Received let analytics: LazilyInstantiated<Analytics>
				}

				@Instantiable(mockOnly: true, customMockName: "customMock")
				extension T0 {
					public static func customMock(name: String = "mock") -> T0 {
						T0(t3: T3(), analytics: LazilyInstantiated { Analytics() })
					}
				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["T8.swift": Self.publicT8ErasingT0], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T0 {
		    public static func mock(
		        name: String? = nil
		    ) -> T0 {
		        T0.__safeDI_mock(name: name)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        name: String? = nil
		    ) -> T0 {
		        let name = name ?? ("mock")
		        return T0.customMock(name: name)
		    }
		}

		extension T0 {
		    public enum __safeDI_T0_mock_072A01A8096B7A0E {}
		}
		#endif
		"""])
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension T8 {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            anyT0: __safeDI_Other_T0_MockConfiguration = .init(),
		            analytics: (() -> Analytics)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                anyT0: anyT0,
		                analytics: analytics
		            )
		        }

		        public var anyT0: __safeDI_Other_T0_MockConfiguration { __safeDI_storage.anyT0 }
		        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                anyT0: __safeDI_Other_T0_MockConfiguration,
		                analytics: (() -> Analytics)?
		            ) {
		                self.anyT0 = anyT0
		                self.analytics = analytics
		            }

		            let anyT0: __safeDI_Other_T0_MockConfiguration
		            let analytics: (() -> Analytics)?
		        }
		    }

		    public static func mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        T8.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        analytics: LazilyInstantiated<Analytics>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> T8 {
		        func __safeDI_anyT0() -> AnyT0 {
		            return AnyT0(T0.__safeDI_mock(name: safeDIOverrides.anyT0.name, safeDIBuilder: safeDIOverrides.anyT0.safeDIBuilder))
		        }
		        let anyT0: AnyT0 = __safeDI_anyT0()
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = if let analytics { analytics } else { LazilyInstantiated<Analytics>(__safeDI_analytics) }
		        return T8(anyT0: anyT0, analytics: analytics)
		    }
		}

		extension T8 {
		    public enum __safeDI_T8_mock_E6F54C5E4AC4B0CA {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `T0` is constructed within the public mock trees of module `Other`.
		nonisolated public struct __safeDI_Other_T0_MockConfiguration {
		    public init(
		        name: String? = nil,
		        _ safeDIBuilder: ((String) -> T0)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            name: name,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    /// `nil` keeps the default of `T0`’s `name`.
		    public var name: String? { __safeDI_storage.name }
		    /// Overrides how `T0` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((String) -> T0)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            name: String?,
		            safeDIBuilder: ((String) -> T0)?
		        ) {
		            self.name = name
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let name: String?
		        let safeDIBuilder: ((String) -> T0)?
		    }
		}

		extension T0 {
		    static func __safeDI_mock(name: String?, safeDIBuilder: ((String) -> T0)?) -> T0 {
		        let name = name ?? ("mock")
		        return if let safeDIBuilder { safeDIBuilder(name) } else { T0.customMock(name: name) }
		    }
		}
		#endif

		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `T0`, whose public mock calls its `customMock`, which another module can call, and the eraser `AnyT0`.
	private static let featureTypes = """
	import SafeDI

	public protocol T0Protocol {}

	extension T0: T0Protocol {}

	public struct AnyT0: T0Protocol {
		public init(_ value: any T0Protocol) {
			self.value = value
		}

		public let value: any T0Protocol
	}

	@Instantiable
	public final class Analytics: Instantiable {
		public init() {}
	}

	@Instantiable
	public final class T3: Instantiable {
		public init() {}
	}

	@Instantiable(generateMock: .public, customMockName: "customMock")
	public final class T0: Instantiable {
		init(t3: T3, analytics: LazilyInstantiated<Analytics>) {
			self.t3 = t3
			self.analytics = analytics
		}

		@Instantiated let t3: T3
		@Received let analytics: LazilyInstantiated<Analytics>

		public static func customMock(t3: T3, analytics: LazilyInstantiated<Analytics>) -> T0 {
			T0(t3: t3, analytics: analytics)
		}
	}
	"""

	/// `T8`, whose public mock builds `T0` erased to `AnyT0`.
	private static let publicT8ErasingT0 = """
	import SafeDI
	import Feature

	@Instantiable(generateMock: .public)
	public final class T8: Instantiable {
		public init(anyT0: AnyT0, analytics: LazilyInstantiated<Analytics>) {
			self.anyT0 = anyT0
			self.analytics = analytics
		}

		@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0: AnyT0
		@Received let analytics: LazilyInstantiated<Analytics>
	}
	"""
}
