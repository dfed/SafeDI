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
		                public let subBBuilder_secondBuilder: (subBBuilder_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subBBuilder_secondBuilder: @escaping (subBBuilder_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subBBuilder_secondBuilder = subBBuilder_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_B6A79FB2B35A6BBA.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let x = X()
		                    let __safeDI_gadgetBuilder_subBBuilder_secondBuilder = __safeDI_top_firstBuilder.subBBuilder_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subBBuilder_secondBuilder_Values(x: x))
		                    @inline(never) func __safeDI_subBBuilder(x: X) -> SubB {
		                        _ = SubB.__safeDI_SubB_3416F5143420EA5F.self\(seamCallComment(seam: "SubB", module: "Feature"))
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
		            @inline(never) func __safeDI_secondBuilder_SubB_second(_ scope_x: X, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subBBuilder: __safeDI_secondBuilder_SubB(up: up.subBBuilder))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { scope_x in __safeDI_secondBuilder_SubB_second(scope_x, __safeDI_top_secondBuilder: up.second(scope_x)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_7B76A267FBC99F5F {}
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
		                public let subBBuilder_secondBuilder: (subBBuilder_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built, subBBuilder_secondBuilder: @escaping (subBBuilder_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.gadget = gadget
		                    self.subBBuilder_secondBuilder = subBBuilder_secondBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        @inline(never) func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
		            .init(subA: __safeDI_firstBuilder_SubA())
		        }
		        @inline(never) func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
		            .init(first: {
		                let first: any First = DefaultFirst()
		                return first
		            })
		        }
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let __safeDI_gadgetBuilder_subBBuilder_secondBuilder = __safeDI_top_secondBuilder.subBBuilder_secondBuilder(SafeDIScope_Gadget.DefaultSecond_Scope.subBBuilder_secondBuilder_Values())
		                    @inline(never) func __safeDI_subBBuilder() -> SubB {
		                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subBBuilder_secondBuilder))
		                    }
		                    let subBBuilder = Instantiator<SubB>(__safeDI_subBBuilder)
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values(subBBuilder: subBBuilder))
		                    return DefaultSecond(gadget: gadget, subBBuilder: subBBuilder)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3B0EA154FB759809 {}
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
		                public let subBBuilder_secondBuilder: @Sendable (subBBuilder_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subBBuilder_secondBuilder: @escaping @Sendable (subBBuilder_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subBBuilder_secondBuilder = subBBuilder_secondBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let top_firstBuilder_Sendable: @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>
		            public let top_secondBuilder: @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder_Sendable: @escaping @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>, top_secondBuilder: @escaping @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder_Sendable = top_firstBuilder_Sendable
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable = __safeDI_gadgetSendableBuilder.top_firstBuilder_Sendable(SafeDISendableScope_Gadget.top_firstBuilder_Sendable_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            let __safeDI_gadgetSendableBuilder_top_secondBuilder = __safeDI_gadgetSendableBuilder.top_secondBuilder(SafeDISendableScope_Gadget.top_secondBuilder_Values())
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first() -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    @inline(never) @Sendable nonisolated func __safeDI_subBBuilder() -> SubB {
		                        let __safeDI_gadgetSendableBuilder_subBBuilder_secondBuilder = __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable.subBBuilder_secondBuilder(SafeDISendableScope_Gadget.DefaultFirst_Scope.subBBuilder_secondBuilder_Values())
		                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetSendableBuilder_subBBuilder_secondBuilder))
		                    }
		                    let subBBuilder = SendableInstantiator<SubB>(__safeDI_subBBuilder)
		                    return DefaultFirst(subBBuilder: subBBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA())
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first() })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetSendableBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_9364B9B95B46342E {}
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
		            }
		        }

		        nonisolated public enum Mid_Scope {
		            nonisolated public struct subB_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let label = Label()
		                    let __safeDI_gadgetBuilder_mid = __safeDI_top_firstBuilder.mid(SafeDIScope_Gadget.DefaultFirst_Scope.mid_Values(label: label))
		                    @inline(never) func __safeDI_mid() -> Mid {
		                        let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_gadgetBuilder_mid.subB_secondBuilder(SafeDIScope_Gadget.Mid_Scope.subB_secondBuilder_Values())
		                        @inline(never) func __safeDI_subB() -> SubB {
		                            _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
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
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_7A86F127FA5F2FAB {}
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
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_EB6A236832228D10.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(_ scope_label: Label, __safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                let label = scope_label
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_top_firstBuilder.subB_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
		                    @inline(never) func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_11E4062CD4CF852B.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_label: label, __safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subB_secondBuilder))
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(_ scope_label: Label, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { scope_label in __safeDI_firstBuilder_SubA_first(scope_label, __safeDI_top_firstBuilder: up.first(scope_label)) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { scope_label in __safeDI_secondBuilder_SubB_second(scope_label, __safeDI_top_secondBuilder: up.second(scope_label)) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_46673885A0CD7C40 {}
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
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
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { values_label in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_label in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(label: values_label) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_46673885A0CD7C40.self\(seamCallComment(seam: "Host", module: "Middle"))
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
	mutating func generate_takesBuilderStructInPublicMock_whenMockedTreeHoldsCallThatReentersFill() async throws {
		// `Panel`'s public mock builds `Top`, whose tree holds a call that reenters the seam's fill: the mock takes its
		// builder struct, as the seam does, and its enums declare no case.
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
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_top_firstBuilder.subB_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
		                    @inline(never) func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subB_secondBuilder))
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3B6957495A4D519E {}
		}

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct top_Values {}

		        nonisolated public enum Top_Scope {
		            nonisolated public struct subA_Values {}

		            nonisolated public struct subB_Values {
		                public let subA: SubA
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subA: (subA_Values) -> SafeDIMockScope_Gadget.SubA_Scope.__safeDI_Builder<__safeDI_Built>
		                public let subB: (subB_Values) -> SafeDIMockScope_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(subA: @escaping (subA_Values) -> SafeDIMockScope_Gadget.SubA_Scope.__safeDI_Builder<__safeDI_Built>, subB: @escaping (subB_Values) -> SafeDIMockScope_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.subA = subA
		                    self.subB = subB
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(subA: { _ in .init(__safeDI_noScope: __safeDI_builder) }, subB: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum SubA_Scope {
		            nonisolated public struct first_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let first: (first_Values) -> SafeDIMockScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(first: @escaping (first_Values) -> SafeDIMockScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.first = first
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(first: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum SubB_Scope {
		            nonisolated public struct second_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let second: (second_Values) -> SafeDIMockScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(second: @escaping (second_Values) -> SafeDIMockScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.second = second
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(second: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subB_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB: (subB_Values) -> SafeDIMockScope_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(subB: @escaping (subB_Values) -> SafeDIMockScope_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.subB = subB
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(subB: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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
		                    self.init(gadget: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top: (top_Values) -> SafeDIMockScope_Gadget.Top_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(top: @escaping (top_Values) -> SafeDIMockScope_Gadget.Top_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.top = top
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(top: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
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
		        gadgetBuilder: @escaping () -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gadgetBuilder __safeDI_gadgetBuilder: Panel.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let __safeDI_gadgetBuilder_top = __safeDI_gadgetBuilder.top(SafeDIMockScope_Gadget.top_Values())
		        func __safeDI_top() -> Top {
		            let __safeDI_gadgetBuilder_subA = __safeDI_gadgetBuilder_top.subA(SafeDIMockScope_Gadget.Top_Scope.subA_Values())
		            func __safeDI_subA() -> SubA {
		                let __safeDI_gadgetBuilder_first = __safeDI_gadgetBuilder_subA.first(SafeDIMockScope_Gadget.SubA_Scope.first_Values())
		                func __safeDI_first() -> any First {
		                    let __safeDI_gadgetBuilder_subB = __safeDI_gadgetBuilder_first.subB(SafeDIMockScope_Gadget.DefaultFirst_Scope.subB_Values())
		                    func __safeDI_subB() -> SubB {
		                        let __safeDI_gadgetBuilder_second = __safeDI_gadgetBuilder_subB.second(SafeDIMockScope_Gadget.SubB_Scope.second_Values())
		                        func __safeDI_second() -> any Second {
		                            let gadget: any Gadget = __safeDI_gadgetBuilder_second.gadget(SafeDIMockScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                            return if let safeDIBuilder = safeDIOverrides.top.subA.first.subB.second { safeDIBuilder(gadget) } else { DefaultSecond(gadget: gadget) }
		                        }
		                        let second: any Second = __safeDI_second()
		                        return SubB.__safeDI_init(second: second, safeDIBuilder: safeDIOverrides.top.subA.first.subB.safeDIBuilder)
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst.__safeDI_init(subB: subB, safeDIBuilder: safeDIOverrides.top.subA.first.safeDIBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return SubA.__safeDI_init(first: first, safeDIBuilder: safeDIOverrides.top.subA.safeDIBuilder)
		            }
		            let subA: SubA = __safeDI_subA()
		            let __safeDI_gadgetBuilder_subB = __safeDI_gadgetBuilder_top.subB(SafeDIMockScope_Gadget.Top_Scope.subB_Values(subA: subA))
		            func __safeDI_subB() -> SubB {
		                let __safeDI_gadgetBuilder_second = __safeDI_gadgetBuilder_subB.second(SafeDIMockScope_Gadget.SubB_Scope.second_Values())
		                func __safeDI_second() -> any Second {
		                    let gadget: any Gadget = __safeDI_gadgetBuilder_second.gadget(SafeDIMockScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return if let safeDIBuilder = safeDIOverrides.top.subB.second { safeDIBuilder(gadget) } else { DefaultSecond(gadget: gadget) }
		                }
		                let second: any Second = __safeDI_second()
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
		    public enum __safeDI_Panel_mock_4AAC07AB84B3DEFA {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `SubB` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_SubB_MockConfiguration {
		    public init(
		        second: ((any Gadget) -> any Second)? = nil,
		        _ safeDIBuilder: ((any Second) -> SubB)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            second: second,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var second: ((any Gadget) -> any Second)? { __safeDI_storage.second }
		    /// Overrides how `SubB` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Second) -> SubB)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            second: ((any Gadget) -> any Second)?,
		            safeDIBuilder: ((any Second) -> SubB)?
		        ) {
		            self.second = second
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let second: ((any Gadget) -> any Second)?
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
	mutating func generate_takesBuilderStructInPublicMock_whenMockedTreeHoldsCallThatReentersFillAndPlaceForwardsValue() async throws {
		// `Panel`'s public mock builds `Top`, whose tree holds a call that reenters the seam's fill, and `DefaultSecond` holds
		// `Gadget`'s place in an instantiator that forwards an `Int`: the mock takes its builder struct for that place, as the
		// seam does, its enums declare no case, and its plain `mock` takes the instantiator's builder.
		let fixture = Fixture(
			middleTypes: [seamFixtureType(named: "Panel", declarations: ["@Instantiated let top: Top"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")],
			defaultSecondDeclarations: [#"@Instantiated(fulfilledByType: "DefaultGadget") let gadgetBuilder: ErasedInstantiator<Int, any Gadget>"#],
			gadgetDeclarations: ["@Forwarded let id: Int"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_DefaultGadget_Gadget {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public struct top_secondBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subB_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
		                }
		            }
		        }

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadgetBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadgetBuilder: (gadgetBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		                public init(gadgetBuilder: @escaping (gadgetBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.gadgetBuilder = gadgetBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_defaultGadget_GadgetBuilder: SafeDIScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_defaultGadget_GadgetBuilder_top_firstBuilder = __safeDI_defaultGadget_GadgetBuilder.top_firstBuilder(SafeDIScope_DefaultGadget_Gadget.top_firstBuilder_Values())
		        let __safeDI_defaultGadget_GadgetBuilder_top_secondBuilder = __safeDI_defaultGadget_GadgetBuilder.top_secondBuilder(SafeDIScope_DefaultGadget_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_defaultGadget_GadgetBuilder_subB_secondBuilder = __safeDI_top_firstBuilder.subB_secondBuilder(SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
		                    @inline(never) func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_defaultGadget_GadgetBuilder_subB_secondBuilder))
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadgetBuilder = ErasedInstantiator<Int, any Gadget>(__safeDI_top_secondBuilder.gadgetBuilder(SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.gadgetBuilder_Values()))
		                    return DefaultSecond(gadgetBuilder: gadgetBuilder)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_defaultGadget_GadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_defaultGadget_GadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_D133371C667165CD {}
		}

		#if DEBUG
		extension Panel {
		    nonisolated public enum SafeDIMockScope_DefaultGadget_Gadget {
		        nonisolated public struct top_Values {}

		        nonisolated public enum Top_Scope {
		            nonisolated public struct subA_Values {}

		            nonisolated public struct subB_Values {
		                public let subA: SubA
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subA: (subA_Values) -> SafeDIMockScope_DefaultGadget_Gadget.SubA_Scope.__safeDI_Builder<__safeDI_Built>
		                public let subB: (subB_Values) -> SafeDIMockScope_DefaultGadget_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(subA: @escaping (subA_Values) -> SafeDIMockScope_DefaultGadget_Gadget.SubA_Scope.__safeDI_Builder<__safeDI_Built>, subB: @escaping (subB_Values) -> SafeDIMockScope_DefaultGadget_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.subA = subA
		                    self.subB = subB
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.init(subA: { _ in .init(__safeDI_noScope: __safeDI_builder) }, subB: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum SubA_Scope {
		            nonisolated public struct first_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let first: (first_Values) -> SafeDIMockScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(first: @escaping (first_Values) -> SafeDIMockScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.first = first
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.init(first: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum SubB_Scope {
		            nonisolated public struct second_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let second: (second_Values) -> SafeDIMockScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(second: @escaping (second_Values) -> SafeDIMockScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.second = second
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.init(second: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct subB_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let subB: (subB_Values) -> SafeDIMockScope_DefaultGadget_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(subB: @escaping (subB_Values) -> SafeDIMockScope_DefaultGadget_Gadget.SubB_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.subB = subB
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.init(subB: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum DefaultSecond_Scope {
		            nonisolated public struct gadgetBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadgetBuilder: (gadgetBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		                public init(gadgetBuilder: @escaping (gadgetBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.gadgetBuilder = gadgetBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.init(gadgetBuilder: { _ in __safeDI_builder })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top: (top_Values) -> SafeDIMockScope_DefaultGadget_Gadget.Top_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(top: @escaping (top_Values) -> SafeDIMockScope_DefaultGadget_Gadget.Top_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.top = top
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(top: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
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
		        defaultGadget_GadgetBuilder: @escaping ErasedInstantiator<Int, any Gadget>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.__safeDI_mock(defaultGadget_GadgetBuilder: .init(__safeDI_noScope: defaultGadget_GadgetBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        defaultGadget_GadgetBuilder __safeDI_defaultGadget_GadgetBuilder: Panel.SafeDIMockScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let __safeDI_defaultGadget_GadgetBuilder_top = __safeDI_defaultGadget_GadgetBuilder.top(SafeDIMockScope_DefaultGadget_Gadget.top_Values())
		        func __safeDI_top() -> Top {
		            let __safeDI_defaultGadget_GadgetBuilder_subA = __safeDI_defaultGadget_GadgetBuilder_top.subA(SafeDIMockScope_DefaultGadget_Gadget.Top_Scope.subA_Values())
		            func __safeDI_subA() -> SubA {
		                let __safeDI_defaultGadget_GadgetBuilder_first = __safeDI_defaultGadget_GadgetBuilder_subA.first(SafeDIMockScope_DefaultGadget_Gadget.SubA_Scope.first_Values())
		                func __safeDI_first() -> any First {
		                    let __safeDI_defaultGadget_GadgetBuilder_subB = __safeDI_defaultGadget_GadgetBuilder_first.subB(SafeDIMockScope_DefaultGadget_Gadget.DefaultFirst_Scope.subB_Values())
		                    func __safeDI_subB() -> SubB {
		                        let __safeDI_defaultGadget_GadgetBuilder_second = __safeDI_defaultGadget_GadgetBuilder_subB.second(SafeDIMockScope_DefaultGadget_Gadget.SubB_Scope.second_Values())
		                        func __safeDI_second() -> any Second {
		                            let gadgetBuilder = ErasedInstantiator<Int, any Gadget>(__safeDI_defaultGadget_GadgetBuilder_second.gadgetBuilder(SafeDIMockScope_DefaultGadget_Gadget.DefaultSecond_Scope.gadgetBuilder_Values()))
		                            return if let safeDIBuilder = safeDIOverrides.top.subA.first.subB.second { safeDIBuilder(gadgetBuilder) } else { DefaultSecond(gadgetBuilder: gadgetBuilder) }
		                        }
		                        let second: any Second = __safeDI_second()
		                        return SubB.__safeDI_init(second: second, safeDIBuilder: safeDIOverrides.top.subA.first.subB.safeDIBuilder)
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst.__safeDI_init(subB: subB, safeDIBuilder: safeDIOverrides.top.subA.first.safeDIBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return SubA.__safeDI_init(first: first, safeDIBuilder: safeDIOverrides.top.subA.safeDIBuilder)
		            }
		            let subA: SubA = __safeDI_subA()
		            let __safeDI_defaultGadget_GadgetBuilder_subB = __safeDI_defaultGadget_GadgetBuilder_top.subB(SafeDIMockScope_DefaultGadget_Gadget.Top_Scope.subB_Values(subA: subA))
		            func __safeDI_subB() -> SubB {
		                let __safeDI_defaultGadget_GadgetBuilder_second = __safeDI_defaultGadget_GadgetBuilder_subB.second(SafeDIMockScope_DefaultGadget_Gadget.SubB_Scope.second_Values())
		                func __safeDI_second() -> any Second {
		                    let gadgetBuilder = ErasedInstantiator<Int, any Gadget>(__safeDI_defaultGadget_GadgetBuilder_second.gadgetBuilder(SafeDIMockScope_DefaultGadget_Gadget.DefaultSecond_Scope.gadgetBuilder_Values()))
		                    return if let safeDIBuilder = safeDIOverrides.top.subB.second { safeDIBuilder(gadgetBuilder) } else { DefaultSecond(gadgetBuilder: gadgetBuilder) }
		                }
		                let second: any Second = __safeDI_second()
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
		    public enum __safeDI_Panel_mock_F827D4C42BE91338 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `SubB` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_SubB_MockConfiguration {
		    public init(
		        second: ((ErasedInstantiator<Int, any Gadget>) -> any Second)? = nil,
		        _ safeDIBuilder: ((any Second) -> SubB)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            second: second,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var second: ((ErasedInstantiator<Int, any Gadget>) -> any Second)? { __safeDI_storage.second }
		    /// Overrides how `SubB` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((any Second) -> SubB)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            second: ((ErasedInstantiator<Int, any Gadget>) -> any Second)?,
		            safeDIBuilder: ((any Second) -> SubB)?
		        ) {
		            self.second = second
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let second: ((ErasedInstantiator<Int, any Gadget>) -> any Second)?
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
		            _ = Host.__safeDI_Host_D133371C667165CD.self\(seamCallComment(seam: "Host", module: "Middle"))
		            func __safeDI_defaultGadget_GadgetBuilder_Host_DefaultSecond_Scope_gadgetBuilder() -> ErasedInstantiator<Int, any Gadget>.Builder {
		                func __safeDI_gadgetBuilder(id: Int) -> DefaultGadget {
		                    DefaultGadget(id: id)
		                }
		                return { forwarded in __safeDI_gadgetBuilder(id: forwarded) }
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host() -> Host.SafeDIScope_DefaultGadget_Gadget.__safeDI_Builder<any Gadget> {
		                .init(top_firstBuilder: { _ in __safeDI_defaultGadget_GadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_defaultGadget_GadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		                .init(subB_secondBuilder: { _ in __safeDI_defaultGadget_GadgetBuilder_Host_SubB() })
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadgetBuilder: { _ in __safeDI_defaultGadget_GadgetBuilder_Host_DefaultSecond_Scope_gadgetBuilder() })
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subA: __safeDI_defaultGadget_GadgetBuilder_Host_SubA())
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_DefaultGadget_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		                .init(first: { __safeDI_defaultGadget_GadgetBuilder_Host_DefaultFirst_Scope() })
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(subB: __safeDI_defaultGadget_GadgetBuilder_Host_SubB())
		            }
		            func __safeDI_defaultGadget_GadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_DefaultGadget_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		                .init(second: { __safeDI_defaultGadget_GadgetBuilder_Host_DefaultSecond_Scope() })
		            }
		            return Host(__safeDI_defaultGadget_GadgetBuilder: __safeDI_defaultGadget_GadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture, samples: [DifferentialValueSample(type: "Int", expression: "7")])
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
		                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.subB_secondBuilder = subB_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gearBuilder: SafeDIScope_Gear.__safeDI_Builder<any Gear>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        let __safeDI_gearBuilder_top_firstBuilder = __safeDI_gearBuilder.top_firstBuilder(SafeDIScope_Gear.top_firstBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder_gadgetBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>, __safeDI_top_firstBuilder_gearBuilder: SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<any Gear>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_subB_secondBuilder = __safeDI_top_firstBuilder_gadgetBuilder.subB_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
		                    @inline(never) func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetBuilder_subB_secondBuilder))
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    let gear: any Gear = __safeDI_top_firstBuilder_gearBuilder.gear(SafeDIScope_Gear.DefaultFirst_Scope.gear_Values(subB: subB))
		                    return DefaultFirst(gear: gear, subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up_top_firstBuilder_gadgetBuilder: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>, up_top_firstBuilder_gearBuilder: Top.__safeDI_FirstCarrier<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<any Gear>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up_top_firstBuilder_gadgetBuilder: up_top_firstBuilder_gadgetBuilder.subA, up_top_firstBuilder_gearBuilder: up_top_firstBuilder_gearBuilder.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up_top_firstBuilder_gadgetBuilder: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>, up_top_firstBuilder_gearBuilder: SubA.__safeDI_FirstCarrier<SafeDIScope_Gear.DefaultFirst_Scope.__safeDI_Builder<any Gear>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder_gadgetBuilder: up_top_firstBuilder_gadgetBuilder.first(), __safeDI_top_firstBuilder_gearBuilder: up_top_firstBuilder_gearBuilder.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up_top_firstBuilder_gadgetBuilder: __safeDI_gadgetBuilder_top_firstBuilder, up_top_firstBuilder_gearBuilder: __safeDI_gearBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B039814C158DBFA7 {}
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_GadgetCarrier<__safeDI_Built> {
		        public let gadget: (Top) -> __safeDI_Built

		        public init(gadget: @escaping (Top) -> __safeDI_Built) {
		            self.gadget = gadget
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: __safeDI_GadgetCarrier<any Gadget>) {
		        @inline(never) func __safeDI_secondBuilder_Top() -> Top.__safeDI_SecondCarrier<any Second> {
		            .init(subB: __safeDI_secondBuilder_SubB())
		        }
		        @inline(never) func __safeDI_secondBuilder_SubB() -> SubB.__safeDI_SecondCarrier<any Second> {
		            .init(second: {
		                let second: any Second = DefaultSecond()
		                return second
		            })
		        }
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first() -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    @inline(never) func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
		                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB())
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA())
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first() })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top())
		        }
		        let top: Top = __safeDI_top()
		        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(top)
		        self.init(top: top, gadget: gadget)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_C6F23F5C0656CAE2 {}
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenPlaceWhoseFillBuildsSeamAgainCarriesLabelToo() async {
		// `SubA` binds `x` before `first`, so the place whose fill calls `SubB` again carries `x`, which a fill that builds its
		// seam again and reads it from the caller's scope is rejected for (`fieldOfReenteringPlace`). `DefaultFirst` binds `x`
		// again before that call, nearer the reader inline: both builds report the declaration on the path, which their
		// checks test first.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received let x: X` on `SubB`, with `x` declared on every route to `SubB`, so SafeDI hands it to the builder; receive it only if available on `SubB` and `DefaultGadget`, with `@Received(onlyIfAvailable: true) let x: X?`; or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subBBuilder`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `Holder` declares on the path from the builder for `SubB`’s `second: any Second` (`second` of `secondBuilder`) to the call by which `Holder` instantiates `SubB` again (`subBBuilder`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `Holder`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subBBuilder`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGizmo` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["Outer"]!["DefaultGadget.swift"]):11:5: error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`), but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`) and `Holder` declares on the path from the builder for `SubB`’s `second: any Second` (`second` of `secondBuilder`) to the call by which `Holder` instantiates `SubB` again (`subBBuilder`), but those calls pass the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s and `Holder`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subB`) and `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `SubB` again (`subBBuilder`), but those calls pass the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `Relay` builds where it calls `SubB`, but `Relay` passes the builder for `SubB`’s `second: any Second` (`second` of `secondBuilder`) on from its own caller, which cannot hand it `Relay`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies, so `Relay` fills the builder itself.
			\(fixtures["Feature"]!["Relay.swift"]):8:5: note: `Relay` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamPassingPlaceUpBindsLabelSeamBuiltAgainReceivesOnlyIfAvailable() async throws {
		// The remedy of the error above, applied as written: `SubB` receives `x` only if available, so the scope of `second`
		// carries `Relay`'s `x` on the route through `Relay` and `nil` on `Top`'s own, as inline reads.
		let fixture = Fixture(
			xIsFinalClass: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			subBDeclarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_41A1837E388EE2AF.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_x: nil, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueBoundByPassingUpSeam_whenTypeAboveSeamCallDeclaresLabelToo() async {
		// As above, with `Host` binding `x` before it calls `Top` and the gadget requiring `x`: `gadget` carries `Host`'s `x`
		// as a field, but on the route through `Relay` inline reads `Relay`'s, so the field does not lift the rejection.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X`, which `Relay` builds where it calls `SubB`, but `Relay` passes the builder for `SubB`’s `second: any Second` (`second` of `secondBuilder`) on from its own caller, which cannot hand it `Relay`’s values. Declare `@Received let x: X` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies, so `Relay` fills the builder itself.
			\(fixtures["Feature"]!["Relay.swift"]):8:5: note: `Relay` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueBoundByPassingUpSeam_whenTypeAboveSeamCallDeclaresLabelTooForReaderOnlyIfAvailable() async {
		// As above, with the gadget receiving `x` only if available.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `Relay` builds where it calls `SubB`, but `Relay` passes the builder for `SubB`’s `second: any Second` (`second` of `secondBuilder`) on from its own caller, which cannot hand it `Relay`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies, so `Relay` fills the builder itself.
			\(fixtures["Feature"]!["Relay.swift"]):8:5: note: `Relay` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueBoundByPassingUpSeam_whenSeamAboveHostPassesPlaceUpAgain() async {
		// As above, with `Shell`, a seam of `Upper`, building `Host` and passing `gadget` up again, and `App` filling it: on the
		// route through `Relay` the gadget would read `Host`'s `x`, where inline it reads `Relay`'s.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
			upperTypes: [seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let host: Host"])],
			rootDeclarations: ["@Instantiated let shell: Shell"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X`, which `Relay` builds where it calls `SubB`, but `Relay` passes the builder for `SubB`’s `second: any Second` (`second` of `secondBuilder`) on from its own caller, which cannot hand it `Relay`’s values. Declare `@Received let x: X` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies, so `Relay` fills the builder itself.
			\(fixtures["Feature"]!["Relay.swift"]):8:5: note: `Relay` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelBoundOnEveryRouteToItAndSeamAboveHostPassesPlaceUpAgain() async throws {
		// The remedy of the error above, applied as written: `SubB` receives `x`, `Host`'s on `Top`'s own route and `Relay`'s on
		// the route through `Relay`, as inline reads.
		let fixture = Fixture(
			xIsFinalClass: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			subBDeclarations: ["@Received let x: X", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
			upperTypes: [seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let host: Host"])],
			rootDeclarations: ["@Instantiated let shell: Shell"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Relay {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_SecondCarrier<__safeDI_Built> {
		        public let subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>

		        public init(subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>) {
		            self.subB = subB
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_secondBuilder: __safeDI_SecondCarrier<any Second>) {
		        let x = X()
		        @inline(never) func __safeDI_subB() -> SubB {
		            _ = SubB.__safeDI_SubB_3416F5143420EA5F.self
		            return SubB(__safeDI_x: x, __safeDI_secondBuilder: __safeDI_secondBuilder.subB)
		        }
		        let subB: SubB = __safeDI_subB()
		        self.init(x: x, subB: subB)
		    }
		}

		extension Relay {
		    public enum __safeDI_Relay_79820786BC06F586 {}
		}

		extension SubA {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_FirstCarrier<__safeDI_Built> {
		        public let first: () -> __safeDI_Built

		        public init(first: @escaping () -> __safeDI_Built) {
		            self.first = first
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_firstBuilder: __safeDI_FirstCarrier<any First>) {
		        let first: any First = __safeDI_firstBuilder.first()
		        self.init(first: first)
		    }
		}

		extension SubA {
		    public enum __safeDI_SubA_A892DC5C7EEFD6A2 {}
		}

		extension SubB {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_SecondCarrier<__safeDI_Built> {
		        public let second: (X) -> __safeDI_Built

		        public init(second: @escaping (X) -> __safeDI_Built) {
		            self.second = second
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x x: X, __safeDI_secondBuilder: __safeDI_SecondCarrier<any Second>) {
		        let second: any Second = __safeDI_secondBuilder.second(x)
		        self.init(x: x, second: second)
		    }
		}

		extension SubB {
		    public enum __safeDI_SubB_3416F5143420EA5F {}
		}

		extension Top {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_FirstCarrier<__safeDI_Built> {
		        public let subA: SubA.__safeDI_FirstCarrier<__safeDI_Built>

		        public init(subA: SubA.__safeDI_FirstCarrier<__safeDI_Built>) {
		            self.subA = subA
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_SecondCarrier<__safeDI_Built> {
		        public let subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>

		        public init(subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>) {
		            self.subB = subB
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x: @autoclosure @escaping () -> X, __safeDI_firstBuilder: __safeDI_FirstCarrier<any First>, __safeDI_secondBuilder: __safeDI_SecondCarrier<any Second>) {
		        let x = LazilyInstantiated<X>(__safeDI_x)
		        @inline(never) func __safeDI_subA() -> SubA {
		            _ = SubA.__safeDI_SubA_A892DC5C7EEFD6A2.self
		            return SubA(__safeDI_firstBuilder: __safeDI_firstBuilder.subA)
		        }
		        let subA: SubA = __safeDI_subA()
		        @inline(never) func __safeDI_subB() -> SubB {
		            _ = SubB.__safeDI_SubB_3416F5143420EA5F.self
		            return SubB(__safeDI_x: x.instance, __safeDI_secondBuilder: __safeDI_secondBuilder.subB)
		        }
		        let subB: SubB = __safeDI_subB()
		        self.init(subA: subA, subB: subB)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_E14200E0531FC9C4 {}
		}
		"""])
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {
		            public let x: X
		        }

		        nonisolated public struct top_secondBuilder_Values {
		            public let x: X
		        }

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct relay_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relay_secondBuilder: (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relay_secondBuilder: @escaping (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relay_secondBuilder = relay_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let x = X()
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values(x: x))
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values(x: x))
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_E14200E0531FC9C4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_relay_secondBuilder = __safeDI_top_firstBuilder.relay_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.relay_secondBuilder_Values())
		                    @inline(never) func __safeDI_relay() -> Relay {
		                        _ = Relay.__safeDI_Relay_79820786BC06F586.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetBuilder_relay_secondBuilder))
		                    }
		                    let relay: Relay = __safeDI_relay()
		                    return DefaultFirst(relay: relay)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(_ scope_x: X, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { scope_x in __safeDI_secondBuilder_SubB_second(scope_x, __safeDI_top_secondBuilder: up.second(scope_x)) })
		            }
		            return Top(__safeDI_x: x, __safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(x: x, top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_786FA421D28BC998 {}
		}
		"""])
		#expect(output.modules["Upper"]?.generatedFiles == ["Upper.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Shell {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_GadgetCarrier<__safeDI_Built> {
		        public let host: Host.SafeDIScope_Gadget.__safeDI_Builder<__safeDI_Built>

		        public init(host: Host.SafeDIScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
		            self.host = host
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: __safeDI_GadgetCarrier<any Gadget>) {
		        @inline(never) func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_786FA421D28BC998.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder.host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_428C86B9E38BACF5 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif
		#if canImport(Upper)
		import Upper
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Shell() -> Shell.__safeDI_GadgetCarrier<any Gadget> {
		            .init(host: __safeDI_gadgetBuilder_Host())
		        }
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_428C86B9E38BACF5.self // If this line does not compile, compile the code SafeDI generates for module Upper into Upper: under Bazel, add Upper’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Shell(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Shell())
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelBoundOnEveryRouteToIt() async throws {
		// The remedy of the required reader's error above, applied as written: `SubB` receives `x`, `Host`'s on `Top`'s own
		// route and `Relay`'s on the route through `Relay`, as inline reads.
		let fixture = Fixture(
			xIsFinalClass: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			subBDeclarations: ["@Received let x: X", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_786FA421D28BC998.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelOnlyIfAvailableBoundOnEveryRouteToIt() async throws {
		// The remedy of the only-if-available reader's error above, applied as written: `SubB` receives `x` only if available.
		let fixture = Fixture(
			xIsFinalClass: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			subBDeclarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3CEB950125B14383.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueOfOneRoute_whenCallOnPathIsOfSeamThatPassesPlaceUp() async {
		// `DefaultFirst` binds `x` before it calls `Relay`, a seam that builds `SubB` and passes `second` up, so the call is of
		// `Relay` and the seam built again is `SubB`: the error names the call as written, and the remedy the seam built again.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let relay: Relay"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, fixtures in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which `DefaultFirst` declares on the path from the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) to the call by which `DefaultFirst` instantiates `Relay` (`relay`), which instantiates `SubB` again, but that call passes the builder on as module `Middle` fills it, which cannot hand it `DefaultFirst`’s values. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Middle"]!["DefaultFirst.swift"]):10:5: note: `DefaultFirst` declares `x: X` here.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelDeclaredOnPathToCallOfSeamThatPassesPlaceUp() async throws {
		// The remedy of the error above, applied as written: `SubB`, the seam built again, receives `x` only if available, so
		// the scope of `second` carries `DefaultFirst`'s on the route through `Relay` and `nil` on `Top`'s own, as inline reads.
		let fixture = Fixture(
			xIsFinalClass: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"])],
			subBDeclarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let relay: Relay"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_17A6D5BCB913588E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_x: nil, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
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
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_2424E2AF2B5FE163.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_x: nil, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelThePlaceWhoseFillBuildsItAgainCarriesToo() async throws {
		// The remedy of the error both builds report where `SubA` binds `x` before `first` too: `SubB` receives `x` only if
		// available, so the scope of `second` carries `DefaultFirst`'s on the route through its call, which inline reads.
		let fixture = Fixture(
			xIsFinalClass: true,
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			subBDeclarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { values_x in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_4D735532D4B8270C.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_x: nil, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
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
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_12A4A9768D40A314.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
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
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        let x = X()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_9A2093DC16C41D0F.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_x: x, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(x: x, host: host)
		    }
		}
		"""])
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
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension SubA {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_FirstCarrier<__safeDI_Built> {
		        public let first: () -> __safeDI_Built

		        public init(first: @escaping () -> __safeDI_Built) {
		            self.first = first
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_firstBuilder: __safeDI_FirstCarrier<any First>) {
		        let first: any First = __safeDI_firstBuilder.first()
		        self.init(first: first)
		    }
		}

		extension SubA {
		    public enum __safeDI_SubA_A892DC5C7EEFD6A2 {}
		}

		extension SubB {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x: @autoclosure @escaping () -> X) {
		        let x = LazilyInstantiated<X>(__safeDI_x)
		        @inline(never) func __safeDI_second() -> DefaultSecond {
		            let gadget: any Gadget = DefaultGadget(x: x.instance)
		            return DefaultSecond(gadget: gadget)
		        }
		        let second: any Second = __safeDI_second()
		        self.init(second: second)
		    }
		}

		extension SubB {
		    public enum __safeDI_SubB_29925053977349E6 {}
		}

		extension Top {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_FirstCarrier<__safeDI_Built> {
		        public let subA: SubA.__safeDI_FirstCarrier<__safeDI_Built>

		        public init(subA: SubA.__safeDI_FirstCarrier<__safeDI_Built>) {
		            self.subA = subA
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x: @autoclosure @escaping () -> X, __safeDI_firstBuilder: __safeDI_FirstCarrier<any First>) {
		        let x = LazilyInstantiated<X>(__safeDI_x)
		        @inline(never) func __safeDI_subA() -> SubA {
		            _ = SubA.__safeDI_SubA_A892DC5C7EEFD6A2.self
		            return SubA(__safeDI_firstBuilder: __safeDI_firstBuilder.subA)
		        }
		        let subA: SubA = __safeDI_subA()
		        @inline(never) func __safeDI_subB() -> SubB {
		            _ = SubB.__safeDI_SubB_29925053977349E6.self
		            return SubB(__safeDI_x: x.instance)
		        }
		        let subB: SubB = __safeDI_subB()
		        self.init(subA: subA, subB: subB)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_F38317630461F2FF {}
		}
		"""])
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        let x = X()
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_F38317630461F2FF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_firstBuilder_SubA_first() -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let x = X()
		                    @inline(never) func __safeDI_subB() -> SubB {
		                        _ = SubB.__safeDI_SubB_29925053977349E6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return SubB(__safeDI_x: x)
		                    }
		                    let subB: SubB = __safeDI_subB()
		                    return DefaultFirst(x: x, subB: subB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA())
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first() })
		            }
		            return Top(__safeDI_x: x, __safeDI_firstBuilder: __safeDI_firstBuilder_Top())
		        }
		        let top: Top = __safeDI_top()
		        self.init(x: x, top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host()
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
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
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_F24E6F42FD6E645A.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
	mutating func generate_buildsInlineValues_whenFillBuiltAgainDeclaresLabelAbovePlace() async throws {
		// `DefaultSecond` binds an `x` of its own before `gadget`: inline reads it on every route, and the place carries it.
		let fixture = Fixture(
			xIsFinalClass: true,
			defaultFirstDeclarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"],
			defaultSecondDeclarations: ["@Instantiated let x: X", "@Instantiated let gadget: any Gadget"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { scope in
		                let x = scope.x
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_CA15DCDF423BE69E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: A place a caller fills inside the fill built again, reading what the re-entering place carries

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenCallerFillsPlaceInsideFillBuiltAgainAndOnlyThePlaceCarriesLabel() async {
		// `SubA` binds `x` before `first`, whose fill `DefaultFirst` calls `SubB` again, and nothing on the path to that call
		// declares `x`: inline, the gadget reads `SubA`'s `x` on the route through that call and `nil` on `Top`'s own, while the
		// one fill `Middle` generates for `second` reads the outer call's. `Host`'s module records what its visible build
		// rejects, so `App` rejects it too.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subB`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenTypeAboveSeamCallDeclaresLabelTooAndReaderRequiresIt() async {
		// `Host` binds `x` before it calls `Top`, so `gadget` carries `Host`'s `x` as a field, but on the route through
		// `DefaultFirst`'s call of `SubB` inline reads `SubA`'s: a field of the label does not lift the rejection.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subB`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get another value. Declare `@Received let x: X` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenTypeAboveSeamCallDeclaresLabelTooAndReaderReceivesItOnlyIfAvailable() async {
		// As above, with the gadget receiving `x` only if available.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subB`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenCallBuildsSeamAgainThroughInstantiatorAndOnlyThePlaceCarriesLabel() async {
		// `DefaultFirst` builds `SubB` again through an `Instantiator`.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			defaultFirstDeclarations: ["@Instantiated let subBBuilder: Instantiator<SubB>"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subBBuilder`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlaceNamingEveryCall_whenFillOfPlaceThatCarriesLabelBuildsSeamAgainTwice() async {
		// `DefaultFirst` builds `SubB` again twice, once through an `Instantiator`: `Host` records the field once per call, and
		// the error names both calls, as the visible build's does.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			defaultFirstDeclarations: ["@Instantiated let subB: SubB", "@Instantiated let subBBuilder: Instantiator<SubB>"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subB` and `subBBuilder`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but those calls pass the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlaceNamingEveryPlace_whenTwoPlacesWhoseFillsBuildSeamAgainCarryLabel() async {
		// `Top` calls `SubA` and `SubC`, each binding an `x` of its own before a place `DefaultFirst` fills, which calls `SubB`
		// again: `Host` records both places' fields, and the error names both, as the visible build's does.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "SubC", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let first: any First"])],
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			topDeclarations: ["@Instantiated let subA: SubA", "@Instantiated let subC: SubC", "@Instantiated let subB: SubB"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builders for `SubA`’s `first: any First` (`first` of `firstBuilder_SubA`) and `SubC`’s `first: any First` (`first` of `firstBuilder_SubC`) carry from `SubA` and `SubC`, and each of their fills instantiates `SubB` again (`subB`). Inline, `DefaultGadget` would read `SubA`’s or `SubC`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenCallBuildsSeamAgainInSendableFunctionAndOnlyThePlaceCarriesLabel() async {
		// `DefaultFirst` builds `SubB` again in a `SendableInstantiator`'s `@Sendable` function.
		let fixture = Fixture(
			isSendable: true,
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			defaultFirstDeclarations: ["@Instantiated let subBBuilder: SendableInstantiator<SubB>"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subBBuilder`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenSeamCalledInsideFillBuiltAgainPassesPlaceUpAndOnlyThePlaceCarriesLabel() async {
		// The fill of `second` calls `Inner`, whose place `gizmo` `Host` passes up, inside that fill, and `App` fills.
		let fixture = Fixture(
			featureTypes: ["public protocol Gizmo {}", seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let gizmo: any Gizmo"])],
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			defaultSecondDeclarations: ["@Instantiated let inner: Inner"],
			appTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGizmo", fulfilling: "Gizmo", declarations: ["@Received(onlyIfAvailable: true) let x: X?"])],
		)
		await expectBothBuildsThrow(fixture, readerFile: "DefaultGizmo.swift", readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGizmo` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subB`). Inline, `DefaultGizmo` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGizmo` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenModuleAboveSeamThatPassesPlaceUpFillsItAndOnlyThePlaceCarriesLabel() async {
		// `App`'s `Shell` calls `Host` and passes `gadget` up; `Outer` fills it. The copy `Shell` takes keeps what `Host` recorded.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
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
			\(fixtures["Outer"]!["DefaultGadget.swift"]):11:5: error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subB`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenCallInsideFillIsOfSeamThatPassesPlaceUp() async {
		// `DefaultFirst` builds `Mid`, which builds `Relay` through an `Instantiator`; `Relay` builds `SubB` and passes `second`
		// up. The seam built again is `SubB`, beneath `Relay`, which inline reads `SubA`'s `x` inside: the error names the call
		// as written, and puts the receive on `SubB`. A receive on `Relay` would not reach `second`, which `Relay` passes up.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"])],
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			middleTypes: [seamFixtureType(named: "Mid", declarations: ["@Instantiated let relayBuilder: Instantiator<Relay>"])],
			defaultFirstDeclarations: ["@Instantiated let mid: Mid"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `Relay` (`relayBuilder`), which instantiates `SubB` again. Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldOfReenteringPlace_whenCallInsideFillBeneathFilledTypeBuildsSeamAgainThroughInstantiator() async {
		// The neighbour of the shape above whose call is of `SubB` itself: the called seam is the seam built again, so the
		// error says the call instantiates `SubB` again, as before.
		let fixture = Fixture(
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			middleTypes: [seamFixtureType(named: "Mid", declarations: ["@Instantiated let subBBuilder: Instantiator<SubB>"])],
			defaultFirstDeclarations: ["@Instantiated let mid: Mid"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		await expectBothBuildsThrow(fixture, readerLineInMiddle: 9) { readerLocation, _ in
			"""
			\(readerLocation): error: `DefaultGadget` receives `x: X?`, which the builder for `SubA`’s `first: any First` (`first` of `firstBuilder`) carries from `SubA`, and that builder’s fill instantiates `SubB` again (`subBBuilder`). Inline, `DefaultGadget` would read `SubA`’s `x` inside that `SubB`, but the call passes the builder on as module `Middle` fills it, whose scope there does not carry `x`, so `DefaultGadget` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let x: X?` on `SubB`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Second` in module `Feature` or a module it lists among its SafeDI dependencies.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelOnlyThePlaceWhoseFillCallsSeamThatPassesPlaceUpCarries() async throws {
		// The remedy of `generate_throwsFieldOfReenteringPlace_whenCallInsideFillIsOfSeamThatPassesPlaceUp`, applied as written:
		// `SubB` receives `x` only if available, so `Relay` passes `SubA`'s on to it on the route through `Mid`'s call, and the
		// scope of `second` carries it there and `nil` on `Top`'s own, as inline reads.
		let fixture = Fixture(
			xIsFinalClass: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"])],
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			subBDeclarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let second: any Second"],
			middleTypes: [seamFixtureType(named: "Mid", declarations: ["@Instantiated let relayBuilder: Instantiator<Relay>"])],
			defaultFirstDeclarations: ["@Instantiated let mid: Mid"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(mid: { _ in __safeDI_gadgetBuilder_Host_Mid_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Mid_Scope() -> Host.SafeDIScope_Gadget.Mid_Scope.__safeDI_Builder<any Gadget> {
		            .init(relayBuilder_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { values_x in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_ED40D67527DBFE68.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_x: nil, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Relay {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_SecondCarrier<__safeDI_Built> {
		        public let subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>

		        public init(subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>) {
		            self.subB = subB
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x: @autoclosure @escaping () -> X?, __safeDI_secondBuilder: __safeDI_SecondCarrier<any Second>) {
		        let x = LazilyInstantiated<X?>(__safeDI_x)
		        @inline(never) func __safeDI_subB() -> SubB {
		            _ = SubB.__safeDI_SubB_125D1DDEE6D70613.self
		            return SubB(__safeDI_x: x.instance, __safeDI_secondBuilder: __safeDI_secondBuilder.subB)
		        }
		        let subB: SubB = __safeDI_subB()
		        self.init(subB: subB)
		    }
		}

		extension Relay {
		    public enum __safeDI_Relay_27929B83E5E6A46D {}
		}

		extension SubA {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_FirstCarrier<__safeDI_Built> {
		        public let first: (X) -> __safeDI_Built

		        public init(first: @escaping (X) -> __safeDI_Built) {
		            self.first = first
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_firstBuilder: __safeDI_FirstCarrier<any First>) {
		        let x = X()
		        let first: any First = __safeDI_firstBuilder.first(x)
		        self.init(x: x, first: first)
		    }
		}

		extension SubA {
		    public enum __safeDI_SubA_9190E577971D591D {}
		}

		extension SubB {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_SecondCarrier<__safeDI_Built> {
		        public let second: (X?) -> __safeDI_Built

		        public init(second: @escaping (X?) -> __safeDI_Built) {
		            self.second = second
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x x: X?, __safeDI_secondBuilder: __safeDI_SecondCarrier<any Second>) {
		        let second: any Second = __safeDI_secondBuilder.second(x)
		        self.init(x: x, second: second)
		    }
		}

		extension SubB {
		    public enum __safeDI_SubB_125D1DDEE6D70613 {}
		}

		extension Top {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_FirstCarrier<__safeDI_Built> {
		        public let subA: SubA.__safeDI_FirstCarrier<__safeDI_Built>

		        public init(subA: SubA.__safeDI_FirstCarrier<__safeDI_Built>) {
		            self.subA = subA
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_SecondCarrier<__safeDI_Built> {
		        public let subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>

		        public init(subB: SubB.__safeDI_SecondCarrier<__safeDI_Built>) {
		            self.subB = subB
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x: @autoclosure @escaping () -> X?, __safeDI_firstBuilder: __safeDI_FirstCarrier<any First>, __safeDI_secondBuilder: __safeDI_SecondCarrier<any Second>) {
		        let x = LazilyInstantiated<X?>(__safeDI_x)
		        @inline(never) func __safeDI_subA() -> SubA {
		            _ = SubA.__safeDI_SubA_9190E577971D591D.self
		            return SubA(__safeDI_firstBuilder: __safeDI_firstBuilder.subA)
		        }
		        let subA: SubA = __safeDI_subA()
		        @inline(never) func __safeDI_subB() -> SubB {
		            _ = SubB.__safeDI_SubB_125D1DDEE6D70613.self
		            return SubB(__safeDI_x: x.instance, __safeDI_secondBuilder: __safeDI_secondBuilder.subB)
		        }
		        let subB: SubB = __safeDI_subB()
		        self.init(subA: subA, subB: subB)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_20018567BD221129 {}
		}
		"""])
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {
		            public var x: X? { __safeDI_x.instance }
		            public let __safeDI_x: LazilyInstantiated<X?>

		            init(x: LazilyInstantiated<X?>) {
		                __safeDI_x = x
		            }
		        }

		        nonisolated public struct top_secondBuilder_Values {
		            public var x: X? { __safeDI_x.instance }
		            public let __safeDI_x: LazilyInstantiated<X?>

		            init(x: LazilyInstantiated<X?>) {
		                __safeDI_x = x
		            }
		        }

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct mid_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let mid: (mid_Values) -> SafeDIScope_Gadget.Mid_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(mid: @escaping (mid_Values) -> SafeDIScope_Gadget.Mid_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.mid = mid
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
		            }
		        }

		        nonisolated public enum Mid_Scope {
		            nonisolated public struct relayBuilder_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relayBuilder_secondBuilder: (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relayBuilder_secondBuilder: @escaping (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relayBuilder_secondBuilder = relayBuilder_secondBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_x: @autoclosure @escaping () -> X?, __safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let x = LazilyInstantiated<X?>(__safeDI_x)
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values(x: x))
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values(x: x))
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_20018567BD221129.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(_ scope_x: X, __safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                let x = scope_x
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_mid = __safeDI_top_firstBuilder.mid(SafeDIScope_Gadget.DefaultFirst_Scope.mid_Values())
		                    @inline(never) func __safeDI_mid() -> Mid {
		                        let __safeDI_gadgetBuilder_relayBuilder_secondBuilder = __safeDI_gadgetBuilder_mid.relayBuilder_secondBuilder(SafeDIScope_Gadget.Mid_Scope.relayBuilder_secondBuilder_Values())
		                        @inline(never) func __safeDI_relayBuilder() -> Relay {
		                            _ = Relay.__safeDI_Relay_27929B83E5E6A46D.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                            @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                            }
		                            return Relay(__safeDI_x: x, __safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetBuilder_relayBuilder_secondBuilder))
		                        }
		                        let relayBuilder = Instantiator<Relay>(__safeDI_relayBuilder)
		                        return Mid(relayBuilder: relayBuilder)
		                    }
		                    let mid: Mid = __safeDI_mid()
		                    return DefaultFirst(mid: mid)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(_ scope_x: X?, __safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { scope_x in __safeDI_firstBuilder_SubA_first(scope_x, __safeDI_top_firstBuilder: up.first(scope_x)) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { scope_x in __safeDI_secondBuilder_SubB_second(scope_x, __safeDI_top_secondBuilder: up.second(scope_x)) })
		            }
		            return Top(__safeDI_x: x.instance, __safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_ED40D67527DBFE68 {}
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(mid: { _ in __safeDI_gadgetBuilder_Host_Mid_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Mid_Scope() -> Host.SafeDIScope_Gadget.Mid_Scope.__safeDI_Builder<any Gadget> {
		            .init(relayBuilder_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { values_x in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_ED40D67527DBFE68.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_x: nil, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesLabelOnlyThePlaceWhoseFillBuildsItAgainCarries() async throws {
		// The error's first remedy: `SubB` receives `x` only if available, so the scope of `second` carries `SubA`'s on the route
		// through `DefaultFirst`'s call and `nil` on `Top`'s own, as inline reads.
		let fixture = Fixture(
			xIsFinalClass: true,
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			subBDeclarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let second: any Second"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X?) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { values_x in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_48F9968190970D95.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_x: nil, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesRequiredLabelOnlyThePlaceWhoseFillBuildsItAgainCarries() async throws {
		// The first remedy for a required reader, where `Host` binds `x` above its call of `Top`: `SubB` receives `x`, `Host`'s
		// on `Top`'s own route and `SubA`'s on the route through `DefaultFirst`'s call.
		let fixture = Fixture(
			xIsFinalClass: true,
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			subBDeclarations: ["@Received let x: X", "@Instantiated let second: any Second"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: X) -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { values_x in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { values_x in __safeDI_gadgetBuilder_Host_DefaultSecond_Scope(x: values_x) })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_424F56FFDCA7D59E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		_ = try await executeSafeDIToolMultiModuleTest(modules: fixture.hostFillsEveryPlaceModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenFillBuiltAgainDeclaresLabelAbovePlaceThePlaceWhoseFillBuildsItAgainCarries() async throws {
		// `DefaultSecond` binds an `x` of its own before `gadget`: inline reads it on every route, and the place carries it.
		let fixture = Fixture(
			xIsFinalClass: true,
			subADeclarations: ["@Instantiated let x: X", "@Instantiated let first: any First"],
			defaultSecondDeclarations: ["@Instantiated let x: X", "@Instantiated let gadget: any Gadget"],
			gadgetDeclarations: ["@Received(onlyIfAvailable: true) let x: X?"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(subB_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_SubB() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { scope in
		                let x = scope.x
		                let gadget: any Gadget = DefaultGadget(x: x)
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { values_x in __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_ABEB2A855897D0A8.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
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
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3B6957495A4D519E.self\(seamCallComment(seam: "Host", module: "Middle"))
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() }, top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() })
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
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_8EB5E3FC6042D63E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsCarriedStructToReusedLevelFunction_whenFillCallsSeamThatPassesReenteredPlaceUp() async throws {
		// `DefaultFirst` calls `Relay`, a seam that calls `SubB` and passes `second` up: `Relay`'s level function, which this call
		// declares, leads to `SubB`'s, which the call of `Top` declares and this call reuses, so it takes the struct of its level
		// and hands `SubB`'s what that struct's member returns.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
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
		            nonisolated public struct relay_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relay_secondBuilder: (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relay_secondBuilder: @escaping (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relay_secondBuilder = relay_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_relay_secondBuilder = __safeDI_top_firstBuilder.relay_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.relay_secondBuilder_Values())
		                    @inline(never) func __safeDI_relay() -> Relay {
		                        _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetBuilder_relay_secondBuilder))
		                    }
		                    let relay: Relay = __safeDI_relay()
		                    return DefaultFirst(relay: relay)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3490048B6071A3C9 {}
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3490048B6071A3C9.self\(seamCallComment(seam: "Host", module: "Middle"))
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
	mutating func generate_namesBuilderFunctionApartFromReusedLevelFunction_whenFillCallingSeamThatPassesReenteredPlaceUpDeclaresPropertyOfItsName() async throws {
		// `DefaultFirst` calls `Relay`, whose level function's case calls `SubB`'s, `__safeDI_secondBuilder_SubB`, which the
		// call of `Top` declares and this call reuses. `DefaultFirst`'s instantiator `secondBuilder_SubB` would take that name
		// for its builder function and hide the reused one from the case, so it takes another.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay", "@Instantiated let secondBuilder_SubB: Instantiator<X>"],
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
		            nonisolated public struct relay_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relay_secondBuilder: (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relay_secondBuilder: @escaping (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relay_secondBuilder = relay_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_relay_secondBuilder = __safeDI_top_firstBuilder.relay_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.relay_secondBuilder_Values())
		                    @inline(never) func __safeDI_relay() -> Relay {
		                        _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetBuilder_relay_secondBuilder))
		                    }
		                    let relay: Relay = __safeDI_relay()
		                    @inline(never) func __safeDI_secondBuilder_SubB_X() -> X {
		                        X()
		                    }
		                    let secondBuilder_SubB = Instantiator<X>(__safeDI_secondBuilder_SubB_X)
		                    return DefaultFirst(relay: relay, secondBuilder_SubB: secondBuilder_SubB)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3490048B6071A3C9 {}
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_3490048B6071A3C9.self\(seamCallComment(seam: "Host", module: "Middle"))
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
	mutating func generate_handsCarriedStructThroughEachLevelFunction_whenFillCallsSeamThatPassesReenteredPlaceUpTwoSeamsDeep() async throws {
		// `DefaultFirst` calls `Outer`, a seam that calls `Relay`, which calls `SubB`: both pass `second` up, so each level
		// function this call declares takes the struct of its level on the way to `SubB`'s, which it reuses.
		let fixture = Fixture(
			featureTypes: [
				seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let relay: Relay"]),
			],
			defaultFirstDeclarations: ["@Instantiated let outer: Outer"],
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
		            nonisolated public struct outer_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let outer_secondBuilder: (outer_secondBuilder_Values) -> Outer.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(outer_secondBuilder: @escaping (outer_secondBuilder_Values) -> Outer.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.outer_secondBuilder = outer_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_outer_secondBuilder = __safeDI_top_firstBuilder.outer_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.outer_secondBuilder_Values())
		                    @inline(never) func __safeDI_outer() -> Outer {
		                        _ = Outer.__safeDI_Outer_428924FBACC54F23.self\(seamCallComment(seam: "Outer", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Outer(up: Outer.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Outer.__safeDI_SecondCarrier<any Second> {
		                            .init(relay: __safeDI_secondBuilder_Relay(up: up.relay))
		                        }
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Outer(__safeDI_secondBuilder: __safeDI_secondBuilder_Outer(up: __safeDI_gadgetBuilder_outer_secondBuilder))
		                    }
		                    let outer: Outer = __safeDI_outer()
		                    return DefaultFirst(outer: outer)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B2124894D647F377 {}
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(outer_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Outer() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Outer() -> Outer.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(relay: __safeDI_gadgetBuilder_Host_Relay())
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_B2124894D647F377.self\(seamCallComment(seam: "Host", module: "Middle"))
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
	mutating func generate_handsCarriedStructToReusedLevelFunction_whenFillCallsSeamThatPassesReenteredPlaceUpThroughInstantiator() async throws {
		// `DefaultFirst` builds `Relay` through an `Instantiator`: `Relay`'s level function still takes the struct of its level
		// and hands it on to `SubB`'s, which it reuses.
		let fixture = Fixture(
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"])],
			defaultFirstDeclarations: ["@Instantiated let relayBuilder: Instantiator<Relay>"],
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
		            nonisolated public struct relayBuilder_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relayBuilder_secondBuilder: (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relayBuilder_secondBuilder: @escaping (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relayBuilder_secondBuilder = relayBuilder_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetBuilder_top_secondBuilder = __safeDI_gadgetBuilder.top_secondBuilder(SafeDIScope_Gadget.top_secondBuilder_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_relayBuilder_secondBuilder = __safeDI_top_firstBuilder.relayBuilder_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.relayBuilder_secondBuilder_Values())
		                    @inline(never) func __safeDI_relayBuilder() -> Relay {
		                        _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetBuilder_relayBuilder_secondBuilder))
		                    }
		                    let relayBuilder = Instantiator<Relay>(__safeDI_relayBuilder)
		                    return DefaultFirst(relayBuilder: relayBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_C376D785FB5B33E3 {}
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relayBuilder_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_C376D785FB5B33E3.self\(seamCallComment(seam: "Host", module: "Middle"))
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
	mutating func generate_marksReusedLevelFunctionSendable_whenFillCallsSeamThatPassesReenteredPlaceUpThroughSendableInstantiator() async throws {
		// `DefaultFirst` builds `Relay` through a `SendableInstantiator`: `Relay`'s level function, declared inside that
		// `@Sendable` function, calls `SubB`'s, which the call of `Top` declares outside it, so `SubB`'s is `@Sendable`.
		let fixture = Fixture(
			isSendable: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"], conformances: ", Sendable")],
			defaultFirstDeclarations: ["@Instantiated let relayBuilder: SendableInstantiator<Relay>"],
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
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_Gadget {
		        nonisolated public struct top_firstBuilder_Sendable_Values: Sendable {}

		        nonisolated public struct top_secondBuilder_Values: Sendable {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct relayBuilder_secondBuilder_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		                public let relayBuilder_secondBuilder: @Sendable (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relayBuilder_secondBuilder: @escaping @Sendable (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relayBuilder_secondBuilder = relayBuilder_secondBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let top_firstBuilder_Sendable: @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>
		            public let top_secondBuilder: @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder_Sendable: @escaping @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>, top_secondBuilder: @escaping @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder_Sendable = top_firstBuilder_Sendable
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable = __safeDI_gadgetSendableBuilder.top_firstBuilder_Sendable(SafeDISendableScope_Gadget.top_firstBuilder_Sendable_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            let __safeDI_gadgetSendableBuilder_top_secondBuilder = __safeDI_gadgetSendableBuilder.top_secondBuilder(SafeDISendableScope_Gadget.top_secondBuilder_Values())
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first() -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    @inline(never) @Sendable nonisolated func __safeDI_relayBuilder() -> Relay {
		                        let __safeDI_gadgetSendableBuilder_relayBuilder_secondBuilder = __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable.relayBuilder_secondBuilder(SafeDISendableScope_Gadget.DefaultFirst_Scope.relayBuilder_secondBuilder_Values())
		                        _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetSendableBuilder_relayBuilder_secondBuilder))
		                    }
		                    let relayBuilder = SendableInstantiator<Relay>(__safeDI_relayBuilder)
		                    return DefaultFirst(relayBuilder: relayBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA())
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first() })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetSendableBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_9473E71383DEC8EC {}
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
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultFirst_Scope() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultFirst_Scope() -> Host.SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relayBuilder_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Top() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_9473E71383DEC8EC.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
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
	mutating func generate_marksReusedLevelFunctionSendable_whenFillCallsSeamThatPassesReenteredPlaceUpInPlainAndSendableFunctions() async throws {
		// `DefaultFirst` calls `Relay` in its own function and again in a `SendableInstantiator`'s: each call declares `Relay`'s
		// level function where it is made, and `SubB`'s, which both reuse, is `@Sendable`.
		let fixture = Fixture(
			isSendable: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"], conformances: ", Sendable")],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay", "@Instantiated let relayBuilder: SendableInstantiator<Relay>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public struct top_firstBuilder_Values {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct relay_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relay_secondBuilder: (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relay_secondBuilder: @escaping (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relay_secondBuilder = relay_secondBuilder
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
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let top_firstBuilder: (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder: @escaping (top_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder = top_firstBuilder
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_Gadget {
		        nonisolated public struct top_firstBuilder_Sendable_Values: Sendable {}

		        nonisolated public struct top_secondBuilder_Values: Sendable {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct relayBuilder_secondBuilder_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		                public let relayBuilder_secondBuilder: @Sendable (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relayBuilder_secondBuilder: @escaping @Sendable (relayBuilder_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relayBuilder_secondBuilder = relayBuilder_secondBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let top_firstBuilder_Sendable: @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>
		            public let top_secondBuilder: @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder_Sendable: @escaping @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>, top_secondBuilder: @escaping @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder_Sendable = top_firstBuilder_Sendable
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetBuilder_top_firstBuilder = __safeDI_gadgetBuilder.top_firstBuilder(SafeDIScope_Gadget.top_firstBuilder_Values())
		        let __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable = __safeDI_gadgetSendableBuilder.top_firstBuilder_Sendable(SafeDISendableScope_Gadget.top_firstBuilder_Sendable_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            let __safeDI_gadgetSendableBuilder_top_secondBuilder = __safeDI_gadgetSendableBuilder.top_secondBuilder(SafeDISendableScope_Gadget.top_secondBuilder_Values())
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetBuilder_relay_secondBuilder = __safeDI_top_firstBuilder.relay_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.relay_secondBuilder_Values())
		                    @inline(never) func __safeDI_relay() -> Relay {
		                        _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetBuilder_relay_secondBuilder))
		                    }
		                    let relay: Relay = __safeDI_relay()
		                    @inline(never) @Sendable nonisolated func __safeDI_relayBuilder() -> Relay {
		                        let __safeDI_gadgetSendableBuilder_relayBuilder_secondBuilder = __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable.relayBuilder_secondBuilder(SafeDISendableScope_Gadget.DefaultFirst_Scope.relayBuilder_secondBuilder_Values())
		                        _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetSendableBuilder_relayBuilder_secondBuilder))
		                    }
		                    let relayBuilder = SendableInstantiator<Relay>(__safeDI_relayBuilder)
		                    return DefaultFirst(relay: relay, relayBuilder: relayBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetBuilder_top_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetSendableBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_528EE64E6124915C {}
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
		        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() })
		        }
		        func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultFirst_Scope() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultFirst_Scope() -> Host.SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relayBuilder_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_First() -> Top.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subA: __safeDI_gadgetBuilder_Host_SubA())
		        }
		        func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_528EE64E6124915C.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host(), __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
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
	mutating func generate_marksReusedLevelFunctionSendable_whenSendableFillCallsSeamThatPassesReenteredPlaceUp() async throws {
		// `Top` builds `SubA` in a `SendableInstantiator`, so the fill of `first` is `@Sendable`, and `DefaultFirst` calls `Relay`
		// in plain code inside it: the fill calls `SubB`'s level function through `Relay`'s, so `SubB`'s is `@Sendable`.
		let fixture = Fixture(
			isSendable: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"], conformances: ", Sendable")],
			topDeclarations: ["@Instantiated let subABuilder: SendableInstantiator<SubA>", "@Instantiated let subB: SubB"],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, ["Middle.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Host {
		    nonisolated public enum SafeDIScope_Gadget {
		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct relay_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relay_secondBuilder: (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relay_secondBuilder: @escaping (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relay_secondBuilder = relay_secondBuilder
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
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_Gadget {
		        nonisolated public struct top_firstSendableBuilder_Values: Sendable {}

		        nonisolated public struct top_secondBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let top_firstSendableBuilder: @Sendable (top_firstSendableBuilder_Values) -> Top.__safeDI_FirstSendableCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let top_secondBuilder: @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstSendableBuilder: @escaping @Sendable (top_firstSendableBuilder_Values) -> Top.__safeDI_FirstSendableCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, top_secondBuilder: @escaping @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstSendableBuilder = top_firstSendableBuilder
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
		        @inline(never) func __safeDI_top() -> Top {
		            let __safeDI_gadgetSendableBuilder_top_firstSendableBuilder = __safeDI_gadgetSendableBuilder.top_firstSendableBuilder(SafeDISendableScope_Gadget.top_firstSendableBuilder_Values())
		            let __safeDI_gadgetSendableBuilder_top_secondBuilder = __safeDI_gadgetSendableBuilder.top_secondBuilder(SafeDISendableScope_Gadget.top_secondBuilder_Values())
		            _ = Top.__safeDI_Top_35BAA0B44101C5C3.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) @Sendable nonisolated func __safeDI_firstBuilder_SubA_first(__safeDI_top_firstSendableBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    let __safeDI_gadgetSendableBuilder_relay_secondBuilder = __safeDI_top_firstSendableBuilder.relay_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.relay_secondBuilder_Values())
		                    @inline(never) func __safeDI_relay() -> Relay {
		                        _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                        @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                            .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                        }
		                        return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetSendableBuilder_relay_secondBuilder))
		                    }
		                    let relay: Relay = __safeDI_relay()
		                    return DefaultFirst(relay: relay)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_firstSendableBuilder_Top(up: Top.__safeDI_FirstSendableCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstSendableCarrier<any First> {
		                .init(subABuilder: { __safeDI_firstBuilder_SubA(up: up.subABuilder()) })
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_top_firstSendableBuilder: up.first()) })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstSendableBuilder: __safeDI_firstSendableBuilder_Top(up: __safeDI_gadgetSendableBuilder_top_firstSendableBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetSendableBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_997A2A5E4C678235 {}
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
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDISendableCarrierScope_First() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() -> Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Top_SafeDISendableCarrierScope_First() -> Top.__safeDI_FirstSendableCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subABuilder: { __safeDI_gadgetBuilder_Host_SubA() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_SubA() -> SubA.__safeDI_FirstCarrier<Host.SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>> {
		            .init(first: { __safeDI_gadgetBuilder_Host_DefaultFirst_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Top_SafeDICarrierScope_Second() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_997A2A5E4C678235.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
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
	mutating func generate_marksReusedLevelFunctionSendable_whenTypeOfAnotherModuleCallsSeamThatPassesReenteredPlaceUpInsideSendableInstantiator() async throws {
		// `DefaultFirst` builds `Hub`, a type of `Feature`, through a `SendableInstantiator`, and `Hub` calls `Relay` in plain code:
		// the call is made inside the `@Sendable` function above it, which calls `SubB`'s level function, so `SubB`'s is `@Sendable`.
		let fixture = Fixture(
			isSendable: true,
			featureTypes: [
				seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let subB: SubB"], conformances: ", Sendable"),
				seamFixtureType(named: "Hub", declarations: ["@Instantiated let relay: Relay"], conformances: ", Sendable"),
			],
			defaultFirstDeclarations: ["@Instantiated let hubBuilder: SendableInstantiator<Hub>"],
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
		            }
		        }

		        nonisolated public enum Hub_Scope {
		            nonisolated public struct relay_secondBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let relay_secondBuilder: (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		                public init(relay_secondBuilder: @escaping (relay_secondBuilder_Values) -> Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                    self.relay_secondBuilder = relay_secondBuilder
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_Gadget {
		        nonisolated public struct top_firstBuilder_Sendable_Values: Sendable {}

		        nonisolated public struct top_secondBuilder_Values: Sendable {}

		        nonisolated public enum DefaultFirst_Scope {
		            nonisolated public struct hubBuilder_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		                public let hubBuilder: @Sendable (hubBuilder_Values) -> SafeDIScope_Gadget.Hub_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(hubBuilder: @escaping @Sendable (hubBuilder_Values) -> SafeDIScope_Gadget.Hub_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.hubBuilder = hubBuilder
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let top_firstBuilder_Sendable: @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>
		            public let top_secondBuilder: @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(top_firstBuilder_Sendable: @escaping @Sendable (top_firstBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>, top_secondBuilder: @escaping @Sendable (top_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.top_firstBuilder_Sendable = top_firstBuilder_Sendable
		                self.top_secondBuilder = top_secondBuilder
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
		        let __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable = __safeDI_gadgetSendableBuilder.top_firstBuilder_Sendable(SafeDISendableScope_Gadget.top_firstBuilder_Sendable_Values())
		        @inline(never) func __safeDI_top() -> Top {
		            let __safeDI_gadgetSendableBuilder_top_secondBuilder = __safeDI_gadgetSendableBuilder.top_secondBuilder(SafeDISendableScope_Gadget.top_secondBuilder_Values())
		            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
		            @inline(never) func __safeDI_firstBuilder_SubA_first() -> any First {
		                @inline(never) func __safeDI_first() -> DefaultFirst {
		                    @inline(never) @Sendable nonisolated func __safeDI_hubBuilder() -> Hub {
		                        let __safeDI_gadgetSendableBuilder_hubBuilder = __safeDI_gadgetSendableBuilder_top_firstBuilder_Sendable.hubBuilder(SafeDISendableScope_Gadget.DefaultFirst_Scope.hubBuilder_Values())
		                        let __safeDI_gadgetSendableBuilder_relay_secondBuilder = __safeDI_gadgetSendableBuilder_hubBuilder.relay_secondBuilder(SafeDIScope_Gadget.Hub_Scope.relay_secondBuilder_Values())
		                        @inline(never) func __safeDI_relay() -> Relay {
		                            _ = Relay.__safeDI_Relay_8EFA7EEA9C19A38B.self\(seamCallComment(seam: "Relay", module: "Feature"))
		                            @inline(never) func __safeDI_secondBuilder_Relay(up: Relay.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Relay.__safeDI_SecondCarrier<any Second> {
		                                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		                            }
		                            return Relay(__safeDI_secondBuilder: __safeDI_secondBuilder_Relay(up: __safeDI_gadgetSendableBuilder_relay_secondBuilder))
		                        }
		                        let relay: Relay = __safeDI_relay()
		                        return Hub(relay: relay)
		                    }
		                    let hubBuilder = SendableInstantiator<Hub>(__safeDI_hubBuilder)
		                    return DefaultFirst(hubBuilder: hubBuilder)
		                }
		                let first: any First = __safeDI_first()
		                return first
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
		                @inline(never) func __safeDI_second() -> DefaultSecond {
		                    let gadget: any Gadget = __safeDI_top_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
		                    return DefaultSecond(gadget: gadget)
		                }
		                let second: any Second = __safeDI_second()
		                return second
		            }
		            @inline(never) func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
		                .init(subA: __safeDI_firstBuilder_SubA())
		            }
		            @inline(never) func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
		                .init(first: { __safeDI_firstBuilder_SubA_first() })
		            }
		            @inline(never) func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
		                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
		            }
		            @inline(never) @Sendable nonisolated func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
		                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_top_secondBuilder: up.second()) })
		            }
		            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetSendableBuilder_top_secondBuilder))
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_500B8BEE7D8A0017 {}
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
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(top_firstBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultFirst_Scope() }, top_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Top() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultFirst_Scope() -> Host.SafeDISendableScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget> {
		            .init(hubBuilder: { _ in __safeDI_gadgetBuilder_Host_Hub_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Hub_Scope() -> Host.SafeDIScope_Gadget.Hub_Scope.__safeDI_Builder<any Gadget> {
		            .init(relay_secondBuilder: { _ in __safeDI_gadgetBuilder_Host_Relay() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() -> Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = DefaultGadget()
		                return gadget
		            })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Top() -> Top.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_SubB() -> SubB.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(second: { __safeDI_gadgetBuilder_Host_DefaultSecond_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Relay() -> Relay.__safeDI_SecondCarrier<Host.SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>> {
		            .init(subB: __safeDI_gadgetBuilder_Host_SubB())
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_500B8BEE7D8A0017.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The types of a fixture, in the modules that declare them: `Feature` (package `Shop`); `Middle` (package `Mid`), which
	/// depends on it; with `upperTypes`, `Upper` (package `Up`), which depends on both; and `App` (package `Other`), which
	/// depends on every module before it. Each type of the graph conforms to `Sendable` when
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
			upperTypes: [String] = [],
			appTypes: [String] = [],
			rootDeclarations: [String] = ["@Instantiated let host: Host"],
		) {
			upper = upperTypes
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
		/// The types of `Upper` (package `Up`), between `Middle` and `App`, or none, where the fixture has no such module.
		let upper: [String]
		let app: [String]
		let root: String

		var modules: [ModuleFixture] {
			modules(upperFillsEveryPlace: false)
		}

		/// The same graph with every declaration but the root in one module, so no seam has a hole.
		var visibleModules: [ModuleFixture] {
			SafeDIToolSeamBuilderParameterTests.modules(feature: feature + middle + upper + app, app: [root])
		}

		/// The same graph with `App`'s types in the module beneath `App`, `Middle`, so `Host`'s module fills every place its
		/// call of `Top` leads to, or, where the fixture has `Upper`, `Upper`, whose seams then fill every place `Host`
		/// passes up.
		var hostFillsEveryPlaceModules: [ModuleFixture] {
			upper.isEmpty
				? [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
					ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: (middle + app).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [root].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
				]
				: modules(upperFillsEveryPlace: true)
		}

		/// The module beneath `App`, which `hostFillsEveryPlaceModules` moves `App`'s types to.
		var moduleBeneathApp: String {
			upper.isEmpty ? "Middle" : "Upper"
		}

		/// The fixture's modules, with `Upper` where the fixture has it, holding `App`'s types too where
		/// `upperFillsEveryPlace`.
		private func modules(upperFillsEveryPlace: Bool) -> [ModuleFixture] {
			var modules = [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			]
			guard !upper.isEmpty else {
				modules.append(ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (app + [root]).map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]))
				return modules
			}
			let upperTypes = upperFillsEveryPlace ? upper + app : upper
			let appTypes = upperFillsEveryPlace ? [root] : app + [root]
			modules.append(ModuleFixture(name: "Upper", packageName: "Up", swiftFileContent: upperTypes.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]))
			modules.append(ModuleFixture(name: "App", packageName: "Other", swiftFileContent: appTypes.map { "import Feature\nimport Middle\nimport Upper\n\n" + $0 }, dependencies: ["Feature", "Middle", "Upper"]))
			return modules
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
	/// module generates, and the same in the visible build, where the module beneath `App` (`Middle`, `Host`'s module, or
	/// `Upper`) fills every place: the error is at the reader, in `readerFile`, at `readerLineInMiddle` in `Middle`, a line
	/// further down in a module whose files import one more module, and two in one whose files import two more.
	private mutating func expectBothBuildsThrow(
		_ fixture: Fixture,
		readerFile: String = "DefaultGadget.swift",
		readerLineInMiddle: Int,
		diagnostics: (_ readerLocation: String, _ fixtures: [String: FixturePaths]) -> String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async {
		let upperImportCount = fixture.upper.isEmpty ? 0 : 1
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			diagnostics("\(fixtures["App"]![readerFile]):\(readerLineInMiddle + 1 + upperImportCount):5", fixtures)
		}, sourceLocation: sourceLocation) {
			try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: fixture.moduleBeneathApp, diagnostics: { fixtures in
			diagnostics("\(fixtures[fixture.moduleBeneathApp]![readerFile]):\(readerLineInMiddle + upperImportCount):5", fixtures)
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
