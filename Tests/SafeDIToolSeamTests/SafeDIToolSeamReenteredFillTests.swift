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

/// The comment a call of `seam`, a seam of `module`, carries under `.moduleInfo`.
private func seamCallComment(seam: String, module: String) -> String {
	MultiModuleIntegration.moduleInfo.seamCallComment(type: seam, declaringModule: module)
}

/// A seam's call made inside a fill whose own fill is the reuse, by name, of a level function of an enclosing call that
/// takes a carried struct: the call takes that struct from a member of its own case, `<call>_<builder>`, on the level of
/// the type that makes the call, nested under the level of the enclosing fill, bound before the calling property's builder
/// function, or at the top of the `@Sendable` function that builds the called seam.
///
/// `Feature` declares `Top`, a seam that calls `SubA` and `SubB`, whose holes `First` and `Second` `Top` passes up. `Middle`'s
/// `Host` calls `Top` and fills `First` with `DefaultFirst`, whose tree calls `SubB` again, and `Second` with `DefaultSecond`,
/// which holds `gadget`, a place `App` fills.
struct SafeDIToolSeamReenteredFillTests: ~Copyable {
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
	mutating func generate_readsForwardedValueOfReenteredSeam_whenCallingTypeDeclaresValueOfSameLabelBeforeCall() async throws {
		// `DefaultFirst` binds `x` before it builds `SubB` through an `Instantiator` that forwards `x`, and `DefaultGadget`
		// receives `x`: inline, the gadget reads the `x` `SubB` is forwarded, on both routes.
		let fixture = Fixture(
			subBDeclarations: ["@Forwarded let x: X", "@Instantiated let second: any Second"],
			topDeclarations: ["@Instantiated let subA: SubA", "@Instantiated let subBBuilder: Instantiator<SubB>"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subBBuilder: Instantiator<SubB>"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public struct top_secondBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subBBuilder_secondBuilder_Values {
		                public let x: X
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subBBuilder_secondBuilder: (subBBuilder_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subBBuilder_secondBuilder: @escaping (subBBuilder_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subBBuilder_secondBuilder = subBBuilder_secondBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.subBBuilder_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                }
		            }
		        }

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.top_firstBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.top_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_F040B41D9F722082.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_SubA_first(_ scope: SubA.SafeDIScope_First.first_Values, __safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                func __safeDI_first() -> DefaultFirst {
		                    let x = X()
		                    let __safeDI_gadgetBuilder_subBBuilder_secondBuilder = __safeDI_top_firstBuilder.subBBuilder_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subBBuilder_secondBuilder_Values(x: x))
		                    func __safeDI_subBBuilder(x: X) -> SubB {
		                        _ = SubB.__safeDI_SubB_421B6BA2506CEF55.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_x: x, __safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subBBuilder_secondBuilder))
		                    }
		                    let subBBuilder = Instantiator<SubB> {
		                        __safeDI_subBBuilder(x: $0)
		                    }
		                    return DefaultFirst(x: x, subBBuilder: subBBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            func __safeDI_secondBuilder_SubB_second(_ scope: SubB.SafeDIScope_Second.second_Values, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            func __safeDI_firstBuilder_Top(up: Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { values in __safeDI_firstBuilder_SubA(up: up.subA(values)) })
		            }
		            func __safeDI_firstBuilder_SubA(up: SubA.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { scope in __safeDI_firstBuilder_SubA_first(scope, __safeDI_top_firstBuilder: up.first(scope)) })
		            }
		            func __safeDI_secondBuilder_Top(up: Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subBBuilder: { values in __safeDI_secondBuilder_SubB(up: up.subBBuilder(values)) })
		            }
		            func __safeDI_secondBuilder_SubB(up: SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { scope in __safeDI_secondBuilder_SubB_second(scope, __safeDI_top_secondBuilder: up.second(scope)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_ADD3FA557E32EC97 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture, samples: [DifferentialValueSample(type: "X", expression: "X()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesRecursiveMember_whenReusedFillEnclosesCallThatReentersIt() async throws {
		// `DefaultSecond`, which the fill of `second` builds, calls `SubB` again through an `Instantiator`: the call re-enters the
		// fill that encloses it, so `DefaultSecond`'s level returns `SubB`'s struct over itself.
		let fixture = Fixture(
			defaultFirstDeclarations: [],
			defaultSecondDeclarations: ["@Instantiated let gadget: any Gadget", "@Instantiated let subBBuilder: Instantiator<SubB>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_secondBuilder_Values {}

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadget_Values {
		                public let subBBuilder: Instantiator<SubB>
		            }

		            nonisolated public struct subBBuilder_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built
		                public let subBBuilder_secondBuilder: (subBBuilder_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built, subBBuilder_secondBuilder: @escaping (subBBuilder_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.gadget = gadget
		                    self.subBBuilder_secondBuilder = subBBuilder_secondBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                    self.subBBuilder_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_secondBuilder = top_secondBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.top_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_333CA8E405D3F446.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_secondBuilder_SubB_second(_ scope: SubB.SafeDIScope_Second.second_Values, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                func __safeDI_second() -> DefaultSecond {
		                    let __safeDI_gadgetBuilder_subBBuilder_secondBuilder = __safeDI_top_secondBuilder.subBBuilder_secondBuilder(SafeDIScope_Gadget.DefaultSecond_Scope.subBBuilder_secondBuilder_Values())
		                    func __safeDI_subBBuilder() -> SubB {
		                        _ = SubB.__safeDI_SubB_7CCD5CF6807E942D.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subBBuilder_secondBuilder))
		                    }
		                    let subBBuilder = Instantiator<SubB>(__safeDI_subBBuilder)
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values(subBBuilder: subBBuilder))
		                    return DefaultSecond(gadget: gadget, subBBuilder: subBBuilder)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            func __safeDI_firstBuilder_Top() -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { _ in __safeDI_firstBuilder_SubA() })
		            }
		            func __safeDI_firstBuilder_SubA() -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { _ in
		                    let first: any First = DefaultFirst()
		                    return first
		                })
		            }
		            func __safeDI_secondBuilder_Top(up: Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subB: { values in __safeDI_secondBuilder_SubB(up: up.subB(values)) })
		            }
		            func __safeDI_secondBuilder_SubB(up: SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { scope in __safeDI_secondBuilder_SubB_second(scope, __safeDI_top_secondBuilder: up.second(scope)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_C59EA60CF18DE7E7 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsMemberInsideSendableFunction_whenReenteringCallIsBuiltInSendableBuilderFunction() async throws {
		// The fill of `first` is plain, but it calls `SubB` in a `SendableInstantiator`: the member is the `@Sendable` family's,
		// bound at the top of that function, and carries no values.
		let fixture = Fixture(
			isSendable: true,
			defaultFirstDeclarations: ["@Instantiated let subBBuilder: SendableInstantiator<SubB>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_Gadget {
		        nonisolated public struct top_firstBuilder_Sendable_Values: Sendable {}

		        nonisolated public struct top_secondBuilder_Values: Sendable {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subBBuilder_secondBuilder_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		                public let subBBuilder_secondBuilder: @Sendable (subBBuilder_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subBBuilder_secondBuilder: @escaping @Sendable (subBBuilder_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subBBuilder_secondBuilder = subBBuilder_secondBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                    self.subBBuilder_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let top_firstBuilder_Sendable: @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>
		            public let top_secondBuilder: @Sendable (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder_Sendable: @escaping @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>, top_secondBuilder: @escaping @Sendable (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder_Sendable = top_firstBuilder_Sendable
		                self.top_secondBuilder = top_secondBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.top_firstBuilder_Sendable = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.top_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable = __safeDI_gadgetSendableBuilder.top_firstBuilder_Sendable(SafeDISendableScope_Gadget.top_firstBuilder_Sendable_Values())
		        func __safeDI_top() -> Top {
		            let __safeDI_gadgetSendableBuilder_top_secondBuilder = __safeDI_gadgetSendableBuilder.top_secondBuilder(SafeDISendableScope_Gadget.top_secondBuilder_Values())
		            _ = Top.__safeDI_Top_333CA8E405D3F446.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_SubA_first(_ scope: SubA.SafeDIScope_First.first_Values) -> any First {
		                func __safeDI_first() -> DefaultFirst {
		                    @Sendable nonisolated func __safeDI_subBBuilder() -> SubB {
		                        let __safeDI_gadgetSendableBuilder_subBBuilder_secondBuilder = __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable.subBBuilder_secondBuilder(SafeDISendableScope_Gadget.DefaultFirst_Scope.subBBuilder_secondBuilder_Values())
		                        _ = SubB.__safeDI_SubB_7CCD5CF6807E942D.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetSendableBuilder_subBBuilder_secondBuilder))
		                    }
		                    let subBBuilder = SendableInstantiator<SubB>(__safeDI_subBBuilder)
		                    return DefaultFirst(subBBuilder: subBBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @Sendable func __safeDI_secondBuilder_SubB_second(_ scope: SubB.SafeDIScope_Second.second_Values, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            func __safeDI_firstBuilder_Top() -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { _ in __safeDI_firstBuilder_SubA() })
		            }
		            func __safeDI_firstBuilder_SubA() -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { scope in __safeDI_firstBuilder_SubA_first(scope) })
		            }
		            func __safeDI_secondBuilder_Top(up: Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subB: { values in __safeDI_secondBuilder_SubB(up: up.subB(values)) })
		            }
		            @Sendable nonisolated func __safeDI_secondBuilder_SubB(up: SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { scope in __safeDI_secondBuilder_SubB_second(scope, __safeDI_top_secondBuilder: up.second(scope)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetSendableBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_E52360C5A7EDC7FC {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_nestsMemberUnderCallingTypesLevel_whenCallingTypeIsBeneathFilledType() async throws {
		// `DefaultFirst` builds `Mid`, which calls `SubB`, after binding `label`, which nothing reads.
		let fixture = Fixture(
			middleTypes: [seamFixtureType(named: "Mid", declarations: ["@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let label: Label", "@Instantiated let mid: Mid"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public struct top_secondBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct mid_Values {
		                public let label: Label
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let mid: (mid_Values) -> SafeDIScope_Gadget.Mid_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(mid: @escaping (mid_Values) -> SafeDIScope_Gadget.Mid_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.mid = mid
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.mid = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        nonisolated public enum Mid_Scope {
		            nonisolated public struct subB_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.subB_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.top_firstBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.top_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_333CA8E405D3F446.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_SubA_first(_ scope: SubA.SafeDIScope_First.first_Values, __safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                func __safeDI_first() -> DefaultFirst {
		                    let label = Label()
		                    let __safeDI_gadgetBuilder_mid = __safeDI_top_firstBuilder.mid(SafeDIScope_Gadget.DefaultFirst_Scope.mid_Values(label: label))
		                    func __safeDI_mid() -> Mid {
		                        let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_gadgetBuilder_mid.subB_secondBuilder(SafeDIScope_Gadget.Mid_Scope.subB_secondBuilder_Values())
		                        func __safeDI_subB() -> SubB {
		                            _ = SubB.__safeDI_SubB_7CCD5CF6807E942D.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                            return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subB_secondBuilder))
		                        }
		                        let subB: SubB = __safeDI_subB()
		                        return Mid(subB: subB)
		                    }
		                    let mid: Mid = __safeDI_mid()
		                    return DefaultFirst(label: label, mid: mid)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            func __safeDI_secondBuilder_SubB_second(_ scope: SubB.SafeDIScope_Second.second_Values, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            func __safeDI_firstBuilder_Top(up: Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { values in __safeDI_firstBuilder_SubA(up: up.subA(values)) })
		            }
		            func __safeDI_firstBuilder_SubA(up: SubA.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { scope in __safeDI_firstBuilder_SubA_first(scope, __safeDI_top_firstBuilder: up.first(scope)) })
		            }
		            func __safeDI_secondBuilder_Top(up: Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subB: { values in __safeDI_secondBuilder_SubB(up: up.subB(values)) })
		            }
		            func __safeDI_secondBuilder_SubB(up: SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { scope in __safeDI_secondBuilder_SubB_second(scope, __safeDI_top_secondBuilder: up.second(scope)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_96E2ABCF4139485B {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsValueOfLevelAboveFillToReusedLevelFunction_whenFulfillerReadsIt() async throws {
		// `Top` binds `label` before `subA` and `subB`, which receive it, and `DefaultGadget` receives it: the route through the
		// fill of `first` hands the reused level function what the levels above the fill carry.
		let fixture = Fixture(
			subADeclarations: ["@Received let label: Label", "@Instantiated let first: any First"],
			subBDeclarations: ["@Received let label: Label", "@Instantiated let second: any Second"],
			topDeclarations: ["@Instantiated let label: Label", "@Instantiated let subA: SubA", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received let label: Label"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public struct top_secondBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subB_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.subB_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                }
		            }
		        }

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.top_firstBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.top_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9DD764DA354467EE.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_SubA_first(_ scope: SubA.SafeDIScope_First.first_Values, __safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                let label = scope.label
		                func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_top_firstBuilder.subB_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
		                    func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_12FFA0134DD5AF99.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_label: label, __safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subB_secondBuilder))
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            func __safeDI_secondBuilder_SubB_second(_ scope: SubB.SafeDIScope_Second.second_Values, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            func __safeDI_firstBuilder_Top(up: Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { values in __safeDI_firstBuilder_SubA(up: up.subA(values)) })
		            }
		            func __safeDI_firstBuilder_SubA(up: SubA.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { scope in __safeDI_firstBuilder_SubA_first(scope, __safeDI_top_firstBuilder: up.first(scope)) })
		            }
		            func __safeDI_secondBuilder_Top(up: Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subB: { values in __safeDI_secondBuilder_SubB(up: up.subB(values)) })
		            }
		            func __safeDI_secondBuilder_SubB(up: SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { scope in __safeDI_secondBuilder_SubB_second(scope, __safeDI_top_secondBuilder: up.second(scope)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_37EDBDE082B78566 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_37EDBDE082B78566.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDIScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDIScope_Second() })
		            }
		            func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		                .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		            }
		            func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(label: Label) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { _ in
		                    let gadget: any Gadget = DefaultGadget(label: label)
		                    return gadget
		                })
		            }
		            func __safeDI_gadgetBuilder_Host_Top_SafeDIScope_First() -> Top.SafeDIScope_First.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subA: { _ in __safeDI_gadgetBuilder_Host_SubA() })
		            }
		            func __safeDI_gadgetBuilder_Host_SubA() -> SubA.SafeDIScope_First.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(first: { _ in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		            }
		            func __safeDI_gadgetBuilder_Host_Top_SafeDIScope_Second() -> Top.SafeDIScope_Second.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subB: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		            }
		            func __safeDI_gadgetBuilder_Host_SubB() -> SubB.SafeDIScope_Second.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(second: { values in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(label: values.label) })
		            }
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicMockInEnumForm_whenMockedTreeHoldsCallThatReentersFill() async throws {
		// `Panel`'s public mock builds `Top`, whose tree the seam's would take its struct from a member for: the mock keeps its
		// enum form, keyed by the deeper seam.
		let fixture = Fixture(
			middleTypes: [seamFixtureType(named: "Panel", declarations: ["@Instantiated let top: Top"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public struct top_secondBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subB_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.subB_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                }
		            }
		        }

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.top_firstBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.top_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_333CA8E405D3F446.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_SubA_first(_ scope: SubA.SafeDIScope_First.first_Values, __safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_top_firstBuilder.subB_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
		                    func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_7CCD5CF6807E942D.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subB_secondBuilder))
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            func __safeDI_secondBuilder_SubB_second(_ scope: SubB.SafeDIScope_Second.second_Values, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            func __safeDI_firstBuilder_Top(up: Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { values in __safeDI_firstBuilder_SubA(up: up.subA(values)) })
		            }
		            func __safeDI_firstBuilder_SubA(up: SubA.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { scope in __safeDI_firstBuilder_SubA_first(scope, __safeDI_top_firstBuilder: up.first(scope)) })
		            }
		            func __safeDI_secondBuilder_Top(up: Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subB: { values in __safeDI_secondBuilder_SubB(up: up.subB(values)) })
		            }
		            func __safeDI_secondBuilder_SubB(up: SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { scope in __safeDI_secondBuilder_SubB_second(scope, __safeDI_top_secondBuilder: up.second(scope)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_FB1A96447B9C287E {}
		}

		#if DEBUG
		extension Panel {
		    @frozen public enum SafeDIMockScope_Gadget {
		        case top(top_Values, SafeDIMockScope_Gadget.Top_Scope)

		        public struct top_Values {}

		        @frozen public enum Top_Scope {
		            case subA(subA_Values, SafeDIMockScope_Gadget.SubA_Scope)
		            case subB(subB_Values, SafeDIMockScope_Gadget.SubB_Scope)

		            public struct subA_Values {}

		            public struct subB_Values {
		                public let subA: SubA
		            }
		        }

		        @frozen public enum SubA_Scope {
		            case first(first_Values, SafeDIMockScope_Gadget.DefaultFirst_Scope)

		            public struct first_Values {}
		        }

		        @frozen public enum SubB_Scope {
		            case second(second_Values, SafeDIMockScope_Gadget.DefaultSecond_Scope)

		            public struct second_Values {}
		        }

		        @frozen public enum DefaultFirst_Scope {
		            case subB(subB_Values, SafeDIMockScope_Gadget.SubB_Scope)

		            public struct subB_Values {}
		        }

		        @frozen public enum DefaultSecond_Scope {
		            case gadget(gadget_Values)

		            public struct gadget_Values {}
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            top: __safeDI_Middle_Top_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                top: top
		            )
		        }

		        public var top: __safeDI_Middle_Top_MockConfiguration { __safeDI_storage.top }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                top: __safeDI_Middle_Top_MockConfiguration
		            ) {
		                self.top = top
		            }

		            let top: __safeDI_Middle_Top_MockConfiguration
		        }
		    }

		    public static func mock(
		        gadgetBuilder: @escaping (Panel.SafeDIMockScope_Gadget) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let __safeDI_gadgetValues_top = SafeDIMockScope_Gadget.top_Values()
		        func __safeDI_top() -> Top {
		            let __safeDI_gadgetValues_subA = SafeDIMockScope_Gadget.Top_Scope.subA_Values()
		            func __safeDI_subA() -> SubA {
		                let __safeDI_gadgetValues_first = SafeDIMockScope_Gadget.SubA_Scope.first_Values()
		                func __safeDI_first() -> First {
		                    let __safeDI_gadgetValues_subB = SafeDIMockScope_Gadget.DefaultFirst_Scope.subB_Values()
		                    func __safeDI_subB() -> SubB {
		                        let __safeDI_gadgetValues_second = SafeDIMockScope_Gadget.SubB_Scope.second_Values()
		                        func __safeDI_second() -> Second {
		                            let gadget: any Gadget = __safeDI_gadgetBuilder(.top(__safeDI_gadgetValues_top, .subA(__safeDI_gadgetValues_subA, .first(__safeDI_gadgetValues_first, .subB(__safeDI_gadgetValues_subB, .second(__safeDI_gadgetValues_second, .gadget(SafeDIMockScope_Gadget.DefaultSecond_Scope.gadget_Values())))))))
		                            return if let safeDIBuilder = safeDIOverrides.top.subA.first.subB.second { safeDIBuilder(gadget) } else { DefaultSecond(gadget: gadget) }
		                        }
		                        let second: Second = __safeDI_second()
		                        return SubB.__safeDI_init(second: second, safeDIBuilder: safeDIOverrides.top.subA.first.subB.safeDIBuilder)
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst.__safeDI_init(subB: subB, safeDIBuilder: safeDIOverrides.top.subA.first.safeDIBuilder)
		                }
		                let first: First = __safeDI_first()
		                return SubA.__safeDI_init(first: first, safeDIBuilder: safeDIOverrides.top.subA.safeDIBuilder)
		            }
		            let subA: SubA = __safeDI_subA()
		            let __safeDI_gadgetValues_subB = SafeDIMockScope_Gadget.Top_Scope.subB_Values(subA: subA)
		            func __safeDI_subB() -> SubB {
		                let __safeDI_gadgetValues_second = SafeDIMockScope_Gadget.SubB_Scope.second_Values()
		                func __safeDI_second() -> Second {
		                    let gadget: any Gadget = __safeDI_gadgetBuilder(.top(__safeDI_gadgetValues_top, .subB(__safeDI_gadgetValues_subB, .second(__safeDI_gadgetValues_second, .gadget(SafeDIMockScope_Gadget.DefaultSecond_Scope.gadget_Values())))))
		                    return if let safeDIBuilder = safeDIOverrides.top.subB.second { safeDIBuilder(gadget) } else { DefaultSecond(gadget: gadget) }
		                }
		                let second: Second = __safeDI_second()
		                return SubB.__safeDI_init(second: second, safeDIBuilder: safeDIOverrides.top.subB.safeDIBuilder)
		            }
		            let subB: SubB = __safeDI_subB()
		            return Top.__safeDI_init(subA: subA, subB: subB, safeDIBuilder: safeDIOverrides.top.safeDIBuilder)
		        }
		        let top: Top = __safeDI_top()
		        return Panel(top: top)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_3EB3A8EA3025FE42 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `SubB` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_SubB_MockConfiguration {
		    public init(
		        second: ((any Gadget) -> Second)? = nil,
		        _ safeDIBuilder: ((any Second) -> SubB)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            second: second,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var second: ((any Gadget) -> Second)? { __safeDI_storage.second }
		    /// Overrides how `SubB` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Second) -> SubB)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            second: ((any Gadget) -> Second)?,
		            safeDIBuilder: ((any Second) -> SubB)?
		        ) {
		            self.second = second
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let second: ((any Gadget) -> Second)?
		        let safeDIBuilder: ((any Second) -> SubB)?
		    }
		}

		extension SubB {
		    static func __safeDI_init(second: any Second, safeDIBuilder: ((any Second) -> SubB)?) -> SubB {
		        if let safeDIBuilder { safeDIBuilder(second) } else { SubB(second: second) }
		    }
		}

		/// Configuration for how `DefaultFirst` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_DefaultFirst_MockConfiguration {
		    public init(
		        subB: __safeDI_Middle_SubB_MockConfiguration = .init(),
		        _ safeDIBuilder: ((SubB) -> DefaultFirst)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            subB: subB,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var subB: __safeDI_Middle_SubB_MockConfiguration { __safeDI_storage.subB }
		    /// Overrides how `DefaultFirst` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((SubB) -> DefaultFirst)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            subB: __safeDI_Middle_SubB_MockConfiguration,
		            safeDIBuilder: ((SubB) -> DefaultFirst)?
		        ) {
		            self.subB = subB
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let subB: __safeDI_Middle_SubB_MockConfiguration
		        let safeDIBuilder: ((SubB) -> DefaultFirst)?
		    }
		}

		extension DefaultFirst {
		    static func __safeDI_init(subB: SubB, safeDIBuilder: ((SubB) -> DefaultFirst)?) -> DefaultFirst {
		        if let safeDIBuilder { safeDIBuilder(subB) } else { DefaultFirst(subB: subB) }
		    }
		}

		/// Configuration for how `SubA` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_SubA_MockConfiguration {
		    public init(
		        first: __safeDI_Middle_DefaultFirst_MockConfiguration = .init(),
		        _ safeDIBuilder: ((any First) -> SubA)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            first: first,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var first: __safeDI_Middle_DefaultFirst_MockConfiguration { __safeDI_storage.first }
		    /// Overrides how `SubA` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any First) -> SubA)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            first: __safeDI_Middle_DefaultFirst_MockConfiguration,
		            safeDIBuilder: ((any First) -> SubA)?
		        ) {
		            self.first = first
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let first: __safeDI_Middle_DefaultFirst_MockConfiguration
		        let safeDIBuilder: ((any First) -> SubA)?
		    }
		}

		extension SubA {
		    static func __safeDI_init(first: any First, safeDIBuilder: ((any First) -> SubA)?) -> SubA {
		        if let safeDIBuilder { safeDIBuilder(first) } else { SubA(first: first) }
		    }
		}

		/// Configuration for how `Top` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_Top_MockConfiguration {
		    public init(
		        subA: __safeDI_Middle_SubA_MockConfiguration = .init(),
		        subB: __safeDI_Middle_SubB_MockConfiguration = .init(),
		        _ safeDIBuilder: ((SubA, SubB) -> Top)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            subA: subA,
		            subB: subB,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var subA: __safeDI_Middle_SubA_MockConfiguration { __safeDI_storage.subA }
		    public var subB: __safeDI_Middle_SubB_MockConfiguration { __safeDI_storage.subB }
		    /// Overrides how `Top` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((SubA, SubB) -> Top)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            subA: __safeDI_Middle_SubA_MockConfiguration,
		            subB: __safeDI_Middle_SubB_MockConfiguration,
		            safeDIBuilder: ((SubA, SubB) -> Top)?
		        ) {
		            self.subA = subA
		            self.subB = subB
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let subA: __safeDI_Middle_SubA_MockConfiguration
		        let subB: __safeDI_Middle_SubB_MockConfiguration
		        let safeDIBuilder: ((SubA, SubB) -> Top)?
		    }
		}

		extension Top {
		    static func __safeDI_init(subA: SubA, subB: SubB, safeDIBuilder: ((SubA, SubB) -> Top)?) -> Top {
		        if let safeDIBuilder { safeDIBuilder(subA, subB) } else { Top(subA: subA, subB: subB) }
		    }
		}
		#endif

		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_addsNoMemberToOtherHoleType_whenReusedFillHoldsPlacesOfOneHoleType() async throws {
		// `DefaultFirst` holds `gear`, a place of another hole type, which the reused fill of `second` holds none of.
		let fixture = Fixture(
			middleTypes: ["public protocol Gear {}"],
			defaultFirstDeclarations: ["@Instantiated let gear: any Gear", "@Instantiated let subB: SubB"],
			appTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGear", fulfilling: "Gear", declarations: [])],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public struct top_secondBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subB_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.subB_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                }
		            }
		        }

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.top_firstBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.top_secondBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    nonisolated public enum SafeDIScope_Gear {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct gear_Values {
		                public let subB: SubB
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gear: (gear_Values) -> __safeDI_Built

		                public init(gear: @escaping (gear_Values) -> __safeDI_Built) {
		                    self.gear = gear
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gear = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.top_firstBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gearBuilder: SafeDIScope_Gear.__safeDI_Builder<any Gear>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        let __safeDI_gearBuilder_top_firstBuilder = __safeDI_gearBuilder.top_firstBuilder(SafeDIScope_Gear.top_firstBuilder_Values())
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_333CA8E405D3F446.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_SubA_first(_ scope: SubA.SafeDIScope_First.first_Values, __safeDI_top_firstBuilder_gadgetBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>, __safeDI_top_firstBuilder_gearBuilder: SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<any Gear>) -> any First {
		                func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_top_firstBuilder_gadgetBuilder.subB_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
		                    func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_7CCD5CF6807E942D.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subB_secondBuilder))
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    let gear: any Gear = __safeDI_top_firstBuilder_gearBuilder.gear(SafeDIScope_Gear.DefaultFirst_Scope.gear_Values(subB: subB))
		                    return DefaultFirst(gear: gear, subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            func __safeDI_secondBuilder_SubB_second(_ scope: SubB.SafeDIScope_Second.second_Values, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            func __safeDI_firstBuilder_Top(up_top_firstBuilder_gadgetBuilder: Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>, up_top_firstBuilder_gearBuilder: Top.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<any Gear>>) -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { values in __safeDI_firstBuilder_SubA(up_top_firstBuilder_gadgetBuilder: up_top_firstBuilder_gadgetBuilder.subA(values), up_top_firstBuilder_gearBuilder: up_top_firstBuilder_gearBuilder.subA(values)) })
		            }
		            func __safeDI_firstBuilder_SubA(up_top_firstBuilder_gadgetBuilder: SubA.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>, up_top_firstBuilder_gearBuilder: SubA.SafeDIScope_First.__safeDI_Builder<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<any Gear>>) -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { scope in __safeDI_firstBuilder_SubA_first(scope, __safeDI_top_firstBuilder_gadgetBuilder: up_top_firstBuilder_gadgetBuilder.first(scope), __safeDI_top_firstBuilder_gearBuilder: up_top_firstBuilder_gearBuilder.first(scope)) })
		            }
		            func __safeDI_secondBuilder_Top(up: Top.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subB: { values in __safeDI_secondBuilder_SubB(up: up.subB(values)) })
		            }
		            func __safeDI_secondBuilder_SubB(up: SubB.SafeDIScope_Second.__safeDI_Builder<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { scope in __safeDI_secondBuilder_SubB_second(scope, __safeDI_top_secondBuilder: up.second(scope)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up_top_firstBuilder_gadgetBuilder: __safeDI_gadgetBuilder_top_firstBuilder, up_top_firstBuilder_gearBuilder: __safeDI_gearBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0DC063A7C1E607B7 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReusedFillByNameWithNoMember_whenReusedFillLeadsToNoPlace() async throws {
		// `Host`'s own `gadget` is its only place: the fill of `second` builds `DefaultSecond`, which holds none, so the fill of
		// `first`, whose `SubB` re-enters it, leads to no place either, and its call takes no member of its own case.
		let fixture = Fixture(
			defaultSecondDeclarations: [],
			hostDeclarations: ["@Instantiated let top: Top", "@Instantiated let gadget: any Gadget"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct gadget_Values {
		            public let top: Top
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let gadget: (gadget_Values) -> __safeDI_Built

		            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                self.gadget = gadget
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.gadget = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_333CA8E405D3F446.self\(seamCallComment(seam: "Top", module: "Feature"))
		            func __safeDI_firstBuilder_SubA_first(_ scope: SubA.SafeDIScope_First.first_Values) -> any First {
		                func __safeDI_first() -> DefaultFirst {
		                    func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_7CCD5CF6807E942D.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB())
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            func __safeDI_firstBuilder_Top() -> Top.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(subA: { _ in __safeDI_firstBuilder_SubA() })
		            }
		            func __safeDI_firstBuilder_SubA() -> SubA.SafeDIScope_First.__safeDI_Builder<any First> {
		                .init(first: { scope in __safeDI_firstBuilder_SubA_first(scope) })
		            }
		            func __safeDI_secondBuilder_Top() -> Top.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(subB: { _ in __safeDI_secondBuilder_SubB() })
		            }
		            func __safeDI_secondBuilder_SubB() -> SubB.SafeDIScope_Second.__safeDI_Builder<any Second> {
		                .init(second: { _ in
		                    let second: any Second = DefaultSecond()
		                    return second
		                })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top())
		        }
		        let top: Top = __safeDI_top()
		        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(SafeDIScope_Gadget.gadget_Values(top: top))
		        self.init(top: top, gadget: gadget)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_167A4D1422DC7248 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: A place a caller fills inside the fill built again

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenCallerFillsPlaceInsideFillBuiltAgain() async {
		// `DefaultFirst` binds `x` before it calls `SubB` again, and `App` fills `gadget`, inside the fill of `second`, with
		// `DefaultGadget`, which receives `x` only if available: inline, the gadget reads `DefaultFirst`'s `x` on the route
		// through that call and `nil` on `Top`'s own, while the one fill `Middle` generates for `second` reads the outer call's.
		// `Host`'s module records what its visible build rejects, so `App` rejects it too.
		let fixture = Fixture(
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenTypeAboveSeamCallDeclaresLabelTooAndReaderRequiresIt() async {
		// `Host` binds `x` before it calls `Top`, so `gadget` carries `Host`'s `x` as a field, but on the route through
		// `DefaultFirst`'s call of `SubB` inline reads `DefaultFirst`'s: a field of the label does not lift the rejection.
		let fixture = Fixture(
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received let x: X` on `SubB`, with `x` declared on every route to `SubB`, so the builder’s scope carries it; receive it only if available on `SubB` and `DefaultGadget`, with `@Received(onlyIfAvailable: true) let x: X?`; or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenTypeAboveSeamCallDeclaresLabelTooAndReaderReceivesItOnlyIfAvailable() async {
		// As above, with the gadget receiving `x` only if available.
		let fixture = Fixture(
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenCallBuildsSeamAgainThroughInstantiator() async {
		// `DefaultFirst` builds `SubB` again through an `Instantiator`, after binding `x`.
		let fixture = Fixture(
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subBBuilder: Instantiator<SubB>"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subBBuilder`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenFillBuiltAgainBuildsItsSeamAgain() async {
		// The fill of `second` builds `Holder`, which binds `x` and holds `SubB` in an `Instantiator`: the fill is passed to a
		// call inside its own tree, and `gadget`, beside `holder`, reads `Holder`'s `x` inline only on that call's route.
		let fixture = Fixture(
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Instantiated let x: X", "@Instantiated let subBBuilder: Instantiator<SubB>"])],
			defaultSecondDeclarations: ["@Instantiated let holder: Holder", "@Instantiated let gadget: any Gadget"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `Holder` declares on the path from the builder for `SubB`’s `second: any Second` (case `second` of `secondBuilder`) to the call by which `Holder` instantiates `SubB` again (`subBBuilder`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `Holder`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["Holder.swift"]):10:5: note: `Holder` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenCallBuildsSeamAgainInSendableFunction() async {
		// `DefaultFirst` builds `SubB` again in a `SendableInstantiator`'s `@Sendable` function, after binding `x`.
		let fixture = Fixture(
			isSendable: true,
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subBBuilder: SendableInstantiator<SubB>"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subBBuilder`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenSeamCalledInsideFillBuiltAgainPassesPlaceUp() async {
		// The fill of `second` calls `Inner`, whose place `gizmo` `Host` passes up, inside that fill, and `App` fills.
		let fixture = Fixture(
			featureTypes: ["public protocol Gizmo {}", seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let gizmo: any Gizmo"])],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			defaultSecondDeclarations: ["@Instantiated let inner: Inner"],
			appTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGizmo", fulfilling: "Gizmo", declarations: ["@Received(onlyIfAvailable: true) let x: X?"])],
		)
		await expectBothBuildsThrow(fixture, readerFile: "DefaultGizmo.swift", readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGizmo` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenModuleAboveSeamThatPassesPlaceUpFillsIt() async {
		// `App`'s `Shell` calls `Host` and passes `gadget` up; `Outer` fills it. The copy `Shell` takes keeps what `Host` recorded.
		let fixture = Fixture(
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: fixture.feature),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: fixture.middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let host: Host"])].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			ModuleFixture(
				name: "Outer",
				packageName: "Outer",
				swiftFileContent: (fixture.app + [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])]).map { "import Feature\nimport Middle\nimport App\n\n" + $0 },
				dependencies: ["Feature", "Middle", "App"],
			),
		]
		await assertThrowsMultiModuleError(inModule: "Outer", diagnostics: { fixtures in
			"""
			\(fixtures["Outer"]!["DefaultGadget.swift"]):11:5: error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRouteNamingEveryPath_whenTwoPathsDeclareLabel() async {
		// `DefaultFirst` binds `x` before its call of `SubB`, and `Holder`, inside the fill of `second`, before its own: one
		// error names both, in both builds.
		let fixture = Fixture(
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Instantiated let x: X", "@Instantiated let subBBuilder: Instantiator<SubB>"])],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			defaultSecondDeclarations: ["@Instantiated let holder: Holder", "@Instantiated let gadget: any Gadget"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`) and `Holder` declares on the path from the builder for `SubB`’s `second: any Second` (case `second` of `secondBuilder`) to the call by which `Holder` instantiates `SubB` again (`subBBuilder`), but those calls pass the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s and `Holder`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			\(fixtures["Middle"]!["Holder.swift"]):10:5: note: `Holder` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRouteNamingEveryCall_whenOneDeclarationHidesLabelFromTwoCalls() async {
		// `DefaultFirst` binds `x` before two calls of `SubB`, one through an `Instantiator`: one declaration on two paths,
		// which `Host` records once per call and the error names once, with each call.
		let fixture = Fixture(
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB", "@Instantiated let subBBuilder: Instantiator<SubB>"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`) and `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (case `first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subBBuilder`), but those calls pass the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):11:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueBoundByPassingUpSeam_whenCallInsideFillPassesFillToSeamThatPassesPlaceUp() async {
		// `DefaultFirst` calls `Relay`, which binds `x` before it calls `SubB` and passes `second` up: the call hands the fill
		// of `second` `Relay`'s copy of the hole, which does not carry `x`. `Host`'s place `gadget`, inside that fill, joins
		// the copy's declaration to its own, so `App`'s fill is rejected as the visible build's is.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `Relay` builds where it calls `SubB`, but `Relay` passes the builder for `SubB`’s `second: any Second` (case `second` of `secondBuilder`) on from its own caller, which cannot hand it `Relay`’s values. Declare `@Received let x: X?` on `SubB`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies, so `Relay` fills the builder itself.
			\(fixtures["Feature"]!["Relay.swift"]):8:5: note: `Relay` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelOnlyIfAvailable() async throws {
		// The first remedy for a reader only if available: `SubB` receives `x` only if available, so the scope of `second`
		// carries the value of each route, `nil` on `Top`'s own. `X` is a class, so the comparison tells the routes' values apart.
		let fixture = Fixture(
			xIsFinalClass: true,
			subBDeclarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelTypeAboveSeamCallDeclares() async throws {
		// The first remedy for a required reader where `Host` binds `x` above its call of `Top`: `SubB` receives `x`, `Host`'s
		// on `Top`'s own route and `DefaultFirst`'s on the route through its call.
		let fixture = Fixture(
			xIsFinalClass: true,
			subBDeclarations: ["@Received let x: X", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelCallerOfSeamDeclares() async throws {
		// The first remedy for a required reader where `Root`, above `Host`, declares `x` on `Top`'s own route: `SubB` receives
		// `x`, which `Top` and `Host` take from their callers on that route, and `DefaultFirst`'s on the route through its call.
		let fixture = Fixture(
			xIsFinalClass: true,
			subBDeclarations: ["@Received let x: X", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received let x: X"],
			rootDeclarations: ["@Instantiated let x: X", "@Instantiated let host: Host"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamsModuleDeclaresTypeThatFulfillsPlaceBuiltAgain() async throws {
		// The last remedy: `Feature` declares `DefaultSecond`, with the gadget it builds, so `SubB` builds `second` inline and no
		// module fills a place inside it. `Host` declares `x` above `Top`, which `SubB`'s tree then takes on `Top`'s own route.
		let fixture = Fixture(
			xIsFinalClass: true,
			featureTypes: [
				"public protocol Gadget {}",
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: ["@Instantiated let gadget: any Gadget"]),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let x: X"]),
			],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
		)
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: fixture.feature),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: fixture.middle.filter { !$0.contains("protocol Gadget") && !$0.contains("struct DefaultSecond") }.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [fixture.root].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let oneModule = SafeDIToolSeamBuilderParameterTests.modules(feature: fixture.feature + fixture.middle.filter { !$0.contains("protocol Gadget") && !$0.contains("struct DefaultSecond") }, app: [fixture.root])
		let oneModuleOutput = try await executeSafeDIToolMultiModuleTest(modules: oneModule, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let comparison = try await DifferentialValueOracle.compare(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: oneModuleOutput, modules: oneModule),
			probes: [DifferentialValueProbe("Root()")],
			samples: [],
			filesToDelete: &filesToDelete,
		)
		#expect(comparison?.differences.isEmpty != false, "\(comparison?.report ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainDeclaresLabel() async throws {
		// `SubB` binds an `x` of its own before `second`: inline reads it on every route, and the scope carries it.
		let fixture = Fixture(
			xIsFinalClass: true,
			subBDeclarations: ["@Instantiated let x: X", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenFillBuiltAgainDeclaresLabelAbovePlace() async throws {
		// `DefaultSecond` binds an `x` of its own before `gadget`: inline reads it on every route, and the place carries it.
		let fixture = Fixture(
			xIsFinalClass: true,
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			defaultSecondDeclarations: ["@Instantiated let x: X", "@Instantiated let gadget: any Gadget"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Level functions of root enums under one builder

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesLevelFunctionsByTheirEnums_whenTwoRootEnumsAreLevelsOfOneBuilder() async throws {
		// `Host`'s fill of `gadget` leads through both of `Top`'s root enums, `SafeDIScope_First` and `SafeDIScope_Second`, each a
		// level of `gadgetBuilder` whose function would be named `__safeDI_gadgetBuilder_Host_Top`: each takes its enum's name, so
		// swapping the names `First` and `Second`, which swaps the order of `Top`'s builder labels, names each level's function
		// as before once the swap is undone. The second output, the swap undone, differs from the first only in `Host`'s guard
		// hash, which hashes the labels, and in the order of what is sorted by label: the call's arguments and the functions.
		let fixture = Fixture()
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let swappedModules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: fixture.feature.map(Self.swappingFirstAndSecond)),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: fixture.middle.map { "import Feature\n\n" + Self.swappingFirstAndSecond($0) }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (fixture.app + [fixture.root]).map { "import Feature\nimport Middle\n\n" + Self.swappingFirstAndSecond($0) }, dependencies: ["Feature", "Middle"]),
		]
		let swappedOutput = try await executeSafeDIToolMultiModuleTest(modules: swappedModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_FB1A96447B9C287E.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDIScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDIScope_Second() })
		            }
		            func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		                .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		            }
		            func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { _ in
		                    let gadget: any Gadget = DefaultGadget()
		                    return gadget
		                })
		            }
		            func __safeDI_gadgetBuilder_Host_Top_SafeDIScope_First() -> Top.SafeDIScope_First.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subA: { _ in __safeDI_gadgetBuilder_Host_SubA() })
		            }
		            func __safeDI_gadgetBuilder_Host_SubA() -> SubA.SafeDIScope_First.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(first: { _ in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		            }
		            func __safeDI_gadgetBuilder_Host_Top_SafeDIScope_Second() -> Top.SafeDIScope_Second.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subB: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		            }
		            func __safeDI_gadgetBuilder_Host_SubB() -> SubB.SafeDIScope_Second.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(second: { _ in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		            }
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		expectGeneratedFiles(swappedOutput.modules["App"]?.generatedFiles.mapValues(Self.swappingFirstAndSecond), ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_FB771D7B163E0742.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDIScope_Second() }, top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDIScope_First() })
		            }
		            func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { _ in
		                    let gadget: any Gadget = DefaultGadget()
		                    return gadget
		                })
		            }
		            func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		                .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		            }
		            func __safeDI_gadgetBuilder_Host_Top_SafeDIScope_Second() -> Top.SafeDIScope_Second.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subB: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		            }
		            func __safeDI_gadgetBuilder_Host_SubB() -> SubB.SafeDIScope_Second.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(second: { _ in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		            }
		            func __safeDI_gadgetBuilder_Host_Top_SafeDIScope_First() -> Top.SafeDIScope_First.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subA: { _ in __safeDI_gadgetBuilder_Host_SubA() })
		            }
		            func __safeDI_gadgetBuilder_Host_SubA() -> SubA.SafeDIScope_First.__safeDI_Builder<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(first: { _ in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		            }
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The types of a fixture, in the modules that declare them: `Feature` (package `Shop`); `Middle` (package `Mid`), which
	/// depends on it; and `App` (package `Other`), which depends on both. Each type of the graph conforms to `Sendable` when
	/// `isSendable`. `X` is a final class when `xIsFinalClass`, so the value comparison tells two instances apart.
	private struct Fixture {
		init(
			isSendable: Bool = false,
			xIsFinalClass: Bool = false,
			featureTypes: [String] = [],
			subADeclarations: [String] = ["@Instantiated let first: any First"],
			subBDeclarations: [String] = ["@Instantiated let second: any Second"],
			topDeclarations: [String] = ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"],
			middleTypes: [String] = [],
			defaultFirstDeclarations: [String] = ["@Instantiated let subB: SubB"],
			defaultSecondDeclarations: [String] = ["@Instantiated let gadget: any Gadget"],
			hostDeclarations: [String] = ["@Instantiated let top: Top"],
			gadgetDeclarations: [String] = [],
			appTypes: [String] = [],
			rootDeclarations: [String] = ["@Instantiated let host: Host"],
		) {
			let protocolConformance = isSendable ? ": Sendable" : ""
			let conformance = isSendable ? ", Sendable" : ""
			feature = [
				"public protocol First\(protocolConformance) {}",
				"public protocol Second\(protocolConformance) {}",
				seamFixtureType(named: "X", isFinalClass: xIsFinalClass, declarations: [], conformances: conformance),
				seamFixtureType(named: "Label", declarations: [], conformances: conformance),
				seamFixtureType(named: "SubA", isSeam: true, declarations: subADeclarations, conformances: conformance),
				seamFixtureType(named: "SubB", isSeam: true, declarations: subBDeclarations, conformances: conformance),
				seamFixtureType(named: "Top", isSeam: true, declarations: topDeclarations, conformances: conformance),
			] + featureTypes
			middle = ["public protocol Gadget\(protocolConformance) {}"] + middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: defaultFirstDeclarations),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: defaultSecondDeclarations),
				seamFixtureType(named: "Host", isSeam: true, declarations: hostDeclarations),
			]
			app = [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: gadgetDeclarations)] + appTypes
			root = seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations)
		}

		let feature: [String]
		let middle: [String]
		let app: [String]
		let root: String

		var modules: [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (app + [root]).map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			]
		}

		/// The same graph with every declaration but the root in one module, so no seam has a hole.
		var visibleModules: [ModuleFixture] {
			SafeDIToolSeamBuilderParameterTests.modules(feature: feature + middle + app, app: [root])
		}

		/// The same graph with `App`'s types in `Middle`, so `Host`'s module fills every place its call of `Top` leads to.
		var hostFillsEveryPlaceModules: [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: (middle + app).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [root].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			]
		}
	}

	/// `text` with `First` and `Second`, and `first` and `second`, in each other's places.
	private static func swappingFirstAndSecond(_ text: String) -> String {
		text
			.replacingOccurrences(of: "First", with: "\u{0}F")
			.replacingOccurrences(of: "first", with: "\u{0}f")
			.replacingOccurrences(of: "Second", with: "First")
			.replacingOccurrences(of: "second", with: "first")
			.replacingOccurrences(of: "\u{0}F", with: "Second")
			.replacingOccurrences(of: "\u{0}f", with: "second")
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}

	/// Expects the run of `fixture` to throw what `diagnostics` gives in `App`, which fills a place inside a fill `Host`'s
	/// module generates, and the same in the visible build, where `Middle`, `Host`'s module, fills every place: the error is
	/// at the reader, in `readerFile`, at `readerLineInMiddle` in `Middle` and a line further down in `App`, whose files
	/// import one more module.
	private mutating func expectBothBuildsThrow(
		_ fixture: Fixture,
		readerFile: String = "DefaultGadget.swift",
		readerLineInMiddle: Int,
		diagnostics: (_ readerLocation: String, _ fixtures: [String: FixturePaths]) -> String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			diagnostics("\(fixtures["App"]![readerFile]):\(readerLineInMiddle + 1):5", fixtures)
		}, sourceLocation: sourceLocation) {
			try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			diagnostics("\(fixtures["Middle"]![readerFile]):\(readerLineInMiddle):5", fixtures)
		}, sourceLocation: sourceLocation) {
			try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	/// Expects the values `output`, the run of `fixture`, builds for `Root` to equal those of the same graph in one module,
	/// calling each instantiator that forwards a value of a type of `samples` with that sample.
	private mutating func expectValuesEqualVisibleBuild(_ output: MultiModuleTestOutput, _ fixture: Fixture, samples: [DifferentialValueSample] = [], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: fixture.visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		guard let comparison = try await DifferentialValueOracle.compare(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: fixture.modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: fixture.visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			samples: samples,
			filesToDelete: &filesToDelete,
		) else { return }
		for difference in comparison.differences {
			Issue.record("The seam builds other values than the visible build for \(difference)\n\(comparison.report)", sourceLocation: sourceLocation)
		}
	}
}
