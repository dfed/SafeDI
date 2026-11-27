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

/// A calling mock whose fill of a called public mock's place constructs a type the calling mock's module cannot reach
/// reports the access error its production twin reports, at the same declarations and with the same fix-its, where the
/// build compiles the generated mocks, but for a hand-written mock method the fill calls where the twin calls the
/// initializer. `Screen`, in `App`, instantiates `Panel`, whose initializer `App` cannot call, so
/// its mock calls `Panel`'s public mock; `App`'s `DefaultService` fills `Panel`'s place and instantiates `any Clock`, which
/// only `Meter`, declared in `Core`, fulfills.
struct SafeDIToolCallingMockAccessErrorTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the twin’s access errors, reported for the calling mock

	@Test(arguments: CallingMockCallerKind.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsAccessErrors_whenFillConstructsInternalTypeOfAnotherModuleOfSamePackage(caller: CallingMockCallerKind, calledTypes: CalledTypeDeclaration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1: error: `Meter` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Meter` `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1-6:1: fixit: package\(" ")
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5: error: `Meter`’s initializer is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5-7:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(caller: caller, callee: calledTypes.attribute, meter: .internalInSamePackage), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1: error: `Meter` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Meter` `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1-6:1: fixit: package\(" ")
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5: error: `Meter`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5-7:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.twinModules(meter: .internalInSamePackage), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCallerKind.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsAccessErrors_whenFillConstructsPackageTypeOfAnotherPackage(caller: CallingMockCallerKind, calledTypes: CalledTypeDeclaration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1: error: `Meter` is `package`, so the mock of `Screen`, generated in module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Meter` `public` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1-6:8: fixit: public
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5: error: `Meter`’s initializer is `package`, so the mock of `Screen`, generated in module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5-7:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(caller: caller, callee: calledTypes.attribute, meter: .packageInAnotherPackage), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1: error: `Meter` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Meter` `public` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1-6:8: fixit: public
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5: error: `Meter`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5-7:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.twinModules(meter: .packageInAnotherPackage), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsAccessErrors_whenTypeBeneathFillConstructsInternalTypeOfAnotherModule(caller: CallingMockCallerKind) async {
		// `DefaultService` instantiates `Part`, of `App`, which instantiates `any Clock`: the construction is one level beneath
		// the fill, where the twin reports it too.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1: error: `Meter` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Meter` `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1-6:1: fixit: package\(" ")
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5: error: `Meter`’s initializer is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5-7:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(caller: caller, callee: Self.twinCalledTypes, meter: .internalInSamePackage, clockIsBeneathFill: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1: error: `Meter` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Meter` `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1-6:1: fixit: package\(" ")
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5: error: `Meter`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5-7:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.twinModules(meter: .internalInSamePackage, clockIsBeneathFill: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEachAccessErrorOnceNamingMockDeclaredFirst_whenTwentyMockRootsReachFillThatConstructsInternalTypeOfAnotherModule() async {
		// `Screen` and the nineteen roots declared after it, whose names all sort before it, each generate a mock whose tree
		// calls `Panel`’s public mock, and each fills its place with `DefaultService`: each declaration to widen is reported
		// once, naming `Screen`, the mock declared first, which neither name order nor an unordered pick would name.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1: error: `Meter` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Meter` `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):6:1-6:1: fixit: package\(" ")
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5: error: `Meter`’s initializer is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):7:5-7:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(caller: .internal, callee: Self.twinCalledTypes, meter: .internalInSamePackage, declaresOtherMockRoots: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsMockMethodsAccessError_whenFillBuildsTypeWhoseHandWrittenMockIsInternalToAnotherModuleOfSamePackage(caller: CallingMockCallerKind) async throws {
		// `Meter` and its initializer are `public`, and its hand-written `mock()` is `internal`. The twin builds `Meter` with
		// its initializer and is accepted; the calling mock’s fill, as every mock’s tree, builds it with its hand-written
		// mock, which `App` cannot call (`seam-and-mock-contract.md`, rule 7).
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.twinModules(meter: .publicWithInternalMockInSamePackage), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["CoreTypes.swift"]):8:5: error: `Meter.mock()` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make `Meter.mock()` `package` to fix.
			\(fixtures["Core"]!["CoreTypes.swift"]):8:5-8:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(caller: caller, callee: Self.twinCalledTypes, meter: .publicWithInternalMockInSamePackage), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – each error’s remedy works for the calling mock

	@Test(arguments: CallingMockCallerKind.allCases, MeterDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceAsTwin_whenAccessErrorsFixItsAreApplied(caller: CallingMockCallerKind, meter: MeterDeclaration) async throws {
		// Each fix-it applied: the calling mock and its twin are accepted, and the mock fills the place with `DefaultService`,
		// as the twin does, so `mock()` takes no builder for it. The fill builds `Meter` with its hand-written mock where it
		// has one.
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.twinModules(meter: meter.remedied), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(caller: caller, callee: Self.twinCalledTypes, meter: meter.remedied), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.expectedFileWhereFillIsFilled(caller: caller, meterConstruction: meter.remedied.construction)])
	}

	// MARK: Tests – the mock condition off

	@Test(arguments: [MockConditionCaller.internal, .public, .listed], MockConditionInactiveBuild.allCases.flatMap { build in [MeterDeclaration.internalInSamePackage, .publicWithInternalMockInSamePackage].map { (build: build, meter: $0) } })
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUp_whenBuildLeavesMockConditionInactive(caller: MockConditionCaller, buildAndMeter: (build: MockConditionInactiveBuild, meter: MeterDeclaration)) async throws {
		// A build that does not tell the tool `DEBUG`, the mock condition, never compiles the fill the error is about: a
		// release build compiles no generated mock, and a debug build whose integration does not report `DEBUG` compiles the
		// mock, which, the place passed up, constructs nothing it cannot reach. So the tool reports nothing, whether the fill
		// would construct a type or call a hand-written mock it cannot reach.
		let (build, meter) = buildAndMeter
		let callerKind: CallingMockCallerKind = switch caller {
		case .internal:
			.internal
		case .public:
			.public
		case .listed:
			.listed
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(caller: callerKind, callee: Self.twinCalledTypes, meter: meter, appBuild: build),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.expectedFileWherePlaceIsPassedUp(caller: callerKind)])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A called type’s attribute line in the production twin: a seam as well as a public mock.
	private static let twinCalledTypes = CalledTypeDeclaration.seamAndPublicMock.attribute

	/// What `App` generates where `Meter` is accessible: `Panel`’s place filled with `DefaultService`, which builds `Meter`
	/// with `meterConstruction`, as the twin fills it, and `mock()` taking no builder for it. A listed type’s mock is an
	/// internal mock’s.
	private static func expectedFileWhereFillIsFilled(caller: CallingMockCallerKind, meterConstruction: String) -> String {
		switch caller {
		case .internal, .listed:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: ((@escaping () -> any Service) -> Panel)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        var panel: ((@escaping () -> any Service) -> Panel)? { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((@escaping () -> any Service) -> Panel)?
			            ) {
			                self.panel = panel
			            }

			            let panel: ((@escaping () -> any Service) -> Panel)?
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let clock: any Clock = \(meterConstruction)
			                    return DefaultService(clock: clock)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Panel_service() })
			            }
			            _ = Panel.__safeDI_Panel_mock_4C19E5205B40458C.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Panel_service() } }) } else { Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel()) }
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			"""
		case .public:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            panel: ((@escaping () -> any Service) -> Panel)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        public var panel: ((@escaping () -> any Service) -> Panel)? { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((@escaping () -> any Service) -> Panel)?
			            ) {
			                self.panel = panel
			            }

			            let panel: ((@escaping () -> any Service) -> Panel)?
			        }
			    }

			    public static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel_service() -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let clock: any Clock = \(meterConstruction)
			                    return DefaultService(clock: clock)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { _ in __safeDI_serviceBuilder_Panel_service() })
			            }
			            _ = Panel.__safeDI_Panel_mock_4C19E5205B40458C.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder({ if let __safeDI_serviceBuilder { __safeDI_serviceBuilder() } else { __safeDI_serviceBuilder_Panel_service() } }) } else { Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel()) }
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_E1553F902C7FFA09 {}
			}
			#endif
			"""
		}
	}

	/// What `App` generates in a build that leaves the mock condition inactive: `Panel`’s place passed up, as
	/// `serviceBuilder`, which `mock()` takes. A listed type’s mock is an internal mock’s.
	private static func expectedFileWherePlaceIsPassedUp(caller: CallingMockCallerKind) -> String {
		switch caller {
		case .internal, .listed:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: ((@escaping () -> any Service) -> Panel)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        var panel: ((@escaping () -> any Service) -> Panel)? { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((@escaping () -> any Service) -> Panel)?
			            ) {
			                self.panel = panel
			            }

			            let panel: ((@escaping () -> any Service) -> Panel)?
			        }
			    }

			    static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_serviceBuilder = serviceBuilder
			        _ = Panel.__safeDI_Panel_mock_4C19E5205B40458C.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_panel() -> Panel {
			            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(serviceBuilder) } else { Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder)) }
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			"""
		case .public:
			generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct panel_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let panel: (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.panel = panel
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Screen.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        _ = Panel.__safeDI_Panel_mock_4C19E5205B40458C.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        let panel = Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.panel(SafeDIMockScope_Service.panel_Values()))
			        return Screen(panel: panel)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_1A111754C3259C52 {}
			}
			#endif
			"""
		}
	}

	/// How `Core` declares `Meter`, and which package `Core` is in.
	enum MeterDeclaration: CaseIterable, CustomTestStringConvertible {
		/// `internal`, in `App`’s package.
		case internalInSamePackage
		/// `package`, in a package of its own.
		case packageInAnotherPackage
		/// `package`, in `App`’s package: the fix-it of `internalInSamePackage` applied.
		case packageInSamePackage
		/// `public`, in a package of its own: the fix-it of `packageInAnotherPackage` applied.
		case publicInAnotherPackage
		/// `public`, with a `public` initializer and an `internal` hand-written mock, in `App`’s package.
		case publicWithInternalMockInSamePackage
		/// `public`, with a `public` initializer and a `package` hand-written mock, in `App`’s package: the fix-it of
		/// `publicWithInternalMockInSamePackage` applied.
		case publicWithPackageMockInSamePackage

		static let allCases: [Self] = [.internalInSamePackage, .packageInAnotherPackage, .publicWithInternalMockInSamePackage]

		/// The declaration with its error’s fix-its applied.
		var remedied: Self {
			switch self {
			case .internalInSamePackage, .packageInSamePackage:
				.packageInSamePackage
			case .packageInAnotherPackage, .publicInAnotherPackage:
				.publicInAnotherPackage
			case .publicWithInternalMockInSamePackage, .publicWithPackageMockInSamePackage:
				.publicWithPackageMockInSamePackage
			}
		}

		/// The access `Meter` and its initializer spell, with the space after it.
		var access: String {
			switch self {
			case .internalInSamePackage:
				""
			case .packageInAnotherPackage, .packageInSamePackage:
				"package "
			case .publicInAnotherPackage, .publicWithInternalMockInSamePackage, .publicWithPackageMockInSamePackage:
				"public "
			}
		}

		/// The line that declares `Meter`’s hand-written mock, or an empty one where it has none.
		var mockMethod: String {
			switch self {
			case .internalInSamePackage, .packageInAnotherPackage, .packageInSamePackage, .publicInAnotherPackage:
				""
			case .publicWithInternalMockInSamePackage:
				"static func mock() -> Meter { Meter() }"
			case .publicWithPackageMockInSamePackage:
				"package static func mock() -> Meter { Meter() }"
			}
		}

		/// How a mock’s tree builds `Meter`: with its hand-written mock where it has one.
		var construction: String {
			switch self {
			case .internalInSamePackage, .packageInAnotherPackage, .packageInSamePackage, .publicInAnotherPackage:
				"Meter()"
			case .publicWithInternalMockInSamePackage, .publicWithPackageMockInSamePackage:
				"Meter.mock()"
			}
		}

		/// `Core`’s package.
		var packageName: String {
			switch self {
			case .internalInSamePackage, .packageInSamePackage, .publicWithInternalMockInSamePackage, .publicWithPackageMockInSamePackage:
				"App"
			case .packageInAnotherPackage, .publicInAnotherPackage:
				"Core"
			}
		}

		var testDescription: String {
			switch self {
			case .internalInSamePackage:
				"internal type of another module of the same package"
			case .packageInAnotherPackage:
				"package type of another package"
			case .packageInSamePackage:
				"package type of another module of the same package"
			case .publicInAnotherPackage:
				"public type of another package"
			case .publicWithInternalMockInSamePackage:
				"public type with an internal hand-written mock, of another module of the same package"
			case .publicWithPackageMockInSamePackage:
				"public type with a package hand-written mock, of another module of the same package"
			}
		}
	}

	/// The calling mock’s modules: `Core`, which declares `Meter` as `meter` says; `Up`, whose `Panel` has a place `App`’s
	/// `DefaultService` fills; and `App`, whose `Screen` is the caller `caller` says. `App`’s build tells the tool `DEBUG`,
	/// the mock condition, unless `appBuild` says otherwise.
	private static func modules(
		caller: CallingMockCallerKind,
		callee: String,
		meter: MeterDeclaration,
		clockIsBeneathFill: Bool = false,
		declaresOtherMockRoots: Bool = false,
		appBuild: MockConditionInactiveBuild? = nil,
	) -> [ModuleFixture] {
		var appFiles = ["AppTypes.swift": appContent(caller: caller.attribute(listed: "@Instantiable"), clockIsBeneathFill: clockIsBeneathFill, declaresOtherMockRoots: declaresOtherMockRoots)]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n"
		}
		return [
			coreModule(meter: meter),
			upModule(callee: callee),
			ModuleFixture(
				name: "App",
				packageName: "App",
				swiftFileContentByFilePath: appFiles,
				dependencies: ["Core", "Up"],
				activeCompilationConditions: appBuild == nil ? ["DEBUG"] : [],
				isReleaseConfiguration: appBuild == .release,
			),
		]
	}

	/// The production twin’s modules: `Screen` a seam, `Panel` a seam and a public mock.
	private static func twinModules(meter: MeterDeclaration, clockIsBeneathFill: Bool = false) -> [ModuleFixture] {
		[
			coreModule(meter: meter),
			upModule(callee: twinCalledTypes),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": appContent(caller: "@Instantiable(generateDependencyTree: true)", clockIsBeneathFill: clockIsBeneathFill, declaresOtherMockRoots: false)], dependencies: ["Core", "Up"]),
		]
	}

	private static func coreModule(meter: MeterDeclaration) -> ModuleFixture {
		ModuleFixture(name: "Core", packageName: meter.packageName, swiftFileContentByFilePath: [
			"CoreTypes.swift": """
			import SafeDI

			public protocol Clock: AnyObject {}

			@Instantiable(fulfillingAdditionalTypes: [Clock.self])
			\(meter.access)final class Meter: Clock, Instantiable {
			    \(meter.access)init() {}
			    \(meter.mockMethod)
			}
			""",
		])
	}

	private static func upModule(callee: String) -> ModuleFixture {
		ModuleFixture(name: "Up", packageName: "Up", swiftFileContentByFilePath: [
			"UpTypes.swift": """
			import SafeDI

			public protocol Service: AnyObject {}

			\(callee)
			public final class Panel: Instantiable {
			    init(service: any Service) { self.service = service }
			    @Instantiated public let service: any Service
			}
			""",
		])
	}

	/// Nineteen types `App` declares after `Screen`, each a mock root whose tree calls `Panel`’s public mock, whose names all
	/// sort before `Screen`’s.
	private static let otherMockRootNames = ["Alcove", "Annex", "Arcade", "Atrium", "Attic", "Aviary", "Balcony", "Bazaar", "Cabin", "Cellar", "Chapel", "Cloister", "Corridor", "Courtyard", "Den", "Foyer", "Gallery", "Garage", "Hall"]

	private static func appContent(caller: String, clockIsBeneathFill: Bool, declaresOtherMockRoots: Bool) -> String {
		let part = """

		@Instantiable
		public final class Part: Instantiable {
		    public init(clock: any Clock) { self.clock = clock }
		    @Instantiated let clock: any Clock
		}

		"""
		let otherMockRoots = otherMockRootNames.map { name in
			"""

			@Instantiable(generateMock: true)
			public final class \(name): Instantiable {
			    public init(panel: Panel) { self.panel = panel }
			    @Instantiated public let panel: Panel
			}
			"""
		}.joined()
		let serviceProperty = clockIsBeneathFill ? (label: "part", type: "Part") : (label: "clock", type: "any Clock")
		return """
		import Core
		import SafeDI
		import Up
		\(clockIsBeneathFill ? part : "")
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Service, Instantiable {
		    public init(\(serviceProperty.label): \(serviceProperty.type)) { self.\(serviceProperty.label) = \(serviceProperty.label) }
		    @Instantiated let \(serviceProperty.label): \(serviceProperty.type)
		}

		\(caller)
		public final class Screen: Instantiable {
		    public init(panel: Panel) { self.panel = panel }
		    @Instantiated public let panel: Panel
		}
		\(declaresOtherMockRoots ? otherMockRoots : "")
		"""
	}
}
