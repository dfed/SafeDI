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

/// Carriers of seams that call one another: each seam builds the other in an instantiator, so a member of one seam's
/// carrier leads to the other seam's root carrier, and the two seams' levels form one loop. A level in that loop is a
/// closure member, which the seam's tree calls, never a `let` it reads, though the seam's own levels alone form no loop.
struct SafeDIToolSeamCarrierCallRingTests: ~Copyable {
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

	/// `First` builds `Mid`, which builds `Second`, and `Second` builds `First`, each seam in an `Instantiator`, and only
	/// `Second` builds a place of `Api`. `First` passes `Second`'s place up through its `Mid` level, whose member leads to
	/// `Second`'s root carrier, whose member leads back to `First`'s: a loop of levels across the two seams, so `First`'s
	/// carrier declares its `mid` member a closure, and `First`'s tree calls it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsNestedLevelLeadingToOtherSeam_whenTwoSeamsBuildEachOtherInInstantiators() async throws {
		let modules = Self.twoSeamRing(wrapper: "Instantiator")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		extension First {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let mid: () -> __safeDI_ApiCarrier_Mid<__safeDI_Built>

		        public init(mid: @escaping () -> __safeDI_ApiCarrier_Mid<__safeDI_Built>) {
		            self.mid = mid
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(mid: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Mid<__safeDI_Built> {
		        public let secondBuilder: () -> Second.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(secondBuilder: @escaping () -> Second.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.secondBuilder = secondBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(secondBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_mid = __safeDI_apiBuilder.mid()
		        func __safeDI_mid() -> Mid {
		            func __safeDI_secondBuilder() -> Second {
		                _ = Second.__safeDI_Second_65EDB0DFB850B578.self
		                return Second(__safeDI_apiBuilder: __safeDI_apiBuilder_mid.secondBuilder())
		            }
		            let secondBuilder = Instantiator<Second>(__safeDI_secondBuilder)
		            return Mid(secondBuilder: secondBuilder)
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}

		extension First {
		    public enum __safeDI_First_65EDB0DFB850B578 {}
		}

		extension Second {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Instantiator<First>) -> __safeDI_Built
		        public let firstBuilder: () -> First.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(api: @escaping (Instantiator<First>) -> __safeDI_Built, firstBuilder: @escaping () -> First.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.api = api
		            self.firstBuilder = firstBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() }, firstBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        func __safeDI_firstBuilder() -> First {
		            _ = First.__safeDI_First_65EDB0DFB850B578.self
		            return First(__safeDI_apiBuilder: __safeDI_apiBuilder.firstBuilder())
		        }
		        let firstBuilder = Instantiator<First>(__safeDI_firstBuilder)
		        let api: any Api = __safeDI_apiBuilder.api(firstBuilder)
		        self.init(api: api, firstBuilder: firstBuilder)
		    }
		}

		extension Second {
		    public enum __safeDI_Second_65EDB0DFB850B578 {}
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, filesToDelete: &filesToDelete)
	}

	/// The same ring in `SendableInstantiator`s: `First`'s `@Sendable` carrier declares its `mid_Sendable` member a closure,
	/// and `First`'s tree calls it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsNestedLevelLeadingToOtherSeam_whenTwoSeamsBuildEachOtherInSendableInstantiators() async throws {
		let modules = Self.twoSeamRing(wrapper: "SendableInstantiator")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		extension First {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let mid_Sendable: @Sendable () -> __safeDI_ApiSendableCarrier_Mid<__safeDI_Built>

		        public init(mid_Sendable: @escaping @Sendable () -> __safeDI_ApiSendableCarrier_Mid<__safeDI_Built>) {
		            self.mid_Sendable = mid_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(mid_Sendable: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier_Mid<__safeDI_Built>: Sendable {
		        public let secondBuilder: @Sendable () -> Second.__safeDI_ApiCarrier<__safeDI_Built>
		        public let secondBuilder_Sendable: @Sendable () -> Second.__safeDI_ApiSendableCarrier<__safeDI_Built>

		        public init(secondBuilder: @escaping @Sendable () -> Second.__safeDI_ApiCarrier<__safeDI_Built>, secondBuilder_Sendable: @escaping @Sendable () -> Second.__safeDI_ApiSendableCarrier<__safeDI_Built>) {
		            self.secondBuilder = secondBuilder
		            self.secondBuilder_Sendable = secondBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(secondBuilder: { .init(__safeDI_noScope: __safeDI_builder) }, secondBuilder_Sendable: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let __safeDI_apiSendableBuilder_mid_Sendable = __safeDI_apiSendableBuilder.mid_Sendable()
		        func __safeDI_mid() -> Mid {
		            @Sendable nonisolated func __safeDI_secondBuilder() -> Second {
		                _ = Second.__safeDI_Second_3B1EC6CD5520D2F2.self
		                return Second(__safeDI_apiBuilder: __safeDI_apiSendableBuilder_mid_Sendable.secondBuilder(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_mid_Sendable.secondBuilder_Sendable())
		            }
		            let secondBuilder = SendableInstantiator<Second>(__safeDI_secondBuilder)
		            return Mid(secondBuilder: secondBuilder)
		        }
		        let mid: Mid = __safeDI_mid()
		        self.init(mid: mid)
		    }
		}

		extension First {
		    public enum __safeDI_First_DEFB40E03FD8B994 {}
		}

		extension Second {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (SendableInstantiator<First>) -> __safeDI_Built

		        public init(api: @escaping (SendableInstantiator<First>) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let firstBuilder_Sendable: @Sendable () -> First.__safeDI_ApiSendableCarrier<__safeDI_Built>

		        public init(firstBuilder_Sendable: @escaping @Sendable () -> First.__safeDI_ApiSendableCarrier<__safeDI_Built>) {
		            self.firstBuilder_Sendable = firstBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(firstBuilder_Sendable: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @Sendable nonisolated func __safeDI_firstBuilder() -> First {
		            _ = First.__safeDI_First_DEFB40E03FD8B994.self
		            return First(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder.firstBuilder_Sendable())
		        }
		        let firstBuilder = SendableInstantiator<First>(__safeDI_firstBuilder)
		        let api: any Api = __safeDI_apiBuilder.api(firstBuilder)
		        self.init(api: api, firstBuilder: firstBuilder)
		    }
		}

		extension Second {
		    public enum __safeDI_Second_3B1EC6CD5520D2F2 {}
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, filesToDelete: &filesToDelete)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func twoSeamRing(wrapper: String) -> [ModuleFixture] {
		CarrierCells.modules(
			seam: [
				"public protocol Api" + (wrapper == "SendableInstantiator" ? ": Sendable" : "") + " {}",
				seamFixtureType(named: "First", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let mid: Mid"]),
				seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let secondBuilder: \(wrapper)<Second>"]),
				seamFixtureType(named: "Second", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated let firstBuilder: \(wrapper)<First>"]),
			],
			app: [
				CarrierCells.fulfillingImpl(named: "ApiImpl", fulfilling: "Api", reading: []),
				CarrierCellRoot.structRoot.declaration(building: "first: First"),
			],
		)
	}
}
