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

/// A seam's parameter whose type is a name a tree declares `@escaping`, a typealias of a function type. Wherever a
/// generated initializer takes such a parameter by value, it spells it `@escaping`, or the value could not be stored,
/// forwarded, or captured by the autoclosure of the initializer only generated code calls. Each test compiles the
/// modules with the code generated from them.
struct SafeDIToolSeamEscapingTypealiasParameterTests: ~Copyable {
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
	mutating func generate_takesOwnForwardedTypealiasOfClosureEscaping_onBothInitializers(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.declarations,
					"""
					@Instantiable
					public final class ConfigReader: Instantiable {
					    public init(config: Config) { self.config = config }
					    @Received let config: Config
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(onTap: @escaping OnTap, reader: ConfigReader) { self.onTap = onTap; self.reader = reader }
					    @Forwarded let onTap: OnTap
					    @Instantiated let reader: ConfigReader
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: """
		extension Screen {
		    public convenience init(onTap: @escaping OnTap, config: Config) {
		        self.init(__safeDI_onTap: onTap, __safeDI_config: config)
		    }

		    public convenience init(__safeDI_onTap onTap: @escaping OnTap, __safeDI_config: @autoclosure @escaping () -> Config) {
		        let config = LazilyInstantiated<Config>(__safeDI_config)
		        let reader = ConfigReader(config: config.instance)
		        self.init(onTap: onTap, reader: reader)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_78E35F6751F3A2C5 {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesDeferredTypealiasOfClosureEscaping_onPlainInitializer(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.declarations,
					Self.tapReader,
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(reader: TapReader) { self.reader = reader }
					    @Instantiated let reader: TapReader
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: """
		extension Screen {
		    public convenience init(onTap: @escaping OnTap) {
		        self.init(__safeDI_onTap: onTap)
		    }

		    public convenience init(__safeDI_onTap: @autoclosure @escaping () -> OnTap) {
		        let onTap = LazilyInstantiated<OnTap>(__safeDI_onTap)
		        let reader = TapReader(onTap: onTap.instance)
		        self.init(reader: reader)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_620B4A759064B3AE {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesAliasFulfillingTypealiasEscaping_whenReceiverDeclaresOnlyItsOwnNameEscaping(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.declarations,
					"""
					public typealias Handler = (Int) -> Void
					""",
					"""
					@Instantiable
					public final class TapReader: Instantiable {
					    public init(onTap: @escaping OnTap) { self.onTap = onTap }
					    @Received(fulfilledByDependencyNamed: "tap", ofType: Handler.self) let onTap: OnTap
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(reader: TapReader) { self.reader = reader }
					    @Instantiated let reader: TapReader
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let fixtures = try #require(output.modules["Feature"]).fixtures
		let tapReaderPath = switch integration {
		case .moduleInfo: fixtures["TapReader.swift"]
		case .swiftPackagePlugin: fixtures.compilerPath(of: "TapReader.swift")
		}
		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: """
		extension Screen {
		    public convenience init(tap: @escaping Handler) {
		        self.init(__safeDI_tap: tap)
		    }

		    public convenience init(__safeDI_tap: @autoclosure @escaping () -> Handler) {
		        let tap = LazilyInstantiated<Handler>(__safeDI_tap)
		        func __safeDI_reader() -> TapReader {
		            #sourceLocation(file: "\(tapReaderPath)", line: 4)
		            let onTap: OnTap = tap.instance
		            #sourceLocation()
		            return TapReader(onTap: onTap)
		        }
		        let reader: TapReader = __safeDI_reader()
		        self.init(reader: reader)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_BECF708EDD1150DB {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypealiasOfClosureEscapingOnEveryTier_whenWiderTierForwardsOwnAndDeferredParameters(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesDeclaringTieredScreen,
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: Self.tieredScreenCode), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_compiles_whenPlainInitializerIsPassedAClosure(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesDeclaringTieredScreen + [
				ModuleFixture(name: "App", packageName: "Application", swiftFileContent: [
					"""
					import Feature

					public func screenFromLiteral() -> Screen {
					    Screen(onForward: { _ in }, onTap: { _ in })
					}

					public func screen(onForward: @escaping OnTap, onTap: @escaping OnTap) -> Screen {
					    Screen(onForward: onForward, onTap: onTap)
					}
					""",
				], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: Self.tieredScreenCode), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamFromAnotherModule_whenCallerHoldsForwardedTypealiasOfClosure(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesDeclaringTieredScreen + [
				ModuleFixture(name: "App", packageName: "Application", swiftFileContent: [
					"""
					import Feature

					@Instantiable
					public final class Host: Instantiable {
					    public init(onTap: @escaping OnTap, screenBuilder: Instantiator<Screen>) { self.onTap = onTap; self.screenBuilder = screenBuilder }
					    @Forwarded let onTap: OnTap
					    @Instantiated let screenBuilder: Instantiator<Screen>
					}
					""",
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(hostBuilder: Instantiator<Host>) { self.hostBuilder = hostBuilder }
					    @Instantiated let hostBuilder: Instantiator<Host>
					}
					""",
				], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "App", typeName: "Root", in: output, under: integration)
		#expect(file == Self.expectedFile(imports: ["Feature"], code: """
		extension Root {
		    public convenience init() {
		        func __safeDI_hostBuilder(onTap: @escaping OnTap) -> Host {
		            func __safeDI_screenBuilder(onForward: @escaping OnTap) -> Screen {
		                _ = Screen.__safeDI_Screen_09F3399971E0C31B.self // \(Self.guardComment(under: integration, moduleName: "Feature", typeName: "Screen"))
		                return Screen(__safeDI_onForward: onForward, __safeDI_onTap: onTap)
		            }
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(onForward: $0)
		            }
		            return Host(onTap: onTap, screenBuilder: screenBuilder)
		        }
		        let hostBuilder = Instantiator<Host> {
		            __safeDI_hostBuilder(onTap: $0)
		        }
		        self.init(hostBuilder: hostBuilder)
		    }
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesParameterEscaping_whenOnlyATypeBeneathANestedSeamThroughTwoModulesDeclaresIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.declarations,
					Self.tapReader,
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Inner: Instantiable {
					    public init(reader: TapReader) { self.reader = reader }
					    @Instantiated let reader: TapReader
					}
					""",
				]),
				ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Mid: Instantiable {
					    public init(inner: Inner) { self.inner = inner }
					    @Instantiated let inner: Inner
					}
					""",
				], dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Application", swiftFileContent: [
					"""
					import Feature
					import Middle

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(mid: Mid) { self.mid = mid }
					    @Instantiated let mid: Mid
					}
					""",
				], dependencies: ["Middle", "Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "App", typeName: "Outer", in: output, under: integration)
		#expect(file == Self.expectedFile(imports: ["Feature", "Middle"], code: """
		extension Outer {
		    public convenience init(onTap: @escaping OnTap) {
		        self.init(__safeDI_onTap: onTap)
		    }

		    public convenience init(__safeDI_onTap: @autoclosure @escaping () -> OnTap) {
		        let onTap = LazilyInstantiated<OnTap>(__safeDI_onTap)
		        func __safeDI_mid() -> Mid {
		            _ = Mid.__safeDI_Mid_620B4A759064B3AE.self // \(Self.guardComment(under: integration, moduleName: "Middle", typeName: "Mid"))
		            return Mid(__safeDI_onTap: onTap.instance)
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_620B4A759064B3AE {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesFieldEscaping_whenPayloadStructHoldsTypealiasOfClosureBesideDeferredParameter(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.declarations,
					"""
					public protocol Service {}
					""",
					"""
					@Instantiable
					public final class ServiceOwner: Instantiable {
					    public init(onForward: @escaping OnTap, config: Config, service: any Service) { self.onForward = onForward; self.config = config; self.service = service }
					    @Received let onForward: OnTap
					    @Received let config: Config
					    @Instantiated let service: any Service
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(onForward: @escaping OnTap, owner: ServiceOwner) { self.onForward = onForward; self.owner = owner }
					    @Forwarded let onForward: OnTap
					    @Instantiated let owner: ServiceOwner
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: """
		extension Screen {
		    @frozen public enum SafeDIScope_Service {
		        case owner_service(owner_service_Values)

		        public struct owner_service_Values {
		            public let onForward: OnTap
		            public var config: Config { __safeDI_config.instance }
		            let __safeDI_config: LazilyInstantiated<Config>

		            init(onForward: @escaping OnTap, config: LazilyInstantiated<Config>) {
		                self.onForward = onForward
		                __safeDI_config = config
		            }
		        }
		    }

		    public convenience init(onForward: @escaping OnTap, config: Config, serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        self.init(__safeDI_onForward: onForward, __safeDI_config: config, __safeDI_serviceBuilder: serviceBuilder)
		    }

		    public convenience init(__safeDI_onForward onForward: @escaping OnTap, __safeDI_config: @autoclosure @escaping () -> Config, __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        let config = LazilyInstantiated<Config>(__safeDI_config)
		        func __safeDI_owner() -> ServiceOwner {
		            let service: any Service = __safeDI_serviceBuilder(.owner_service(SafeDIScope_Service.owner_service_Values(onForward: onForward, config: config)))
		            return ServiceOwner(onForward: onForward, config: config.instance, service: service)
		        }
		        let owner: ServiceOwner = __safeDI_owner()
		        self.init(onForward: onForward, owner: owner)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_35392AC4A24860DB {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesFieldEscaping_whenStageStructHoldsTypealiasOfClosureBesideDeferredParameter(integration: MultiModuleIntegration) async throws {
		// The place is held in a `Sendable` wrapper, so its builder is staged: the first stage's struct stores the forwarded
		// function beside the memo of a deferred parameter, so its initializer takes the function `@escaping`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.declarations,
					"""
					public protocol Service: Sendable {}
					""",
					"""
					@Instantiable
					public final class ServiceOwner: Instantiable {
					    public init(onForward: @escaping OnTap, config: Config, service: SendableLazilyInstantiated<any Service>) { self.onForward = onForward; self.config = config; self.service = service }
					    @Received let onForward: OnTap
					    @Received let config: Config
					    @Instantiated let service: SendableLazilyInstantiated<any Service>
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(onForward: @escaping OnTap, owner: ServiceOwner) { self.onForward = onForward; self.owner = owner }
					    @Forwarded let onForward: OnTap
					    @Instantiated let owner: ServiceOwner
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: """
		extension Screen {
		    public enum SafeDIStagedScope_Service_owner_service {
		        public struct Stage1 {
		            public let onForward: OnTap
		            public var config: Config { __safeDI_config.instance }
		            let __safeDI_config: LazilyInstantiated<Config>

		            init(onForward: @escaping OnTap, config: LazilyInstantiated<Config>) {
		                self.onForward = onForward
		                __safeDI_config = config
		            }
		        }

		        public struct Stage2 {}
		    }

		    public convenience init(onForward: @escaping OnTap, config: Config, serviceBuilder_owner_service: @escaping (SafeDIStagedScope_Service_owner_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_owner_service.Stage2) -> any Service) {
		        self.init(__safeDI_onForward: onForward, __safeDI_config: config, __safeDI_serviceBuilder_owner_service: serviceBuilder_owner_service)
		    }

		    public convenience init(__safeDI_onForward onForward: @escaping OnTap, __safeDI_config: @autoclosure @escaping () -> Config, __safeDI_serviceBuilder_owner_service: @escaping (SafeDIStagedScope_Service_owner_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_owner_service.Stage2) -> any Service) {
		        let config = LazilyInstantiated<Config>(__safeDI_config)
		        func __safeDI_owner() -> ServiceOwner {
		            let __safeDI_serviceBuilder_owner_service_Stage2 = __safeDI_serviceBuilder_owner_service(SafeDIStagedScope_Service_owner_service.Stage1(onForward: onForward, config: config))
		            @Sendable func __safeDI_service() -> any Service {
		                __safeDI_serviceBuilder_owner_service_Stage2(SafeDIStagedScope_Service_owner_service.Stage2())
		            }
		            let service = SendableLazilyInstantiated<any Service>(__safeDI_service)
		            return ServiceOwner(onForward: onForward, config: config.instance, service: service)
		        }
		        let owner: ServiceOwner = __safeDI_owner()
		        self.init(onForward: onForward, owner: owner)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_DD790B818D2088B3 {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsEscapingOnlyOnNamesDeclaredEscaping_whenParametersAreMemberGenericAndOptional(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public typealias OnTap = (Int) -> Void
					public typealias Callback<Value> = (Value) -> Void

					public enum Space {
					    public typealias OnTap = (String) -> Void
					}
					""",
					"""
					@Instantiable
					public final class Reader: Instantiable {
					    public init(generic: @escaping Callback<String>, member: @escaping Space.OnTap, optional: OnTap?) { self.generic = generic; self.member = member; self.optional = optional }
					    @Received let generic: Callback<String>
					    @Received let member: Space.OnTap
					    @Received(onlyIfAvailable: true) let optional: OnTap?
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(reader: Reader) { self.reader = reader }
					    @Instantiated let reader: Reader
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: """
		extension Screen {
		    public convenience init(generic: @escaping Callback<String>, member: @escaping Space.OnTap, optional: OnTap?) {
		        self.init(__safeDI_generic: generic, __safeDI_member: member, __safeDI_optional: optional)
		    }

		    public convenience init(__safeDI_generic: @autoclosure @escaping () -> Callback<String>, __safeDI_member: @autoclosure @escaping () -> Space.OnTap, __safeDI_optional: @autoclosure @escaping () -> OnTap?) {
		        let generic = LazilyInstantiated<Callback<String>>(__safeDI_generic)
		        let member = LazilyInstantiated<Space.OnTap>(__safeDI_member)
		        let optional = LazilyInstantiated<OnTap?>(__safeDI_optional)
		        let reader = Reader(generic: generic.instance, member: member.instance, optional: optional.instance)
		        self.init(reader: reader)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_8B7DDFC30AB0E0DC {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypealiasOfClosureEscaping_whenDeferredParameterIsSendable(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public typealias SendableTap = @Sendable (Int) -> Void
					""",
					"""
					@Instantiable
					public final class SendableReader: Instantiable, Sendable {
					    public init(onTap: @escaping SendableTap) { self.onTap = onTap }
					    @Received let onTap: SendableTap
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable, Sendable {
					    public init(readerBuilder: SendableInstantiator<SendableReader>) { self.readerBuilder = readerBuilder }
					    @Instantiated let readerBuilder: SendableInstantiator<SendableReader>
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let file = try generatedFile(ofModuleNamed: "Feature", typeName: "Screen", in: output, under: integration)
		#expect(file == Self.expectedFile(code: """
		extension Screen {
		    public convenience init(onTap: @escaping SendableTap) {
		        self.init(__safeDI_onTap: onTap)
		    }

		    public convenience init(__safeDI_onTap: @autoclosure @escaping @Sendable () -> SendableTap) {
		        let onTap = SendableLazilyInstantiated<SendableTap>(__safeDI_onTap)
		        @Sendable func __safeDI_readerBuilder() -> SendableReader {
		            SendableReader(onTap: onTap.instance)
		        }
		        let readerBuilder = SendableInstantiator<SendableReader>(__safeDI_readerBuilder)
		        self.init(readerBuilder: readerBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_5B08F57331B6EB31 {}
		}
		"""), "Unexpected output \(file)")
		try expectEveryModuleCompiled(output)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let declarations = """
	public typealias OnTap = (Int) -> Void

	public struct Config {
	    public init() {}
	}
	"""

	private static let tapReader = """
	@Instantiable
	public final class TapReader: Instantiable {
	    public init(onTap: @escaping OnTap) { self.onTap = onTap }
	    @Received let onTap: OnTap
	}
	"""

	/// `Screen` takes its own `onForward` and a deferred `onTap` on both its tiers, and `secret`, whose type is `internal`,
	/// on the narrower one only, so its `public` tier forwards both to the `internal` one.
	private static let modulesDeclaringTieredScreen = [
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			declarations,
			tapReader,
			"""
			struct Secret {}
			""",
			"""
			@Instantiable
			public final class SecretReader: Instantiable {
			    init(secret: Secret?) { self.secret = secret }
			    @Received(onlyIfAvailable: true) let secret: Secret?
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Screen: Instantiable {
			    public init(onForward: @escaping OnTap, reader: TapReader, secretReader: SecretReader) { self.onForward = onForward; self.reader = reader; self.secretReader = secretReader }
			    @Forwarded let onForward: OnTap
			    @Instantiated let reader: TapReader
			    @Instantiated let secretReader: SecretReader
			}
			""",
		]),
	]

	private static let tieredScreenCode = """
	extension Screen {
	    public convenience init(onForward: @escaping OnTap, onTap: @escaping OnTap) {
	        self.init(__safeDI_onForward: onForward, __safeDI_onTap: onTap)
	    }

	    public convenience init(__safeDI_onForward onForward: @escaping OnTap, __safeDI_onTap: @autoclosure @escaping () -> OnTap) {
	        self.init(__safeDI_onForward: onForward, __safeDI_onTap: __safeDI_onTap(), __safeDI_secret: nil)
	    }

	    internal convenience init(onForward: @escaping OnTap, onTap: @escaping OnTap, secret: Secret?) {
	        self.init(__safeDI_onForward: onForward, __safeDI_onTap: onTap, __safeDI_secret: secret)
	    }

	    internal convenience init(__safeDI_onForward onForward: @escaping OnTap, __safeDI_onTap: @autoclosure @escaping () -> OnTap, __safeDI_secret: @autoclosure @escaping () -> Secret?) {
	        let onTap = LazilyInstantiated<OnTap>(__safeDI_onTap)
	        let secret = LazilyInstantiated<Secret?>(__safeDI_secret)
	        let reader = TapReader(onTap: onTap.instance)
	        let secretReader = SecretReader(secret: secret.instance)
	        self.init(onForward: onForward, reader: reader, secretReader: secretReader)
	    }
	}

	extension Screen {
	    public enum __safeDI_Screen_09F3399971E0C31B {}
	}
	"""

	/// The file generated for `typeName` in module `moduleName`.
	private func generatedFile(ofModuleNamed moduleName: String, typeName: String, in output: MultiModuleTestOutput, under integration: MultiModuleIntegration) throws -> String {
		let generatedFiles = try #require(output.modules[moduleName]).generatedFiles
		let fileName = switch integration {
		case .moduleInfo: "\(moduleName).swift"
		case .swiftPackagePlugin: "\(typeName)+SafeDI.swift"
		}
		return try #require(generatedFiles[fileName], "Unexpected files \(generatedFiles)")
	}

	/// A generated file's whole text: the header, `imports`, and `code`.
	private static func expectedFile(imports: [String] = [], code: String) -> String {
		generatedFileHeader + imports.map { "#if canImport(\($0))\nimport \($0)\n#endif\n" }.joined() + (imports.isEmpty ? "" : "\n") + code
	}

	/// The comment on a generated line that names the guard enum of `typeName`, declared in module `moduleName`.
	private static func guardComment(under integration: MultiModuleIntegration, moduleName: String, typeName: String) -> String {
		switch integration {
		case .moduleInfo:
			"If this line does not compile, compile the code SafeDI generates for module \(moduleName) into \(moduleName): under Bazel, add \(moduleName)'s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."
		case .swiftPackagePlugin:
			"If this line does not compile, add the SafeDI plugin to the target that declares \(typeName)."
		}
	}

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.moduleName) == output.moduleNames, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}
}
