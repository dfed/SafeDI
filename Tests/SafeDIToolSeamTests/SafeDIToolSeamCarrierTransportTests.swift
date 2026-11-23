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

/// A carrier level takes its values positionally where its longest case takes at most eight values, each at least as
/// visible as the carrier's members are where the seam's type caps them, and in run structs otherwise
/// (`SeamCarrierValues.positionalLevels(of:memberAccess:)`). The seam's module decides, and records the decision on its
/// enums for its callers. Each test sits on one side of one of the two bounds.
struct SafeDIToolSeamCarrierTransportTests: ~Copyable {
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
	mutating func generate_takesLevelsValuesPositionally_whenLevelHoldsEightValuesAsVisibleAsSeam() async throws {
		// Eight values, each `public` like the seam: the most a level takes positionally.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public protocol Api {}

					@Instantiable
					public struct Value1: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value2: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value3: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value4: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value5: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value6: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value7: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value8: Instantiable {
					    public init() {}
					}

					@Instantiable(generateDependencyTree: true)
					public final class Home: Instantiable {
					    public init(value1: Value1, value2: Value2, value3: Value3, value4: Value4, value5: Value5, value6: Value6, value7: Value7, value8: Value8, api: any Api) {
					        self.value1 = value1
					        self.value2 = value2
					        self.value3 = value3
					        self.value4 = value4
					        self.value5 = value5
					        self.value6 = value6
					        self.value7 = value7
					        self.value8 = value8
					        self.api = api
					    }

					    @Instantiated let value1: Value1
					    @Instantiated let value2: Value2
					    @Instantiated let value3: Value3
					    @Instantiated let value4: Value4
					    @Instantiated let value5: Value5
					    @Instantiated let value6: Value6
					    @Instantiated let value7: Value7
					    @Instantiated let value8: Value8
					    @Instantiated let api: any Api
					}
					""",
				]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Value1, Value2, Value3, Value4, Value5, Value6, Value7, Value8) -> __safeDI_Built

		        public init(api: @escaping (Value1, Value2, Value3, Value4, Value5, Value6, Value7, Value8) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _, _, _, _, _, _, _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let value1 = Value1()
		        let value2 = Value2()
		        let value3 = Value3()
		        let value4 = Value4()
		        let value5 = Value5()
		        let value6 = Value6()
		        let value7 = Value7()
		        let value8 = Value8()
		        let api: any Api = __safeDI_apiBuilder.api(value1, value2, value3, value4, value5, value6, value7, value8)
		        self.init(value1: value1, value2: value2, value3: value3, value4: value4, value5: value5, value6: value6, value7: value7, value8: value8, api: api)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_4B37A3194B09D2F8 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_formsRunStructs_whenLevelHoldsNineValues() async throws {
		// Nine values: one more than a level takes positionally, so the level's values travel in a run struct.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public protocol Api {}

					@Instantiable
					public struct Value1: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value2: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value3: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value4: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value5: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value6: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value7: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value8: Instantiable {
					    public init() {}
					}

					@Instantiable
					public struct Value9: Instantiable {
					    public init() {}
					}

					@Instantiable(generateDependencyTree: true)
					public final class Home: Instantiable {
					    public init(value1: Value1, value2: Value2, value3: Value3, value4: Value4, value5: Value5, value6: Value6, value7: Value7, value8: Value8, value9: Value9, api: any Api) {
					        self.value1 = value1
					        self.value2 = value2
					        self.value3 = value3
					        self.value4 = value4
					        self.value5 = value5
					        self.value6 = value6
					        self.value7 = value7
					        self.value8 = value8
					        self.value9 = value9
					        self.api = api
					    }

					    @Instantiated let value1: Value1
					    @Instantiated let value2: Value2
					    @Instantiated let value3: Value3
					    @Instantiated let value4: Value4
					    @Instantiated let value5: Value5
					    @Instantiated let value6: Value6
					    @Instantiated let value7: Value7
					    @Instantiated let value8: Value8
					    @Instantiated let value9: Value9
					    @Instantiated let api: any Api
					}
					""",
				]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public struct __safeDI_Values9 {
		        public let value1: Value1
		        public let value2: Value2
		        public let value3: Value3
		        public let value4: Value4
		        public let value5: Value5
		        public let value6: Value6
		        public let value7: Value7
		        public let value8: Value8
		        public let value9: Value9

		        init(value1: Value1, value2: Value2, value3: Value3, value4: Value4, value5: Value5, value6: Value6, value7: Value7, value8: Value8, value9: Value9) {
		            self.value1 = value1
		            self.value2 = value2
		            self.value3 = value3
		            self.value4 = value4
		            self.value5 = value5
		            self.value6 = value6
		            self.value7 = value7
		            self.value8 = value8
		            self.value9 = value9
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (__safeDI_Values9) -> __safeDI_Built

		        public init(api: @escaping (__safeDI_Values9) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let value1 = Value1()
		        let value2 = Value2()
		        let value3 = Value3()
		        let value4 = Value4()
		        let value5 = Value5()
		        let value6 = Value6()
		        let value7 = Value7()
		        let value8 = Value8()
		        let value9 = Value9()
		        let __safeDI__values9 = __safeDI_Values9(value1: value1, value2: value2, value3: value3, value4: value4, value5: value5, value6: value6, value7: value7, value8: value8, value9: value9)
		        let api: any Api = __safeDI_apiBuilder.api(__safeDI__values9)
		        self.init(value1: value1, value2: value2, value3: value3, value4: value4, value5: value5, value6: value6, value7: value7, value8: value8, value9: value9, api: api)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_9CB9B9F9E8E0A587 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesLevelsValuesPositionally_whenInternalSeamHoldsInternalValues() async throws {
		// An `internal` seam's carrier members are `internal` where the seam caps them, so `internal` values travel positionally.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					protocol Api {}

					@Instantiable
					struct Value1: Instantiable {
					    init() {}
					}

					@Instantiable
					struct Value2: Instantiable {
					    init() {}
					}

					@Instantiable
					struct Value3: Instantiable {
					    init() {}
					}

					@Instantiable
					struct Value4: Instantiable {
					    init() {}
					}

					@Instantiable
					struct Value5: Instantiable {
					    init() {}
					}

					@Instantiable
					struct Value6: Instantiable {
					    init() {}
					}

					@Instantiable
					struct Value7: Instantiable {
					    init() {}
					}

					@Instantiable
					struct Value8: Instantiable {
					    init() {}
					}

					@Instantiable(generateDependencyTree: true)
					final class Home: Instantiable {
					    init(value1: Value1, value2: Value2, value3: Value3, value4: Value4, value5: Value5, value6: Value6, value7: Value7, value8: Value8, api: any Api) {
					        self.value1 = value1
					        self.value2 = value2
					        self.value3 = value3
					        self.value4 = value4
					        self.value5 = value5
					        self.value6 = value6
					        self.value7 = value7
					        self.value8 = value8
					        self.api = api
					    }

					    @Instantiated let value1: Value1
					    @Instantiated let value2: Value2
					    @Instantiated let value3: Value3
					    @Instantiated let value4: Value4
					    @Instantiated let value5: Value5
					    @Instantiated let value6: Value6
					    @Instantiated let value7: Value7
					    @Instantiated let value8: Value8
					    @Instantiated let api: any Api
					}
					""",
				]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Value1, Value2, Value3, Value4, Value5, Value6, Value7, Value8) -> __safeDI_Built

		        public init(api: @escaping (Value1, Value2, Value3, Value4, Value5, Value6, Value7, Value8) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _, _, _, _, _, _, _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    internal convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let value1 = Value1()
		        let value2 = Value2()
		        let value3 = Value3()
		        let value4 = Value4()
		        let value5 = Value5()
		        let value6 = Value6()
		        let value7 = Value7()
		        let value8 = Value8()
		        let api: any Api = __safeDI_apiBuilder.api(value1, value2, value3, value4, value5, value6, value7, value8)
		        self.init(value1: value1, value2: value2, value3: value3, value4: value4, value5: value5, value6: value6, value7: value7, value8: value8, api: api)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_308BD31BE147DC84 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_formsRunStructs_whenPublicSeamHoldsPackageValue() async throws {
		// A `package` value cannot be a positional argument of a `public` member, so it travels as a run struct's `package` field.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public protocol Api {}

					@Instantiable
					public struct Value1: Instantiable {
					    public init() {}
					}

					@Instantiable
					package struct Value2: Instantiable {
					    package init() {}
					}

					@Instantiable(generateDependencyTree: true)
					public final class Home: Instantiable {
					    package init(value1: Value1, value2: Value2, api: any Api) {
					        self.value1 = value1
					        self.value2 = value2
					        self.api = api
					    }

					    @Instantiated let value1: Value1
					    @Instantiated let value2: Value2
					    @Instantiated let api: any Api
					}
					""",
				]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public struct __safeDI_Values2 {
		        public let value1: Value1
		        package let value2: Value2

		        init(value1: Value1, value2: Value2) {
		            self.value1 = value1
		            self.value2 = value2
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (__safeDI_Values2) -> __safeDI_Built

		        public init(api: @escaping (__safeDI_Values2) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let value1 = Value1()
		        let value2 = Value2()
		        let __safeDI__values2 = __safeDI_Values2(value1: value1, value2: value2)
		        let api: any Api = __safeDI_apiBuilder.api(__safeDI__values2)
		        self.init(value1: value1, value2: value2, api: api)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_B3BD8B75915DC3E5 {}
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
