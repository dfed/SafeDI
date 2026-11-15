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

/// A seam's plain scope enum is nested by type: one enum per type of the seam's tree that leads to a place, wrapped by the
/// case of the property that builds it, so a type reached on many paths has one enum, and the caller's dispatchers are one
/// per enum.
struct SafeDIToolSeamScopeByTypeTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneEnumPerTypeAndCallerCompiles_whenTwentyFourScreensOpenTheNextLayerInLayers() async throws {
		// Shape E: `Home` opens four screens, each screen opens three of the next layer's four, six layers deep, and each
		// screen of the last layer builds a model whose `api` only `App` can build. One case per path would be 972 cases,
		// which the caller's switch could not compile; by type it is a case per property: 4 + 20 × 3 + 4 + 4. The caller's
		// file is compared in full, so the order of its dispatchers and their cases is pinned.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.shapeEModules(screenCount: 24),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let featureFile = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
		let enumDeclaration = try #require(featureFile.components(separatedBy: "    /// Only code SafeDI generates calls this initializer").first)
		let caseCount = enumDeclaration.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ") }.count
		let enumCount = enumDeclaration.components(separatedBy: "@frozen public enum ").count - 1
		#expect(caseCount == 72)
		#expect(enumCount == 29)
		// One dispatcher per enum, one-level switches: the caller compiled above.
		let appFile = try #require(output.modules["App"]?.generatedFiles["App.swift"])
		#expect(appFile.components(separatedBy: "func __safeDI_apiBuilder_Home").count - 1 == 29)
		#expect(appFile == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_32D04396E763F41A.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(screen0Builder: { _ in __safeDI_apiBuilder_Home_Screen0_Scope() }, screen1Builder: { _ in __safeDI_apiBuilder_Home_Screen1_Scope() }, screen2Builder: { _ in __safeDI_apiBuilder_Home_Screen2_Scope() }, screen3Builder: { _ in __safeDI_apiBuilder_Home_Screen3_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen0_Scope() -> Home.SafeDIScope_Api.Screen0_Scope.__safeDI_Builder<any Api> {
		                .init(screen5Builder: { _ in __safeDI_apiBuilder_Home_Screen5_Scope() }, screen6Builder: { _ in __safeDI_apiBuilder_Home_Screen6_Scope() }, screen7Builder: { _ in __safeDI_apiBuilder_Home_Screen7_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen5_Scope() -> Home.SafeDIScope_Api.Screen5_Scope.__safeDI_Builder<any Api> {
		                .init(screen8Builder: { _ in __safeDI_apiBuilder_Home_Screen8_Scope() }, screen10Builder: { _ in __safeDI_apiBuilder_Home_Screen10_Scope() }, screen11Builder: { _ in __safeDI_apiBuilder_Home_Screen11_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen8_Scope() -> Home.SafeDIScope_Api.Screen8_Scope.__safeDI_Builder<any Api> {
		                .init(screen13Builder: { _ in __safeDI_apiBuilder_Home_Screen13_Scope() }, screen14Builder: { _ in __safeDI_apiBuilder_Home_Screen14_Scope() }, screen15Builder: { _ in __safeDI_apiBuilder_Home_Screen15_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen13_Scope() -> Home.SafeDIScope_Api.Screen13_Scope.__safeDI_Builder<any Api> {
		                .init(screen16Builder: { _ in __safeDI_apiBuilder_Home_Screen16_Scope() }, screen18Builder: { _ in __safeDI_apiBuilder_Home_Screen18_Scope() }, screen19Builder: { _ in __safeDI_apiBuilder_Home_Screen19_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen16_Scope() -> Home.SafeDIScope_Api.Screen16_Scope.__safeDI_Builder<any Api> {
		                .init(screen21Builder: { _ in __safeDI_apiBuilder_Home_Screen21_Scope() }, screen22Builder: { _ in __safeDI_apiBuilder_Home_Screen22_Scope() }, screen23Builder: { _ in __safeDI_apiBuilder_Home_Screen23_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen21_Scope() -> Home.SafeDIScope_Api.Screen21_Scope.__safeDI_Builder<any Api> {
		                .init(model21: { values in __safeDI_apiBuilder_Home_Model21_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_Model21_Scope(id: Int) -> Home.SafeDIScope_Api.Model21_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen22_Scope() -> Home.SafeDIScope_Api.Screen22_Scope.__safeDI_Builder<any Api> {
		                .init(model22: { values in __safeDI_apiBuilder_Home_Model22_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_Model22_Scope(id: Int) -> Home.SafeDIScope_Api.Model22_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen23_Scope() -> Home.SafeDIScope_Api.Screen23_Scope.__safeDI_Builder<any Api> {
		                .init(model23: { values in __safeDI_apiBuilder_Home_Model23_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_Model23_Scope(id: Int) -> Home.SafeDIScope_Api.Model23_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen18_Scope() -> Home.SafeDIScope_Api.Screen18_Scope.__safeDI_Builder<any Api> {
		                .init(screen20Builder: { _ in __safeDI_apiBuilder_Home_Screen20_Scope() }, screen21Builder: { _ in __safeDI_apiBuilder_Home_Screen21_Scope() }, screen23Builder: { _ in __safeDI_apiBuilder_Home_Screen23_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen20_Scope() -> Home.SafeDIScope_Api.Screen20_Scope.__safeDI_Builder<any Api> {
		                .init(model20: { values in __safeDI_apiBuilder_Home_Model20_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_Model20_Scope(id: Int) -> Home.SafeDIScope_Api.Model20_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen19_Scope() -> Home.SafeDIScope_Api.Screen19_Scope.__safeDI_Builder<any Api> {
		                .init(screen20Builder: { _ in __safeDI_apiBuilder_Home_Screen20_Scope() }, screen21Builder: { _ in __safeDI_apiBuilder_Home_Screen21_Scope() }, screen22Builder: { _ in __safeDI_apiBuilder_Home_Screen22_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen14_Scope() -> Home.SafeDIScope_Api.Screen14_Scope.__safeDI_Builder<any Api> {
		                .init(screen16Builder: { _ in __safeDI_apiBuilder_Home_Screen16_Scope() }, screen17Builder: { _ in __safeDI_apiBuilder_Home_Screen17_Scope() }, screen19Builder: { _ in __safeDI_apiBuilder_Home_Screen19_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen17_Scope() -> Home.SafeDIScope_Api.Screen17_Scope.__safeDI_Builder<any Api> {
		                .init(screen20Builder: { _ in __safeDI_apiBuilder_Home_Screen20_Scope() }, screen22Builder: { _ in __safeDI_apiBuilder_Home_Screen22_Scope() }, screen23Builder: { _ in __safeDI_apiBuilder_Home_Screen23_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen15_Scope() -> Home.SafeDIScope_Api.Screen15_Scope.__safeDI_Builder<any Api> {
		                .init(screen16Builder: { _ in __safeDI_apiBuilder_Home_Screen16_Scope() }, screen17Builder: { _ in __safeDI_apiBuilder_Home_Screen17_Scope() }, screen18Builder: { _ in __safeDI_apiBuilder_Home_Screen18_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen10_Scope() -> Home.SafeDIScope_Api.Screen10_Scope.__safeDI_Builder<any Api> {
		                .init(screen12Builder: { _ in __safeDI_apiBuilder_Home_Screen12_Scope() }, screen13Builder: { _ in __safeDI_apiBuilder_Home_Screen13_Scope() }, screen15Builder: { _ in __safeDI_apiBuilder_Home_Screen15_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen12_Scope() -> Home.SafeDIScope_Api.Screen12_Scope.__safeDI_Builder<any Api> {
		                .init(screen17Builder: { _ in __safeDI_apiBuilder_Home_Screen17_Scope() }, screen18Builder: { _ in __safeDI_apiBuilder_Home_Screen18_Scope() }, screen19Builder: { _ in __safeDI_apiBuilder_Home_Screen19_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen11_Scope() -> Home.SafeDIScope_Api.Screen11_Scope.__safeDI_Builder<any Api> {
		                .init(screen12Builder: { _ in __safeDI_apiBuilder_Home_Screen12_Scope() }, screen13Builder: { _ in __safeDI_apiBuilder_Home_Screen13_Scope() }, screen14Builder: { _ in __safeDI_apiBuilder_Home_Screen14_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen6_Scope() -> Home.SafeDIScope_Api.Screen6_Scope.__safeDI_Builder<any Api> {
		                .init(screen8Builder: { _ in __safeDI_apiBuilder_Home_Screen8_Scope() }, screen9Builder: { _ in __safeDI_apiBuilder_Home_Screen9_Scope() }, screen11Builder: { _ in __safeDI_apiBuilder_Home_Screen11_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen9_Scope() -> Home.SafeDIScope_Api.Screen9_Scope.__safeDI_Builder<any Api> {
		                .init(screen12Builder: { _ in __safeDI_apiBuilder_Home_Screen12_Scope() }, screen14Builder: { _ in __safeDI_apiBuilder_Home_Screen14_Scope() }, screen15Builder: { _ in __safeDI_apiBuilder_Home_Screen15_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen7_Scope() -> Home.SafeDIScope_Api.Screen7_Scope.__safeDI_Builder<any Api> {
		                .init(screen8Builder: { _ in __safeDI_apiBuilder_Home_Screen8_Scope() }, screen9Builder: { _ in __safeDI_apiBuilder_Home_Screen9_Scope() }, screen10Builder: { _ in __safeDI_apiBuilder_Home_Screen10_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen1_Scope() -> Home.SafeDIScope_Api.Screen1_Scope.__safeDI_Builder<any Api> {
		                .init(screen4Builder: { _ in __safeDI_apiBuilder_Home_Screen4_Scope() }, screen6Builder: { _ in __safeDI_apiBuilder_Home_Screen6_Scope() }, screen7Builder: { _ in __safeDI_apiBuilder_Home_Screen7_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen4_Scope() -> Home.SafeDIScope_Api.Screen4_Scope.__safeDI_Builder<any Api> {
		                .init(screen9Builder: { _ in __safeDI_apiBuilder_Home_Screen9_Scope() }, screen10Builder: { _ in __safeDI_apiBuilder_Home_Screen10_Scope() }, screen11Builder: { _ in __safeDI_apiBuilder_Home_Screen11_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen2_Scope() -> Home.SafeDIScope_Api.Screen2_Scope.__safeDI_Builder<any Api> {
		                .init(screen4Builder: { _ in __safeDI_apiBuilder_Home_Screen4_Scope() }, screen5Builder: { _ in __safeDI_apiBuilder_Home_Screen5_Scope() }, screen7Builder: { _ in __safeDI_apiBuilder_Home_Screen7_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen3_Scope() -> Home.SafeDIScope_Api.Screen3_Scope.__safeDI_Builder<any Api> {
		                .init(screen4Builder: { _ in __safeDI_apiBuilder_Home_Screen4_Scope() }, screen5Builder: { _ in __safeDI_apiBuilder_Home_Screen5_Scope() }, screen6Builder: { _ in __safeDI_apiBuilder_Home_Screen6_Scope() })
		            }
		            return Home(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(service: service, home: home)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ordersEnumsCasesAndDispatchersBySeamsDeclarations_whenScreenNamesSortOtherwiseThanTheyAreDeclaredOrReached() async throws {
		// Shape E at eight screens, named so that their spelling order is neither the order they are declared in nor the
		// order the tree reaches them: both files are compared in full.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.shapeEModules(screenCount: 8, screenNames: ["Kilo", "Echo", "Zulu", "Alpha", "Mike", "Bravo", "Yankee", "Delta"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case kiloBuilder(kiloBuilder_Values, SafeDIScope_Api.Kilo_Scope)
		        case echoBuilder(echoBuilder_Values, SafeDIScope_Api.Echo_Scope)
		        case zuluBuilder(zuluBuilder_Values, SafeDIScope_Api.Zulu_Scope)
		        case alphaBuilder(alphaBuilder_Values, SafeDIScope_Api.Alpha_Scope)

		        nonisolated public struct kiloBuilder_Values {
		            public var service: Service { __safeDI_service.instance }
		            let __safeDI_service: LazilyInstantiated<Service>

		            init(service: LazilyInstantiated<Service>) {
		                __safeDI_service = service
		            }
		        }

		        nonisolated public struct echoBuilder_Values {
		            public var service: Service { __safeDI_service.instance }
		            public let kiloBuilder: Instantiator<Kilo>
		            let __safeDI_service: LazilyInstantiated<Service>

		            init(service: LazilyInstantiated<Service>, kiloBuilder: Instantiator<Kilo>) {
		                __safeDI_service = service
		                self.kiloBuilder = kiloBuilder
		            }
		        }

		        nonisolated public struct zuluBuilder_Values {
		            public var service: Service { __safeDI_service.instance }
		            public let kiloBuilder: Instantiator<Kilo>
		            public let echoBuilder: Instantiator<Echo>
		            let __safeDI_service: LazilyInstantiated<Service>

		            init(service: LazilyInstantiated<Service>, kiloBuilder: Instantiator<Kilo>, echoBuilder: Instantiator<Echo>) {
		                __safeDI_service = service
		                self.kiloBuilder = kiloBuilder
		                self.echoBuilder = echoBuilder
		            }
		        }

		        nonisolated public struct alphaBuilder_Values {
		            public var service: Service { __safeDI_service.instance }
		            public let kiloBuilder: Instantiator<Kilo>
		            public let echoBuilder: Instantiator<Echo>
		            public let zuluBuilder: Instantiator<Zulu>
		            let __safeDI_service: LazilyInstantiated<Service>

		            init(service: LazilyInstantiated<Service>, kiloBuilder: Instantiator<Kilo>, echoBuilder: Instantiator<Echo>, zuluBuilder: Instantiator<Zulu>) {
		                __safeDI_service = service
		                self.kiloBuilder = kiloBuilder
		                self.echoBuilder = echoBuilder
		                self.zuluBuilder = zuluBuilder
		            }
		        }

		        @frozen nonisolated public enum Kilo_Scope {
		            case bravoBuilder(bravoBuilder_Values, SafeDIScope_Api.Bravo_Scope)
		            case yankeeBuilder(yankeeBuilder_Values, SafeDIScope_Api.Yankee_Scope)
		            case deltaBuilder(deltaBuilder_Values, SafeDIScope_Api.Delta_Scope)

		            nonisolated public struct bravoBuilder_Values {
		                public let id: Int
		                public let kiloModel: KiloModel
		            }

		            nonisolated public struct yankeeBuilder_Values {
		                public let id: Int
		                public let kiloModel: KiloModel
		                public let bravoBuilder: Instantiator<Bravo>
		            }

		            nonisolated public struct deltaBuilder_Values {
		                public let id: Int
		                public let kiloModel: KiloModel
		                public let bravoBuilder: Instantiator<Bravo>
		                public let yankeeBuilder: Instantiator<Yankee>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let bravoBuilder: (bravoBuilder_Values) -> SafeDIScope_Api.Bravo_Scope.__safeDI_Builder<Built>
		                public let yankeeBuilder: (yankeeBuilder_Values) -> SafeDIScope_Api.Yankee_Scope.__safeDI_Builder<Built>
		                public let deltaBuilder: (deltaBuilder_Values) -> SafeDIScope_Api.Delta_Scope.__safeDI_Builder<Built>

		                public init(bravoBuilder: @escaping (bravoBuilder_Values) -> SafeDIScope_Api.Bravo_Scope.__safeDI_Builder<Built>, yankeeBuilder: @escaping (yankeeBuilder_Values) -> SafeDIScope_Api.Yankee_Scope.__safeDI_Builder<Built>, deltaBuilder: @escaping (deltaBuilder_Values) -> SafeDIScope_Api.Delta_Scope.__safeDI_Builder<Built>) {
		                    self.bravoBuilder = bravoBuilder
		                    self.yankeeBuilder = yankeeBuilder
		                    self.deltaBuilder = deltaBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.bravoBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.yankeeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.deltaBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Echo_Scope {
		            case mikeBuilder(mikeBuilder_Values, SafeDIScope_Api.Mike_Scope)
		            case yankeeBuilder(yankeeBuilder_Values, SafeDIScope_Api.Yankee_Scope)
		            case deltaBuilder(deltaBuilder_Values, SafeDIScope_Api.Delta_Scope)

		            nonisolated public struct mikeBuilder_Values {
		                public let id: Int
		                public let echoModel: EchoModel
		            }

		            nonisolated public struct yankeeBuilder_Values {
		                public let id: Int
		                public let echoModel: EchoModel
		                public let mikeBuilder: Instantiator<Mike>
		            }

		            nonisolated public struct deltaBuilder_Values {
		                public let id: Int
		                public let echoModel: EchoModel
		                public let mikeBuilder: Instantiator<Mike>
		                public let yankeeBuilder: Instantiator<Yankee>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let mikeBuilder: (mikeBuilder_Values) -> SafeDIScope_Api.Mike_Scope.__safeDI_Builder<Built>
		                public let yankeeBuilder: (yankeeBuilder_Values) -> SafeDIScope_Api.Yankee_Scope.__safeDI_Builder<Built>
		                public let deltaBuilder: (deltaBuilder_Values) -> SafeDIScope_Api.Delta_Scope.__safeDI_Builder<Built>

		                public init(mikeBuilder: @escaping (mikeBuilder_Values) -> SafeDIScope_Api.Mike_Scope.__safeDI_Builder<Built>, yankeeBuilder: @escaping (yankeeBuilder_Values) -> SafeDIScope_Api.Yankee_Scope.__safeDI_Builder<Built>, deltaBuilder: @escaping (deltaBuilder_Values) -> SafeDIScope_Api.Delta_Scope.__safeDI_Builder<Built>) {
		                    self.mikeBuilder = mikeBuilder
		                    self.yankeeBuilder = yankeeBuilder
		                    self.deltaBuilder = deltaBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.mikeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.yankeeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.deltaBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Zulu_Scope {
		            case mikeBuilder(mikeBuilder_Values, SafeDIScope_Api.Mike_Scope)
		            case bravoBuilder(bravoBuilder_Values, SafeDIScope_Api.Bravo_Scope)
		            case deltaBuilder(deltaBuilder_Values, SafeDIScope_Api.Delta_Scope)

		            nonisolated public struct mikeBuilder_Values {
		                public let id: Int
		                public let zuluModel: ZuluModel
		            }

		            nonisolated public struct bravoBuilder_Values {
		                public let id: Int
		                public let zuluModel: ZuluModel
		                public let mikeBuilder: Instantiator<Mike>
		            }

		            nonisolated public struct deltaBuilder_Values {
		                public let id: Int
		                public let zuluModel: ZuluModel
		                public let mikeBuilder: Instantiator<Mike>
		                public let bravoBuilder: Instantiator<Bravo>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let mikeBuilder: (mikeBuilder_Values) -> SafeDIScope_Api.Mike_Scope.__safeDI_Builder<Built>
		                public let bravoBuilder: (bravoBuilder_Values) -> SafeDIScope_Api.Bravo_Scope.__safeDI_Builder<Built>
		                public let deltaBuilder: (deltaBuilder_Values) -> SafeDIScope_Api.Delta_Scope.__safeDI_Builder<Built>

		                public init(mikeBuilder: @escaping (mikeBuilder_Values) -> SafeDIScope_Api.Mike_Scope.__safeDI_Builder<Built>, bravoBuilder: @escaping (bravoBuilder_Values) -> SafeDIScope_Api.Bravo_Scope.__safeDI_Builder<Built>, deltaBuilder: @escaping (deltaBuilder_Values) -> SafeDIScope_Api.Delta_Scope.__safeDI_Builder<Built>) {
		                    self.mikeBuilder = mikeBuilder
		                    self.bravoBuilder = bravoBuilder
		                    self.deltaBuilder = deltaBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.mikeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.bravoBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.deltaBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Alpha_Scope {
		            case mikeBuilder(mikeBuilder_Values, SafeDIScope_Api.Mike_Scope)
		            case bravoBuilder(bravoBuilder_Values, SafeDIScope_Api.Bravo_Scope)
		            case yankeeBuilder(yankeeBuilder_Values, SafeDIScope_Api.Yankee_Scope)

		            nonisolated public struct mikeBuilder_Values {
		                public let id: Int
		                public let alphaModel: AlphaModel
		            }

		            nonisolated public struct bravoBuilder_Values {
		                public let id: Int
		                public let alphaModel: AlphaModel
		                public let mikeBuilder: Instantiator<Mike>
		            }

		            nonisolated public struct yankeeBuilder_Values {
		                public let id: Int
		                public let alphaModel: AlphaModel
		                public let mikeBuilder: Instantiator<Mike>
		                public let bravoBuilder: Instantiator<Bravo>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let mikeBuilder: (mikeBuilder_Values) -> SafeDIScope_Api.Mike_Scope.__safeDI_Builder<Built>
		                public let bravoBuilder: (bravoBuilder_Values) -> SafeDIScope_Api.Bravo_Scope.__safeDI_Builder<Built>
		                public let yankeeBuilder: (yankeeBuilder_Values) -> SafeDIScope_Api.Yankee_Scope.__safeDI_Builder<Built>

		                public init(mikeBuilder: @escaping (mikeBuilder_Values) -> SafeDIScope_Api.Mike_Scope.__safeDI_Builder<Built>, bravoBuilder: @escaping (bravoBuilder_Values) -> SafeDIScope_Api.Bravo_Scope.__safeDI_Builder<Built>, yankeeBuilder: @escaping (yankeeBuilder_Values) -> SafeDIScope_Api.Yankee_Scope.__safeDI_Builder<Built>) {
		                    self.mikeBuilder = mikeBuilder
		                    self.bravoBuilder = bravoBuilder
		                    self.yankeeBuilder = yankeeBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.mikeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.bravoBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                    self.yankeeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Bravo_Scope {
		            case bravoModel(bravoModel_Values, SafeDIScope_Api.BravoModel_Scope)

		            nonisolated public struct bravoModel_Values {
		                public let id: Int
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let bravoModel: (bravoModel_Values) -> SafeDIScope_Api.BravoModel_Scope.__safeDI_Builder<Built>

		                public init(bravoModel: @escaping (bravoModel_Values) -> SafeDIScope_Api.BravoModel_Scope.__safeDI_Builder<Built>) {
		                    self.bravoModel = bravoModel
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.bravoModel = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Yankee_Scope {
		            case yankeeModel(yankeeModel_Values, SafeDIScope_Api.YankeeModel_Scope)

		            nonisolated public struct yankeeModel_Values {
		                public let id: Int
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let yankeeModel: (yankeeModel_Values) -> SafeDIScope_Api.YankeeModel_Scope.__safeDI_Builder<Built>

		                public init(yankeeModel: @escaping (yankeeModel_Values) -> SafeDIScope_Api.YankeeModel_Scope.__safeDI_Builder<Built>) {
		                    self.yankeeModel = yankeeModel
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.yankeeModel = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Delta_Scope {
		            case deltaModel(deltaModel_Values, SafeDIScope_Api.DeltaModel_Scope)

		            nonisolated public struct deltaModel_Values {
		                public let id: Int
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let deltaModel: (deltaModel_Values) -> SafeDIScope_Api.DeltaModel_Scope.__safeDI_Builder<Built>

		                public init(deltaModel: @escaping (deltaModel_Values) -> SafeDIScope_Api.DeltaModel_Scope.__safeDI_Builder<Built>) {
		                    self.deltaModel = deltaModel
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.deltaModel = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Mike_Scope {
		            case mikeModel(mikeModel_Values, SafeDIScope_Api.MikeModel_Scope)

		            nonisolated public struct mikeModel_Values {
		                public let id: Int
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let mikeModel: (mikeModel_Values) -> SafeDIScope_Api.MikeModel_Scope.__safeDI_Builder<Built>

		                public init(mikeModel: @escaping (mikeModel_Values) -> SafeDIScope_Api.MikeModel_Scope.__safeDI_Builder<Built>) {
		                    self.mikeModel = mikeModel
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.mikeModel = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum BravoModel_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum YankeeModel_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum DeltaModel_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum MikeModel_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<Built> {
		            public let kiloBuilder: (kiloBuilder_Values) -> SafeDIScope_Api.Kilo_Scope.__safeDI_Builder<Built>
		            public let echoBuilder: (echoBuilder_Values) -> SafeDIScope_Api.Echo_Scope.__safeDI_Builder<Built>
		            public let zuluBuilder: (zuluBuilder_Values) -> SafeDIScope_Api.Zulu_Scope.__safeDI_Builder<Built>
		            public let alphaBuilder: (alphaBuilder_Values) -> SafeDIScope_Api.Alpha_Scope.__safeDI_Builder<Built>

		            public init(kiloBuilder: @escaping (kiloBuilder_Values) -> SafeDIScope_Api.Kilo_Scope.__safeDI_Builder<Built>, echoBuilder: @escaping (echoBuilder_Values) -> SafeDIScope_Api.Echo_Scope.__safeDI_Builder<Built>, zuluBuilder: @escaping (zuluBuilder_Values) -> SafeDIScope_Api.Zulu_Scope.__safeDI_Builder<Built>, alphaBuilder: @escaping (alphaBuilder_Values) -> SafeDIScope_Api.Alpha_Scope.__safeDI_Builder<Built>) {
		                self.kiloBuilder = kiloBuilder
		                self.echoBuilder = echoBuilder
		                self.zuluBuilder = zuluBuilder
		                self.alphaBuilder = alphaBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                self.kiloBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.echoBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.zuluBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.alphaBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_service: @autoclosure @escaping () -> Service, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let service = LazilyInstantiated<Service>(__safeDI_service)
		        let __safeDI_apiBuilder_kiloBuilder = __safeDI_apiBuilder.kiloBuilder(SafeDIScope_Api.kiloBuilder_Values(service: service))
		        func __safeDI_kiloBuilder(id: Int) -> Kilo {
		            let kiloModel = KiloModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_bravoBuilder = __safeDI_apiBuilder_kiloBuilder.bravoBuilder(SafeDIScope_Api.Kilo_Scope.bravoBuilder_Values(id: id, kiloModel: kiloModel))
		            func __safeDI_bravoBuilder(id: Int) -> Bravo {
		                let __safeDI_apiBuilder_bravoModel = __safeDI_apiBuilder_bravoBuilder.bravoModel(SafeDIScope_Api.Bravo_Scope.bravoModel_Values(id: id))
		                func __safeDI_bravoModel() -> BravoModel {
		                    let api: any Api = __safeDI_apiBuilder_bravoModel.api(SafeDIScope_Api.BravoModel_Scope.api_Values())
		                    return BravoModel(id: id, service: service.instance, api: api)
		                }
		                let bravoModel: BravoModel = __safeDI_bravoModel()
		                return Bravo(id: id, service: service.instance, bravoModel: bravoModel)
		            }
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_yankeeBuilder = __safeDI_apiBuilder_kiloBuilder.yankeeBuilder(SafeDIScope_Api.Kilo_Scope.yankeeBuilder_Values(id: id, kiloModel: kiloModel, bravoBuilder: bravoBuilder))
		            func __safeDI_yankeeBuilder(id: Int) -> Yankee {
		                let __safeDI_apiBuilder_yankeeModel = __safeDI_apiBuilder_yankeeBuilder.yankeeModel(SafeDIScope_Api.Yankee_Scope.yankeeModel_Values(id: id))
		                func __safeDI_yankeeModel() -> YankeeModel {
		                    let api: any Api = __safeDI_apiBuilder_yankeeModel.api(SafeDIScope_Api.YankeeModel_Scope.api_Values())
		                    return YankeeModel(id: id, service: service.instance, api: api)
		                }
		                let yankeeModel: YankeeModel = __safeDI_yankeeModel()
		                return Yankee(id: id, service: service.instance, yankeeModel: yankeeModel)
		            }
		            let yankeeBuilder = Instantiator<Yankee> {
		                __safeDI_yankeeBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_deltaBuilder = __safeDI_apiBuilder_kiloBuilder.deltaBuilder(SafeDIScope_Api.Kilo_Scope.deltaBuilder_Values(id: id, kiloModel: kiloModel, bravoBuilder: bravoBuilder, yankeeBuilder: yankeeBuilder))
		            func __safeDI_deltaBuilder(id: Int) -> Delta {
		                let __safeDI_apiBuilder_deltaModel = __safeDI_apiBuilder_deltaBuilder.deltaModel(SafeDIScope_Api.Delta_Scope.deltaModel_Values(id: id))
		                func __safeDI_deltaModel() -> DeltaModel {
		                    let api: any Api = __safeDI_apiBuilder_deltaModel.api(SafeDIScope_Api.DeltaModel_Scope.api_Values())
		                    return DeltaModel(id: id, service: service.instance, api: api)
		                }
		                let deltaModel: DeltaModel = __safeDI_deltaModel()
		                return Delta(id: id, service: service.instance, deltaModel: deltaModel)
		            }
		            let deltaBuilder = Instantiator<Delta> {
		                __safeDI_deltaBuilder(id: $0)
		            }
		            return Kilo(id: id, service: service.instance, kiloModel: kiloModel, bravoBuilder: bravoBuilder, yankeeBuilder: yankeeBuilder, deltaBuilder: deltaBuilder)
		        }
		        let kiloBuilder = Instantiator<Kilo> {
		            __safeDI_kiloBuilder(id: $0)
		        }
		        let __safeDI_apiBuilder_echoBuilder = __safeDI_apiBuilder.echoBuilder(SafeDIScope_Api.echoBuilder_Values(service: service, kiloBuilder: kiloBuilder))
		        func __safeDI_echoBuilder(id: Int) -> Echo {
		            let echoModel = EchoModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_mikeBuilder = __safeDI_apiBuilder_echoBuilder.mikeBuilder(SafeDIScope_Api.Echo_Scope.mikeBuilder_Values(id: id, echoModel: echoModel))
		            func __safeDI_mikeBuilder(id: Int) -> Mike {
		                let __safeDI_apiBuilder_mikeModel = __safeDI_apiBuilder_mikeBuilder.mikeModel(SafeDIScope_Api.Mike_Scope.mikeModel_Values(id: id))
		                func __safeDI_mikeModel() -> MikeModel {
		                    let api: any Api = __safeDI_apiBuilder_mikeModel.api(SafeDIScope_Api.MikeModel_Scope.api_Values())
		                    return MikeModel(id: id, service: service.instance, api: api)
		                }
		                let mikeModel: MikeModel = __safeDI_mikeModel()
		                return Mike(id: id, service: service.instance, mikeModel: mikeModel)
		            }
		            let mikeBuilder = Instantiator<Mike> {
		                __safeDI_mikeBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_yankeeBuilder = __safeDI_apiBuilder_echoBuilder.yankeeBuilder(SafeDIScope_Api.Echo_Scope.yankeeBuilder_Values(id: id, echoModel: echoModel, mikeBuilder: mikeBuilder))
		            func __safeDI_yankeeBuilder(id: Int) -> Yankee {
		                let __safeDI_apiBuilder_yankeeModel = __safeDI_apiBuilder_yankeeBuilder.yankeeModel(SafeDIScope_Api.Yankee_Scope.yankeeModel_Values(id: id))
		                func __safeDI_yankeeModel() -> YankeeModel {
		                    let api: any Api = __safeDI_apiBuilder_yankeeModel.api(SafeDIScope_Api.YankeeModel_Scope.api_Values())
		                    return YankeeModel(id: id, service: service.instance, api: api)
		                }
		                let yankeeModel: YankeeModel = __safeDI_yankeeModel()
		                return Yankee(id: id, service: service.instance, yankeeModel: yankeeModel)
		            }
		            let yankeeBuilder = Instantiator<Yankee> {
		                __safeDI_yankeeBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_deltaBuilder = __safeDI_apiBuilder_echoBuilder.deltaBuilder(SafeDIScope_Api.Echo_Scope.deltaBuilder_Values(id: id, echoModel: echoModel, mikeBuilder: mikeBuilder, yankeeBuilder: yankeeBuilder))
		            func __safeDI_deltaBuilder(id: Int) -> Delta {
		                let __safeDI_apiBuilder_deltaModel = __safeDI_apiBuilder_deltaBuilder.deltaModel(SafeDIScope_Api.Delta_Scope.deltaModel_Values(id: id))
		                func __safeDI_deltaModel() -> DeltaModel {
		                    let api: any Api = __safeDI_apiBuilder_deltaModel.api(SafeDIScope_Api.DeltaModel_Scope.api_Values())
		                    return DeltaModel(id: id, service: service.instance, api: api)
		                }
		                let deltaModel: DeltaModel = __safeDI_deltaModel()
		                return Delta(id: id, service: service.instance, deltaModel: deltaModel)
		            }
		            let deltaBuilder = Instantiator<Delta> {
		                __safeDI_deltaBuilder(id: $0)
		            }
		            return Echo(id: id, service: service.instance, echoModel: echoModel, mikeBuilder: mikeBuilder, yankeeBuilder: yankeeBuilder, deltaBuilder: deltaBuilder)
		        }
		        let echoBuilder = Instantiator<Echo> {
		            __safeDI_echoBuilder(id: $0)
		        }
		        let __safeDI_apiBuilder_zuluBuilder = __safeDI_apiBuilder.zuluBuilder(SafeDIScope_Api.zuluBuilder_Values(service: service, kiloBuilder: kiloBuilder, echoBuilder: echoBuilder))
		        func __safeDI_zuluBuilder(id: Int) -> Zulu {
		            let zuluModel = ZuluModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_mikeBuilder = __safeDI_apiBuilder_zuluBuilder.mikeBuilder(SafeDIScope_Api.Zulu_Scope.mikeBuilder_Values(id: id, zuluModel: zuluModel))
		            func __safeDI_mikeBuilder(id: Int) -> Mike {
		                let __safeDI_apiBuilder_mikeModel = __safeDI_apiBuilder_mikeBuilder.mikeModel(SafeDIScope_Api.Mike_Scope.mikeModel_Values(id: id))
		                func __safeDI_mikeModel() -> MikeModel {
		                    let api: any Api = __safeDI_apiBuilder_mikeModel.api(SafeDIScope_Api.MikeModel_Scope.api_Values())
		                    return MikeModel(id: id, service: service.instance, api: api)
		                }
		                let mikeModel: MikeModel = __safeDI_mikeModel()
		                return Mike(id: id, service: service.instance, mikeModel: mikeModel)
		            }
		            let mikeBuilder = Instantiator<Mike> {
		                __safeDI_mikeBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_bravoBuilder = __safeDI_apiBuilder_zuluBuilder.bravoBuilder(SafeDIScope_Api.Zulu_Scope.bravoBuilder_Values(id: id, zuluModel: zuluModel, mikeBuilder: mikeBuilder))
		            func __safeDI_bravoBuilder(id: Int) -> Bravo {
		                let __safeDI_apiBuilder_bravoModel = __safeDI_apiBuilder_bravoBuilder.bravoModel(SafeDIScope_Api.Bravo_Scope.bravoModel_Values(id: id))
		                func __safeDI_bravoModel() -> BravoModel {
		                    let api: any Api = __safeDI_apiBuilder_bravoModel.api(SafeDIScope_Api.BravoModel_Scope.api_Values())
		                    return BravoModel(id: id, service: service.instance, api: api)
		                }
		                let bravoModel: BravoModel = __safeDI_bravoModel()
		                return Bravo(id: id, service: service.instance, bravoModel: bravoModel)
		            }
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_deltaBuilder = __safeDI_apiBuilder_zuluBuilder.deltaBuilder(SafeDIScope_Api.Zulu_Scope.deltaBuilder_Values(id: id, zuluModel: zuluModel, mikeBuilder: mikeBuilder, bravoBuilder: bravoBuilder))
		            func __safeDI_deltaBuilder(id: Int) -> Delta {
		                let __safeDI_apiBuilder_deltaModel = __safeDI_apiBuilder_deltaBuilder.deltaModel(SafeDIScope_Api.Delta_Scope.deltaModel_Values(id: id))
		                func __safeDI_deltaModel() -> DeltaModel {
		                    let api: any Api = __safeDI_apiBuilder_deltaModel.api(SafeDIScope_Api.DeltaModel_Scope.api_Values())
		                    return DeltaModel(id: id, service: service.instance, api: api)
		                }
		                let deltaModel: DeltaModel = __safeDI_deltaModel()
		                return Delta(id: id, service: service.instance, deltaModel: deltaModel)
		            }
		            let deltaBuilder = Instantiator<Delta> {
		                __safeDI_deltaBuilder(id: $0)
		            }
		            return Zulu(id: id, service: service.instance, zuluModel: zuluModel, mikeBuilder: mikeBuilder, bravoBuilder: bravoBuilder, deltaBuilder: deltaBuilder)
		        }
		        let zuluBuilder = Instantiator<Zulu> {
		            __safeDI_zuluBuilder(id: $0)
		        }
		        let __safeDI_apiBuilder_alphaBuilder = __safeDI_apiBuilder.alphaBuilder(SafeDIScope_Api.alphaBuilder_Values(service: service, kiloBuilder: kiloBuilder, echoBuilder: echoBuilder, zuluBuilder: zuluBuilder))
		        func __safeDI_alphaBuilder(id: Int) -> Alpha {
		            let alphaModel = AlphaModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_mikeBuilder = __safeDI_apiBuilder_alphaBuilder.mikeBuilder(SafeDIScope_Api.Alpha_Scope.mikeBuilder_Values(id: id, alphaModel: alphaModel))
		            func __safeDI_mikeBuilder(id: Int) -> Mike {
		                let __safeDI_apiBuilder_mikeModel = __safeDI_apiBuilder_mikeBuilder.mikeModel(SafeDIScope_Api.Mike_Scope.mikeModel_Values(id: id))
		                func __safeDI_mikeModel() -> MikeModel {
		                    let api: any Api = __safeDI_apiBuilder_mikeModel.api(SafeDIScope_Api.MikeModel_Scope.api_Values())
		                    return MikeModel(id: id, service: service.instance, api: api)
		                }
		                let mikeModel: MikeModel = __safeDI_mikeModel()
		                return Mike(id: id, service: service.instance, mikeModel: mikeModel)
		            }
		            let mikeBuilder = Instantiator<Mike> {
		                __safeDI_mikeBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_bravoBuilder = __safeDI_apiBuilder_alphaBuilder.bravoBuilder(SafeDIScope_Api.Alpha_Scope.bravoBuilder_Values(id: id, alphaModel: alphaModel, mikeBuilder: mikeBuilder))
		            func __safeDI_bravoBuilder(id: Int) -> Bravo {
		                let __safeDI_apiBuilder_bravoModel = __safeDI_apiBuilder_bravoBuilder.bravoModel(SafeDIScope_Api.Bravo_Scope.bravoModel_Values(id: id))
		                func __safeDI_bravoModel() -> BravoModel {
		                    let api: any Api = __safeDI_apiBuilder_bravoModel.api(SafeDIScope_Api.BravoModel_Scope.api_Values())
		                    return BravoModel(id: id, service: service.instance, api: api)
		                }
		                let bravoModel: BravoModel = __safeDI_bravoModel()
		                return Bravo(id: id, service: service.instance, bravoModel: bravoModel)
		            }
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(id: $0)
		            }
		            let __safeDI_apiBuilder_yankeeBuilder = __safeDI_apiBuilder_alphaBuilder.yankeeBuilder(SafeDIScope_Api.Alpha_Scope.yankeeBuilder_Values(id: id, alphaModel: alphaModel, mikeBuilder: mikeBuilder, bravoBuilder: bravoBuilder))
		            func __safeDI_yankeeBuilder(id: Int) -> Yankee {
		                let __safeDI_apiBuilder_yankeeModel = __safeDI_apiBuilder_yankeeBuilder.yankeeModel(SafeDIScope_Api.Yankee_Scope.yankeeModel_Values(id: id))
		                func __safeDI_yankeeModel() -> YankeeModel {
		                    let api: any Api = __safeDI_apiBuilder_yankeeModel.api(SafeDIScope_Api.YankeeModel_Scope.api_Values())
		                    return YankeeModel(id: id, service: service.instance, api: api)
		                }
		                let yankeeModel: YankeeModel = __safeDI_yankeeModel()
		                return Yankee(id: id, service: service.instance, yankeeModel: yankeeModel)
		            }
		            let yankeeBuilder = Instantiator<Yankee> {
		                __safeDI_yankeeBuilder(id: $0)
		            }
		            return Alpha(id: id, service: service.instance, alphaModel: alphaModel, mikeBuilder: mikeBuilder, bravoBuilder: bravoBuilder, yankeeBuilder: yankeeBuilder)
		        }
		        let alphaBuilder = Instantiator<Alpha> {
		            __safeDI_alphaBuilder(id: $0)
		        }
		        self.init(kiloBuilder: kiloBuilder, echoBuilder: echoBuilder, zuluBuilder: zuluBuilder, alphaBuilder: alphaBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_3FA0CC4D3070999A {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_3FA0CC4D3070999A.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(kiloBuilder: { _ in __safeDI_apiBuilder_Home_Kilo_Scope() }, echoBuilder: { _ in __safeDI_apiBuilder_Home_Echo_Scope() }, zuluBuilder: { _ in __safeDI_apiBuilder_Home_Zulu_Scope() }, alphaBuilder: { _ in __safeDI_apiBuilder_Home_Alpha_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Kilo_Scope() -> Home.SafeDIScope_Api.Kilo_Scope.__safeDI_Builder<any Api> {
		                .init(bravoBuilder: { _ in __safeDI_apiBuilder_Home_Bravo_Scope() }, yankeeBuilder: { _ in __safeDI_apiBuilder_Home_Yankee_Scope() }, deltaBuilder: { _ in __safeDI_apiBuilder_Home_Delta_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Bravo_Scope() -> Home.SafeDIScope_Api.Bravo_Scope.__safeDI_Builder<any Api> {
		                .init(bravoModel: { values in __safeDI_apiBuilder_Home_BravoModel_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_BravoModel_Scope(id: Int) -> Home.SafeDIScope_Api.BravoModel_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Yankee_Scope() -> Home.SafeDIScope_Api.Yankee_Scope.__safeDI_Builder<any Api> {
		                .init(yankeeModel: { values in __safeDI_apiBuilder_Home_YankeeModel_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_YankeeModel_Scope(id: Int) -> Home.SafeDIScope_Api.YankeeModel_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Delta_Scope() -> Home.SafeDIScope_Api.Delta_Scope.__safeDI_Builder<any Api> {
		                .init(deltaModel: { values in __safeDI_apiBuilder_Home_DeltaModel_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_DeltaModel_Scope(id: Int) -> Home.SafeDIScope_Api.DeltaModel_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Echo_Scope() -> Home.SafeDIScope_Api.Echo_Scope.__safeDI_Builder<any Api> {
		                .init(mikeBuilder: { _ in __safeDI_apiBuilder_Home_Mike_Scope() }, yankeeBuilder: { _ in __safeDI_apiBuilder_Home_Yankee_Scope() }, deltaBuilder: { _ in __safeDI_apiBuilder_Home_Delta_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Mike_Scope() -> Home.SafeDIScope_Api.Mike_Scope.__safeDI_Builder<any Api> {
		                .init(mikeModel: { values in __safeDI_apiBuilder_Home_MikeModel_Scope(id: values.id) })
		            }
		            func __safeDI_apiBuilder_Home_MikeModel_Scope(id: Int) -> Home.SafeDIScope_Api.MikeModel_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Zulu_Scope() -> Home.SafeDIScope_Api.Zulu_Scope.__safeDI_Builder<any Api> {
		                .init(mikeBuilder: { _ in __safeDI_apiBuilder_Home_Mike_Scope() }, bravoBuilder: { _ in __safeDI_apiBuilder_Home_Bravo_Scope() }, deltaBuilder: { _ in __safeDI_apiBuilder_Home_Delta_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Alpha_Scope() -> Home.SafeDIScope_Api.Alpha_Scope.__safeDI_Builder<any Api> {
		                .init(mikeBuilder: { _ in __safeDI_apiBuilder_Home_Mike_Scope() }, bravoBuilder: { _ in __safeDI_apiBuilder_Home_Bravo_Scope() }, yankeeBuilder: { _ in __safeDI_apiBuilder_Home_Yankee_Scope() })
		            }
		            return Home(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(service: service, home: home)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesSixValuesInLabelOrder_whenSharedCaseReadsSixValuesOneRouteBindsAndTheOtherDoesNot() async throws {
		// `Leaf` is reached under `hub`, which binds six values before it, and under `spoke`, which binds none. The fill reads
		// all six only if available, so `Leaf`'s dispatcher takes six parameters, which `Hub`'s case passes from its payload
		// and the root dispatcher passes `nil` for. The labels are declared in an order their spelling does not sort in, and
		// two are `scope` and `values`, so each dispatcher names its own `scope_` and `values_`, and the fill keeps its
		// function, whose scope parameter is named apart.
		let labels = ["zeta", "scope", "mu", "values", "kappa", "delta"]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Api {}",
					"public final class Value {\n    public init() {}\n}",
					Self.type(named: "Leaf", properties: ["@Instantiated let api: any Api"]),
					Self.type(named: "Hub", properties: labels.map { "@Forwarded let \($0): Value" } + ["@Instantiated let leaf: Leaf"]),
					Self.type(named: "Spoke", properties: ["@Instantiated let leaf: Leaf"]),
					Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let hubBuilder: Instantiator<Hub>", "@Instantiated let spoke: Spoke"]),
				],
				app: [
					"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable {\n    init(\(labels.map { "\($0): Value?" }.joined(separator: ", "))) {\n" + labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n") + "\n    }\n" + labels.map { "    @Received(onlyIfAvailable: true) let \($0): Value?" }.joined(separator: "\n") + "\n}",
					Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let home: Home"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_B994657558296860.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home_Leaf_Scope_api(_ scope_: Home.SafeDIScope_Api.Leaf_Scope.api_Values, zeta: Value?, scope: Value?, mu: Value?, values: Value?, kappa: Value?, delta: Value?) -> any Api {
		                let api: any Api = LiveApi(zeta: zeta, scope: scope, mu: mu, values: values, kappa: kappa, delta: delta)
		                return api
		            }
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(hubBuilder: { _ in __safeDI_apiBuilder_Home_Hub_Scope() }, spoke: { _ in __safeDI_apiBuilder_Home_Spoke_Scope(delta: nil, kappa: nil, mu: nil, scope: nil, values: nil, zeta: nil) })
		            }
		            func __safeDI_apiBuilder_Home_Hub_Scope() -> Home.SafeDIScope_Api.Hub_Scope.__safeDI_Builder<any Api> {
		                .init(leaf: { values_ in __safeDI_apiBuilder_Home_Leaf_Scope(delta: values_.delta, kappa: values_.kappa, mu: values_.mu, scope: values_.scope, values: values_.values, zeta: values_.zeta) })
		            }
		            func __safeDI_apiBuilder_Home_Leaf_Scope(delta: Value?, kappa: Value?, mu: Value?, scope: Value?, values: Value?, zeta: Value?) -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope_ in __safeDI_apiBuilder_Home_Leaf_Scope_api(scope_, zeta: zeta, scope: scope, mu: mu, values: values, kappa: kappa, delta: delta) })
		            }
		            func __safeDI_apiBuilder_Home_Spoke_Scope(delta: Value?, kappa: Value?, mu: Value?, scope: Value?, values: Value?, zeta: Value?) -> Home.SafeDIScope_Api.Spoke_Scope.__safeDI_Builder<any Api> {
		                .init(leaf: { _ in __safeDI_apiBuilder_Home_Leaf_Scope(delta: delta, kappa: kappa, mu: mu, scope: scope, values: values, zeta: zeta) })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNestedEnumAsSeamsModuleSpellsItsType_whenCallersModuleDeclaresTypeOfSameName() async throws {
		// `Feature`'s `Store` holds `Home`'s place `api`; `App` declares a `Store` of its own, so `App`'s run spells
		// `Feature`'s as `Feature.Store`. The enum is named by `Feature`'s spelling in both runs, so `App`'s dispatcher names
		// the enum `Feature` declares.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Api {}",
					Self.type(named: "Store", access: "internal", properties: ["@Instantiated let api: any Api"]),
					Self.type(named: "Home", initializerAccess: "internal", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let store: Store"]),
				],
				app: [
					Self.type(named: "Store", properties: []),
					"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init(appStore: Store) { self.appStore = appStore }\n    @Received let appStore: Store\n}",
					Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let appStore: Store", "@Instantiated let home: Home"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case store(store_Values, SafeDIScope_Api.Store_Scope)

		        nonisolated public struct store_Values {}

		        @frozen nonisolated public enum Store_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<Built> {
		            public let store: (store_Values) -> SafeDIScope_Api.Store_Scope.__safeDI_Builder<Built>

		            public init(store: @escaping (store_Values) -> SafeDIScope_Api.Store_Scope.__safeDI_Builder<Built>) {
		                self.store = store
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                self.store = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_store = __safeDI_apiBuilder.store(SafeDIScope_Api.store_Values())
		        func __safeDI_store() -> Store {
		            let api: any Api = __safeDI_apiBuilder_store.api(SafeDIScope_Api.Store_Scope.api_Values())
		            return Store(api: api)
		        }
		        let store: Store = __safeDI_store()
		        self.init(store: store)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_C9CBF76AB2C9BB81 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let appStore = Store()
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_C9CBF76AB2C9BB81.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(store: { _ in __safeDI_apiBuilder_Home_Store_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Store_Scope() -> Home.SafeDIScope_Api.Store_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(appStore: appStore)
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(appStore: appStore, home: home)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNestedEnumApart_whenPayloadSpellsTypeOfItsName() async throws {
		// `Host` builds `jobScope: Job_Scope`, a type of the person's, before `job`, whose `Job` holds the place `api`: the
		// payload of `Host`'s case `job` spells `Job_Scope`, which an enum nested in the root and named `Job_Scope` would
		// shadow, so the enum takes `_`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Api {}",
					Self.type(named: "Job_Scope", properties: []),
					Self.type(named: "Job", properties: ["@Instantiated let api: any Api"]),
					Self.type(named: "Host", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let jobScope: Job_Scope", "@Instantiated let job: Job"]),
				],
				app: [
					"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init(jobScope: Job_Scope) { self.jobScope = jobScope }\n    @Received let jobScope: Job_Scope\n}",
					Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let host: Host"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Host {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case job(job_Values, SafeDIScope_Api.Job_Scope_)

		        nonisolated public struct job_Values {
		            public let jobScope: Job_Scope
		        }

		        @frozen nonisolated public enum Job_Scope_ {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<Built> {
		            public let job: (job_Values) -> SafeDIScope_Api.Job_Scope_.__safeDI_Builder<Built>

		            public init(job: @escaping (job_Values) -> SafeDIScope_Api.Job_Scope_.__safeDI_Builder<Built>) {
		                self.job = job
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                self.job = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let jobScope = Job_Scope()
		        let __safeDI_apiBuilder_job = __safeDI_apiBuilder.job(SafeDIScope_Api.job_Values(jobScope: jobScope))
		        func __safeDI_job() -> Job {
		            let api: any Api = __safeDI_apiBuilder_job.api(SafeDIScope_Api.Job_Scope_.api_Values())
		            return Job(api: api)
		        }
		        let job: Job = __safeDI_job()
		        self.init(jobScope: jobScope, job: job)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_BCDBECE06CB53C0B {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_BCDBECE06CB53C0B.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Host() -> Host.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(job: { values in __safeDI_apiBuilder_Host_Job_Scope_(jobScope: values.jobScope) })
		            }
		            func __safeDI_apiBuilder_Host_Job_Scope_(jobScope: Job_Scope) -> Host.SafeDIScope_Api.Job_Scope_.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(jobScope: jobScope)
		                    return api
		                })
		            }
		            return Host(__safeDI_apiBuilder: __safeDI_apiBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesEveryEnumApart_whenSixTypesSpellOneStem() async throws {
		// Six types spell the stem `A_B_C_D`, declared on `Home` in an order that is neither their spelling's nor their
		// nesting's: every enum is named apart, by its module and then in the order of its type's spelling, so no name
		// depends on which type the tree reaches first. Both files are compared in full.
		let api = ["@Instantiated let api: any Api"]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Api {}",
					"public enum A {\n" + Self.type(named: "B_C_D", properties: api) + "\npublic enum B {\n" + Self.type(named: "C_D", properties: api) + "\n}\npublic enum B_C {\n" + Self.type(named: "D", properties: api) + "\n}\n}",
					"public enum A_B {\n" + Self.type(named: "C_D", properties: api) + "\npublic enum C {\n" + Self.type(named: "D", properties: api) + "\n}\n}",
					"public enum A_B_C {\n" + Self.type(named: "D", properties: api) + "\n}",
					Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: [
						"@Instantiated let fourth: A.B.C_D",
						"@Instantiated let second: A_B.C_D",
						"@Instantiated let sixth: A.B_C.D",
						"@Instantiated let first: A.B_C_D",
						"@Instantiated let fifth: A_B.C.D",
						"@Instantiated let third: A_B_C.D",
					]),
				],
				app: [
					"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init() {} }",
					Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let home: Home"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case fourth(fourth_Values, SafeDIScope_Api.Feature_A_B_C_D_Scope)
		        case second(second_Values, SafeDIScope_Api.Feature_A_B_C_D_____Scope)
		        case sixth(sixth_Values, SafeDIScope_Api.Feature_A_B_C_D__Scope)
		        case first(first_Values, SafeDIScope_Api.Feature_A_B_C_D___Scope)
		        case fifth(fifth_Values, SafeDIScope_Api.Feature_A_B_C_D____Scope)
		        case third(third_Values, SafeDIScope_Api.Feature_A_B_C_D______Scope)

		        nonisolated public struct fourth_Values {}

		        nonisolated public struct second_Values {
		            public let fourth: A.B.C_D
		        }

		        nonisolated public struct sixth_Values {
		            public let fourth: A.B.C_D
		            public let second: A_B.C_D
		        }

		        nonisolated public struct first_Values {
		            public let fourth: A.B.C_D
		            public let second: A_B.C_D
		            public let sixth: A.B_C.D
		        }

		        nonisolated public struct fifth_Values {
		            public let fourth: A.B.C_D
		            public let second: A_B.C_D
		            public let sixth: A.B_C.D
		            public let first: A.B_C_D
		        }

		        nonisolated public struct third_Values {
		            public let fourth: A.B.C_D
		            public let second: A_B.C_D
		            public let sixth: A.B_C.D
		            public let first: A.B_C_D
		            public let fifth: A_B.C.D
		        }

		        @frozen nonisolated public enum Feature_A_B_C_D_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum Feature_A_B_C_D_____Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum Feature_A_B_C_D__Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum Feature_A_B_C_D___Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum Feature_A_B_C_D____Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        @frozen nonisolated public enum Feature_A_B_C_D______Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<Built> {
		            public let fourth: (fourth_Values) -> SafeDIScope_Api.Feature_A_B_C_D_Scope.__safeDI_Builder<Built>
		            public let second: (second_Values) -> SafeDIScope_Api.Feature_A_B_C_D_____Scope.__safeDI_Builder<Built>
		            public let sixth: (sixth_Values) -> SafeDIScope_Api.Feature_A_B_C_D__Scope.__safeDI_Builder<Built>
		            public let first: (first_Values) -> SafeDIScope_Api.Feature_A_B_C_D___Scope.__safeDI_Builder<Built>
		            public let fifth: (fifth_Values) -> SafeDIScope_Api.Feature_A_B_C_D____Scope.__safeDI_Builder<Built>
		            public let third: (third_Values) -> SafeDIScope_Api.Feature_A_B_C_D______Scope.__safeDI_Builder<Built>

		            public init(fourth: @escaping (fourth_Values) -> SafeDIScope_Api.Feature_A_B_C_D_Scope.__safeDI_Builder<Built>, second: @escaping (second_Values) -> SafeDIScope_Api.Feature_A_B_C_D_____Scope.__safeDI_Builder<Built>, sixth: @escaping (sixth_Values) -> SafeDIScope_Api.Feature_A_B_C_D__Scope.__safeDI_Builder<Built>, first: @escaping (first_Values) -> SafeDIScope_Api.Feature_A_B_C_D___Scope.__safeDI_Builder<Built>, fifth: @escaping (fifth_Values) -> SafeDIScope_Api.Feature_A_B_C_D____Scope.__safeDI_Builder<Built>, third: @escaping (third_Values) -> SafeDIScope_Api.Feature_A_B_C_D______Scope.__safeDI_Builder<Built>) {
		                self.fourth = fourth
		                self.second = second
		                self.sixth = sixth
		                self.first = first
		                self.fifth = fifth
		                self.third = third
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                self.fourth = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.second = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.sixth = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.first = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.fifth = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.third = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_fourth = __safeDI_apiBuilder.fourth(SafeDIScope_Api.fourth_Values())
		        func __safeDI_fourth() -> A.B.C_D {
		            let api: any Api = __safeDI_apiBuilder_fourth.api(SafeDIScope_Api.Feature_A_B_C_D_Scope.api_Values())
		            return A.B.C_D(api: api)
		        }
		        let fourth: A.B.C_D = __safeDI_fourth()
		        let __safeDI_apiBuilder_second = __safeDI_apiBuilder.second(SafeDIScope_Api.second_Values(fourth: fourth))
		        func __safeDI_second() -> A_B.C_D {
		            let api: any Api = __safeDI_apiBuilder_second.api(SafeDIScope_Api.Feature_A_B_C_D_____Scope.api_Values())
		            return A_B.C_D(api: api)
		        }
		        let second: A_B.C_D = __safeDI_second()
		        let __safeDI_apiBuilder_sixth = __safeDI_apiBuilder.sixth(SafeDIScope_Api.sixth_Values(fourth: fourth, second: second))
		        func __safeDI_sixth() -> A.B_C.D {
		            let api: any Api = __safeDI_apiBuilder_sixth.api(SafeDIScope_Api.Feature_A_B_C_D__Scope.api_Values())
		            return A.B_C.D(api: api)
		        }
		        let sixth: A.B_C.D = __safeDI_sixth()
		        let __safeDI_apiBuilder_first = __safeDI_apiBuilder.first(SafeDIScope_Api.first_Values(fourth: fourth, second: second, sixth: sixth))
		        func __safeDI_first() -> A.B_C_D {
		            let api: any Api = __safeDI_apiBuilder_first.api(SafeDIScope_Api.Feature_A_B_C_D___Scope.api_Values())
		            return A.B_C_D(api: api)
		        }
		        let first: A.B_C_D = __safeDI_first()
		        let __safeDI_apiBuilder_fifth = __safeDI_apiBuilder.fifth(SafeDIScope_Api.fifth_Values(fourth: fourth, second: second, sixth: sixth, first: first))
		        func __safeDI_fifth() -> A_B.C.D {
		            let api: any Api = __safeDI_apiBuilder_fifth.api(SafeDIScope_Api.Feature_A_B_C_D____Scope.api_Values())
		            return A_B.C.D(api: api)
		        }
		        let fifth: A_B.C.D = __safeDI_fifth()
		        let __safeDI_apiBuilder_third = __safeDI_apiBuilder.third(SafeDIScope_Api.third_Values(fourth: fourth, second: second, sixth: sixth, first: first, fifth: fifth))
		        func __safeDI_third() -> A_B_C.D {
		            let api: any Api = __safeDI_apiBuilder_third.api(SafeDIScope_Api.Feature_A_B_C_D______Scope.api_Values())
		            return A_B_C.D(api: api)
		        }
		        let third: A_B_C.D = __safeDI_third()
		        self.init(fourth: fourth, second: second, sixth: sixth, first: first, fifth: fifth, third: third)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_2E1BE41ED5088217 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_2E1BE41ED5088217.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(fourth: { _ in __safeDI_apiBuilder_Home_Feature_A_B_C_D_Scope() }, second: { _ in __safeDI_apiBuilder_Home_Feature_A_B_C_D_____Scope() }, sixth: { _ in __safeDI_apiBuilder_Home_Feature_A_B_C_D__Scope() }, first: { _ in __safeDI_apiBuilder_Home_Feature_A_B_C_D___Scope() }, fifth: { _ in __safeDI_apiBuilder_Home_Feature_A_B_C_D____Scope() }, third: { _ in __safeDI_apiBuilder_Home_Feature_A_B_C_D______Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Feature_A_B_C_D_Scope() -> Home.SafeDIScope_Api.Feature_A_B_C_D_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Feature_A_B_C_D_____Scope() -> Home.SafeDIScope_Api.Feature_A_B_C_D_____Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Feature_A_B_C_D__Scope() -> Home.SafeDIScope_Api.Feature_A_B_C_D__Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Feature_A_B_C_D___Scope() -> Home.SafeDIScope_Api.Feature_A_B_C_D___Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Feature_A_B_C_D____Scope() -> Home.SafeDIScope_Api.Feature_A_B_C_D____Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Feature_A_B_C_D______Scope() -> Home.SafeDIScope_Api.Feature_A_B_C_D______Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNestedEnumApart_whenLevelOfTypeInsideFillSpellsTypeOfItsName() async throws {
		// `Outer` builds `Widget`, whose place `gadget` gives a nested enum `Widget_Scope`, and calls `Inner`, whose place
		// `Middle` fills with `DefaultUserService`, whose own place `gadget` is a case of `DefaultUserService_Scope`, nested
		// in the same root enum. That case's payload carries `DefaultUserService`'s `widgetScope: Widget_Scope`, a type of
		// `Feature`'s, which the nested enum would shadow, so the nested enum takes `_`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"public protocol UserService {}\npublic protocol Gadget {}",
					Self.type(named: "Widget_Scope", properties: []),
					Self.type(named: "Avatar", properties: ["@Instantiated let userService: any UserService"]),
					Self.type(named: "Inner", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let avatar: Avatar"]),
				]),
				ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
					"@Instantiable(fulfillingAdditionalTypes: [UserService.self]) public final class DefaultUserService: UserService, Instantiable {\n    public init(widgetScope: Widget_Scope, gadget: any Gadget) {\n        self.widgetScope = widgetScope\n        self.gadget = gadget\n    }\n    @Instantiated let widgetScope: Widget_Scope\n    @Instantiated let gadget: any Gadget\n}",
					Self.type(named: "Widget", properties: ["@Instantiated let gadget: any Gadget"]),
					Self.type(named: "Outer", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let widget: Widget", "@Instantiated let inner: Inner"]),
				].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					"@Instantiable(fulfillingAdditionalTypes: [Gadget.self]) final class DefaultGadget: Gadget, Instantiable { init() {} }",
					Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let outer: Outer"]),
				].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Outer {
		    @frozen public enum SafeDIScope_Gadget {
		        case widget(widget_Values, SafeDIScope_Gadget.Widget_Scope_)
		        case inner_userServiceBuilder(inner_userServiceBuilder_Values, Inner.SafeDIScope_UserService, SafeDIScope_Gadget.DefaultUserService_Scope)

		        public struct widget_Values {}

		        public struct inner_userServiceBuilder_Values {
		            public let widget: Widget
		        }

		        @frozen public enum Widget_Scope_ {
		            case gadget(gadget_Values)

		            public struct gadget_Values {}
		        }

		        @frozen public enum DefaultUserService_Scope {
		            case gadget(gadget_Values)

		            public struct gadget_Values {
		                public let widgetScope: Widget_Scope
		            }
		        }
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_gadgetBuilder: @escaping (SafeDIScope_Gadget) -> any Gadget) {
		        let __safeDI_gadgetValues_widget = SafeDIScope_Gadget.widget_Values()
		        func __safeDI_widget() -> Widget {
		            let gadget: any Gadget = __safeDI_gadgetBuilder(.widget(__safeDI_gadgetValues_widget, .gadget(SafeDIScope_Gadget.Widget_Scope_.gadget_Values())))
		            return Widget(gadget: gadget)
		        }
		        let widget: Widget = __safeDI_widget()
		        let __safeDI_gadgetValues_inner_userServiceBuilder = SafeDIScope_Gadget.inner_userServiceBuilder_Values(widget: widget)
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_38C8EF5D4844984A.self // \(Self.moduleInfoComment)
		            func __safeDI_userServiceBuilder_Inner(_ __safeDI_inner_userServiceBuilder: Inner.SafeDIScope_UserService) -> any UserService {
		                switch __safeDI_inner_userServiceBuilder {
		                case let .avatar(_, scope): return __safeDI_userServiceBuilder_Inner_Avatar_Scope(scope, __safeDI_inner_userServiceBuilder: __safeDI_inner_userServiceBuilder)
		                }
		            }
		            func __safeDI_userServiceBuilder_Inner_Avatar_Scope(_ scope: Inner.SafeDIScope_UserService.Avatar_Scope, __safeDI_inner_userServiceBuilder: Inner.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        let widgetScope = Widget_Scope()
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_userServiceBuilder(__safeDI_gadgetValues_inner_userServiceBuilder, __safeDI_inner_userServiceBuilder, .gadget(SafeDIScope_Gadget.DefaultUserService_Scope.gadget_Values(widgetScope: widgetScope))))
		                        return DefaultUserService(widgetScope: widgetScope, gadget: gadget)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Inner(__safeDI_userServiceBuilder: .init(
		                avatar: { __safeDI_avatarValues in
		                    .init(userService: { __safeDI_userServiceValues in __safeDI_userServiceBuilder_Inner(.avatar(__safeDI_avatarValues, .userService(__safeDI_userServiceValues))) })
		                }
		            ))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(widget: widget, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_AA37FBAC181F631D {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesDispatcherApart_whenFillOfNestedCaseHasDispatchersName() async throws {
		// `Home`'s place `Scope` is filled by `__safeDI_apiBuilder_Service_Home_Scope_Scope`, which is also the name of the
		// dispatcher of `Home_Scope`'s enum, `Home_Scope_Scope`. Fills claim their names first, so the dispatcher takes `_`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Api {}",
					Self.type(named: "Home", properties: ["@Instantiated let Scope: any Api"]),
					Self.type(named: "Home_Scope", properties: ["@Instantiated let api: any Api"]),
					Self.type(named: "Service", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let home: Home", "@Instantiated let homeScope: Home_Scope"]),
				],
				app: [
					"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init() {} }",
					Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let service: Service"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_46818DC8D89B0285.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Service() -> Service.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(home: { _ in __safeDI_apiBuilder_Service_Home_Scope() }, homeScope: { _ in __safeDI_apiBuilder_Service_Home_Scope_Scope_() })
		            }
		            func __safeDI_apiBuilder_Service_Home_Scope() -> Service.SafeDIScope_Api.Home_Scope.__safeDI_Builder<any Api> {
		                .init(Scope: { _ in
		                    let Scope: any Api = LiveApi()
		                    return Scope
		                })
		            }
		            func __safeDI_apiBuilder_Service_Home_Scope_Scope_() -> Service.SafeDIScope_Api.Home_Scope_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            return Service(__safeDI_apiBuilder: __safeDI_apiBuilder_Service())
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPayloadBindingApart_whenTreeBuildsPropertyOfBindingsName() async throws {
		// `Home` binds `Store`'s case's payload as `__safeDI_apiValues_store` before building `store`; it also builds
		// `apiValues_store`, whose builder function has that name, so the binding takes `_`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Api {}",
					Self.type(named: "Clock", properties: []),
					Self.type(named: "Shelf", properties: ["@Instantiated let api: any Api"]),
					Self.type(named: "Store", properties: ["@Instantiated let shelf: Shelf"]),
					Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let apiValues_store: Clock", "@Instantiated let store: Store"]),
				],
				app: [
					"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init() {} }",
					Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let home: Home"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case store(store_Values, SafeDIScope_Api.Store_Scope)

		        nonisolated public struct store_Values {
		            public let apiValues_store: Clock
		        }

		        @frozen nonisolated public enum Store_Scope {
		            case shelf(shelf_Values, SafeDIScope_Api.Shelf_Scope)

		            nonisolated public struct shelf_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let shelf: (shelf_Values) -> SafeDIScope_Api.Shelf_Scope.__safeDI_Builder<Built>

		                public init(shelf: @escaping (shelf_Values) -> SafeDIScope_Api.Shelf_Scope.__safeDI_Builder<Built>) {
		                    self.shelf = shelf
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.shelf = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Shelf_Scope {
		            case api(api_Values)

		            nonisolated public struct api_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<Built> {
		                public let api: (api_Values) -> Built

		                public init(api: @escaping (api_Values) -> Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<Built> {
		            public let store: (store_Values) -> SafeDIScope_Api.Store_Scope.__safeDI_Builder<Built>

		            public init(store: @escaping (store_Values) -> SafeDIScope_Api.Store_Scope.__safeDI_Builder<Built>) {
		                self.store = store
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> Built) {
		                self.store = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let apiValues_store = Clock()
		        let __safeDI_apiBuilder_store = __safeDI_apiBuilder.store(SafeDIScope_Api.store_Values(apiValues_store: apiValues_store))
		        func __safeDI_store() -> Store {
		            let __safeDI_apiBuilder_shelf = __safeDI_apiBuilder_store.shelf(SafeDIScope_Api.Store_Scope.shelf_Values())
		            func __safeDI_shelf() -> Shelf {
		                let api: any Api = __safeDI_apiBuilder_shelf.api(SafeDIScope_Api.Shelf_Scope.api_Values())
		                return Shelf(api: api)
		            }
		            let shelf: Shelf = __safeDI_shelf()
		            return Store(shelf: shelf)
		        }
		        let store: Store = __safeDI_store()
		        self.init(apiValues_store: apiValues_store, store: store)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_2B3F58416F9566DA {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheGuard_whenNestedTypesLevelGainsAField() async throws {
		// `Store`'s level before `api` gains `clock`: only an enum nested in the root changes, and the guard with it.
		let without = try await guardOfHome(storeName: "Store", storeProperties: ["@Instantiated let api: any Api"])
		let with = try await guardOfHome(storeName: "Store", storeProperties: ["@Instantiated let clock: Clock", "@Instantiated let api: any Api"])
		#expect(without != with)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesTheGuard_whenDescribedTypeIsRenamed() async throws {
		// Renaming `Store` renames its enum, `Store_Scope`, which a helper a person writes can spell, so the guard changes.
		let store = try await guardOfHome(storeName: "Store", storeProperties: ["@Instantiated let api: any Api"])
		let shop = try await guardOfHome(storeName: "Shop", storeProperties: ["@Instantiated let api: any Api"])
		#expect(store != shop)
	}

	// MARK: Private

	/// The guard of `Home`, which instantiates `store`, of type `storeName`, declared with `storeProperties`.
	private mutating func guardOfHome(storeName: String, storeProperties: [String]) async throws -> String {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				Self.type(named: "Clock", properties: []),
				Self.type(named: storeName, properties: storeProperties),
				Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let store: \(storeName)"]),
			])],
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		let generated = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
		return try #require(generated.components(separatedBy: "\n").first { $0.contains("enum __safeDI_Home_") })
	}

	/// The comment a call of `Feature`'s seam carries in a `.safedi` flow.
	private static let moduleInfoComment = "If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."

	private var filesToDelete: [URL]

	/// Shape E with `screenCount` screens in layers of four: screen `i` opens the three screens of the next layer but the one
	/// at its own position, every screen forwards an `id` and receives `Service`, and each screen of the last layer
	/// instantiates a model with the hole `api`, which `App` fills. Screen `i` is named `screenNames[i]` and its model
	/// `<name>Model`, or `Screen<i>` and `Model<i>`.
	private static func shapeEModules(screenCount: Int, screenNames: [String]? = nil) -> [ModuleFixture] {
		func screen(_ index: Int) -> String {
			screenNames?[index] ?? "Screen\(index)"
		}
		func model(_ index: Int) -> String {
			screenNames.map { "\($0[index])Model" } ?? "Model\(index)"
		}
		func label(_ typeName: String) -> String {
			typeName.prefix(1).lowercased() + typeName.dropFirst()
		}
		let layerCount = screenCount / 4
		var feature = [
			"@Instantiable public final class Service: Instantiable { public init() {} }",
			"public protocol Api {}",
		]
		for index in 0..<screenCount {
			let layer = index / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != index % 4 }.map { (layer + 1) * 4 + $0 } : []
			var screenProperties = ["@Forwarded let id: Int", "@Received let service: Service", "@Instantiated let \(label(model(index))): \(model(index))"]
			screenProperties += opened.map { "@Instantiated let \(label(screen($0)))Builder: Instantiator<\(screen($0))>" }
			feature.append(Self.type(named: screen(index), properties: screenProperties))
			var modelProperties = ["@Received let id: Int", "@Received let service: Service"]
			if opened.isEmpty {
				modelProperties.append("@Instantiated let api: any Api")
			}
			feature.append(Self.type(named: model(index), properties: modelProperties))
		}
		feature.append(Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: (0..<4).map { "@Instantiated let \(label(screen($0)))Builder: Instantiator<\(screen($0))>" }))
		return SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: [
			"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init(id: Int, service: Service) { self.id = id; self.service = service }\n    @Received let id: Int\n    @Received let service: Service\n}",
			Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let service: Service", "@Instantiated let home: Home"]),
		])
	}

	/// A `public final class` named `name` whose initializer takes `properties`, each of `@Attribute let label: Type`.
	private static func type(named name: String, access: String = "public", initializerAccess: String? = nil, attributes: String = "@Instantiable", properties: [String]) -> String {
		let parameters = properties.map { property in
			property.components(separatedBy: " let ").last ?? ""
		}
		let labels = parameters.map { String($0.prefix { $0 != ":" }) }
		return """
		\(attributes)
		\(access) final class \(name): Instantiable {
		    \(initializerAccess ?? access) init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }
		\(properties.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}
}
