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

/// A module's public mocks build each configured type through construction functions in the type's extension, which
/// they all share. When they build a type both with its hand-written mock (as an additional type the mock returns) and
/// with its initializer or `instantiate(…)` method (as itself, or erased), taking equal parameters, the module declares
/// one function per construction, `__safeDI_init` and `__safeDI_mock`, from one configuration, whichever public mock
/// sorts first.
struct SafeDIToolPublicMockSharedConstructionTests: ~Copyable {
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

	/// `A`'s public mock builds `SystemClock` as `Clock` with its custom mock, and `B`'s as itself with its `instantiate(…)`
	/// method, which takes the custom mock's parameters.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBothConstructionFunctions_whenPublicMocksBuildCustomMockTypeTwoWays(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": Self.featureSystemClock]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["A.swift": Self.otherClockFirst], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension SystemClock {
			    static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
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
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock
			            )
			        }

			        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.clock = clock
			            }

			            let clock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_clock() -> Clock {
			            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
			        }
			        let clock: Clock = __safeDI_clock()
			        return A(clock: clock)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                systemClock: systemClock
			            )
			        }

			        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                systemClock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.systemClock = systemClock
			            }

			            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_systemClock() -> SystemClock {
			            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
			        }
			        let systemClock: SystemClock = __safeDI_systemClock()
			        return B(systemClock: systemClock)
			    }
			}

			extension B {
			    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
			    public init(
			        zone: String? = nil,
			        _ safeDIBuilder: ((String) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `SystemClock`’s `zone`.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    static func mock(
				        zone: String = "UTC"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"A+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension A {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.clock = clock
				            }

				            let clock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        func __safeDI_clock() -> Clock {
				            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
				        }
				        let clock: Clock = __safeDI_clock()
				        return A(clock: clock)
				    }
				}

				extension A {
				    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                systemClock: systemClock
				            )
				        }

				        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                systemClock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.systemClock = systemClock
				            }

				            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        func __safeDI_systemClock() -> SystemClock {
				            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
				        }
				        let systemClock: SystemClock = __safeDI_systemClock()
				        return B(systemClock: systemClock)
				    }
				}

				extension B {
				    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
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
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
				    public init(
				        zone: String? = nil,
				        _ safeDIBuilder: ((String) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// `nil` keeps the default of `SystemClock`’s `zone`.
				    public var zone: String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: String?,
				            safeDIBuilder: ((String) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: String?
				        let safeDIBuilder: ((String) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// The two public mocks of the test above with their names swapped: the module declares the same configuration and
	/// construction functions, byte for byte, whichever public mock sorts first.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBothConstructionFunctions_whenPublicMockBuildingTypeWithInstantiateMethodSortsFirst(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": Self.featureSystemClock]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["A.swift": Self.otherSystemClockFirst], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension SystemClock {
			    static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
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
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                systemClock: systemClock
			            )
			        }

			        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                systemClock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.systemClock = systemClock
			            }

			            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_systemClock() -> SystemClock {
			            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
			        }
			        let systemClock: SystemClock = __safeDI_systemClock()
			        return A(systemClock: systemClock)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock
			            )
			        }

			        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.clock = clock
			            }

			            let clock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_clock() -> Clock {
			            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
			        }
			        let clock: Clock = __safeDI_clock()
			        return B(clock: clock)
			    }
			}

			extension B {
			    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
			    public init(
			        zone: String? = nil,
			        _ safeDIBuilder: ((String) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `SystemClock`’s `zone`.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    static func mock(
				        zone: String = "UTC"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"A+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension A {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                systemClock: systemClock
				            )
				        }

				        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                systemClock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.systemClock = systemClock
				            }

				            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        func __safeDI_systemClock() -> SystemClock {
				            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
				        }
				        let systemClock: SystemClock = __safeDI_systemClock()
				        return A(systemClock: systemClock)
				    }
				}

				extension A {
				    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.clock = clock
				            }

				            let clock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        func __safeDI_clock() -> Clock {
				            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
				        }
				        let clock: Clock = __safeDI_clock()
				        return B(clock: clock)
				    }
				}

				extension B {
				    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
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
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
				    public init(
				        zone: String? = nil,
				        _ safeDIBuilder: ((String) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// `nil` keeps the default of `SystemClock`’s `zone`.
				    public var zone: String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: String?,
				            safeDIBuilder: ((String) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: String?
				        let safeDIBuilder: ((String) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// One public mock holds `SystemClock` both as `Clock` and as itself.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBothConstructionFunctions_whenOnePublicMockBuildsCustomMockTypeTwoWays(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": Self.featureSystemClock]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["Both.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: .public)
				public final class Both: Instantiable {
					public init(clock: Clock, systemClock: SystemClock) {
						self.clock = clock
						self.systemClock = systemClock
					}

					@Instantiated let clock: Clock
					@Instantiated let systemClock: SystemClock
				}
				"""], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension SystemClock {
			    static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
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
			extension Both {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clock: __safeDI_Other_SystemClock_MockConfiguration = .init(),
			            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock,
			                systemClock: systemClock
			            )
			        }

			        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }
			        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: __safeDI_Other_SystemClock_MockConfiguration,
			                systemClock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.clock = clock
			                self.systemClock = systemClock
			            }

			            let clock: __safeDI_Other_SystemClock_MockConfiguration
			            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Both {
			        Both.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Both {
			        func __safeDI_clock() -> Clock {
			            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
			        }
			        let clock: Clock = __safeDI_clock()
			        func __safeDI_systemClock() -> SystemClock {
			            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
			        }
			        let systemClock: SystemClock = __safeDI_systemClock()
			        return Both(clock: clock, systemClock: systemClock)
			    }
			}

			extension Both {
			    public enum __safeDI_Both_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
			    public init(
			        zone: String? = nil,
			        _ safeDIBuilder: ((String) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `SystemClock`’s `zone`.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    static func mock(
				        zone: String = "UTC"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"Both+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Both {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clock: __safeDI_Other_SystemClock_MockConfiguration = .init(),
				            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock,
				                systemClock: systemClock
				            )
				        }

				        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }
				        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: __safeDI_Other_SystemClock_MockConfiguration,
				                systemClock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.clock = clock
				                self.systemClock = systemClock
				            }

				            let clock: __safeDI_Other_SystemClock_MockConfiguration
				            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Both {
				        Both.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Both {
				        func __safeDI_clock() -> Clock {
				            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
				        }
				        let clock: Clock = __safeDI_clock()
				        func __safeDI_systemClock() -> SystemClock {
				            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
				        }
				        let systemClock: SystemClock = __safeDI_systemClock()
				        return Both(clock: clock, systemClock: systemClock)
				    }
				}

				extension Both {
				    public enum __safeDI_Both_mock_51799E6AA5E7B634 {}
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
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
				    public init(
				        zone: String? = nil,
				        _ safeDIBuilder: ((String) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// `nil` keeps the default of `SystemClock`’s `zone`.
				    public var zone: String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: String?,
				            safeDIBuilder: ((String) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: String?
				        let safeDIBuilder: ((String) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// The module that declares `SystemClock` declares the two public mocks that build it two ways.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBothConstructionFunctions_whenDeclaringModulesPublicMocksBuildCustomMockTypeTwoWays(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Types.swift": Self.featureSystemClock,
					"A.swift": """
					import SafeDI

					@Instantiable(generateMock: .public)
					public final class A: Instantiable {
						public init(clock: Clock) {
							self.clock = clock
						}

						@Instantiated let clock: Clock
					}

					@Instantiable(generateMock: .public)
					public final class B: Instantiable {
						public init(systemClock: SystemClock) {
							self.systemClock = systemClock
						}

						@Instantiated let systemClock: SystemClock
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clock: __safeDI_Feature_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock
			            )
			        }

			        public var clock: __safeDI_Feature_SystemClock_MockConfiguration { __safeDI_storage.clock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: __safeDI_Feature_SystemClock_MockConfiguration
			            ) {
			                self.clock = clock
			            }

			            let clock: __safeDI_Feature_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_clock() -> Clock {
			            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
			        }
			        let clock: Clock = __safeDI_clock()
			        return A(clock: clock)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            systemClock: __safeDI_Feature_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                systemClock: systemClock
			            )
			        }

			        public var systemClock: __safeDI_Feature_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                systemClock: __safeDI_Feature_SystemClock_MockConfiguration
			            ) {
			                self.systemClock = systemClock
			            }

			            let systemClock: __safeDI_Feature_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_systemClock() -> SystemClock {
			            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
			        }
			        let systemClock: SystemClock = __safeDI_systemClock()
			        return B(systemClock: systemClock)
			    }
			}

			extension B {
			    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension SystemClock {
			    static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_SystemClock_MockConfiguration {
			    public init(
			        zone: String? = nil,
			        _ safeDIBuilder: ((String) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `SystemClock`’s `zone`.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"A+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension A {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clock: __safeDI_Feature_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        public var clock: __safeDI_Feature_SystemClock_MockConfiguration { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: __safeDI_Feature_SystemClock_MockConfiguration
				            ) {
				                self.clock = clock
				            }

				            let clock: __safeDI_Feature_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        func __safeDI_clock() -> Clock {
				            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
				        }
				        let clock: Clock = __safeDI_clock()
				        return A(clock: clock)
				    }
				}

				extension A {
				    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            systemClock: __safeDI_Feature_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                systemClock: systemClock
				            )
				        }

				        public var systemClock: __safeDI_Feature_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                systemClock: __safeDI_Feature_SystemClock_MockConfiguration
				            ) {
				                self.systemClock = systemClock
				            }

				            let systemClock: __safeDI_Feature_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        func __safeDI_systemClock() -> SystemClock {
				            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
				        }
				        let systemClock: SystemClock = __safeDI_systemClock()
				        return B(systemClock: systemClock)
				    }
				}

				extension B {
				    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_SystemClock_MockConfiguration {
				    public init(
				        zone: String? = nil,
				        _ safeDIBuilder: ((String) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// `nil` keeps the default of `SystemClock`’s `zone`.
				    public var zone: String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: String?,
				            safeDIBuilder: ((String) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: String?
				        let safeDIBuilder: ((String) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}
				#endif

				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    static func mock(
				        zone: String = "UTC"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
		}
	}

	/// The two constructions share the provider of the optional default, which resolves to the custom mock's, and its
	/// module-level forwarder, each declared once.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresProvidersOnce_whenPublicMocksBuildTypeWithOptionalDefaultTwoWays(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
				import SafeDI

				public protocol Clock {}

				public final class SystemClock: Clock {
					public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Clock.self], generateMock: true, customMockName: "customMock")
				extension SystemClock: Instantiable {
					public static func instantiate(zone: String? = "UTC") -> SystemClock {
						SystemClock()
					}

					public static func customMock(zone: String? = "GMT") -> Clock {
						SystemClock()
					}
				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["A.swift": Self.otherClockFirst], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension SystemClock {
			    static func mock(
			        zone: String? = "GMT"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
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
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock
			            )
			        }

			        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.clock = clock
			            }

			            let clock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_clock() -> Clock {
			            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
			        }
			        let clock: Clock = __safeDI_clock()
			        return A(clock: clock)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                systemClock: systemClock
			            )
			        }

			        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                systemClock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.systemClock = systemClock
			            }

			            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_systemClock() -> SystemClock {
			            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
			        }
			        let systemClock: SystemClock = __safeDI_systemClock()
			        return B(systemClock: systemClock)
			    }
			}

			extension B {
			    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
			    public init(
			        zone: String? = __safeDI_Other_SystemClock_mockDefault_zone(),
			        _ safeDIBuilder: ((String?) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// The default of `SystemClock`’s `zone` unless set.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String?) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String?) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String?) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    nonisolated static func __safeDI_mockDefault_zone() -> String? { "GMT" }
			    static func __safeDI_init(zone: String?, safeDIBuilder: ((String?) -> SystemClock)?) -> SystemClock {
			        if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String?) -> SystemClock)?) -> Clock {
			        if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Other_SystemClock_mockDefault_zone() -> String? { SystemClock.__safeDI_mockDefault_zone() }
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    static func mock(
				        zone: String? = "GMT"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"A+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension A {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.clock = clock
				            }

				            let clock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        func __safeDI_clock() -> Clock {
				            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
				        }
				        let clock: Clock = __safeDI_clock()
				        return A(clock: clock)
				    }
				}

				extension A {
				    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                systemClock: systemClock
				            )
				        }

				        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                systemClock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.systemClock = systemClock
				            }

				            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        func __safeDI_systemClock() -> SystemClock {
				            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
				        }
				        let systemClock: SystemClock = __safeDI_systemClock()
				        return B(systemClock: systemClock)
				    }
				}

				extension B {
				    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
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
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
				    public init(
				        zone: String? = __safeDI_Other_SystemClock_mockDefault_zone(),
				        _ safeDIBuilder: ((String?) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// The default of `SystemClock`’s `zone` unless set.
				    public var zone: String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String?) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: String?,
				            safeDIBuilder: ((String?) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: String?
				        let safeDIBuilder: ((String?) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    nonisolated static func __safeDI_mockDefault_zone() -> String? { "GMT" }
				    static func __safeDI_init(zone: String?, safeDIBuilder: ((String?) -> SystemClock)?) -> SystemClock {
				        if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String?) -> SystemClock)?) -> Clock {
				        if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}
				@usableFromInline nonisolated func __safeDI_Other_SystemClock_mockDefault_zone() -> String? { SystemClock.__safeDI_mockDefault_zone() }
				#endif

				""",
			])
		}
	}

	/// `Feature`'s own public mock builds `ConcreteService` with its `mockOnly` mock, so `Feature` declares an internal
	/// `__safeDI_mock`; `Other`'s public mocks build it erased with its initializer and as `ServiceProtocol` with that mock, and
	/// declare both functions of their own.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBothConstructionFunctions_whenDeclaringModuleDeclaresInternalMockConstructionFunction(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["ConcreteService.swift": """
				import SafeDI

				public protocol ServiceProtocol {}

				public struct AnyService: ServiceProtocol {
					public init(_ value: any ServiceProtocol) {}
				}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				public final class ConcreteService: ServiceProtocol, Instantiable {
					public init(name: String = "init") {}
				}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
				extension ConcreteService {
					public static func mock(name: String = "mock") -> ServiceProtocol {
						ConcreteService()
					}
				}

				@Instantiable(generateMock: .public)
				public final class FeatureRoot: Instantiable {
					public init(service: ServiceProtocol) {
						self.service = service
					}

					@Instantiated let service: ServiceProtocol
				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["Other.swift": Self.otherErasedAndLeaf], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension FeatureRoot {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            service: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        public var service: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: __safeDI_Feature_ConcreteService_MockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: __safeDI_Feature_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> FeatureRoot {
			        FeatureRoot.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> FeatureRoot {
			        func __safeDI_service() -> ServiceProtocol {
			            return ConcreteService.__safeDI_mock(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
			        }
			        let service: ServiceProtocol = __safeDI_service()
			        return FeatureRoot(service: service)
			    }
			}

			extension FeatureRoot {
			    public enum __safeDI_FeatureRoot_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
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
			#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OtherErased {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: __safeDI_Other_ConcreteService_MockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: __safeDI_Other_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherErased {
			        OtherErased.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherErased {
			        func __safeDI_service() -> AnyService {
			            return AnyService(ConcreteService.__safeDI_init(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder))
			        }
			        let service: AnyService = __safeDI_service()
			        return OtherErased(service: service)
			    }
			}

			extension OtherErased {
			    public enum __safeDI_OtherErased_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension OtherLeaf {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: __safeDI_Other_ConcreteService_MockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: __safeDI_Other_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherLeaf {
			        OtherLeaf.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherLeaf {
			        func __safeDI_service() -> ServiceProtocol {
			            return ConcreteService.__safeDI_mock(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
			        }
			        let service: ServiceProtocol = __safeDI_service()
			        return OtherLeaf(service: service)
			    }
			}

			extension OtherLeaf {
			    public enum __safeDI_OtherLeaf_mock_51799E6AA5E7B634 {}
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
			    static func __safeDI_init(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ConcreteService {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService(name: name) }
			    }
			    static func __safeDI_mock(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ServiceProtocol {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService.mock(name: name) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"ConcreteService+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension FeatureRoot {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            service: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                service: service
				            )
				        }

				        public var service: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.service }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                service: __safeDI_Feature_ConcreteService_MockConfiguration
				            ) {
				                self.service = service
				            }

				            let service: __safeDI_Feature_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> FeatureRoot {
				        FeatureRoot.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> FeatureRoot {
				        func __safeDI_service() -> ServiceProtocol {
				            return ConcreteService.__safeDI_mock(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
				        }
				        let service: ServiceProtocol = __safeDI_service()
				        return FeatureRoot(service: service)
				    }
				}

				extension FeatureRoot {
				    public enum __safeDI_FeatureRoot_mock_51799E6AA5E7B634 {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
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

				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"Other+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension OtherErased {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                service: service
				            )
				        }

				        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                service: __safeDI_Other_ConcreteService_MockConfiguration
				            ) {
				                self.service = service
				            }

				            let service: __safeDI_Other_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherErased {
				        OtherErased.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherErased {
				        func __safeDI_service() -> AnyService {
				            return AnyService(ConcreteService.__safeDI_init(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder))
				        }
				        let service: AnyService = __safeDI_service()
				        return OtherErased(service: service)
				    }
				}

				extension OtherErased {
				    public enum __safeDI_OtherErased_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension OtherLeaf {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                service: service
				            )
				        }

				        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                service: __safeDI_Other_ConcreteService_MockConfiguration
				            ) {
				                self.service = service
				            }

				            let service: __safeDI_Other_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherLeaf {
				        OtherLeaf.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherLeaf {
				        func __safeDI_service() -> ServiceProtocol {
				            return ConcreteService.__safeDI_mock(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
				        }
				        let service: ServiceProtocol = __safeDI_service()
				        return OtherLeaf(service: service)
				    }
				}

				extension OtherLeaf {
				    public enum __safeDI_OtherLeaf_mock_51799E6AA5E7B634 {}
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
				    static func __safeDI_init(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ConcreteService {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService(name: name) }
				    }
				    static func __safeDI_mock(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ServiceProtocol {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService.mock(name: name) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// `OtherErased`'s public mock, which sorts first, builds `ConcreteService` erased with its initializer, and `OtherLeaf`'s
	/// as `ServiceProtocol` with its `mockOnly` mock, which takes the initializer's parameters.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBothConstructionFunctions_whenPublicMocksBuildErasedMockOnlyMockTypeTwoWays(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["ConcreteService.swift": Self.featureConcreteService]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["Other.swift": Self.otherErasedAndLeaf], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
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
			extension OtherErased {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: __safeDI_Other_ConcreteService_MockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: __safeDI_Other_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherErased {
			        OtherErased.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherErased {
			        func __safeDI_service() -> AnyService {
			            return AnyService(ConcreteService.__safeDI_init(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder))
			        }
			        let service: AnyService = __safeDI_service()
			        return OtherErased(service: service)
			    }
			}

			extension OtherErased {
			    public enum __safeDI_OtherErased_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension OtherLeaf {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: __safeDI_Other_ConcreteService_MockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: __safeDI_Other_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherLeaf {
			        OtherLeaf.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherLeaf {
			        func __safeDI_service() -> ServiceProtocol {
			            return ConcreteService.__safeDI_mock(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
			        }
			        let service: ServiceProtocol = __safeDI_service()
			        return OtherLeaf(service: service)
			    }
			}

			extension OtherLeaf {
			    public enum __safeDI_OtherLeaf_mock_51799E6AA5E7B634 {}
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
			    static func __safeDI_init(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ConcreteService {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService(name: name) }
			    }
			    static func __safeDI_mock(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ServiceProtocol {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService.mock(name: name) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Other"]?.generatedFiles == [
				"Other+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension OtherErased {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                service: service
				            )
				        }

				        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                service: __safeDI_Other_ConcreteService_MockConfiguration
				            ) {
				                self.service = service
				            }

				            let service: __safeDI_Other_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherErased {
				        OtherErased.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherErased {
				        func __safeDI_service() -> AnyService {
				            return AnyService(ConcreteService.__safeDI_init(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder))
				        }
				        let service: AnyService = __safeDI_service()
				        return OtherErased(service: service)
				    }
				}

				extension OtherErased {
				    public enum __safeDI_OtherErased_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension OtherLeaf {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            service: __safeDI_Other_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                service: service
				            )
				        }

				        public var service: __safeDI_Other_ConcreteService_MockConfiguration { __safeDI_storage.service }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                service: __safeDI_Other_ConcreteService_MockConfiguration
				            ) {
				                self.service = service
				            }

				            let service: __safeDI_Other_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherLeaf {
				        OtherLeaf.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> OtherLeaf {
				        func __safeDI_service() -> ServiceProtocol {
				            return ConcreteService.__safeDI_mock(name: safeDIOverrides.service.name, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
				        }
				        let service: ServiceProtocol = __safeDI_service()
				        return OtherLeaf(service: service)
				    }
				}

				extension OtherLeaf {
				    public enum __safeDI_OtherLeaf_mock_51799E6AA5E7B634 {}
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
				    static func __safeDI_init(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ConcreteService {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService(name: name) }
				    }
				    static func __safeDI_mock(name: String?, safeDIBuilder: ((String) -> ConcreteService)?) -> ServiceProtocol {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name) } else { ConcreteService.mock(name: name) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// `Root`'s public mock builds `ConcreteService` as itself with its initializer, and, beneath the cycle through
	/// `Ticker`, as `ServiceProtocol` with its `mockOnly` mock, which takes other parameters: that node reads no overrides,
	/// so its `__safeDI_mock` takes a builder of the mock's parameters, which it passes `nil`, and the provider of the
	/// mock's optional default, which the configuration does not name.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBothConstructionFunctions_whenOnlyNodeBuiltWithMockIsBeneathCycleEdge(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["ConcreteService.swift": """
				import SafeDI

				public protocol ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				public final class ConcreteService: ServiceProtocol, Instantiable {
					public init(name: String = "init", tickerBuilder: Instantiator<Ticker>) {
						self.tickerBuilder = tickerBuilder
					}

					@Instantiated let tickerBuilder: Instantiator<Ticker>
				}

				public struct StubService: ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
				extension ConcreteService {
					public static func mock(name: String = "mock", tone: String? = "loud") -> ServiceProtocol {
						StubService()
					}
				}

				@Instantiable
				public final class Ticker: Instantiable {
					public init(service: ServiceProtocol) {
						self.service = service
					}

					@Instantiated let service: ServiceProtocol
				}

				@Instantiable(generateMock: .public)
				public final class Root: Instantiable {
					public init(concreteService: ConcreteService) {
						self.concreteService = concreteService
					}

					@Instantiated let concreteService: ConcreteService
				}
				"""]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            concreteService: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                concreteService: concreteService
			            )
			        }

			        public var concreteService: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.concreteService }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
			            ) {
			                self.concreteService = concreteService
			            }

			            let concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_concreteService() -> ConcreteService {
			            func __safeDI_tickerBuilder() -> Ticker {
			                func __safeDI_service() -> ServiceProtocol {
			                    return ConcreteService.__safeDI_mock(name: nil, tone: ConcreteService.__safeDI_mockDefault_tone(), safeDIBuilder: nil)
			                }
			                let service: ServiceProtocol = __safeDI_service()
			                return Ticker.__safeDI_init(service: service, safeDIBuilder: safeDIOverrides.concreteService.tickerBuilder.safeDIBuilder)
			            }
			            let tickerBuilder = Instantiator<Ticker>(__safeDI_tickerBuilder)
			            return ConcreteService.__safeDI_init(name: safeDIOverrides.concreteService.name, tickerBuilder: tickerBuilder, safeDIBuilder: safeDIOverrides.concreteService.safeDIBuilder)
			        }
			        let concreteService: ConcreteService = __safeDI_concreteService()
			        return Root(concreteService: concreteService)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Ticker` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Ticker_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((ServiceProtocol) -> Ticker)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `Ticker` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((ServiceProtocol) -> Ticker)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: ((ServiceProtocol) -> Ticker)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: ((ServiceProtocol) -> Ticker)?
			    }
			}

			extension Ticker {
			    static func __safeDI_init(service: ServiceProtocol, safeDIBuilder: ((ServiceProtocol) -> Ticker)?) -> Ticker {
			        if let safeDIBuilder { safeDIBuilder(service) } else { Ticker(service: service) }
			    }
			}

			/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
			    public init(
			        tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration = .init(),
			        name: String? = nil,
			        _ safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            tickerBuilder: tickerBuilder,
			            name: name,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration { __safeDI_storage.tickerBuilder }
			    /// `nil` keeps the default of `ConcreteService`’s `name`.
			    public var name: String? { __safeDI_storage.name }
			    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration,
			            name: String?,
			            safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)?
			        ) {
			            self.tickerBuilder = tickerBuilder
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration
			        let name: String?
			        let safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)?
			    }
			}

			extension ConcreteService {
			    nonisolated static func __safeDI_mockDefault_tone() -> String? { "loud" }
			    static func __safeDI_init(name: String?, tickerBuilder: Instantiator<Ticker>, safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)?) -> ConcreteService {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name, tickerBuilder) } else { ConcreteService(name: name, tickerBuilder: tickerBuilder) }
			    }
			    static func __safeDI_mock(name: String?, tone: String?, safeDIBuilder: ((String, String?) -> ConcreteService)?) -> ServiceProtocol {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name, tone) } else { ConcreteService.mock(name: name, tone: tone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"ConcreteService+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            concreteService: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                concreteService: concreteService
				            )
				        }

				        public var concreteService: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.concreteService }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
				            ) {
				                self.concreteService = concreteService
				            }

				            let concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        func __safeDI_concreteService() -> ConcreteService {
				            func __safeDI_tickerBuilder() -> Ticker {
				                func __safeDI_service() -> ServiceProtocol {
				                    return ConcreteService.__safeDI_mock(name: nil, tone: ConcreteService.__safeDI_mockDefault_tone(), safeDIBuilder: nil)
				                }
				                let service: ServiceProtocol = __safeDI_service()
				                return Ticker.__safeDI_init(service: service, safeDIBuilder: safeDIOverrides.concreteService.tickerBuilder.safeDIBuilder)
				            }
				            let tickerBuilder = Instantiator<Ticker>(__safeDI_tickerBuilder)
				            return ConcreteService.__safeDI_init(name: safeDIOverrides.concreteService.name, tickerBuilder: tickerBuilder, safeDIBuilder: safeDIOverrides.concreteService.safeDIBuilder)
				        }
				        let concreteService: ConcreteService = __safeDI_concreteService()
				        return Root(concreteService: concreteService)
				    }
				}

				extension Root {
				    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				/// Configuration for how `Ticker` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_Ticker_MockConfiguration {
				    public init(
				        _ safeDIBuilder: ((ServiceProtocol) -> Ticker)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// Overrides how `Ticker` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((ServiceProtocol) -> Ticker)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            safeDIBuilder: ((ServiceProtocol) -> Ticker)?
				        ) {
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let safeDIBuilder: ((ServiceProtocol) -> Ticker)?
				    }
				}

				extension Ticker {
				    static func __safeDI_init(service: ServiceProtocol, safeDIBuilder: ((ServiceProtocol) -> Ticker)?) -> Ticker {
				        if let safeDIBuilder { safeDIBuilder(service) } else { Ticker(service: service) }
				    }
				}

				/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
				    public init(
				        tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration = .init(),
				        name: String? = nil,
				        _ safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            tickerBuilder: tickerBuilder,
				            name: name,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration { __safeDI_storage.tickerBuilder }
				    /// `nil` keeps the default of `ConcreteService`’s `name`.
				    public var name: String? { __safeDI_storage.name }
				    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration,
				            name: String?,
				            safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)?
				        ) {
				            self.tickerBuilder = tickerBuilder
				            self.name = name
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration
				        let name: String?
				        let safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)?
				    }
				}

				extension ConcreteService {
				    nonisolated static func __safeDI_mockDefault_tone() -> String? { "loud" }
				    static func __safeDI_init(name: String?, tickerBuilder: Instantiator<Ticker>, safeDIBuilder: ((String, Instantiator<Ticker>) -> ConcreteService)?) -> ConcreteService {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name, tickerBuilder) } else { ConcreteService(name: name, tickerBuilder: tickerBuilder) }
				    }
				    static func __safeDI_mock(name: String?, tone: String?, safeDIBuilder: ((String, String?) -> ConcreteService)?) -> ServiceProtocol {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name, tone) } else { ConcreteService.mock(name: name, tone: tone) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// The cycle-edge build of the test above, where the initializer and the `mockOnly` mock each declare an optional
	/// `tone` of another type: each construction's function takes its own, whose provider is declared for each type.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresProviderOfEachConstruction_whenNodeBeneathCycleEdgeTakesDefaultOfSameLabelAndOtherType(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["ConcreteService.swift": """
				import SafeDI

				public protocol ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				public final class ConcreteService: ServiceProtocol, Instantiable {
					public init(name: String = "init", tone: Int? = 7, tickerBuilder: Instantiator<Ticker>) {
						self.tickerBuilder = tickerBuilder
					}

					@Instantiated let tickerBuilder: Instantiator<Ticker>
				}

				public struct StubService: ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
				extension ConcreteService {
					public static func mock(name: String = "mock", tone: String? = "loud") -> ServiceProtocol {
						StubService()
					}
				}

				@Instantiable
				public final class Ticker: Instantiable {
					public init(service: ServiceProtocol) {
						self.service = service
					}

					@Instantiated let service: ServiceProtocol
				}

				@Instantiable(generateMock: .public)
				public final class Root: Instantiable {
					public init(concreteService: ConcreteService) {
						self.concreteService = concreteService
					}

					@Instantiated let concreteService: ConcreteService
				}
				"""]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            concreteService: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                concreteService: concreteService
			            )
			        }

			        public var concreteService: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.concreteService }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
			            ) {
			                self.concreteService = concreteService
			            }

			            let concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_concreteService() -> ConcreteService {
			            func __safeDI_tickerBuilder() -> Ticker {
			                func __safeDI_service() -> ServiceProtocol {
			                    return ConcreteService.__safeDI_mock(name: nil, tone: ConcreteService.__safeDI_mockDefault_tone(), safeDIBuilder: nil)
			                }
			                let service: ServiceProtocol = __safeDI_service()
			                return Ticker.__safeDI_init(service: service, safeDIBuilder: safeDIOverrides.concreteService.tickerBuilder.safeDIBuilder)
			            }
			            let tickerBuilder = Instantiator<Ticker>(__safeDI_tickerBuilder)
			            return ConcreteService.__safeDI_init(name: safeDIOverrides.concreteService.name, tone: safeDIOverrides.concreteService.tone, tickerBuilder: tickerBuilder, safeDIBuilder: safeDIOverrides.concreteService.safeDIBuilder)
			        }
			        let concreteService: ConcreteService = __safeDI_concreteService()
			        return Root(concreteService: concreteService)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Ticker` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Ticker_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((ServiceProtocol) -> Ticker)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `Ticker` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((ServiceProtocol) -> Ticker)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: ((ServiceProtocol) -> Ticker)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: ((ServiceProtocol) -> Ticker)?
			    }
			}

			extension Ticker {
			    static func __safeDI_init(service: ServiceProtocol, safeDIBuilder: ((ServiceProtocol) -> Ticker)?) -> Ticker {
			        if let safeDIBuilder { safeDIBuilder(service) } else { Ticker(service: service) }
			    }
			}

			/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
			    public init(
			        tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration = .init(),
			        name: String? = nil,
			        tone: Int? = __safeDI_Feature_ConcreteService_mockDefault_tone(),
			        _ safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            tickerBuilder: tickerBuilder,
			            name: name,
			            tone: tone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration { __safeDI_storage.tickerBuilder }
			    /// `nil` keeps the default of `ConcreteService`’s `name`.
			    public var name: String? { __safeDI_storage.name }
			    /// The default of `ConcreteService`’s `tone` unless set.
			    public var tone: Int? { __safeDI_storage.tone }
			    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration,
			            name: String?,
			            tone: Int?,
			            safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)?
			        ) {
			            self.tickerBuilder = tickerBuilder
			            self.name = name
			            self.tone = tone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration
			        let name: String?
			        let tone: Int?
			        let safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)?
			    }
			}

			extension ConcreteService {
			    nonisolated static func __safeDI_mockDefault_tone() -> Int? { 7 }
			    nonisolated static func __safeDI_mockDefault_tone() -> String? { "loud" }
			    static func __safeDI_init(name: String?, tone: Int?, tickerBuilder: Instantiator<Ticker>, safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)?) -> ConcreteService {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name, tone, tickerBuilder) } else { ConcreteService(name: name, tone: tone, tickerBuilder: tickerBuilder) }
			    }
			    static func __safeDI_mock(name: String?, tone: String?, safeDIBuilder: ((String, String?) -> ConcreteService)?) -> ServiceProtocol {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name, tone) } else { ConcreteService.mock(name: name, tone: tone) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Feature_ConcreteService_mockDefault_tone() -> Int? { ConcreteService.__safeDI_mockDefault_tone() }
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"ConcreteService+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            concreteService: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                concreteService: concreteService
				            )
				        }

				        public var concreteService: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.concreteService }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
				            ) {
				                self.concreteService = concreteService
				            }

				            let concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        func __safeDI_concreteService() -> ConcreteService {
				            func __safeDI_tickerBuilder() -> Ticker {
				                func __safeDI_service() -> ServiceProtocol {
				                    return ConcreteService.__safeDI_mock(name: nil, tone: ConcreteService.__safeDI_mockDefault_tone(), safeDIBuilder: nil)
				                }
				                let service: ServiceProtocol = __safeDI_service()
				                return Ticker.__safeDI_init(service: service, safeDIBuilder: safeDIOverrides.concreteService.tickerBuilder.safeDIBuilder)
				            }
				            let tickerBuilder = Instantiator<Ticker>(__safeDI_tickerBuilder)
				            return ConcreteService.__safeDI_init(name: safeDIOverrides.concreteService.name, tone: safeDIOverrides.concreteService.tone, tickerBuilder: tickerBuilder, safeDIBuilder: safeDIOverrides.concreteService.safeDIBuilder)
				        }
				        let concreteService: ConcreteService = __safeDI_concreteService()
				        return Root(concreteService: concreteService)
				    }
				}

				extension Root {
				    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				/// Configuration for how `Ticker` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_Ticker_MockConfiguration {
				    public init(
				        _ safeDIBuilder: ((ServiceProtocol) -> Ticker)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// Overrides how `Ticker` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((ServiceProtocol) -> Ticker)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            safeDIBuilder: ((ServiceProtocol) -> Ticker)?
				        ) {
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let safeDIBuilder: ((ServiceProtocol) -> Ticker)?
				    }
				}

				extension Ticker {
				    static func __safeDI_init(service: ServiceProtocol, safeDIBuilder: ((ServiceProtocol) -> Ticker)?) -> Ticker {
				        if let safeDIBuilder { safeDIBuilder(service) } else { Ticker(service: service) }
				    }
				}

				/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
				    public init(
				        tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration = .init(),
				        name: String? = nil,
				        tone: Int? = __safeDI_Feature_ConcreteService_mockDefault_tone(),
				        _ safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            tickerBuilder: tickerBuilder,
				            name: name,
				            tone: tone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration { __safeDI_storage.tickerBuilder }
				    /// `nil` keeps the default of `ConcreteService`’s `name`.
				    public var name: String? { __safeDI_storage.name }
				    /// The default of `ConcreteService`’s `tone` unless set.
				    public var tone: Int? { __safeDI_storage.tone }
				    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration,
				            name: String?,
				            tone: Int?,
				            safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)?
				        ) {
				            self.tickerBuilder = tickerBuilder
				            self.name = name
				            self.tone = tone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration
				        let name: String?
				        let tone: Int?
				        let safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)?
				    }
				}

				extension ConcreteService {
				    nonisolated static func __safeDI_mockDefault_tone() -> Int? { 7 }
				    nonisolated static func __safeDI_mockDefault_tone() -> String? { "loud" }
				    static func __safeDI_init(name: String?, tone: Int?, tickerBuilder: Instantiator<Ticker>, safeDIBuilder: ((String, Int?, Instantiator<Ticker>) -> ConcreteService)?) -> ConcreteService {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name, tone, tickerBuilder) } else { ConcreteService(name: name, tone: tone, tickerBuilder: tickerBuilder) }
				    }
				    static func __safeDI_mock(name: String?, tone: String?, safeDIBuilder: ((String, String?) -> ConcreteService)?) -> ServiceProtocol {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name, tone) } else { ConcreteService.mock(name: name, tone: tone) }
				    }
				}
				@usableFromInline nonisolated func __safeDI_Feature_ConcreteService_mockDefault_tone() -> Int? { ConcreteService.__safeDI_mockDefault_tone() }
				#endif

				""",
			])
		}
	}

	/// The cycle-edge build again, where the initializer's optional `tone` is spelled `Optional<String>` with another
	/// default than the `mockOnly` mock's `String?`.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachConstructionWithItsOwnDefault_whenNodeBeneathCycleEdgeTakesDefaultOfSameLabelSpelledOtherwise(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["ConcreteService.swift": """
				import SafeDI

				public protocol ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				public final class ConcreteService: ServiceProtocol, Instantiable {
					public init(name: String = "init", tone: Optional<String> = "quiet", tickerBuilder: Instantiator<Ticker>) {
						self.tickerBuilder = tickerBuilder
					}

					@Instantiated let tickerBuilder: Instantiator<Ticker>
				}

				public struct StubService: ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
				extension ConcreteService {
					public static func mock(name: String = "mock", tone: String? = "loud") -> ServiceProtocol {
						StubService()
					}
				}

				@Instantiable
				public final class Ticker: Instantiable {
					public init(service: ServiceProtocol) {
						self.service = service
					}

					@Instantiated let service: ServiceProtocol
				}

				@Instantiable(generateMock: .public)
				public final class Root: Instantiable {
					public init(concreteService: ConcreteService) {
						self.concreteService = concreteService
					}

					@Instantiated let concreteService: ConcreteService
				}
				"""]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            concreteService: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                concreteService: concreteService
			            )
			        }

			        public var concreteService: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.concreteService }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
			            ) {
			                self.concreteService = concreteService
			            }

			            let concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_concreteService() -> ConcreteService {
			            func __safeDI_tickerBuilder() -> Ticker {
			                func __safeDI_service() -> ServiceProtocol {
			                    return ConcreteService.__safeDI_mock(name: nil, tone: ConcreteService.__safeDI_mockDefault_tone(), safeDIBuilder: nil)
			                }
			                let service: ServiceProtocol = __safeDI_service()
			                return Ticker.__safeDI_init(service: service, safeDIBuilder: safeDIOverrides.concreteService.tickerBuilder.safeDIBuilder)
			            }
			            let tickerBuilder = Instantiator<Ticker>(__safeDI_tickerBuilder)
			            return ConcreteService.__safeDI_init(name: safeDIOverrides.concreteService.name, tone: safeDIOverrides.concreteService.tone, tickerBuilder: tickerBuilder, safeDIBuilder: safeDIOverrides.concreteService.safeDIBuilder)
			        }
			        let concreteService: ConcreteService = __safeDI_concreteService()
			        return Root(concreteService: concreteService)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Ticker` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Ticker_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((ServiceProtocol) -> Ticker)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `Ticker` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((ServiceProtocol) -> Ticker)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: ((ServiceProtocol) -> Ticker)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: ((ServiceProtocol) -> Ticker)?
			    }
			}

			extension Ticker {
			    static func __safeDI_init(service: ServiceProtocol, safeDIBuilder: ((ServiceProtocol) -> Ticker)?) -> Ticker {
			        if let safeDIBuilder { safeDIBuilder(service) } else { Ticker(service: service) }
			    }
			}

			/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
			    public init(
			        tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration = .init(),
			        name: String? = nil,
			        tone: Optional<String>? = nil,
			        _ safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            tickerBuilder: tickerBuilder,
			            name: name,
			            tone: tone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration { __safeDI_storage.tickerBuilder }
			    /// `nil` keeps the default of `ConcreteService`’s `name`.
			    public var name: String? { __safeDI_storage.name }
			    /// `nil` keeps the default of `ConcreteService`’s `tone`.
			    public var tone: Optional<String>? { __safeDI_storage.tone }
			    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration,
			            name: String?,
			            tone: Optional<String>?,
			            safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)?
			        ) {
			            self.tickerBuilder = tickerBuilder
			            self.name = name
			            self.tone = tone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration
			        let name: String?
			        let tone: Optional<String>?
			        let safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)?
			    }
			}

			extension ConcreteService {
			    nonisolated static func __safeDI_mockDefault_tone() -> String? { "loud" }
			    static func __safeDI_init(name: String?, tone: Optional<String>?, tickerBuilder: Instantiator<Ticker>, safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)?) -> ConcreteService {
			        let name = name ?? ("mock")
			        let tone = tone ?? ("quiet")
			        return if let safeDIBuilder { safeDIBuilder(name, tone, tickerBuilder) } else { ConcreteService(name: name, tone: tone, tickerBuilder: tickerBuilder) }
			    }
			    static func __safeDI_mock(name: String?, tone: String?, safeDIBuilder: ((String, String?) -> ConcreteService)?) -> ServiceProtocol {
			        let name = name ?? ("mock")
			        return if let safeDIBuilder { safeDIBuilder(name, tone) } else { ConcreteService.mock(name: name, tone: tone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"ConcreteService+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            concreteService: __safeDI_Feature_ConcreteService_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                concreteService: concreteService
				            )
				        }

				        public var concreteService: __safeDI_Feature_ConcreteService_MockConfiguration { __safeDI_storage.concreteService }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
				            ) {
				                self.concreteService = concreteService
				            }

				            let concreteService: __safeDI_Feature_ConcreteService_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        func __safeDI_concreteService() -> ConcreteService {
				            func __safeDI_tickerBuilder() -> Ticker {
				                func __safeDI_service() -> ServiceProtocol {
				                    return ConcreteService.__safeDI_mock(name: nil, tone: ConcreteService.__safeDI_mockDefault_tone(), safeDIBuilder: nil)
				                }
				                let service: ServiceProtocol = __safeDI_service()
				                return Ticker.__safeDI_init(service: service, safeDIBuilder: safeDIOverrides.concreteService.tickerBuilder.safeDIBuilder)
				            }
				            let tickerBuilder = Instantiator<Ticker>(__safeDI_tickerBuilder)
				            return ConcreteService.__safeDI_init(name: safeDIOverrides.concreteService.name, tone: safeDIOverrides.concreteService.tone, tickerBuilder: tickerBuilder, safeDIBuilder: safeDIOverrides.concreteService.safeDIBuilder)
				        }
				        let concreteService: ConcreteService = __safeDI_concreteService()
				        return Root(concreteService: concreteService)
				    }
				}

				extension Root {
				    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				/// Configuration for how `Ticker` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_Ticker_MockConfiguration {
				    public init(
				        _ safeDIBuilder: ((ServiceProtocol) -> Ticker)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// Overrides how `Ticker` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((ServiceProtocol) -> Ticker)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            safeDIBuilder: ((ServiceProtocol) -> Ticker)?
				        ) {
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let safeDIBuilder: ((ServiceProtocol) -> Ticker)?
				    }
				}

				extension Ticker {
				    static func __safeDI_init(service: ServiceProtocol, safeDIBuilder: ((ServiceProtocol) -> Ticker)?) -> Ticker {
				        if let safeDIBuilder { safeDIBuilder(service) } else { Ticker(service: service) }
				    }
				}

				/// Configuration for how `ConcreteService` is constructed within the public mock trees of module `Feature`.
				nonisolated public struct __safeDI_Feature_ConcreteService_MockConfiguration {
				    public init(
				        tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration = .init(),
				        name: String? = nil,
				        tone: Optional<String>? = nil,
				        _ safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            tickerBuilder: tickerBuilder,
				            name: name,
				            tone: tone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration { __safeDI_storage.tickerBuilder }
				    /// `nil` keeps the default of `ConcreteService`’s `name`.
				    public var name: String? { __safeDI_storage.name }
				    /// `nil` keeps the default of `ConcreteService`’s `tone`.
				    public var tone: Optional<String>? { __safeDI_storage.tone }
				    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration,
				            name: String?,
				            tone: Optional<String>?,
				            safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)?
				        ) {
				            self.tickerBuilder = tickerBuilder
				            self.name = name
				            self.tone = tone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let tickerBuilder: __safeDI_Feature_Ticker_MockConfiguration
				        let name: String?
				        let tone: Optional<String>?
				        let safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)?
				    }
				}

				extension ConcreteService {
				    nonisolated static func __safeDI_mockDefault_tone() -> String? { "loud" }
				    static func __safeDI_init(name: String?, tone: Optional<String>?, tickerBuilder: Instantiator<Ticker>, safeDIBuilder: ((String, Optional<String>, Instantiator<Ticker>) -> ConcreteService)?) -> ConcreteService {
				        let name = name ?? ("mock")
				        let tone = tone ?? ("quiet")
				        return if let safeDIBuilder { safeDIBuilder(name, tone, tickerBuilder) } else { ConcreteService(name: name, tone: tone, tickerBuilder: tickerBuilder) }
				    }
				    static func __safeDI_mock(name: String?, tone: String?, safeDIBuilder: ((String, String?) -> ConcreteService)?) -> ServiceProtocol {
				        let name = name ?? ("mock")
				        return if let safeDIBuilder { safeDIBuilder(name, tone) } else { ConcreteService.mock(name: name, tone: tone) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// `SystemClock`'s `instantiate(…)` is isolated to the main actor and its custom mock is not: each construction
	/// function mirrors the isolation of the method it calls.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresConstructionFunctionsOfEachIsolation_whenInstantiateMethodIsIsolatedToMainActor(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
				import SafeDI

				public protocol Clock {}

				public final class SystemClock: Clock {
					public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Clock.self], generateMock: true, customMockName: "customMock")
				extension SystemClock: Instantiable {
					@MainActor public static func instantiate(zone: String = "UTC") -> SystemClock {
						SystemClock()
					}

					public static func customMock(zone: String = "UTC") -> Clock {
						SystemClock()
					}
				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["A.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: .public)
				@MainActor public final class A: Instantiable {
					public init(clock: Clock) {
						self.clock = clock
					}

					@Instantiated let clock: Clock
				}

				@Instantiable(generateMock: .public)
				@MainActor public final class B: Instantiable {
					public init(systemClock: SystemClock) {
						self.systemClock = systemClock
					}

					@Instantiated let systemClock: SystemClock
				}
				"""], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension SystemClock {
			    static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
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
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock
			            )
			        }

			        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.clock = clock
			            }

			            let clock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_clock() -> Clock {
			            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
			        }
			        let clock: Clock = __safeDI_clock()
			        return A(clock: clock)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                systemClock: systemClock
			            )
			        }

			        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                systemClock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.systemClock = systemClock
			            }

			            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_systemClock() -> SystemClock {
			            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
			        }
			        let systemClock: SystemClock = __safeDI_systemClock()
			        return B(systemClock: systemClock)
			    }
			}

			extension B {
			    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
			    public init(
			        zone: String? = nil,
			        _ safeDIBuilder: ((String) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `SystemClock`’s `zone`.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    @MainActor static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    static func mock(
				        zone: String = "UTC"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"A+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension A {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.clock = clock
				            }

				            let clock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        func __safeDI_clock() -> Clock {
				            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
				        }
				        let clock: Clock = __safeDI_clock()
				        return A(clock: clock)
				    }
				}

				extension A {
				    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                systemClock: systemClock
				            )
				        }

				        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                systemClock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.systemClock = systemClock
				            }

				            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        func __safeDI_systemClock() -> SystemClock {
				            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
				        }
				        let systemClock: SystemClock = __safeDI_systemClock()
				        return B(systemClock: systemClock)
				    }
				}

				extension B {
				    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
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
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
				    public init(
				        zone: String? = nil,
				        _ safeDIBuilder: ((String) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// `nil` keeps the default of `SystemClock`’s `zone`.
				    public var zone: String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: String?,
				            safeDIBuilder: ((String) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: String?
				        let safeDIBuilder: ((String) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    @MainActor static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// The reverse: `SystemClock`'s custom mock is isolated to the main actor and its `instantiate(…)` is not. Its own
	/// generated mock, which calls the custom mock, is put on the main actor with `mockAttributes`.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresConstructionFunctionsOfEachIsolation_whenCustomMockIsIsolatedToMainActor(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
				import SafeDI

				public protocol Clock {}

				public final class SystemClock: Clock {
					public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Clock.self], mockAttributes: "@MainActor", generateMock: true, customMockName: "customMock")
				extension SystemClock: Instantiable {
					public static func instantiate(zone: String = "UTC") -> SystemClock {
						SystemClock()
					}

					@MainActor public static func customMock(zone: String = "UTC") -> Clock {
						SystemClock()
					}
				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["A.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: .public)
				@MainActor public final class A: Instantiable {
					public init(clock: Clock) {
						self.clock = clock
					}

					@Instantiated let clock: Clock
				}

				@Instantiable(generateMock: .public)
				public final class B: Instantiable {
					public init(systemClock: SystemClock) {
						self.systemClock = systemClock
					}

					@Instantiated let systemClock: SystemClock
				}
				"""], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension SystemClock {
			    @MainActor static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
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
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock
			            )
			        }

			        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.clock = clock
			            }

			            let clock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_clock() -> Clock {
			            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
			        }
			        let clock: Clock = __safeDI_clock()
			        return A(clock: clock)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                systemClock: systemClock
			            )
			        }

			        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                systemClock: __safeDI_Other_SystemClock_MockConfiguration
			            ) {
			                self.systemClock = systemClock
			            }

			            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_systemClock() -> SystemClock {
			            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
			        }
			        let systemClock: SystemClock = __safeDI_systemClock()
			        return B(systemClock: systemClock)
			    }
			}

			extension B {
			    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
			    public init(
			        zone: String? = nil,
			        _ safeDIBuilder: ((String) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `SystemClock`’s `zone`.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    @MainActor static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    @MainActor static func mock(
				        zone: String = "UTC"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"A+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension A {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.clock = clock
				            }

				            let clock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        func __safeDI_clock() -> Clock {
				            return SystemClock.__safeDI_mock(zone: safeDIOverrides.clock.zone, safeDIBuilder: safeDIOverrides.clock.safeDIBuilder)
				        }
				        let clock: Clock = __safeDI_clock()
				        return A(clock: clock)
				    }
				}

				extension A {
				    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                systemClock: systemClock
				            )
				        }

				        public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                systemClock: __safeDI_Other_SystemClock_MockConfiguration
				            ) {
				                self.systemClock = systemClock
				            }

				            let systemClock: __safeDI_Other_SystemClock_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        func __safeDI_systemClock() -> SystemClock {
				            return SystemClock.__safeDI_init(zone: safeDIOverrides.systemClock.zone, safeDIBuilder: safeDIOverrides.systemClock.safeDIBuilder)
				        }
				        let systemClock: SystemClock = __safeDI_systemClock()
				        return B(systemClock: systemClock)
				    }
				}

				extension B {
				    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
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
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
				    public init(
				        zone: String? = nil,
				        _ safeDIBuilder: ((String) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// `nil` keeps the default of `SystemClock`’s `zone`.
				    public var zone: String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: String?,
				            safeDIBuilder: ((String) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: String?
				        let safeDIBuilder: ((String) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> SystemClock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    @MainActor static func __safeDI_mock(zone: String?, safeDIBuilder: ((String) -> SystemClock)?) -> Clock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// The holders build `SystemClock` inside `@Sendable` builder functions, through `SendableInstantiator`s of the types
	/// that hold it, so its configuration's builder and both construction functions' builders are `@Sendable`.
	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresSendableConstructionFunctions_whenPublicMocksBuildCustomMockTypeTwoWaysInSendableBuilders(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
				import SafeDI

				public protocol Clock: Sendable {}

				public final class SystemClock: Clock, Sendable {
					public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Clock.self], generateMock: true, customMockName: "customMock")
				extension SystemClock: Instantiable {
					public static func instantiate(zone: String = "UTC") -> SystemClock {
						SystemClock()
					}

					public static func customMock(zone: String = "UTC") -> Clock {
						SystemClock()
					}
				}
				"""]),
				ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["A.swift": """
				import SafeDI
				import Feature

				@Instantiable(generateMock: .public)
				public final class A: Instantiable {
					public init(clockBoxBuilder: SendableInstantiator<ClockBox>) {
						self.clockBoxBuilder = clockBoxBuilder
					}

					@Instantiated let clockBoxBuilder: SendableInstantiator<ClockBox>
				}

				@Instantiable(generateMock: .public)
				public final class B: Instantiable {
					public init(systemClockBoxBuilder: SendableInstantiator<SystemClockBox>) {
						self.systemClockBoxBuilder = systemClockBoxBuilder
					}

					@Instantiated let systemClockBoxBuilder: SendableInstantiator<SystemClockBox>
				}

				@Instantiable
				public final class ClockBox: Instantiable, Sendable {
					public init(clock: Clock) {
						self.clock = clock
					}

					@Instantiated let clock: Clock
				}

				@Instantiable
				public final class SystemClockBox: Instantiable, Sendable {
					public init(systemClock: SystemClock) {
						self.systemClock = systemClock
					}

					@Instantiated let systemClock: SystemClock
				}
				"""], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension SystemClock {
			    static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
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
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clockBoxBuilder: clockBoxBuilder
			            )
			        }

			        public var clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration { __safeDI_storage.clockBoxBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration
			            ) {
			                self.clockBoxBuilder = clockBoxBuilder
			            }

			            let clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let __safeDI_clockBoxBuilder__clockBoxBuilder_clock_safeDIBuilder = safeDIOverrides.clockBoxBuilder.clock.safeDIBuilder
			        let __safeDI_clockBoxBuilder__clockBoxBuilder_clock_zone = safeDIOverrides.clockBoxBuilder.clock.zone
			        let __safeDI_clockBoxBuilder__safeDIBuilder = safeDIOverrides.clockBoxBuilder.safeDIBuilder
			        @Sendable nonisolated func __safeDI_clockBoxBuilder() -> ClockBox {
			            func __safeDI_clock() -> Clock {
			                return SystemClock.__safeDI_mock(zone: __safeDI_clockBoxBuilder__clockBoxBuilder_clock_zone(), safeDIBuilder: __safeDI_clockBoxBuilder__clockBoxBuilder_clock_safeDIBuilder)
			            }
			            let clock: Clock = __safeDI_clock()
			            return ClockBox.__safeDI_init(clock: clock, safeDIBuilder: __safeDI_clockBoxBuilder__safeDIBuilder)
			        }
			        let clockBoxBuilder = SendableInstantiator<ClockBox>(__safeDI_clockBoxBuilder)
			        return A(clockBoxBuilder: clockBoxBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                systemClockBoxBuilder: systemClockBoxBuilder
			            )
			        }

			        public var systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration { __safeDI_storage.systemClockBoxBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration
			            ) {
			                self.systemClockBoxBuilder = systemClockBoxBuilder
			            }

			            let systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        let __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_safeDIBuilder = safeDIOverrides.systemClockBoxBuilder.systemClock.safeDIBuilder
			        let __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_zone = safeDIOverrides.systemClockBoxBuilder.systemClock.zone
			        let __safeDI_systemClockBoxBuilder__safeDIBuilder = safeDIOverrides.systemClockBoxBuilder.safeDIBuilder
			        @Sendable nonisolated func __safeDI_systemClockBoxBuilder() -> SystemClockBox {
			            func __safeDI_systemClock() -> SystemClock {
			                return SystemClock.__safeDI_init(zone: __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_zone(), safeDIBuilder: __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_safeDIBuilder)
			            }
			            let systemClock: SystemClock = __safeDI_systemClock()
			            return SystemClockBox.__safeDI_init(systemClock: systemClock, safeDIBuilder: __safeDI_systemClockBoxBuilder__safeDIBuilder)
			        }
			        let systemClockBoxBuilder = SendableInstantiator<SystemClockBox>(__safeDI_systemClockBoxBuilder)
			        return B(systemClockBoxBuilder: systemClockBoxBuilder)
			    }
			}

			extension B {
			    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
			    public init(
			        zone: @autoclosure @escaping @Sendable () -> String? = nil,
			        _ safeDIBuilder: (@Sendable (String) -> SystemClock)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `SystemClock`’s `zone`.
			    public var zone: @Sendable () -> String? { __safeDI_storage.zone }
			    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: @escaping @Sendable () -> String?,
			            safeDIBuilder: (@Sendable (String) -> SystemClock)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: @Sendable () -> String?
			        let safeDIBuilder: (@Sendable (String) -> SystemClock)?
			    }
			}

			extension SystemClock {
			    static func __safeDI_init(zone: String?, safeDIBuilder: (@Sendable (String) -> SystemClock)?) -> SystemClock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
			    }
			    static func __safeDI_mock(zone: String?, safeDIBuilder: (@Sendable (String) -> SystemClock)?) -> Clock {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
			    }
			}

			/// Configuration for how `ClockBox` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_ClockBox_MockConfiguration {
			    public init(
			        clock: __safeDI_Other_SystemClock_MockConfiguration = .init(),
			        _ safeDIBuilder: (@Sendable (Clock) -> ClockBox)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            clock: clock,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }
			    /// Overrides how `ClockBox` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (Clock) -> ClockBox)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            clock: __safeDI_Other_SystemClock_MockConfiguration,
			            safeDIBuilder: (@Sendable (Clock) -> ClockBox)?
			        ) {
			            self.clock = clock
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let clock: __safeDI_Other_SystemClock_MockConfiguration
			        let safeDIBuilder: (@Sendable (Clock) -> ClockBox)?
			    }
			}

			extension ClockBox {
			    static func __safeDI_init(clock: Clock, safeDIBuilder: (@Sendable (Clock) -> ClockBox)?) -> ClockBox {
			        if let safeDIBuilder { safeDIBuilder(clock) } else { ClockBox(clock: clock) }
			    }
			}

			/// Configuration for how `SystemClockBox` is constructed within the public mock trees of module `Other`.
			nonisolated public struct __safeDI_Other_SystemClockBox_MockConfiguration {
			    public init(
			        systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init(),
			        _ safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            systemClock: systemClock,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }
			    /// Overrides how `SystemClockBox` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            systemClock: __safeDI_Other_SystemClock_MockConfiguration,
			            safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)?
			        ) {
			            self.systemClock = systemClock
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let systemClock: __safeDI_Other_SystemClock_MockConfiguration
			        let safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)?
			    }
			}

			extension SystemClockBox {
			    static func __safeDI_init(systemClock: SystemClock, safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)?) -> SystemClockBox {
			        if let safeDIBuilder { safeDIBuilder(systemClock) } else { SystemClockBox(systemClock: systemClock) }
			    }
			}
			#endif

			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Types+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension SystemClock {
				    static func mock(
				        zone: String = "UTC"
				    ) -> Clock {
				        return SystemClock.customMock(zone: zone)
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["Other"]?.generatedFiles == [
				"A+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension A {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clockBoxBuilder: clockBoxBuilder
				            )
				        }

				        public var clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration { __safeDI_storage.clockBoxBuilder }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration
				            ) {
				                self.clockBoxBuilder = clockBoxBuilder
				            }

				            let clockBoxBuilder: __safeDI_Other_ClockBox_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        A.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> A {
				        let __safeDI_clockBoxBuilder__clockBoxBuilder_clock_safeDIBuilder = safeDIOverrides.clockBoxBuilder.clock.safeDIBuilder
				        let __safeDI_clockBoxBuilder__clockBoxBuilder_clock_zone = safeDIOverrides.clockBoxBuilder.clock.zone
				        let __safeDI_clockBoxBuilder__safeDIBuilder = safeDIOverrides.clockBoxBuilder.safeDIBuilder
				        @Sendable nonisolated func __safeDI_clockBoxBuilder() -> ClockBox {
				            func __safeDI_clock() -> Clock {
				                return SystemClock.__safeDI_mock(zone: __safeDI_clockBoxBuilder__clockBoxBuilder_clock_zone(), safeDIBuilder: __safeDI_clockBoxBuilder__clockBoxBuilder_clock_safeDIBuilder)
				            }
				            let clock: Clock = __safeDI_clock()
				            return ClockBox.__safeDI_init(clock: clock, safeDIBuilder: __safeDI_clockBoxBuilder__safeDIBuilder)
				        }
				        let clockBoxBuilder = SendableInstantiator<ClockBox>(__safeDI_clockBoxBuilder)
				        return A(clockBoxBuilder: clockBoxBuilder)
				    }
				}

				extension A {
				    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                systemClockBoxBuilder: systemClockBoxBuilder
				            )
				        }

				        public var systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration { __safeDI_storage.systemClockBoxBuilder }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration
				            ) {
				                self.systemClockBoxBuilder = systemClockBoxBuilder
				            }

				            let systemClockBoxBuilder: __safeDI_Other_SystemClockBox_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        B.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        let __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_safeDIBuilder = safeDIOverrides.systemClockBoxBuilder.systemClock.safeDIBuilder
				        let __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_zone = safeDIOverrides.systemClockBoxBuilder.systemClock.zone
				        let __safeDI_systemClockBoxBuilder__safeDIBuilder = safeDIOverrides.systemClockBoxBuilder.safeDIBuilder
				        @Sendable nonisolated func __safeDI_systemClockBoxBuilder() -> SystemClockBox {
				            func __safeDI_systemClock() -> SystemClock {
				                return SystemClock.__safeDI_init(zone: __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_zone(), safeDIBuilder: __safeDI_systemClockBoxBuilder__systemClockBoxBuilder_systemClock_safeDIBuilder)
				            }
				            let systemClock: SystemClock = __safeDI_systemClock()
				            return SystemClockBox.__safeDI_init(systemClock: systemClock, safeDIBuilder: __safeDI_systemClockBoxBuilder__safeDIBuilder)
				        }
				        let systemClockBoxBuilder = SendableInstantiator<SystemClockBox>(__safeDI_systemClockBoxBuilder)
				        return B(systemClockBoxBuilder: systemClockBoxBuilder)
				    }
				}

				extension B {
				    public enum __safeDI_B_mock_51799E6AA5E7B634 {}
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
				/// Configuration for how `SystemClock` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClock_MockConfiguration {
				    public init(
				        zone: @autoclosure @escaping @Sendable () -> String? = nil,
				        _ safeDIBuilder: (@Sendable (String) -> SystemClock)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            zone: zone,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    /// `nil` keeps the default of `SystemClock`’s `zone`.
				    public var zone: @Sendable () -> String? { __safeDI_storage.zone }
				    /// Overrides how `SystemClock` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (String) -> SystemClock)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            zone: @escaping @Sendable () -> String?,
				            safeDIBuilder: (@Sendable (String) -> SystemClock)?
				        ) {
				            self.zone = zone
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let zone: @Sendable () -> String?
				        let safeDIBuilder: (@Sendable (String) -> SystemClock)?
				    }
				}

				extension SystemClock {
				    static func __safeDI_init(zone: String?, safeDIBuilder: (@Sendable (String) -> SystemClock)?) -> SystemClock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.instantiate(zone: zone) }
				    }
				    static func __safeDI_mock(zone: String?, safeDIBuilder: (@Sendable (String) -> SystemClock)?) -> Clock {
				        let zone = zone ?? ("UTC")
				        return if let safeDIBuilder { safeDIBuilder(zone) } else { SystemClock.customMock(zone: zone) }
				    }
				}

				/// Configuration for how `ClockBox` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_ClockBox_MockConfiguration {
				    public init(
				        clock: __safeDI_Other_SystemClock_MockConfiguration = .init(),
				        _ safeDIBuilder: (@Sendable (Clock) -> ClockBox)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            clock: clock,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var clock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.clock }
				    /// Overrides how `ClockBox` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (Clock) -> ClockBox)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            clock: __safeDI_Other_SystemClock_MockConfiguration,
				            safeDIBuilder: (@Sendable (Clock) -> ClockBox)?
				        ) {
				            self.clock = clock
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let clock: __safeDI_Other_SystemClock_MockConfiguration
				        let safeDIBuilder: (@Sendable (Clock) -> ClockBox)?
				    }
				}

				extension ClockBox {
				    static func __safeDI_init(clock: Clock, safeDIBuilder: (@Sendable (Clock) -> ClockBox)?) -> ClockBox {
				        if let safeDIBuilder { safeDIBuilder(clock) } else { ClockBox(clock: clock) }
				    }
				}

				/// Configuration for how `SystemClockBox` is constructed within the public mock trees of module `Other`.
				nonisolated public struct __safeDI_Other_SystemClockBox_MockConfiguration {
				    public init(
				        systemClock: __safeDI_Other_SystemClock_MockConfiguration = .init(),
				        _ safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            systemClock: systemClock,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var systemClock: __safeDI_Other_SystemClock_MockConfiguration { __safeDI_storage.systemClock }
				    /// Overrides how `SystemClockBox` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            systemClock: __safeDI_Other_SystemClock_MockConfiguration,
				            safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)?
				        ) {
				            self.systemClock = systemClock
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let systemClock: __safeDI_Other_SystemClock_MockConfiguration
				        let safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)?
				    }
				}

				extension SystemClockBox {
				    static func __safeDI_init(systemClock: SystemClock, safeDIBuilder: (@Sendable (SystemClock) -> SystemClockBox)?) -> SystemClockBox {
				        if let safeDIBuilder { safeDIBuilder(systemClock) } else { SystemClockBox(systemClock: systemClock) }
				    }
				}
				#endif

				""",
			])
		}
	}

	/// `SystemClock`'s custom mock takes the two `Source` dependencies of its `instantiate(…)` method in the other order,
	/// so the one builder of its configuration would be handed each in the other's place.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMocksBuildTypeWithMockTakingSameTypedDependenciesInOtherOrder() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Clock.swift"]):13:5: error: Generated mocks build `SystemClock` with its hand-written `customMock` method for `clock: Clock` on `Parent` in `Parent.mock()`, and with its `instantiate(…)` method for `systemClock: SystemClock` on `Parent` in `Parent.mock()`. The two take different parameters, but both properties are configured with one `SystemClock.SafeDIMockConfiguration`. Make `customMock` return `SystemClock`, so that it builds both properties, or give `customMock` exactly the parameters of `SystemClock`’s `instantiate(…)` method, in the same order.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Parent: Instantiable {
					    public init(primary: Source, backup: Source, clock: Clock, systemClock: SystemClock) {
					        self.primary = primary
					        self.backup = backup
					        self.clock = clock
					        self.systemClock = systemClock
					    }
					    @Instantiated let primary: Source
					    @Instantiated let backup: Source
					    @Instantiated let clock: Clock
					    @Instantiated let systemClock: SystemClock
					}
					""",
					"""
					@Instantiable
					public final class Source: Instantiable {
					    public init() {}
					}
					""",
					"""
					public protocol Clock {}

					public final class SystemClock: Clock {
					    public init() {}
					}

					@Instantiable(fulfillingAdditionalTypes: [Clock.self], generateMock: true, customMockName: "customMock")
					extension SystemClock: Instantiable {
					    public static func instantiate(primary: Source, backup: Source, zone: String = "UTC") -> SystemClock {
					        SystemClock()
					    }

					    public static func customMock(backup: Source, primary: Source, zone: String = "UTC") -> Clock {
					        SystemClock()
					    }
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
	mutating func generate_declaresConstructionFunctionWithInitializersAttributes_whenInitializerSpellsGlobalActorOtherThanMainActor() async throws {
		// `Ledger`'s initializer spells `@DatabaseActor`, which its construction function repeats as written, beside
		// `Ledger`'s own isolation, the same actor.
		let modules = [
			ModuleFixture(name: "Store", packageName: "store", swiftFileContentByFilePath: ["Store.swift": """
			import SafeDI

			@globalActor
			public actor DatabaseActor {
			    public static let shared = DatabaseActor()
			}

			@DatabaseActor
			@Instantiable
			public final class Ledger: Instantiable {
			    @DatabaseActor public init(zone: String = "UTC") {
			        self.zone = zone
			    }

			    public let zone: String
			}

			@Instantiable(mockAttributes: "@DatabaseActor", generateMock: .public)
			public final class Book: Instantiable {
			    @DatabaseActor public init(ledger: Ledger) {
			        self.ledger = ledger
			    }

			    @Instantiated let ledger: Ledger
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Store"]?.generatedFiles == [
			"Store.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Book {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            ledger: __safeDI_Store_Ledger_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                ledger: ledger
			            )
			        }

			        public var ledger: __safeDI_Store_Ledger_MockConfiguration { __safeDI_storage.ledger }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                ledger: __safeDI_Store_Ledger_MockConfiguration
			            ) {
			                self.ledger = ledger
			            }

			            let ledger: __safeDI_Store_Ledger_MockConfiguration
			        }
			    }

			    @DatabaseActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        Book.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    @DatabaseActor public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Book {
			        func __safeDI_ledger() -> Ledger {
			            return Ledger.__safeDI_init(zone: safeDIOverrides.ledger.zone, safeDIBuilder: safeDIOverrides.ledger.safeDIBuilder)
			        }
			        let ledger: Ledger = __safeDI_ledger()
			        return Book(ledger: ledger)
			    }
			}

			extension Book {
			    public enum __safeDI_Book_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Ledger` is constructed within the public mock trees of module `Store`.
			nonisolated public struct __safeDI_Store_Ledger_MockConfiguration {
			    public init(
			        zone: String? = nil,
			        _ safeDIBuilder: ((String) -> Ledger)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            zone: zone,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Ledger`’s `zone`.
			    public var zone: String? { __safeDI_storage.zone }
			    /// Overrides how `Ledger` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> Ledger)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            zone: String?,
			            safeDIBuilder: ((String) -> Ledger)?
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: String?
			        let safeDIBuilder: ((String) -> Ledger)?
			    }
			}

			extension Ledger {
			    @DatabaseActor static func __safeDI_init(zone: String?, safeDIBuilder: ((String) -> Ledger)?) -> Ledger {
			        let zone = zone ?? ("UTC")
			        return if let safeDIBuilder { safeDIBuilder(zone) } else { Ledger(zone: zone) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresConstructionFunctionWithInitializersAttributes_whenInitializerOfTypeOffItsActorSpellsGlobalActor() async throws {
		// `Cache` is on no actor, but its initializer spells `@DatabaseActor`, so its construction function is spelled with
		// the initializer's attributes, as written: SafeDI reads no attribute's name.
		let modules = [
			ModuleFixture(name: "Store", packageName: "store", swiftFileContentByFilePath: ["Store.swift": """
			import SafeDI

			@globalActor
			public actor DatabaseActor {
			    public static let shared = DatabaseActor()
			}

			@Instantiable(mockAttributes: "@DatabaseActor", generateMock: .public)
			public final class Store: Instantiable {
			    @DatabaseActor public init(cache: Cache) {
			        self.cache = cache
			    }

			    @Instantiated let cache: Cache
			}

			@Instantiable
			public final class Cache: Instantiable {
			    @DatabaseActor public init(limit: Int = 3) {
			        self.limit = limit
			    }

			    let limit: Int
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Store"]?.generatedFiles == [
			"Store.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            cache: __safeDI_Store_Cache_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                cache: cache
			            )
			        }

			        public var cache: __safeDI_Store_Cache_MockConfiguration { __safeDI_storage.cache }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                cache: __safeDI_Store_Cache_MockConfiguration
			            ) {
			                self.cache = cache
			            }

			            let cache: __safeDI_Store_Cache_MockConfiguration
			        }
			    }

			    @DatabaseActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        Store.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    @DatabaseActor public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        func __safeDI_cache() -> Cache {
			            return Cache.__safeDI_init(limit: safeDIOverrides.cache.limit, safeDIBuilder: safeDIOverrides.cache.safeDIBuilder)
			        }
			        let cache: Cache = __safeDI_cache()
			        return Store(cache: cache)
			    }
			}

			extension Store {
			    public enum __safeDI_Store_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Cache` is constructed within the public mock trees of module `Store`.
			nonisolated public struct __safeDI_Store_Cache_MockConfiguration {
			    public init(
			        limit: Int? = nil,
			        _ safeDIBuilder: ((Int) -> Cache)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            limit: limit,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Cache`’s `limit`.
			    public var limit: Int? { __safeDI_storage.limit }
			    /// Overrides how `Cache` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Int) -> Cache)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            limit: Int?,
			            safeDIBuilder: ((Int) -> Cache)?
			        ) {
			            self.limit = limit
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let limit: Int?
			        let safeDIBuilder: ((Int) -> Cache)?
			    }
			}

			extension Cache {
			    @DatabaseActor static func __safeDI_init(limit: Int?, safeDIBuilder: ((Int) -> Cache)?) -> Cache {
			        let limit = limit ?? (3)
			        return if let safeDIBuilder { safeDIBuilder(limit) } else { Cache(limit: limit) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresConstructionFunctionWithInitializersAttributes_whenInitializerSpellsQualifiedMainActor() async throws {
		// `Cache`'s initializer spells the main actor qualified by its module, which its construction function copies as
		// written.
		let modules = [
			ModuleFixture(name: "Store", packageName: "store", swiftFileContentByFilePath: ["Store.swift": """
			import SafeDI

			@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
			public final class Store: Instantiable {
			    @MainActor public init(cache: Cache) {
			        self.cache = cache
			    }

			    @Instantiated let cache: Cache
			}

			@Instantiable
			public final class Cache: Instantiable {
			    @_Concurrency.MainActor public init(limit: Int = 3) {
			        self.limit = limit
			    }

			    let limit: Int
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Store"]?.generatedFiles == [
			"Store.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            cache: __safeDI_Store_Cache_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                cache: cache
			            )
			        }

			        public var cache: __safeDI_Store_Cache_MockConfiguration { __safeDI_storage.cache }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                cache: __safeDI_Store_Cache_MockConfiguration
			            ) {
			                self.cache = cache
			            }

			            let cache: __safeDI_Store_Cache_MockConfiguration
			        }
			    }

			    @MainActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        Store.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    @MainActor public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        func __safeDI_cache() -> Cache {
			            return Cache.__safeDI_init(limit: safeDIOverrides.cache.limit, safeDIBuilder: safeDIOverrides.cache.safeDIBuilder)
			        }
			        let cache: Cache = __safeDI_cache()
			        return Store(cache: cache)
			    }
			}

			extension Store {
			    public enum __safeDI_Store_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Cache` is constructed within the public mock trees of module `Store`.
			nonisolated public struct __safeDI_Store_Cache_MockConfiguration {
			    public init(
			        limit: Int? = nil,
			        _ safeDIBuilder: ((Int) -> Cache)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            limit: limit,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Cache`’s `limit`.
			    public var limit: Int? { __safeDI_storage.limit }
			    /// Overrides how `Cache` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Int) -> Cache)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            limit: Int?,
			            safeDIBuilder: ((Int) -> Cache)?
			        ) {
			            self.limit = limit
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let limit: Int?
			        let safeDIBuilder: ((Int) -> Cache)?
			    }
			}

			extension Cache {
			    @_Concurrency.MainActor static func __safeDI_init(limit: Int?, safeDIBuilder: ((Int) -> Cache)?) -> Cache {
			        let limit = limit ?? (3)
			        return if let safeDIBuilder { safeDIBuilder(limit) } else { Cache(limit: limit) }
			    }
			}
			#endif

			""",
		])
	}

	@Test(arguments: [
		("@_spi(Testing) public init(limit: Int = 3)", "let limit: Int"),
		// A `@backDeployed` function's body can read only `public` declarations on Apple platforms.
		("@backDeployed(before: macOS 99) public init(limit: Int = 3)", "public let limit: Int"),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresConstructionFunctionWithoutAttributeOnlyPublicDeclarationsTake_whenInitializerSpellsIt(initializer: String, property: String) async throws {
		// `@_spi` and `@backDeployed` apply only to a `public` declaration, and a construction function is `internal`, so it
		// repeats every attribute of the initializer but these.
		let modules = [
			ModuleFixture(name: "Store", packageName: "store", swiftFileContentByFilePath: ["Store.swift": """
			import SafeDI

			@Instantiable(generateMock: .public)
			public final class Store: Instantiable {
			    public init(cache: Cache) {
			        self.cache = cache
			    }

			    @Instantiated let cache: Cache
			}

			@Instantiable
			public struct Cache: Instantiable {
			    \(initializer) {
			        self.limit = limit
			    }

			    \(property)
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Store"]?.generatedFiles == [
			"Store.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            cache: __safeDI_Store_Cache_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                cache: cache
			            )
			        }

			        public var cache: __safeDI_Store_Cache_MockConfiguration { __safeDI_storage.cache }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                cache: __safeDI_Store_Cache_MockConfiguration
			            ) {
			                self.cache = cache
			            }

			            let cache: __safeDI_Store_Cache_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        Store.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        func __safeDI_cache() -> Cache {
			            return Cache.__safeDI_init(limit: safeDIOverrides.cache.limit, safeDIBuilder: safeDIOverrides.cache.safeDIBuilder)
			        }
			        let cache: Cache = __safeDI_cache()
			        return Store(cache: cache)
			    }
			}

			extension Store {
			    public enum __safeDI_Store_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Cache` is constructed within the public mock trees of module `Store`.
			nonisolated public struct __safeDI_Store_Cache_MockConfiguration {
			    public init(
			        limit: Int? = nil,
			        _ safeDIBuilder: ((Int) -> Cache)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            limit: limit,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Cache`’s `limit`.
			    public var limit: Int? { __safeDI_storage.limit }
			    /// Overrides how `Cache` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Int) -> Cache)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            limit: Int?,
			            safeDIBuilder: ((Int) -> Cache)?
			        ) {
			            self.limit = limit
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let limit: Int?
			        let safeDIBuilder: ((Int) -> Cache)?
			    }
			}

			extension Cache {
			    static func __safeDI_init(limit: Int?, safeDIBuilder: ((Int) -> Cache)?) -> Cache {
			        let limit = limit ?? (3)
			        return if let safeDIBuilder { safeDIBuilder(limit) } else { Cache(limit: limit) }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `SystemClock`, an extension-based type whose custom mock returns the protocol it fulfills and takes the parameters
	/// of its `instantiate(…)` method.
	private static let featureSystemClock = """
	import SafeDI

	public protocol Clock {}

	public final class SystemClock: Clock {
		public init() {}
	}

	@Instantiable(fulfillingAdditionalTypes: [Clock.self], generateMock: true, customMockName: "customMock")
	extension SystemClock: Instantiable {
		public static func instantiate(zone: String = "UTC") -> SystemClock {
			SystemClock()
		}

		public static func customMock(zone: String = "UTC") -> Clock {
			SystemClock()
		}
	}
	"""

	/// `A`, whose public mock builds `SystemClock` as `Clock` with its custom mock, and `B`, whose public mock builds it
	/// as itself with its `instantiate(…)` method.
	private static let otherClockFirst = """
	import SafeDI
	import Feature

	@Instantiable(generateMock: .public)
	public final class A: Instantiable {
		public init(clock: Clock) {
			self.clock = clock
		}

		@Instantiated let clock: Clock
	}

	@Instantiable(generateMock: .public)
	public final class B: Instantiable {
		public init(systemClock: SystemClock) {
			self.systemClock = systemClock
		}

		@Instantiated let systemClock: SystemClock
	}
	"""

	/// `otherClockFirst` with the two holders' names swapped, so the public mock that builds `SystemClock` as itself
	/// sorts first.
	private static let otherSystemClockFirst = """
	import SafeDI
	import Feature

	@Instantiable(generateMock: .public)
	public final class A: Instantiable {
		public init(systemClock: SystemClock) {
			self.systemClock = systemClock
		}

		@Instantiated let systemClock: SystemClock
	}

	@Instantiable(generateMock: .public)
	public final class B: Instantiable {
		public init(clock: Clock) {
			self.clock = clock
		}

		@Instantiated let clock: Clock
	}
	"""

	/// `ConcreteService`, whose `mockOnly` mock returns the protocol it fulfills and takes the parameters of its
	/// initializer, and the eraser `AnyService`.
	private static let featureConcreteService = """
	import SafeDI

	public protocol ServiceProtocol {}

	public struct AnyService: ServiceProtocol {
		public init(_ value: any ServiceProtocol) {}
	}

	@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
	public final class ConcreteService: ServiceProtocol, Instantiable {
		public init(name: String = "init") {}
	}

	@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
	extension ConcreteService {
		public static func mock(name: String = "mock") -> ServiceProtocol {
			ConcreteService()
		}
	}
	"""

	/// `OtherErased`, whose public mock builds `ConcreteService` erased to `AnyService` with its initializer, and
	/// `OtherLeaf`, whose public mock builds it as `ServiceProtocol` with its `mockOnly` mock.
	private static let otherErasedAndLeaf = """
	import SafeDI
	import Feature

	@Instantiable(generateMock: .public)
	public final class OtherErased: Instantiable {
		public init(service: AnyService) {
			self.service = service
		}

		@Instantiated(fulfilledByType: "ConcreteService", erasedToConcreteExistential: true) let service: AnyService
	}

	@Instantiable(generateMock: .public)
	public final class OtherLeaf: Instantiable {
		public init(service: ServiceProtocol) {
			self.service = service
		}

		@Instantiated let service: ServiceProtocol
	}
	"""
}
