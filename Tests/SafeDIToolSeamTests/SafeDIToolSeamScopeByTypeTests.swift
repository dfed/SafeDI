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
		// screen of the last layer builds a model whose `api` only `App` can build. One member per path would be 972 members,
		// which the caller could not compile; by type it is a member of a carrier per property: 4 + 20 × 3 + 4 + 4. The
		// caller's file is compared in full, so the order of its level functions and their members is pinned.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.shapeEModules(screenCount: 24),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let featureFile = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
		let enumDeclaration = try #require(featureFile.components(separatedBy: "    /// Only code SafeDI generates calls this initializer").first)
		let memberCount = enumDeclaration.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("public let ") && $0.contains(") -> ") }.count
		let enumCount = enumDeclaration.components(separatedBy: "nonisolated public final class ").count - 1
		#expect(memberCount == 72)
		#expect(enumCount == 29)
		// One level function per enum: the caller compiled above.
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
		            _ = Home.__safeDI_Home_B7F0BEA9B2D49F3A.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(screen0Builder: { values_service in __safeDI_apiBuilder_Home_Screen0_Scope() }, screen1Builder: { values_service, values_screen0Builder in __safeDI_apiBuilder_Home_Screen1_Scope() }, screen2Builder: { values_service, values_screen0Builder, values_screen1Builder in __safeDI_apiBuilder_Home_Screen2_Scope() }, screen3Builder: { values_service, values_screen0Builder, values_screen1Builder, values_screen2Builder in __safeDI_apiBuilder_Home_Screen3_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen0_Scope() -> Home.__safeDI_ApiCarrier_Screen0<any Api> {
		                .init(screen5Builder: { values_id, values_model0 in __safeDI_apiBuilder_Home_Screen5_Scope() }, screen6Builder: { values_id, values_model0, values_screen5Builder in __safeDI_apiBuilder_Home_Screen6_Scope() }, screen7Builder: { values_id, values_model0, values_screen5Builder, values_screen6Builder in __safeDI_apiBuilder_Home_Screen7_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen5_Scope() -> Home.__safeDI_ApiCarrier_Screen5<any Api> {
		                .init(screen8Builder: { values_id, values_model5 in __safeDI_apiBuilder_Home_Screen8_Scope() }, screen10Builder: { values_id, values_model5, values_screen8Builder in __safeDI_apiBuilder_Home_Screen10_Scope() }, screen11Builder: { values_id, values_model5, values_screen8Builder, values_screen10Builder in __safeDI_apiBuilder_Home_Screen11_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen8_Scope() -> Home.__safeDI_ApiCarrier_Screen8<any Api> {
		                .init(screen13Builder: { values_id, values_model8 in __safeDI_apiBuilder_Home_Screen13_Scope() }, screen14Builder: { values_id, values_model8, values_screen13Builder in __safeDI_apiBuilder_Home_Screen14_Scope() }, screen15Builder: { values_id, values_model8, values_screen13Builder, values_screen14Builder in __safeDI_apiBuilder_Home_Screen15_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen13_Scope() -> Home.__safeDI_ApiCarrier_Screen13<any Api> {
		                .init(screen16Builder: { values_id, values_model13 in __safeDI_apiBuilder_Home_Screen16_Scope() }, screen18Builder: { values_id, values_model13, values_screen16Builder in __safeDI_apiBuilder_Home_Screen18_Scope() }, screen19Builder: { values_id, values_model13, values_screen16Builder, values_screen18Builder in __safeDI_apiBuilder_Home_Screen19_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen16_Scope() -> Home.__safeDI_ApiCarrier_Screen16<any Api> {
		                .init(screen21Builder: { values_id, values_model16 in __safeDI_apiBuilder_Home_Screen21_Scope() }, screen22Builder: { values_id, values_model16, values_screen21Builder in __safeDI_apiBuilder_Home_Screen22_Scope() }, screen23Builder: { values_id, values_model16, values_screen21Builder, values_screen22Builder in __safeDI_apiBuilder_Home_Screen23_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen21_Scope() -> Home.__safeDI_ApiCarrier_Screen21<any Api> {
		                .init(model21: { values_id in __safeDI_apiBuilder_Home_Model21_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_Model21_Scope(id: Int) -> Home.__safeDI_ApiCarrier_Model21<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen22_Scope() -> Home.__safeDI_ApiCarrier_Screen22<any Api> {
		                .init(model22: { values_id in __safeDI_apiBuilder_Home_Model22_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_Model22_Scope(id: Int) -> Home.__safeDI_ApiCarrier_Model22<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen23_Scope() -> Home.__safeDI_ApiCarrier_Screen23<any Api> {
		                .init(model23: { values_id in __safeDI_apiBuilder_Home_Model23_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_Model23_Scope(id: Int) -> Home.__safeDI_ApiCarrier_Model23<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen18_Scope() -> Home.__safeDI_ApiCarrier_Screen18<any Api> {
		                .init(screen20Builder: { values_id, values_model18 in __safeDI_apiBuilder_Home_Screen20_Scope() }, screen21Builder: { values_id, values_model18, values_screen20Builder in __safeDI_apiBuilder_Home_Screen21_Scope() }, screen23Builder: { values_id, values_model18, values_screen20Builder, values_screen21Builder in __safeDI_apiBuilder_Home_Screen23_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen20_Scope() -> Home.__safeDI_ApiCarrier_Screen20<any Api> {
		                .init(model20: { values_id in __safeDI_apiBuilder_Home_Model20_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_Model20_Scope(id: Int) -> Home.__safeDI_ApiCarrier_Model20<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Screen19_Scope() -> Home.__safeDI_ApiCarrier_Screen19<any Api> {
		                .init(screen20Builder: { values_id, values_model19 in __safeDI_apiBuilder_Home_Screen20_Scope() }, screen21Builder: { values_id, values_model19, values_screen20Builder in __safeDI_apiBuilder_Home_Screen21_Scope() }, screen22Builder: { values_id, values_model19, values_screen20Builder, values_screen21Builder in __safeDI_apiBuilder_Home_Screen22_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen14_Scope() -> Home.__safeDI_ApiCarrier_Screen14<any Api> {
		                .init(screen16Builder: { values_id, values_model14 in __safeDI_apiBuilder_Home_Screen16_Scope() }, screen17Builder: { values_id, values_model14, values_screen16Builder in __safeDI_apiBuilder_Home_Screen17_Scope() }, screen19Builder: { values_id, values_model14, values_screen16Builder, values_screen17Builder in __safeDI_apiBuilder_Home_Screen19_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen17_Scope() -> Home.__safeDI_ApiCarrier_Screen17<any Api> {
		                .init(screen20Builder: { values_id, values_model17 in __safeDI_apiBuilder_Home_Screen20_Scope() }, screen22Builder: { values_id, values_model17, values_screen20Builder in __safeDI_apiBuilder_Home_Screen22_Scope() }, screen23Builder: { values_id, values_model17, values_screen20Builder, values_screen22Builder in __safeDI_apiBuilder_Home_Screen23_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen15_Scope() -> Home.__safeDI_ApiCarrier_Screen15<any Api> {
		                .init(screen16Builder: { values_id, values_model15 in __safeDI_apiBuilder_Home_Screen16_Scope() }, screen17Builder: { values_id, values_model15, values_screen16Builder in __safeDI_apiBuilder_Home_Screen17_Scope() }, screen18Builder: { values_id, values_model15, values_screen16Builder, values_screen17Builder in __safeDI_apiBuilder_Home_Screen18_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen10_Scope() -> Home.__safeDI_ApiCarrier_Screen10<any Api> {
		                .init(screen12Builder: { values_id, values_model10 in __safeDI_apiBuilder_Home_Screen12_Scope() }, screen13Builder: { values_id, values_model10, values_screen12Builder in __safeDI_apiBuilder_Home_Screen13_Scope() }, screen15Builder: { values_id, values_model10, values_screen12Builder, values_screen13Builder in __safeDI_apiBuilder_Home_Screen15_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen12_Scope() -> Home.__safeDI_ApiCarrier_Screen12<any Api> {
		                .init(screen17Builder: { values_id, values_model12 in __safeDI_apiBuilder_Home_Screen17_Scope() }, screen18Builder: { values_id, values_model12, values_screen17Builder in __safeDI_apiBuilder_Home_Screen18_Scope() }, screen19Builder: { values_id, values_model12, values_screen17Builder, values_screen18Builder in __safeDI_apiBuilder_Home_Screen19_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen11_Scope() -> Home.__safeDI_ApiCarrier_Screen11<any Api> {
		                .init(screen12Builder: { values_id, values_model11 in __safeDI_apiBuilder_Home_Screen12_Scope() }, screen13Builder: { values_id, values_model11, values_screen12Builder in __safeDI_apiBuilder_Home_Screen13_Scope() }, screen14Builder: { values_id, values_model11, values_screen12Builder, values_screen13Builder in __safeDI_apiBuilder_Home_Screen14_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen6_Scope() -> Home.__safeDI_ApiCarrier_Screen6<any Api> {
		                .init(screen8Builder: { values_id, values_model6 in __safeDI_apiBuilder_Home_Screen8_Scope() }, screen9Builder: { values_id, values_model6, values_screen8Builder in __safeDI_apiBuilder_Home_Screen9_Scope() }, screen11Builder: { values_id, values_model6, values_screen8Builder, values_screen9Builder in __safeDI_apiBuilder_Home_Screen11_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen9_Scope() -> Home.__safeDI_ApiCarrier_Screen9<any Api> {
		                .init(screen12Builder: { values_id, values_model9 in __safeDI_apiBuilder_Home_Screen12_Scope() }, screen14Builder: { values_id, values_model9, values_screen12Builder in __safeDI_apiBuilder_Home_Screen14_Scope() }, screen15Builder: { values_id, values_model9, values_screen12Builder, values_screen14Builder in __safeDI_apiBuilder_Home_Screen15_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen7_Scope() -> Home.__safeDI_ApiCarrier_Screen7<any Api> {
		                .init(screen8Builder: { values_id, values_model7 in __safeDI_apiBuilder_Home_Screen8_Scope() }, screen9Builder: { values_id, values_model7, values_screen8Builder in __safeDI_apiBuilder_Home_Screen9_Scope() }, screen10Builder: { values_id, values_model7, values_screen8Builder, values_screen9Builder in __safeDI_apiBuilder_Home_Screen10_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen1_Scope() -> Home.__safeDI_ApiCarrier_Screen1<any Api> {
		                .init(screen4Builder: { values_id, values_model1 in __safeDI_apiBuilder_Home_Screen4_Scope() }, screen6Builder: { values_id, values_model1, values_screen4Builder in __safeDI_apiBuilder_Home_Screen6_Scope() }, screen7Builder: { values_id, values_model1, values_screen4Builder, values_screen6Builder in __safeDI_apiBuilder_Home_Screen7_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen4_Scope() -> Home.__safeDI_ApiCarrier_Screen4<any Api> {
		                .init(screen9Builder: { values_id, values_model4 in __safeDI_apiBuilder_Home_Screen9_Scope() }, screen10Builder: { values_id, values_model4, values_screen9Builder in __safeDI_apiBuilder_Home_Screen10_Scope() }, screen11Builder: { values_id, values_model4, values_screen9Builder, values_screen10Builder in __safeDI_apiBuilder_Home_Screen11_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen2_Scope() -> Home.__safeDI_ApiCarrier_Screen2<any Api> {
		                .init(screen4Builder: { values_id, values_model2 in __safeDI_apiBuilder_Home_Screen4_Scope() }, screen5Builder: { values_id, values_model2, values_screen4Builder in __safeDI_apiBuilder_Home_Screen5_Scope() }, screen7Builder: { values_id, values_model2, values_screen4Builder, values_screen5Builder in __safeDI_apiBuilder_Home_Screen7_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Screen3_Scope() -> Home.__safeDI_ApiCarrier_Screen3<any Api> {
		                .init(screen4Builder: { values_id, values_model3 in __safeDI_apiBuilder_Home_Screen4_Scope() }, screen5Builder: { values_id, values_model3, values_screen4Builder in __safeDI_apiBuilder_Home_Screen5_Scope() }, screen6Builder: { values_id, values_model3, values_screen4Builder, values_screen5Builder in __safeDI_apiBuilder_Home_Screen6_Scope() })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let kiloBuilder: (LazilyInstantiated<Service>) -> __safeDI_ApiCarrier_Kilo<__safeDI_Built>
		        public let echoBuilder: (LazilyInstantiated<Service>, Instantiator<Kilo>) -> __safeDI_ApiCarrier_Echo<__safeDI_Built>
		        public let zuluBuilder: (LazilyInstantiated<Service>, Instantiator<Kilo>, Instantiator<Echo>) -> __safeDI_ApiCarrier_Zulu<__safeDI_Built>
		        public let alphaBuilder: (LazilyInstantiated<Service>, Instantiator<Kilo>, Instantiator<Echo>, Instantiator<Zulu>) -> __safeDI_ApiCarrier_Alpha<__safeDI_Built>

		        public init(kiloBuilder: @escaping (LazilyInstantiated<Service>) -> __safeDI_ApiCarrier_Kilo<__safeDI_Built>, echoBuilder: @escaping (LazilyInstantiated<Service>, Instantiator<Kilo>) -> __safeDI_ApiCarrier_Echo<__safeDI_Built>, zuluBuilder: @escaping (LazilyInstantiated<Service>, Instantiator<Kilo>, Instantiator<Echo>) -> __safeDI_ApiCarrier_Zulu<__safeDI_Built>, alphaBuilder: @escaping (LazilyInstantiated<Service>, Instantiator<Kilo>, Instantiator<Echo>, Instantiator<Zulu>) -> __safeDI_ApiCarrier_Alpha<__safeDI_Built>) {
		            self.kiloBuilder = kiloBuilder
		            self.echoBuilder = echoBuilder
		            self.zuluBuilder = zuluBuilder
		            self.alphaBuilder = alphaBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Kilo<__safeDI_Built> {
		        public let bravoBuilder: (Int, KiloModel) -> __safeDI_ApiCarrier_Bravo<__safeDI_Built>
		        public let yankeeBuilder: (Int, KiloModel, Instantiator<Bravo>) -> __safeDI_ApiCarrier_Yankee<__safeDI_Built>
		        public let deltaBuilder: (Int, KiloModel, Instantiator<Bravo>, Instantiator<Yankee>) -> __safeDI_ApiCarrier_Delta<__safeDI_Built>

		        public init(bravoBuilder: @escaping (Int, KiloModel) -> __safeDI_ApiCarrier_Bravo<__safeDI_Built>, yankeeBuilder: @escaping (Int, KiloModel, Instantiator<Bravo>) -> __safeDI_ApiCarrier_Yankee<__safeDI_Built>, deltaBuilder: @escaping (Int, KiloModel, Instantiator<Bravo>, Instantiator<Yankee>) -> __safeDI_ApiCarrier_Delta<__safeDI_Built>) {
		            self.bravoBuilder = bravoBuilder
		            self.yankeeBuilder = yankeeBuilder
		            self.deltaBuilder = deltaBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Echo<__safeDI_Built> {
		        public let mikeBuilder: (Int, EchoModel) -> __safeDI_ApiCarrier_Mike<__safeDI_Built>
		        public let yankeeBuilder: (Int, EchoModel, Instantiator<Mike>) -> __safeDI_ApiCarrier_Yankee<__safeDI_Built>
		        public let deltaBuilder: (Int, EchoModel, Instantiator<Mike>, Instantiator<Yankee>) -> __safeDI_ApiCarrier_Delta<__safeDI_Built>

		        public init(mikeBuilder: @escaping (Int, EchoModel) -> __safeDI_ApiCarrier_Mike<__safeDI_Built>, yankeeBuilder: @escaping (Int, EchoModel, Instantiator<Mike>) -> __safeDI_ApiCarrier_Yankee<__safeDI_Built>, deltaBuilder: @escaping (Int, EchoModel, Instantiator<Mike>, Instantiator<Yankee>) -> __safeDI_ApiCarrier_Delta<__safeDI_Built>) {
		            self.mikeBuilder = mikeBuilder
		            self.yankeeBuilder = yankeeBuilder
		            self.deltaBuilder = deltaBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Zulu<__safeDI_Built> {
		        public let mikeBuilder: (Int, ZuluModel) -> __safeDI_ApiCarrier_Mike<__safeDI_Built>
		        public let bravoBuilder: (Int, ZuluModel, Instantiator<Mike>) -> __safeDI_ApiCarrier_Bravo<__safeDI_Built>
		        public let deltaBuilder: (Int, ZuluModel, Instantiator<Mike>, Instantiator<Bravo>) -> __safeDI_ApiCarrier_Delta<__safeDI_Built>

		        public init(mikeBuilder: @escaping (Int, ZuluModel) -> __safeDI_ApiCarrier_Mike<__safeDI_Built>, bravoBuilder: @escaping (Int, ZuluModel, Instantiator<Mike>) -> __safeDI_ApiCarrier_Bravo<__safeDI_Built>, deltaBuilder: @escaping (Int, ZuluModel, Instantiator<Mike>, Instantiator<Bravo>) -> __safeDI_ApiCarrier_Delta<__safeDI_Built>) {
		            self.mikeBuilder = mikeBuilder
		            self.bravoBuilder = bravoBuilder
		            self.deltaBuilder = deltaBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Alpha<__safeDI_Built> {
		        public let mikeBuilder: (Int, AlphaModel) -> __safeDI_ApiCarrier_Mike<__safeDI_Built>
		        public let bravoBuilder: (Int, AlphaModel, Instantiator<Mike>) -> __safeDI_ApiCarrier_Bravo<__safeDI_Built>
		        public let yankeeBuilder: (Int, AlphaModel, Instantiator<Mike>, Instantiator<Bravo>) -> __safeDI_ApiCarrier_Yankee<__safeDI_Built>

		        public init(mikeBuilder: @escaping (Int, AlphaModel) -> __safeDI_ApiCarrier_Mike<__safeDI_Built>, bravoBuilder: @escaping (Int, AlphaModel, Instantiator<Mike>) -> __safeDI_ApiCarrier_Bravo<__safeDI_Built>, yankeeBuilder: @escaping (Int, AlphaModel, Instantiator<Mike>, Instantiator<Bravo>) -> __safeDI_ApiCarrier_Yankee<__safeDI_Built>) {
		            self.mikeBuilder = mikeBuilder
		            self.bravoBuilder = bravoBuilder
		            self.yankeeBuilder = yankeeBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Bravo<__safeDI_Built> {
		        public let bravoModel: (Int) -> __safeDI_ApiCarrier_BravoModel<__safeDI_Built>

		        public init(bravoModel: @escaping (Int) -> __safeDI_ApiCarrier_BravoModel<__safeDI_Built>) {
		            self.bravoModel = bravoModel
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Yankee<__safeDI_Built> {
		        public let yankeeModel: (Int) -> __safeDI_ApiCarrier_YankeeModel<__safeDI_Built>

		        public init(yankeeModel: @escaping (Int) -> __safeDI_ApiCarrier_YankeeModel<__safeDI_Built>) {
		            self.yankeeModel = yankeeModel
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Delta<__safeDI_Built> {
		        public let deltaModel: (Int) -> __safeDI_ApiCarrier_DeltaModel<__safeDI_Built>

		        public init(deltaModel: @escaping (Int) -> __safeDI_ApiCarrier_DeltaModel<__safeDI_Built>) {
		            self.deltaModel = deltaModel
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Mike<__safeDI_Built> {
		        public let mikeModel: (Int) -> __safeDI_ApiCarrier_MikeModel<__safeDI_Built>

		        public init(mikeModel: @escaping (Int) -> __safeDI_ApiCarrier_MikeModel<__safeDI_Built>) {
		            self.mikeModel = mikeModel
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_BravoModel<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_YankeeModel<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_DeltaModel<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_MikeModel<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_service: @autoclosure @escaping () -> Service, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let service = LazilyInstantiated<Service>(__safeDI_service)
		        let __safeDI_apiBuilder_kiloBuilder = __safeDI_apiBuilder.kiloBuilder(service)
		        @inline(never) func __safeDI_bravoBuilder(id: Int, __safeDI_apiBuilder_bravoBuilder: __safeDI_ApiCarrier_Bravo<any Api>) -> Bravo {
		            let __safeDI_apiBuilder_bravoModel = __safeDI_apiBuilder_bravoBuilder.bravoModel(id)
		            let bravoModel: BravoModel = __safeDI_bravoModel(id: id, __safeDI_apiBuilder_bravoModel: __safeDI_apiBuilder_bravoModel)
		            return Bravo(id: id, service: service.instance, bravoModel: bravoModel)
		        }
		        @inline(never) func __safeDI_bravoModel(id: Int, __safeDI_apiBuilder_bravoModel: __safeDI_ApiCarrier_BravoModel<any Api>) -> BravoModel {
		            let api: any Api = __safeDI_apiBuilder_bravoModel.api()
		            return BravoModel(id: id, service: service.instance, api: api)
		        }
		        @inline(never) func __safeDI_yankeeBuilder(id: Int, __safeDI_apiBuilder_yankeeBuilder: __safeDI_ApiCarrier_Yankee<any Api>) -> Yankee {
		            let __safeDI_apiBuilder_yankeeModel = __safeDI_apiBuilder_yankeeBuilder.yankeeModel(id)
		            let yankeeModel: YankeeModel = __safeDI_yankeeModel(id: id, __safeDI_apiBuilder_yankeeModel: __safeDI_apiBuilder_yankeeModel)
		            return Yankee(id: id, service: service.instance, yankeeModel: yankeeModel)
		        }
		        @inline(never) func __safeDI_yankeeModel(id: Int, __safeDI_apiBuilder_yankeeModel: __safeDI_ApiCarrier_YankeeModel<any Api>) -> YankeeModel {
		            let api: any Api = __safeDI_apiBuilder_yankeeModel.api()
		            return YankeeModel(id: id, service: service.instance, api: api)
		        }
		        @inline(never) func __safeDI_deltaBuilder(id: Int, __safeDI_apiBuilder_deltaBuilder: __safeDI_ApiCarrier_Delta<any Api>) -> Delta {
		            let __safeDI_apiBuilder_deltaModel = __safeDI_apiBuilder_deltaBuilder.deltaModel(id)
		            let deltaModel: DeltaModel = __safeDI_deltaModel(id: id, __safeDI_apiBuilder_deltaModel: __safeDI_apiBuilder_deltaModel)
		            return Delta(id: id, service: service.instance, deltaModel: deltaModel)
		        }
		        @inline(never) func __safeDI_deltaModel(id: Int, __safeDI_apiBuilder_deltaModel: __safeDI_ApiCarrier_DeltaModel<any Api>) -> DeltaModel {
		            let api: any Api = __safeDI_apiBuilder_deltaModel.api()
		            return DeltaModel(id: id, service: service.instance, api: api)
		        }
		        @inline(never) func __safeDI_kiloBuilder(id: Int) -> Kilo {
		            let kiloModel = KiloModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_bravoBuilder = __safeDI_apiBuilder_kiloBuilder.bravoBuilder(id, kiloModel)
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(id: $0, __safeDI_apiBuilder_bravoBuilder: __safeDI_apiBuilder_bravoBuilder)
		            }
		            let __safeDI_apiBuilder_yankeeBuilder = __safeDI_apiBuilder_kiloBuilder.yankeeBuilder(id, kiloModel, bravoBuilder)
		            let yankeeBuilder = Instantiator<Yankee> {
		                __safeDI_yankeeBuilder(id: $0, __safeDI_apiBuilder_yankeeBuilder: __safeDI_apiBuilder_yankeeBuilder)
		            }
		            let __safeDI_apiBuilder_deltaBuilder = __safeDI_apiBuilder_kiloBuilder.deltaBuilder(id, kiloModel, bravoBuilder, yankeeBuilder)
		            let deltaBuilder = Instantiator<Delta> {
		                __safeDI_deltaBuilder(id: $0, __safeDI_apiBuilder_deltaBuilder: __safeDI_apiBuilder_deltaBuilder)
		            }
		            return Kilo(id: id, service: service.instance, kiloModel: kiloModel, bravoBuilder: bravoBuilder, yankeeBuilder: yankeeBuilder, deltaBuilder: deltaBuilder)
		        }
		        let kiloBuilder = Instantiator<Kilo> {
		            __safeDI_kiloBuilder(id: $0)
		        }
		        let __safeDI_apiBuilder_echoBuilder = __safeDI_apiBuilder.echoBuilder(service, kiloBuilder)
		        @inline(never) func __safeDI_mikeBuilder(id: Int, __safeDI_apiBuilder_mikeBuilder: __safeDI_ApiCarrier_Mike<any Api>) -> Mike {
		            let __safeDI_apiBuilder_mikeModel = __safeDI_apiBuilder_mikeBuilder.mikeModel(id)
		            let mikeModel: MikeModel = __safeDI_mikeModel(id: id, __safeDI_apiBuilder_mikeModel: __safeDI_apiBuilder_mikeModel)
		            return Mike(id: id, service: service.instance, mikeModel: mikeModel)
		        }
		        @inline(never) func __safeDI_mikeModel(id: Int, __safeDI_apiBuilder_mikeModel: __safeDI_ApiCarrier_MikeModel<any Api>) -> MikeModel {
		            let api: any Api = __safeDI_apiBuilder_mikeModel.api()
		            return MikeModel(id: id, service: service.instance, api: api)
		        }
		        @inline(never) func __safeDI_echoBuilder(id: Int) -> Echo {
		            let echoModel = EchoModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_mikeBuilder = __safeDI_apiBuilder_echoBuilder.mikeBuilder(id, echoModel)
		            let mikeBuilder = Instantiator<Mike> {
		                __safeDI_mikeBuilder(id: $0, __safeDI_apiBuilder_mikeBuilder: __safeDI_apiBuilder_mikeBuilder)
		            }
		            let __safeDI_apiBuilder_yankeeBuilder = __safeDI_apiBuilder_echoBuilder.yankeeBuilder(id, echoModel, mikeBuilder)
		            let yankeeBuilder = Instantiator<Yankee> {
		                __safeDI_yankeeBuilder(id: $0, __safeDI_apiBuilder_yankeeBuilder: __safeDI_apiBuilder_yankeeBuilder)
		            }
		            let __safeDI_apiBuilder_deltaBuilder = __safeDI_apiBuilder_echoBuilder.deltaBuilder(id, echoModel, mikeBuilder, yankeeBuilder)
		            let deltaBuilder = Instantiator<Delta> {
		                __safeDI_deltaBuilder(id: $0, __safeDI_apiBuilder_deltaBuilder: __safeDI_apiBuilder_deltaBuilder)
		            }
		            return Echo(id: id, service: service.instance, echoModel: echoModel, mikeBuilder: mikeBuilder, yankeeBuilder: yankeeBuilder, deltaBuilder: deltaBuilder)
		        }
		        let echoBuilder = Instantiator<Echo> {
		            __safeDI_echoBuilder(id: $0)
		        }
		        let __safeDI_apiBuilder_zuluBuilder = __safeDI_apiBuilder.zuluBuilder(service, kiloBuilder, echoBuilder)
		        @inline(never) func __safeDI_zuluBuilder(id: Int) -> Zulu {
		            let zuluModel = ZuluModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_mikeBuilder = __safeDI_apiBuilder_zuluBuilder.mikeBuilder(id, zuluModel)
		            let mikeBuilder = Instantiator<Mike> {
		                __safeDI_mikeBuilder(id: $0, __safeDI_apiBuilder_mikeBuilder: __safeDI_apiBuilder_mikeBuilder)
		            }
		            let __safeDI_apiBuilder_bravoBuilder = __safeDI_apiBuilder_zuluBuilder.bravoBuilder(id, zuluModel, mikeBuilder)
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(id: $0, __safeDI_apiBuilder_bravoBuilder: __safeDI_apiBuilder_bravoBuilder)
		            }
		            let __safeDI_apiBuilder_deltaBuilder = __safeDI_apiBuilder_zuluBuilder.deltaBuilder(id, zuluModel, mikeBuilder, bravoBuilder)
		            let deltaBuilder = Instantiator<Delta> {
		                __safeDI_deltaBuilder(id: $0, __safeDI_apiBuilder_deltaBuilder: __safeDI_apiBuilder_deltaBuilder)
		            }
		            return Zulu(id: id, service: service.instance, zuluModel: zuluModel, mikeBuilder: mikeBuilder, bravoBuilder: bravoBuilder, deltaBuilder: deltaBuilder)
		        }
		        let zuluBuilder = Instantiator<Zulu> {
		            __safeDI_zuluBuilder(id: $0)
		        }
		        let __safeDI_apiBuilder_alphaBuilder = __safeDI_apiBuilder.alphaBuilder(service, kiloBuilder, echoBuilder, zuluBuilder)
		        @inline(never) func __safeDI_alphaBuilder(id: Int) -> Alpha {
		            let alphaModel = AlphaModel(id: id, service: service.instance)
		            let __safeDI_apiBuilder_mikeBuilder = __safeDI_apiBuilder_alphaBuilder.mikeBuilder(id, alphaModel)
		            let mikeBuilder = Instantiator<Mike> {
		                __safeDI_mikeBuilder(id: $0, __safeDI_apiBuilder_mikeBuilder: __safeDI_apiBuilder_mikeBuilder)
		            }
		            let __safeDI_apiBuilder_bravoBuilder = __safeDI_apiBuilder_alphaBuilder.bravoBuilder(id, alphaModel, mikeBuilder)
		            let bravoBuilder = Instantiator<Bravo> {
		                __safeDI_bravoBuilder(id: $0, __safeDI_apiBuilder_bravoBuilder: __safeDI_apiBuilder_bravoBuilder)
		            }
		            let __safeDI_apiBuilder_yankeeBuilder = __safeDI_apiBuilder_alphaBuilder.yankeeBuilder(id, alphaModel, mikeBuilder, bravoBuilder)
		            let yankeeBuilder = Instantiator<Yankee> {
		                __safeDI_yankeeBuilder(id: $0, __safeDI_apiBuilder_yankeeBuilder: __safeDI_apiBuilder_yankeeBuilder)
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
		    public enum __safeDI_Home_1315FAA515AD6ABA {}
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
		            _ = Home.__safeDI_Home_1315FAA515AD6ABA.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(kiloBuilder: { values_service in __safeDI_apiBuilder_Home_Kilo_Scope() }, echoBuilder: { values_service, values_kiloBuilder in __safeDI_apiBuilder_Home_Echo_Scope() }, zuluBuilder: { values_service, values_kiloBuilder, values_echoBuilder in __safeDI_apiBuilder_Home_Zulu_Scope() }, alphaBuilder: { values_service, values_kiloBuilder, values_echoBuilder, values_zuluBuilder in __safeDI_apiBuilder_Home_Alpha_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Kilo_Scope() -> Home.__safeDI_ApiCarrier_Kilo<any Api> {
		                .init(bravoBuilder: { values_id, values_kiloModel in __safeDI_apiBuilder_Home_Bravo_Scope() }, yankeeBuilder: { values_id, values_kiloModel, values_bravoBuilder in __safeDI_apiBuilder_Home_Yankee_Scope() }, deltaBuilder: { values_id, values_kiloModel, values_bravoBuilder, values_yankeeBuilder in __safeDI_apiBuilder_Home_Delta_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Bravo_Scope() -> Home.__safeDI_ApiCarrier_Bravo<any Api> {
		                .init(bravoModel: { values_id in __safeDI_apiBuilder_Home_BravoModel_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_BravoModel_Scope(id: Int) -> Home.__safeDI_ApiCarrier_BravoModel<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Yankee_Scope() -> Home.__safeDI_ApiCarrier_Yankee<any Api> {
		                .init(yankeeModel: { values_id in __safeDI_apiBuilder_Home_YankeeModel_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_YankeeModel_Scope(id: Int) -> Home.__safeDI_ApiCarrier_YankeeModel<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Delta_Scope() -> Home.__safeDI_ApiCarrier_Delta<any Api> {
		                .init(deltaModel: { values_id in __safeDI_apiBuilder_Home_DeltaModel_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_DeltaModel_Scope(id: Int) -> Home.__safeDI_ApiCarrier_DeltaModel<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Echo_Scope() -> Home.__safeDI_ApiCarrier_Echo<any Api> {
		                .init(mikeBuilder: { values_id, values_echoModel in __safeDI_apiBuilder_Home_Mike_Scope() }, yankeeBuilder: { values_id, values_echoModel, values_mikeBuilder in __safeDI_apiBuilder_Home_Yankee_Scope() }, deltaBuilder: { values_id, values_echoModel, values_mikeBuilder, values_yankeeBuilder in __safeDI_apiBuilder_Home_Delta_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Mike_Scope() -> Home.__safeDI_ApiCarrier_Mike<any Api> {
		                .init(mikeModel: { values_id in __safeDI_apiBuilder_Home_MikeModel_Scope(id: values_id) })
		            }
		            func __safeDI_apiBuilder_Home_MikeModel_Scope(id: Int) -> Home.__safeDI_ApiCarrier_MikeModel<any Api> {
		                .init(api: {
		                    let api: any Api = LiveApi(id: id, service: service)
		                    return api
		                })
		            }
		            func __safeDI_apiBuilder_Home_Zulu_Scope() -> Home.__safeDI_ApiCarrier_Zulu<any Api> {
		                .init(mikeBuilder: { values_id, values_zuluModel in __safeDI_apiBuilder_Home_Mike_Scope() }, bravoBuilder: { values_id, values_zuluModel, values_mikeBuilder in __safeDI_apiBuilder_Home_Bravo_Scope() }, deltaBuilder: { values_id, values_zuluModel, values_mikeBuilder, values_bravoBuilder in __safeDI_apiBuilder_Home_Delta_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Alpha_Scope() -> Home.__safeDI_ApiCarrier_Alpha<any Api> {
		                .init(mikeBuilder: { values_id, values_alphaModel in __safeDI_apiBuilder_Home_Mike_Scope() }, bravoBuilder: { values_id, values_alphaModel, values_mikeBuilder in __safeDI_apiBuilder_Home_Bravo_Scope() }, yankeeBuilder: { values_id, values_alphaModel, values_mikeBuilder, values_bravoBuilder in __safeDI_apiBuilder_Home_Yankee_Scope() })
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
		        func __safeDI_apiBuilder_Home_Hub_Scope() -> Home.__safeDI_ApiCarrier_Hub<any Api> {
		            .init(leaf: { values__zeta, values__scope, values__mu, values__values, values__kappa, values__delta in __safeDI_apiBuilder_Home_Leaf_Scope(delta: values__delta, kappa: values__kappa, mu: values__mu, scope: values__scope, values: values__values, zeta: values__zeta) })
		        }
		        func __safeDI_apiBuilder_Home_Leaf_Scope(delta: Value?, kappa: Value?, mu: Value?, scope: Value?, values: Value?, zeta: Value?) -> Home.__safeDI_ApiCarrier_Leaf<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(zeta: zeta, scope: scope, mu: mu, values: values, kappa: kappa, delta: delta)
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_Spoke_Scope(delta: Value?, kappa: Value?, mu: Value?, scope: Value?, values: Value?, zeta: Value?) -> Home.__safeDI_ApiCarrier_Spoke<any Api> {
		            .init(leaf: __safeDI_apiBuilder_Home_Leaf_Scope(delta: delta, kappa: kappa, mu: mu, scope: scope, values: values, zeta: zeta))
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_E16DE2709E601390.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(hubBuilder: __safeDI_apiBuilder_Home_Hub_Scope(), spoke: { values__hubBuilder in __safeDI_apiBuilder_Home_Spoke_Scope(delta: nil, kappa: nil, mu: nil, scope: nil, values: nil, zeta: nil) })
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let store: __safeDI_ApiCarrier_Store<__safeDI_Built>

		        public init(store: __safeDI_ApiCarrier_Store<__safeDI_Built>) {
		            self.store = store
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Store<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_store = __safeDI_apiBuilder.store
		        @inline(never) func __safeDI_store() -> Store {
		            let api: any Api = __safeDI_apiBuilder_store.api()
		            return Store(api: api)
		        }
		        let store: Store = __safeDI_store()
		        self.init(store: store)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_179E5B2D7FB075F1 {}
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
		            _ = Home.__safeDI_Home_179E5B2D7FB075F1.self // \(Self.moduleInfoComment)
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(store: __safeDI_apiBuilder_Home_Store_Scope())
		            }
		            func __safeDI_apiBuilder_Home_Store_Scope() -> Home.__safeDI_ApiCarrier_Store<any Api> {
		                .init(api: {
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let job: (Job_Scope) -> __safeDI_ApiCarrier_Job_Scope_<__safeDI_Built>

		        public init(job: @escaping (Job_Scope) -> __safeDI_ApiCarrier_Job_Scope_<__safeDI_Built>) {
		            self.job = job
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Job_Scope_<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let jobScope = Job_Scope()
		        let __safeDI_apiBuilder_job = __safeDI_apiBuilder.job(jobScope)
		        @inline(never) func __safeDI_job() -> Job {
		            let api: any Api = __safeDI_apiBuilder_job.api()
		            return Job(api: api)
		        }
		        let job: Job = __safeDI_job()
		        self.init(jobScope: jobScope, job: job)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_61C2B79C5E446E49 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Host() -> Host.__safeDI_ApiCarrier<any Api> {
		            .init(job: { values_jobScope in __safeDI_apiBuilder_Host_Job_Scope_(jobScope: values_jobScope) })
		        }
		        func __safeDI_apiBuilder_Host_Job_Scope_(jobScope: Job_Scope) -> Host.__safeDI_ApiCarrier_Job_Scope_<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(jobScope: jobScope)
		                return api
		            })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_61C2B79C5E446E49.self // \(Self.moduleInfoComment)
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let fourth: __safeDI_ApiCarrier_Feature_A_B_C_D<__safeDI_Built>
		        public let second: (A.B.C_D) -> __safeDI_ApiCarrier_Feature_A_B_C_D____<__safeDI_Built>
		        public let sixth: (A.B.C_D, A_B.C_D) -> __safeDI_ApiCarrier_Feature_A_B_C_D_<__safeDI_Built>
		        public let first: (A.B.C_D, A_B.C_D, A.B_C.D) -> __safeDI_ApiCarrier_Feature_A_B_C_D__<__safeDI_Built>
		        public let fifth: (A.B.C_D, A_B.C_D, A.B_C.D, A.B_C_D) -> __safeDI_ApiCarrier_Feature_A_B_C_D___<__safeDI_Built>
		        public let third: (A.B.C_D, A_B.C_D, A.B_C.D, A.B_C_D, A_B.C.D) -> __safeDI_ApiCarrier_Feature_A_B_C_D_____<__safeDI_Built>

		        public init(fourth: __safeDI_ApiCarrier_Feature_A_B_C_D<__safeDI_Built>, second: @escaping (A.B.C_D) -> __safeDI_ApiCarrier_Feature_A_B_C_D____<__safeDI_Built>, sixth: @escaping (A.B.C_D, A_B.C_D) -> __safeDI_ApiCarrier_Feature_A_B_C_D_<__safeDI_Built>, first: @escaping (A.B.C_D, A_B.C_D, A.B_C.D) -> __safeDI_ApiCarrier_Feature_A_B_C_D__<__safeDI_Built>, fifth: @escaping (A.B.C_D, A_B.C_D, A.B_C.D, A.B_C_D) -> __safeDI_ApiCarrier_Feature_A_B_C_D___<__safeDI_Built>, third: @escaping (A.B.C_D, A_B.C_D, A.B_C.D, A.B_C_D, A_B.C.D) -> __safeDI_ApiCarrier_Feature_A_B_C_D_____<__safeDI_Built>) {
		            self.fourth = fourth
		            self.second = second
		            self.sixth = sixth
		            self.first = first
		            self.fifth = fifth
		            self.third = third
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Feature_A_B_C_D<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Feature_A_B_C_D____<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Feature_A_B_C_D_<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Feature_A_B_C_D__<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Feature_A_B_C_D___<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Feature_A_B_C_D_____<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_fourth = __safeDI_apiBuilder.fourth
		        @inline(never) func __safeDI_fourth() -> A.B.C_D {
		            let api: any Api = __safeDI_apiBuilder_fourth.api()
		            return A.B.C_D(api: api)
		        }
		        let fourth: A.B.C_D = __safeDI_fourth()
		        let __safeDI_apiBuilder_second = __safeDI_apiBuilder.second(fourth)
		        @inline(never) func __safeDI_second() -> A_B.C_D {
		            let api: any Api = __safeDI_apiBuilder_second.api()
		            return A_B.C_D(api: api)
		        }
		        let second: A_B.C_D = __safeDI_second()
		        let __safeDI_apiBuilder_sixth = __safeDI_apiBuilder.sixth(fourth, second)
		        @inline(never) func __safeDI_sixth() -> A.B_C.D {
		            let api: any Api = __safeDI_apiBuilder_sixth.api()
		            return A.B_C.D(api: api)
		        }
		        let sixth: A.B_C.D = __safeDI_sixth()
		        let __safeDI_apiBuilder_first = __safeDI_apiBuilder.first(fourth, second, sixth)
		        @inline(never) func __safeDI_first() -> A.B_C_D {
		            let api: any Api = __safeDI_apiBuilder_first.api()
		            return A.B_C_D(api: api)
		        }
		        let first: A.B_C_D = __safeDI_first()
		        let __safeDI_apiBuilder_fifth = __safeDI_apiBuilder.fifth(fourth, second, sixth, first)
		        @inline(never) func __safeDI_fifth() -> A_B.C.D {
		            let api: any Api = __safeDI_apiBuilder_fifth.api()
		            return A_B.C.D(api: api)
		        }
		        let fifth: A_B.C.D = __safeDI_fifth()
		        let __safeDI_apiBuilder_third = __safeDI_apiBuilder.third(fourth, second, sixth, first, fifth)
		        @inline(never) func __safeDI_third() -> A_B_C.D {
		            let api: any Api = __safeDI_apiBuilder_third.api()
		            return A_B_C.D(api: api)
		        }
		        let third: A_B_C.D = __safeDI_third()
		        self.init(fourth: fourth, second: second, sixth: sixth, first: first, fifth: fifth, third: third)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_1B601D965B062947 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(fourth: __safeDI_apiBuilder_Home_Feature_A_B_C_D_Scope(), second: { values_fourth in __safeDI_apiBuilder_Home_Feature_A_B_C_D_____Scope() }, sixth: { values_fourth, values_second in __safeDI_apiBuilder_Home_Feature_A_B_C_D__Scope() }, first: { values_fourth, values_second, values_sixth in __safeDI_apiBuilder_Home_Feature_A_B_C_D___Scope() }, fifth: { values_fourth, values_second, values_sixth, values_first in __safeDI_apiBuilder_Home_Feature_A_B_C_D____Scope() }, third: { values_fourth, values_second, values_sixth, values_first, values_fifth in __safeDI_apiBuilder_Home_Feature_A_B_C_D______Scope() })
		        }
		        func __safeDI_apiBuilder_Home_Feature_A_B_C_D_Scope() -> Home.__safeDI_ApiCarrier_Feature_A_B_C_D<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_Feature_A_B_C_D_____Scope() -> Home.__safeDI_ApiCarrier_Feature_A_B_C_D____<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_Feature_A_B_C_D__Scope() -> Home.__safeDI_ApiCarrier_Feature_A_B_C_D_<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_Feature_A_B_C_D___Scope() -> Home.__safeDI_ApiCarrier_Feature_A_B_C_D__<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_Feature_A_B_C_D____Scope() -> Home.__safeDI_ApiCarrier_Feature_A_B_C_D___<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_apiBuilder_Home_Feature_A_B_C_D______Scope() -> Home.__safeDI_ApiCarrier_Feature_A_B_C_D_____<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_1B601D965B062947.self // \(Self.moduleInfoComment)
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
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct widget_Values {}

		        nonisolated public struct inner_userServiceBuilder_Values {
		            public let widget: Widget
		        }

		        nonisolated public enum Widget_Scope_ {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }
		            }
		        }

		        nonisolated public enum DefaultUserService_Scope {
		            nonisolated public struct gadget_Values {
		                public let widgetScope: Widget_Scope
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let widget: (widget_Values) -> SafeDIScope_Gadget.Widget_Scope_.__safeDI_Builder<__safeDI_Built>
		            public let inner_userServiceBuilder: (inner_userServiceBuilder_Values) -> Inner.__safeDI_UserServiceCarrier<SafeDIScope_Gadget.DefaultUserService_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(widget: @escaping (widget_Values) -> SafeDIScope_Gadget.Widget_Scope_.__safeDI_Builder<__safeDI_Built>, inner_userServiceBuilder: @escaping (inner_userServiceBuilder_Values) -> Inner.__safeDI_UserServiceCarrier<SafeDIScope_Gadget.DefaultUserService_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.widget = widget
		                self.inner_userServiceBuilder = inner_userServiceBuilder
		            }
		        }
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_widget = __safeDI_gadgetBuilder.widget(SafeDIScope_Gadget.widget_Values())
		        @inline(never) func __safeDI_widget() -> Widget {
		            let gadget: any Gadget = __safeDI_gadgetBuilder_widget.gadget(SafeDIScope_Gadget.Widget_Scope_.gadget_Values())
		            return Widget(gadget: gadget)
		        }
		        let widget: Widget = __safeDI_widget()
		        let __safeDI_gadgetBuilder_inner_userServiceBuilder = __safeDI_gadgetBuilder.inner_userServiceBuilder(SafeDIScope_Gadget.inner_userServiceBuilder_Values(widget: widget))
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_9D3BA82D9336C0A4.self // \(Self.moduleInfoComment)
		            @inline(never) func __safeDI_userServiceBuilder_Inner_Avatar_Scope_userService(__safeDI_inner_userServiceBuilder: SafeDIScope_Gadget.DefaultUserService_Scope.__safeDI_Builder<any Gadget>) -> any UserService {
		                @inline(never) func __safeDI_userService() -> DefaultUserService {
		                    let widgetScope = Widget_Scope()
		                    let gadget: any Gadget = __safeDI_inner_userServiceBuilder.gadget(SafeDIScope_Gadget.DefaultUserService_Scope.gadget_Values(widgetScope: widgetScope))
		                    return DefaultUserService(widgetScope: widgetScope, gadget: gadget)
		                }
		                let userService: any UserService = __safeDI_userService()
		                return userService
		            }
		            @inline(never) func __safeDI_userServiceBuilder_Inner(up: Inner.__safeDI_UserServiceCarrier<SafeDIScope_Gadget.DefaultUserService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_UserServiceCarrier<any UserService> {
		                .init(avatar: __safeDI_userServiceBuilder_Inner_Avatar_Scope(up: up.avatar))
		            }
		            @inline(never) func __safeDI_userServiceBuilder_Inner_Avatar_Scope(up: Inner.__safeDI_UserServiceCarrier_Avatar<SafeDIScope_Gadget.DefaultUserService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_UserServiceCarrier_Avatar<any UserService> {
		                .init(userService: { __safeDI_userServiceBuilder_Inner_Avatar_Scope_userService(__safeDI_inner_userServiceBuilder: up.userService()) })
		            }
		            return Inner(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_userServiceBuilder))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(widget: widget, inner: inner)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_C61A7C6E195F9CED {}
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
		        func __safeDI_apiBuilder_Service() -> Service.__safeDI_ApiCarrier<any Api> {
		            .init(home: __safeDI_apiBuilder_Service_Home_Scope(), homeScope: { values_home in __safeDI_apiBuilder_Service_Home_Scope_Scope_() })
		        }
		        func __safeDI_apiBuilder_Service_Home_Scope() -> Service.__safeDI_ApiCarrier_Home<any Api> {
		            .init(Scope: {
		                let Scope: any Api = LiveApi()
		                return Scope
		            })
		        }
		        func __safeDI_apiBuilder_Service_Home_Scope_Scope_() -> Service.__safeDI_ApiCarrier_Home_Scope<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_270E2831CA75B2B1.self // \(Self.moduleInfoComment)
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let store: (Clock) -> __safeDI_ApiCarrier_Store<__safeDI_Built>

		        public init(store: @escaping (Clock) -> __safeDI_ApiCarrier_Store<__safeDI_Built>) {
		            self.store = store
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Store<__safeDI_Built> {
		        public let shelf: __safeDI_ApiCarrier_Shelf<__safeDI_Built>

		        public init(shelf: __safeDI_ApiCarrier_Shelf<__safeDI_Built>) {
		            self.shelf = shelf
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Shelf<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let apiValues_store = Clock()
		        let __safeDI_apiBuilder_store = __safeDI_apiBuilder.store(apiValues_store)
		        @inline(never) func __safeDI_shelf(__safeDI_apiBuilder_shelf: __safeDI_ApiCarrier_Shelf<any Api>) -> Shelf {
		            let api: any Api = __safeDI_apiBuilder_shelf.api()
		            return Shelf(api: api)
		        }
		        @inline(never) func __safeDI_store() -> Store {
		            let __safeDI_apiBuilder_shelf = __safeDI_apiBuilder_store.shelf
		            let shelf: Shelf = __safeDI_shelf(__safeDI_apiBuilder_shelf: __safeDI_apiBuilder_shelf)
		            return Store(shelf: shelf)
		        }
		        let store: Store = __safeDI_store()
		        self.init(apiValues_store: apiValues_store, store: store)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_83A085F88D949FCA {}
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
	/// `<name>Model`, or `Screen<i>` and `Model<i>`. With `placesInFillsOfInnerSeam`, each model of the last layer instead
	/// instantiates `ApiHolder`, a seam of module `Inner` whose hole `client` `Home`'s tree fills with `LiveClient`, which
	/// holds `api`: so `Home` calls a seam at each path, and its places are in the fills of those calls. With
	/// `opensScreensOfItsOwn`, the `screenCount / 4` layers form a tree instead: each screen but the last layer's opens three
	/// screens no other screen opens, so every path reaches a screen, a model and a place of its own.
	static func shapeEModules(screenCount: Int, screenNames: [String]? = nil, placesInFillsOfInnerSeam: Bool = false, opensScreensOfItsOwn: Bool = false) -> [ModuleFixture] {
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
		// The screens each screen opens, by index.
		var openedByScreen = [[Int]]()
		if opensScreensOfItsOwn {
			var layer = Array(0..<4)
			openedByScreen = layer.map { _ in [] }
			for _ in 1..<layerCount {
				var nextLayer = [Int]()
				for index in layer {
					let opened = Array(openedByScreen.count..<(openedByScreen.count + 3))
					openedByScreen[index] = opened
					openedByScreen += opened.map { _ in [] }
					nextLayer += opened
				}
				layer = nextLayer
			}
		} else {
			openedByScreen = (0..<screenCount).map { index in
				let layer = index / 4
				return layer < layerCount - 1 ? (0..<4).filter { $0 != index % 4 }.map { (layer + 1) * 4 + $0 } : []
			}
		}
		var feature = [
			"@Instantiable public final class Service: Instantiable { public init() {} }",
			"public protocol Api {}",
		]
		for (index, opened) in openedByScreen.enumerated() {
			var screenProperties = ["@Forwarded let id: Int", "@Received let service: Service", "@Instantiated let \(label(model(index))): \(model(index))"]
			screenProperties += opened.map { "@Instantiated let \(label(screen($0)))Builder: Instantiator<\(screen($0))>" }
			feature.append(Self.type(named: screen(index), properties: screenProperties))
			var modelProperties = ["@Received let id: Int", "@Received let service: Service"]
			if opened.isEmpty {
				modelProperties.append(placesInFillsOfInnerSeam ? "@Instantiated let apiHolder: ApiHolder" : "@Instantiated let api: any Api")
			}
			feature.append(Self.type(named: model(index), properties: modelProperties))
		}
		feature.append(Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: (0..<4).map { "@Instantiated let \(label(screen($0)))Builder: Instantiator<\(screen($0))>" }))
		let app = [
			"@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init(id: Int, service: Service) { self.id = id; self.service = service }\n    @Received let id: Int\n    @Received let service: Service\n}",
			Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let service: Service", "@Instantiated let home: Home"]),
		]
		guard placesInFillsOfInnerSeam else {
			return SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
		}
		feature.append(Self.type(named: "LiveClient", attributes: "@Instantiable(fulfillingAdditionalTypes: [Client.self])", conformances: ", Client", properties: ["@Received let id: Int", "@Received let service: Service", "@Instantiated let api: any Api"]))
		return [
			ModuleFixture(name: "Inner", packageName: "Shop", swiftFileContent: [
				"public protocol Client {}",
				Self.type(named: "ApiHolder", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let client: any Client"]),
			]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature.map { "import Inner\n\n" + $0 }, dependencies: ["Inner"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Inner\n\n" + $0 }, dependencies: ["Inner", "Feature"]),
		]
	}

	/// A `public final class` named `name`, conforming to `Instantiable` and then `conformances`, whose initializer takes
	/// `properties`, each of `@Attribute let label: Type`.
	private static func type(named name: String, access: String = "public", initializerAccess: String? = nil, attributes: String = "@Instantiable", conformances: String = "", properties: [String]) -> String {
		let parameters = properties.map { property in
			property.components(separatedBy: " let ").last ?? ""
		}
		let labels = parameters.map { String($0.prefix { $0 != ":" }) }
		return """
		\(attributes)
		\(access) final class \(name): Instantiable\(conformances) {
		    \(initializerAccess ?? access) init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }
		\(properties.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}
}
