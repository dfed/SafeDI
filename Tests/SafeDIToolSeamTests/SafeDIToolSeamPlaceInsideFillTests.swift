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

/// A place inside a fill: `Outer` fills `Inner`'s hole with a type whose tree holds a hole `Outer` cannot fill. `Outer`'s
/// enum has one case per call and builder filled, `<call>_<builder>`, holding `Outer`'s level, the scope value `Inner`
/// handed the fill, and the enum of the type the fill builds, nested by type; a fill `App` generates for the place reads a
/// value `Inner`'s levels hold through one reader per enum of `Inner`'s that leads to it, and the value `Outer`'s levels,
/// or its own scope, hold where a route of `Inner`'s holds none. Each test compiles every module and compares the values
/// the seams build with those of the same graph built inline.
struct SafeDIToolSeamPlaceInsideFillTests: ~Copyable {
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
	mutating func generate_nestsPlaceInsideFillByType_whenOuterFillsInnersHoleWithTypeHoldingHoleItCannotFill() async throws {
		// The design's example. `Inner` builds `service` at its root and in the `Screen` its `screenBuilder` builds, which
		// forwards `id`. `Outer` fills both with `DefaultService`, whose `gadget` only `App` can build: one case of
		// `Outer`'s root, `inner_serviceBuilder`, holds `Outer`'s level, `Inner`'s scope, and `DefaultService_Scope`. `App`'s
		// `LiveGadget` reads `id`, which only the `screenBuilder` route of `Inner`'s holds: the reader finds it there, and the
		// root dispatcher passes `nil`, as inline, on the other.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultService_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let tag = Tag()
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_C5CF4A1EC903198D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_3FF816B8F02AA356 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(tag: tag, id: id)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?, tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id, tag: tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id, tag: tag) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_3FF816B8F02AA356.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(id: nil, tag: values.tag) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func placesQuery_followsEachFillOnAPlacesRoutesIntoTheCaseItFills_whenOneFillTypeFillsPlacesOfTwoOfInnersCases() async throws {
		// `Outer` fills `Inner`'s `service` at `Inner`'s root and in its `Screen` with `DefaultService`, whose `gadget` only
		// `App` can build: `Outer`'s place `gadget` is one case reached through two fills, each of a place of another case of
		// `Inner`'s graph. Only the `Screen` case's route declares `id`, so a fill `App` generates for `gadget` reads it there
		// and from `Outer`'s own scope on the other route, which the called cases' answers say.
		let (stream, continuation) = AsyncStream.makeStream(of: SeamSignature.Places.Observation.self)
		_ = try await SeamPlaceLevels.$observer.withValue({ placeLevels in
			if let observation = placeLevels.placesObservation, observation.seamType.asSource == "Outer" {
				continuation.yield(observation)
			}
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
					middle: [
						Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
						seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
					],
					app: Self.appFillingGadget,
				),
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var observations = [SeamSignature.Places.Observation]()
		for await observation in stream {
			observations.append(observation)
		}
		let observation = try #require(observations.first)
		#expect(observation.places.cases.count == 1)
		let query = SeamSignature.Places.Query(of: observation.places, calledPlaces: observation.calledPlaces(of:))
		let filledCases = query.filledCases(onRoutesTo: 0)
		#expect(filledCases.map { observation.places.levels[$0.fillLevel].key.filledCase?.seamType.asSource } == ["Inner", "Inner"])
		#expect(Set(filledCases.map(\.filledCase.caseIndex)).count == 2)
		#expect(Set(filledCases.map { $0.filledCase.query.answers(ofLabel: "id", at: $0.filledCase.caseIndex) == [.callersOwn] }) == [true, false])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsEveryBuilderAndStructOverTheMostExplicitSpelling_whenPlacesInsideFillSpellTheirTypeWithAndWithoutAny() async throws {
		// `DefaultService` holds six places of `Gadget`: the last it declares spells `any Gadget`, the others `Gadget`. Every
		// builder, struct and level function is over `any Gadget`, the most explicit spelling, whatever the places are named:
		// each rotation of the six labels over the six declarations generates the same code once each label is read back as
		// the position of its declaration, and the guard, which hashes the labels, as one name.
		var generatedByRotation = [String]()
		for rotation in Self.sixLabels.indices {
			let labels = Array(Self.sixLabels[rotation...] + Self.sixLabels[..<rotation])
			let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feature: Self.inner(screen: ["@Forwarded public let id: Int"]), middle: Self.middleSpellingGadgetSixWays(labels: labels), app: Self.appFillingGadget), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			var generated = ["Middle", "App"].map { output.modules[$0]?.generatedFiles["\($0).swift"] ?? "" }.joined(separator: "\n")
			for (position, label) in labels.enumerated() {
				generated = generated.replacingOccurrences(of: label, with: "place\(position)")
			}
			generatedByRotation.append(generated.replacingOccurrences(of: "__safeDI_Outer_[0-9A-F]{16}", with: "__safeDI_Outer_guard", options: .regularExpression))
		}
		#expect(Set(generatedByRotation).count == 1)
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: Self.middleSpellingGadgetSixWays(labels: Self.sixLabels),
			app: Self.appFillingGadget,
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct uniform_Values {}

			            nonisolated public struct victor_Values {
			                public let uniform: Gadget
			            }

			            nonisolated public struct whiskey_Values {
			                public let uniform: Gadget
			                public let victor: Gadget
			            }

			            nonisolated public struct xray_Values {
			                public let uniform: Gadget
			                public let victor: Gadget
			                public let whiskey: Gadget
			            }

			            nonisolated public struct yankee_Values {
			                public let uniform: Gadget
			                public let victor: Gadget
			                public let whiskey: Gadget
			                public let xray: Gadget
			            }

			            nonisolated public struct zulu_Values {
			                public let uniform: Gadget
			                public let victor: Gadget
			                public let whiskey: Gadget
			                public let xray: Gadget
			                public let yankee: Gadget
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let uniform: (uniform_Values) -> __safeDI_Built
			                public let victor: (victor_Values) -> __safeDI_Built
			                public let whiskey: (whiskey_Values) -> __safeDI_Built
			                public let xray: (xray_Values) -> __safeDI_Built
			                public let yankee: (yankee_Values) -> __safeDI_Built
			                public let zulu: (zulu_Values) -> __safeDI_Built

			                public init(uniform: @escaping (uniform_Values) -> __safeDI_Built, victor: @escaping (victor_Values) -> __safeDI_Built, whiskey: @escaping (whiskey_Values) -> __safeDI_Built, xray: @escaping (xray_Values) -> __safeDI_Built, yankee: @escaping (yankee_Values) -> __safeDI_Built, zulu: @escaping (zulu_Values) -> __safeDI_Built) {
			                    self.uniform = uniform
			                    self.victor = victor
			                    self.whiskey = whiskey
			                    self.xray = xray
			                    self.yankee = yankee
			                    self.zulu = zulu
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(uniform: { _ in __safeDI_builder() }, victor: { _ in __safeDI_builder() }, whiskey: { _ in __safeDI_builder() }, xray: { _ in __safeDI_builder() }, yankee: { _ in __safeDI_builder() }, zulu: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_C5CF4A1EC903198D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let uniform: Gadget = __safeDI_inner_serviceBuilder.uniform(SafeDIScope_Gadget.DefaultService_Scope.uniform_Values())
			                    let victor: Gadget = __safeDI_inner_serviceBuilder.victor(SafeDIScope_Gadget.DefaultService_Scope.victor_Values(uniform: uniform))
			                    let whiskey: Gadget = __safeDI_inner_serviceBuilder.whiskey(SafeDIScope_Gadget.DefaultService_Scope.whiskey_Values(uniform: uniform, victor: victor))
			                    let xray: Gadget = __safeDI_inner_serviceBuilder.xray(SafeDIScope_Gadget.DefaultService_Scope.xray_Values(uniform: uniform, victor: victor, whiskey: whiskey))
			                    let yankee: Gadget = __safeDI_inner_serviceBuilder.yankee(SafeDIScope_Gadget.DefaultService_Scope.yankee_Values(uniform: uniform, victor: victor, whiskey: whiskey, xray: xray))
			                    let zulu: any Gadget = __safeDI_inner_serviceBuilder.zulu(SafeDIScope_Gadget.DefaultService_Scope.zulu_Values(uniform: uniform, victor: victor, whiskey: whiskey, xray: xray, yankee: yankee))
			                    return DefaultService(uniform: uniform, victor: victor, whiskey: whiskey, xray: xray, yankee: yankee, zulu: zulu)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let uniform: Gadget = __safeDI_inner_serviceBuilder.uniform(SafeDIScope_Gadget.DefaultService_Scope.uniform_Values())
			                    let victor: Gadget = __safeDI_inner_serviceBuilder.victor(SafeDIScope_Gadget.DefaultService_Scope.victor_Values(uniform: uniform))
			                    let whiskey: Gadget = __safeDI_inner_serviceBuilder.whiskey(SafeDIScope_Gadget.DefaultService_Scope.whiskey_Values(uniform: uniform, victor: victor))
			                    let xray: Gadget = __safeDI_inner_serviceBuilder.xray(SafeDIScope_Gadget.DefaultService_Scope.xray_Values(uniform: uniform, victor: victor, whiskey: whiskey))
			                    let yankee: Gadget = __safeDI_inner_serviceBuilder.yankee(SafeDIScope_Gadget.DefaultService_Scope.yankee_Values(uniform: uniform, victor: victor, whiskey: whiskey, xray: xray))
			                    let zulu: any Gadget = __safeDI_inner_serviceBuilder.zulu(SafeDIScope_Gadget.DefaultService_Scope.zulu_Values(uniform: uniform, victor: victor, whiskey: whiskey, xray: xray, yankee: yankee))
			                    return DefaultService(uniform: uniform, victor: victor, whiskey: whiskey, xray: xray, yankee: yankee, zulu: zulu)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_CED265E91827AB4A {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope() -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(
			                uniform: { _ in
			                    let uniform: Gadget = LiveGadget()
			                    return uniform
			                },
			                victor: { _ in
			                    let victor: Gadget = LiveGadget()
			                    return victor
			                },
			                whiskey: { _ in
			                    let whiskey: Gadget = LiveGadget()
			                    return whiskey
			                },
			                xray: { _ in
			                    let xray: Gadget = LiveGadget()
			                    return xray
			                },
			                yankee: { _ in
			                    let yankee: Gadget = LiveGadget()
			                    return yankee
			                },
			                zulu: { _ in
			                    let zulu: any Gadget = LiveGadget()
			                    return zulu
			                }
			            )
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope() })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope() })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_CED265E91827AB4A.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_nestsEachTypeInsideFillByType_whenPlaceIsTwoTypesDeepInsideFill() async throws {
		// `DefaultService` builds `tool`, then `widget`, whose `Widget` builds `gadget`: `DefaultService_Scope`'s case
		// `widget` carries `tool` and holds `Widget_Scope`. `LiveGadget` reads `tool` from that level, `tag` from `Outer`'s,
		// and `id` through the reader of `Inner`'s.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Tool", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Widget", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let tool: Tool", "@Instantiated public let widget: Widget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let tag: Tag", "@Received public let tool: Tool", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(3)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct widget_Values {
			                public let tool: Tool
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let widget: (widget_Values) -> SafeDIScope_Gadget.Widget_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(widget: @escaping (widget_Values) -> SafeDIScope_Gadget.Widget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.widget = widget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(widget: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum Widget_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let tag = Tag()
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_C5CF4A1EC903198D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let tool = Tool()
			                    let __safeDI_gadgetBuilder_widget = __safeDI_inner_serviceBuilder.widget(SafeDIScope_Gadget.DefaultService_Scope.widget_Values(tool: tool))
			                    func __safeDI_widget() -> Widget {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_widget.gadget(SafeDIScope_Gadget.Widget_Scope.gadget_Values())
			                        return Widget(gadget: gadget)
			                    }
			                    let widget: Widget = __safeDI_widget()
			                    return DefaultService(tool: tool, widget: widget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let tool = Tool()
			                    let __safeDI_gadgetBuilder_widget = __safeDI_inner_serviceBuilder.widget(SafeDIScope_Gadget.DefaultService_Scope.widget_Values(tool: tool))
			                    func __safeDI_widget() -> Widget {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_widget.gadget(SafeDIScope_Gadget.Widget_Scope.gadget_Values())
			                        return Widget(gadget: gadget)
			                    }
			                    let widget: Widget = __safeDI_widget()
			                    return DefaultService(tool: tool, widget: widget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_908A2AF9AE3F249D {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(widget: { values in __safeDI_gadgetBuilder_Outer_Widget_Scope(id: id, tag: tag, tool: values.tool) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Widget_Scope(id: Int?, tag: Tag, tool: Tool) -> Outer.SafeDIScope_Gadget.Widget_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(tag: tag, tool: tool, id: id)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?, tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id, tag: tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id, tag: tag) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_908A2AF9AE3F249D.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(id: nil, tag: values.tag) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsCallsCaseInFulfillersEnum_whenPlaceIsInsideFillOfCallInsideFill() async throws {
		// `DefaultService`, which fills `Inner`'s hole, calls `Part`'s seam `Holder`, whose hole `Outer` fills with
		// `DefaultPart`, whose `gadget` only `App` can build: `DefaultService_Scope` has the case `holder_partBuilder`, which
		// holds `Holder`'s scope and `DefaultPart_Scope`. `LiveGadget` reads `label` through the reader of `Holder`'s levels
		// and `id` through the reader of `Inner`'s.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]) + [
				"public protocol Part {}",
				seamFixtureType(named: "Label", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Holder", isSeam: true, declarations: ["@Instantiated public let label: Label", "@Instantiated public let part: any Part"]),
			],
			middle: [
				Self.fulfillingType(named: "DefaultPart", fulfilling: "Part", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let holder: Holder"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let label: Label", "@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(5)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct holder_partBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let holder_partBuilder: (holder_partBuilder_Values) -> Holder.__safeDI_PartCarrier<SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(holder_partBuilder: @escaping (holder_partBuilder_Values) -> Holder.__safeDI_PartCarrier<SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.holder_partBuilder = holder_partBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(holder_partBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultPart_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_C5CF4A1EC903198D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_gadgetBuilder_holder_partBuilder = __safeDI_inner_serviceBuilder.holder_partBuilder(SafeDIScope_Gadget.DefaultService_Scope.holder_partBuilder_Values())
			                    func __safeDI_holder() -> Holder {
			                        _ = Holder.__safeDI_Holder_3693FA84BE06C19C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                        func __safeDI_partBuilder_Holder_part(_ scope_label: Label, __safeDI_holder_partBuilder: SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>) -> any Part {
			                            func __safeDI_part() -> DefaultPart {
			                                let gadget: any Gadget = __safeDI_holder_partBuilder.gadget(SafeDIScope_Gadget.DefaultPart_Scope.gadget_Values())
			                                return DefaultPart(gadget: gadget)
			                            }
			                            let part: any Part = __safeDI_part()
			                            return part
			                        }
			                        func __safeDI_partBuilder_Holder(up: Holder.__safeDI_PartCarrier<SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>>) -> Holder.__safeDI_PartCarrier<any Part> {
			                            .init(part: { scope_label in __safeDI_partBuilder_Holder_part(scope_label, __safeDI_holder_partBuilder: up.part(scope_label)) })
			                        }
			                        return Holder(__safeDI_partBuilder: __safeDI_partBuilder_Holder(up: __safeDI_gadgetBuilder_holder_partBuilder))
			                    }
			                    let holder: Holder = __safeDI_holder()
			                    return DefaultService(holder: holder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_gadgetBuilder_holder_partBuilder = __safeDI_inner_serviceBuilder.holder_partBuilder(SafeDIScope_Gadget.DefaultService_Scope.holder_partBuilder_Values())
			                    func __safeDI_holder() -> Holder {
			                        _ = Holder.__safeDI_Holder_3693FA84BE06C19C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                        func __safeDI_partBuilder_Holder_part(_ scope_label: Label, __safeDI_holder_partBuilder: SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>) -> any Part {
			                            func __safeDI_part() -> DefaultPart {
			                                let gadget: any Gadget = __safeDI_holder_partBuilder.gadget(SafeDIScope_Gadget.DefaultPart_Scope.gadget_Values())
			                                return DefaultPart(gadget: gadget)
			                            }
			                            let part: any Part = __safeDI_part()
			                            return part
			                        }
			                        func __safeDI_partBuilder_Holder(up: Holder.__safeDI_PartCarrier<SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>>) -> Holder.__safeDI_PartCarrier<any Part> {
			                            .init(part: { scope_label in __safeDI_partBuilder_Holder_part(scope_label, __safeDI_holder_partBuilder: up.part(scope_label)) })
			                        }
			                        return Holder(__safeDI_partBuilder: __safeDI_partBuilder_Holder(up: __safeDI_gadgetBuilder_holder_partBuilder))
			                    }
			                    let holder: Holder = __safeDI_holder()
			                    return DefaultService(holder: holder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_9E647B962487672B {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(holder_partBuilder: { _ in __safeDI_gadgetBuilder_Outer_Holder(id: id) })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultPart_Scope(id: Int?, label: Label) -> Outer.SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(label: label, id: id)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Holder(id: Int?) -> Holder.__safeDI_PartCarrier<Outer.SafeDIScope_Gadget.DefaultPart_Scope.__safeDI_Builder<any Gadget>> {
			            .init(part: { values_label in __safeDI_gadgetBuilder_Outer_DefaultPart_Scope(id: id, label: values_label) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_9E647B962487672B.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(id: nil) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsOuterLevelWhereNoInnerLevelHoldsValue_whenOneRouteOfInnersHoldsIt() async throws {
		// `Screen` forwards `session`, and `Outer` builds its own before `inner`: on the `screenBuilder` route `LiveGadget`
		// reads `Screen`'s, nearer, and on the other `Outer`'s, which `Outer`'s level carries.
		try await expectPlaceInsideFill(
			feature: [seamFixtureType(named: "Session", isFinalClass: true, declarations: [])] + Self.inner(screen: ["@Forwarded public let session: Session"]),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let session: Session", "@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let session: Session"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(Session())")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public let session: Session
			        }

			        nonisolated public enum DefaultService_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let session = Session()
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(session: session))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_BFB299D0D3FCD981.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_session: Session, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_session in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_session, __safeDI_inner_serviceBuilder: up.service(scope_session)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(session: session, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_08BE4F8528B74558 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(session: values.session) })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: Session) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(session: session)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(session: Session) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: session) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_session in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: values_session) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_08BE4F8528B74558.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsCallersDeclarationWhereNoLevelHoldsValue_whenOneRouteOfInnersHoldsIt() async throws {
		// As above, but `Outer` builds no `session`: on the `service` route no level holds it, so the root dispatcher passes
		// `Root`'s, as inline.
		try await expectPlaceInsideFill(
			feature: [seamFixtureType(named: "Session", isFinalClass: true, declarations: [])] + Self.inner(screen: ["@Forwarded public let session: Session"]),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let session: Session"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let session: Session", "@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(Session())")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_BFB299D0D3FCD981.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_session: Session, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_session in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_session, __safeDI_inner_serviceBuilder: up.service(scope_session)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_E3A1642416DBF4A5 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: Session) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(session: session)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(session: Session) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: session) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_session in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: values_session) })
			        }
			        let session = Session()
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_E3A1642416DBF4A5.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(session: session) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(session: session, outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsInnersSendableScopeInSendableCase_whenFillOfPlaceInsideSendableFunctionHoldsPlace() async throws {
		// `Inner` builds `Screen` in a `SendableInstantiator`, so its `service` there is built by `Inner`'s `@Sendable`
		// builder and `Outer`'s fill of it is `@Sendable`: the `gadget` inside it is a case of `Outer`'s `@Sendable` enum,
		// `inner_serviceSendableBuilder`, which holds `Inner`'s `@Sendable` scope and `DefaultService_Scope`, and carries
		// no value `Outer` binds outside the fill. `LiveGadget` reads `id` through the readers of `Inner`'s `@Sendable` enum
		// and of the plain enum it holds.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"], innerScreenBuilder: "SendableInstantiator<Screen>", conformances: ", Sendable"),
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable"),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"], conformances: ", Sendable"),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct inner_serviceSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let inner_serviceSendableBuilder: @Sendable (inner_serviceSendableBuilder_Values) -> Inner.__safeDI_ServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceSendableBuilder: @escaping @Sendable (inner_serviceSendableBuilder_Values) -> Inner.__safeDI_ServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceSendableBuilder = inner_serviceSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(inner_serviceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            let __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder = __safeDI_gadgetSendableBuilder.inner_serviceSendableBuilder(SafeDISendableScope_Gadget.inner_serviceSendableBuilder_Values())
			            _ = Inner.__safeDI_Inner_5772275E3504664C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: SendableInstantiator<Screen>, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceSendableBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceSendableBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder: up.service(scope_screenBuilder)) })
			            }
			            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Inner(up: Inner.__safeDI_ServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceSendableCarrier<any Service> {
			                .init(screenBuilder: { __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceSendableBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceSendableBuilder: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), __safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Inner(up: __safeDI_gadgetSendableBuilder_inner_serviceSendableBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_C67A5A3C8B8E00F3 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            })
			        }
			        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Outer() -> Outer.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_serviceSendableBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_SafeDISendableCarrierScope_Service() })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Service(id: Int?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id) })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner_SafeDISendableCarrierScope_Service() -> Inner.__safeDI_ServiceSendableCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: { __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_C67A5A3C8B8E00F3.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner_SafeDICarrierScope_Service(id: nil) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer(), __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsPlaceTheValueTheFunctionWasPassed_whenPlaceInsideFillIsBeneathCycleThatTakesCycleParameter() async throws {
		// The graph fuzzer's seed 605 inside a fill, by the ruling that a place built inside a function that takes cycle
		// parameters carries that function's values, never the caller's. `DefaultService` builds `T` and `C`, each of which
		// builds the other; `T`'s `reader` receives `mark`, so the function that builds `DefaultService`'s `T` takes it,
		// while the `T` that its `C` builds reads `C`'s. `T_Scope`'s level carries `mark` bound from the parameter where the
		// function takes it, and from `C`'s where it does not.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Api {}",
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
			],
			middle: [
				seamFixtureType(named: "Mark", declarations: []),
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "T", declarations: ["@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe(
				name: "T's api at each build",
				expression: """
				{ () -> [String] in
				    let service = Root().outer.inner.service as! DefaultService
				    let t = service.tBuilder.instantiate()
				    return [t.api, t.cBuilder.instantiate().tBuilder.instantiate().api, service.cBuilder.instantiate().tBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			)],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Api {
			        nonisolated public struct inner_serviceBuilder_Values {
			            public var mark: Mark? { __safeDI_mark.instance }
			            public let __safeDI_mark: LazilyInstantiated<Mark?>

			            init(mark: LazilyInstantiated<Mark?>) {
			                __safeDI_mark = mark
			            }
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct tBuilder_Values {}

			            nonisolated public struct cBuilder_Values {
			                public let tBuilder: Instantiator<T>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let tBuilder: (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>
			                public let cBuilder: (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(tBuilder: @escaping (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>, cBuilder: @escaping (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.tBuilder = tBuilder
			                    self.cBuilder = cBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, cBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum T_Scope {
			            nonisolated public struct cBuilder_Values {
			                public let mark: Mark?
			                public let reader: MarkReader
			            }

			            nonisolated public struct api_Values {
			                public let mark: Mark?
			                public let reader: MarkReader
			                public let cBuilder: Instantiator<C>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let cBuilder: (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>
			                public let api: (api_Values) -> __safeDI_Built

			                public init(cBuilder: @escaping (cBuilder_Values) -> SafeDIScope_Api.C_Scope.__safeDI_Builder<__safeDI_Built>, api: @escaping (api_Values) -> __safeDI_Built) {
			                    self.cBuilder = cBuilder
			                    self.api = api
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(cBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, api: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        nonisolated public enum C_Scope {
			            nonisolated public struct tBuilder_Values {
			                public let mark: Mark
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let tBuilder: (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(tBuilder: @escaping (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.tBuilder = tBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(tBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Api.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Api.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
			        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
			        let __safeDI_apiBuilder_inner_serviceBuilder = __safeDI_apiBuilder.inner_serviceBuilder(SafeDIScope_Api.inner_serviceBuilder_Values(mark: mark))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: SafeDIScope_Api.DefaultService_Scope.__safeDI_Builder<any Api>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_apiBuilder_tBuilder = __safeDI_inner_serviceBuilder.tBuilder(SafeDIScope_Api.DefaultService_Scope.tBuilder_Values())
			                    func __safeDI_tBuilder(mark: Mark?) -> T {
			                        let reader = MarkReader(mark: mark)
			                        func __safeDI_cBuilder() -> C {
			                            let mark = Mark()
			                            let tBuilder = Instantiator<T> {
			                                __safeDI_tBuilder(mark: mark)
			                            }
			                            return C(mark: mark, tBuilder: tBuilder)
			                        }
			                        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                        let api: any Api = __safeDI_apiBuilder_tBuilder.api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))
			                        return T(reader: reader, cBuilder: cBuilder, api: api)
			                    }
			                    let tBuilder = Instantiator<T> {
			                        __safeDI_tBuilder(mark: mark.instance)
			                    }
			                    let __safeDI_apiBuilder_cBuilder = __safeDI_inner_serviceBuilder.cBuilder(SafeDIScope_Api.DefaultService_Scope.cBuilder_Values(tBuilder: tBuilder))
			                    func __safeDI_cBuilder() -> C {
			                        let mark = Mark()
			                        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark))
			                        func __safeDI_tBuilder() -> T {
			                            let reader = MarkReader(mark: mark)
			                            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                            let api: any Api = __safeDI_apiBuilder_tBuilder.api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))
			                            return T(reader: reader, cBuilder: cBuilder, api: api)
			                        }
			                        let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			                        return C(mark: mark, tBuilder: tBuilder)
			                    }
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    return DefaultService(tBuilder: tBuilder, cBuilder: cBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Api.DefaultService_Scope.__safeDI_Builder<any Api>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: up.service()) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_apiBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_FE00A572427877A6 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_apiBuilder_Outer() -> Outer.SafeDIScope_Api.__safeDI_Builder<any Api> {
			            .init(inner_serviceBuilder: { _ in __safeDI_apiBuilder_Outer_Inner() })
			        }
			        func __safeDI_apiBuilder_Outer_DefaultService_Scope() -> Outer.SafeDIScope_Api.DefaultService_Scope.__safeDI_Builder<any Api> {
			            .init(tBuilder: { _ in __safeDI_apiBuilder_Outer_T_Scope() }, cBuilder: { _ in __safeDI_apiBuilder_Outer_C_Scope() })
			        }
			        func __safeDI_apiBuilder_Outer_T_Scope() -> Outer.SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api> {
			            .init(
			                cBuilder: { _ in __safeDI_apiBuilder_Outer_C_Scope() },
			                api: { scope in
			                    let mark = scope.mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            )
			        }
			        func __safeDI_apiBuilder_Outer_C_Scope() -> Outer.SafeDIScope_Api.C_Scope.__safeDI_Builder<any Api> {
			            .init(tBuilder: { _ in __safeDI_apiBuilder_Outer_T_Scope() })
			        }
			        func __safeDI_apiBuilder_Outer_Inner() -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Api.DefaultService_Scope.__safeDI_Builder<any Api>> {
			            .init(service: { __safeDI_apiBuilder_Outer_DefaultService_Scope() })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_FE00A572427877A6.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesCallsCaseAndInnerScopeApart_whenPlaceAndBuilderFunctionHaveTheirName() async throws {
		// `Outer`'s place `inner_serviceBuilder` keeps its label, so the case of `inner` for `serviceBuilder` takes `_`, as
		// does the payload binding named after it; `DefaultService`'s builder function of its own `inner_serviceBuilder`
		// would hide the inner scope's parameter inside the fill, so that takes `_` too.
		try await expectPlaceInsideFill(
			feature: Self.inner(screen: ["@Forwarded public let id: Int"]),
			middle: [
				seamFixtureType(named: "Widget", declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let inner_serviceBuilder: Instantiator<Widget>", "@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner", "@Instantiated public let inner_serviceBuilder: any Gadget"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(2)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder__Values {}

			        nonisolated public struct inner_serviceBuilder_Values {
			            public let inner: Inner
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct gadget_Values {
			                public let inner_serviceBuilder: Instantiator<Widget>
			            }

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
			            public let inner_serviceBuilder_: (inner_serviceBuilder__Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> __safeDI_Built

			            public init(inner_serviceBuilder_: @escaping (inner_serviceBuilder__Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> __safeDI_Built) {
			                self.inner_serviceBuilder_ = inner_serviceBuilder_
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder_: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, inner_serviceBuilder: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder_ = __safeDI_gadgetBuilder.inner_serviceBuilder_(SafeDIScope_Gadget.inner_serviceBuilder__Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_C5CF4A1EC903198D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_screenBuilder: Instantiator<Screen>, __safeDI_inner_serviceBuilder_: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_inner_serviceBuilder() -> Widget {
			                        Widget()
			                    }
			                    let inner_serviceBuilder = Instantiator<Widget>(__safeDI_inner_serviceBuilder)
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder_.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(inner_serviceBuilder: inner_serviceBuilder))
			                    return DefaultService(inner_serviceBuilder: inner_serviceBuilder, gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceBuilder_: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    func __safeDI_inner_serviceBuilder() -> Widget {
			                        Widget()
			                    }
			                    let inner_serviceBuilder = Instantiator<Widget>(__safeDI_inner_serviceBuilder)
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder_.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(inner_serviceBuilder: inner_serviceBuilder))
			                    return DefaultService(inner_serviceBuilder: inner_serviceBuilder, gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), service: { scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_screenBuilder, __safeDI_inner_serviceBuilder_: up.service(scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder_: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder_))
			        }
			        let inner: Inner = __safeDI_inner()
			        let inner_serviceBuilder: any Gadget = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values(inner: inner))
			        self.init(inner: inner, inner_serviceBuilder: inner_serviceBuilder)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_1126F910C29A96FD {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_1126F910C29A96FD.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(
			                    inner_serviceBuilder_: { _ in __safeDI_gadgetBuilder_Outer_Inner(id: nil) },
			                    inner_serviceBuilder: { _ in
			                        let inner_serviceBuilder: any Gadget = LiveGadget(id: nil)
			                        return inner_serviceBuilder
			                    }
			                )
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	// MARK: One case of the inner seam's for several places

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsValueThroughReaderOnRouteThatHoldsIt_whenFirstPlaceOfInnersCaseHoldsNone() async throws {
		// `Inner` builds `Panel` at its root, then in the `Screen` its `screenBuilder` builds, which forwards `id`: one case of
		// `Inner`'s, `Panel_Scope.service`, stands for both places, and `Outer` fills it once. The place inside that fill reads
		// `id` through `Inner`'s scope, which only the `screenBuilder` route holds, though the case's first place, at `Inner`'s
		// root, holds none: `App` passes `nil` on the other route, as inline.
		try await expectPlaceInsideFill(
			feature: Self.panelInner(rootDeclarations: ["@Instantiated public let panel: Panel", "@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			middle: Self.panelMiddle,
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_5D4165CA49C9887C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_Panel_Scope_service(__safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(panel: __safeDI_serviceBuilder_Inner_Panel_Scope(up: up.panel), screenBuilder: { values_panel in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values_panel)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Panel_Scope(up: Inner.__safeDI_ServiceCarrier_Panel<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Panel<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Inner_Panel_Scope_service(__safeDI_inner_serviceBuilder: up.service()) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(panel: { values_id in __safeDI_serviceBuilder_Inner_Panel_Scope(up: up.panel(values_id)) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_6EE1129C869C265E {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(panel: __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope(id: id), screenBuilder: { values_panel in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope(id: Int?) -> Inner.__safeDI_ServiceCarrier_Panel<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(panel: { values_id in __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope(id: values_id) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_6EE1129C869C265E.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(id: nil) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsCallersDeclarationOnRouteThatHoldsNone_whenFirstPlaceOfInnersCaseHoldsTheValue() async throws {
		// As above, with `screenBuilder` declared first, so the case's first place is the one beneath `Screen`, which forwards
		// `session`. `LiveGadget` requires `session`: the reader finds `Screen`'s on that route, and `App` passes `Root`'s own
		// on the route at `Inner`'s root, as inline.
		try await expectPlaceInsideFill(
			feature: Self.panelInner(
				screenDeclarations: ["@Forwarded public let session: Session"],
				rootDeclarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let panel: Panel"],
			),
			middle: Self.panelMiddle,
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let session: Session"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let session: Session", "@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(Session())")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_E3D68725FB914E7F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_Panel_Scope_service(__safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder), panel: { values_screenBuilder in __safeDI_serviceBuilder_Inner_Panel_Scope(up: up.panel(values_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(panel: { values_session in __safeDI_serviceBuilder_Inner_Panel_Scope(up: up.panel(values_session)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Panel_Scope(up: Inner.__safeDI_ServiceCarrier_Panel<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Panel<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Inner_Panel_Scope_service(__safeDI_inner_serviceBuilder: up.service()) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_DE81A6D88D2CA239 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: Session) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(session: session)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(session: Session) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), panel: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope(session: session) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(panel: { values_session in __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope(session: values_session) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope(session: Session) -> Inner.__safeDI_ServiceCarrier_Panel<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope(session: session) })
			        }
			        let session = Session()
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_DE81A6D88D2CA239.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(session: session) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(session: session, outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsValueThroughEveryInnerSeamsReader_whenPlaceIsInsideFillOfPlaceInsideFillOfCaseOfTwoPlaces() async throws {
		// `Top`, in `Upper`, fills `Outer`'s `gadget` with `DefaultGadget`, whose `gizmo` only `App` can build. `Outer`'s case
		// for `gadget` stands for the places inside both of `Inner`'s routes, only one of which holds `id`: `App` reads it
		// through `Outer`'s scope, then `Inner`'s, and passes `nil` on the other route, as inline.
		let feature = Self.inner(screen: ["@Forwarded public let id: Int"]) + ["public protocol Gizmo {}"]
		let middle = [
			Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
			seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
		]
		let upper = [
			Self.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated public let gizmo: any Gizmo"]),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated public let outer: Outer"]),
		]
		let app = [
			Self.fulfillingType(named: "LiveGizmo", fulfilling: "Gizmo", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let top: Top"]),
		]
		func modules(feature: [String], middle: [String], upper: [String], app: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "Upper", packageName: "Other", swiftFileContent: upper.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\nimport Upper\n\n" + $0 }, dependencies: ["Feature", "Middle", "Upper"]),
			]
		}
		let seamModules = modules(feature: feature, middle: middle, upper: upper, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: seamModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		for (module, expected) in [("Upper", """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Top {
		    nonisolated public enum SafeDIScope_Gizmo {
		        nonisolated public struct outer_gadgetBuilder_Values {}

		        nonisolated public enum DefaultGadget_Scope {
		            nonisolated public struct gizmo_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gizmo: (gizmo_Values) -> __safeDI_Built

		                public init(gizmo: @escaping (gizmo_Values) -> __safeDI_Built) {
		                    self.gizmo = gizmo
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(gizmo: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let outer_gadgetBuilder: (outer_gadgetBuilder_Values) -> Outer.SafeDIScope_Gadget.__safeDI_Builder<SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<__safeDI_Built>>

		            public init(outer_gadgetBuilder: @escaping (outer_gadgetBuilder_Values) -> Outer.SafeDIScope_Gadget.__safeDI_Builder<SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<__safeDI_Built>>) {
		                self.outer_gadgetBuilder = outer_gadgetBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(outer_gadgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
		            }
		        }
		    }

		    // SafeDI counts `Gizmo` as `public`: no module it reads declares it narrower. If `Gizmo` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_gizmoBuilder: SafeDIScope_Gizmo.__safeDI_Builder<any Gizmo>) {
		        let __safeDI_gizmoBuilder_outer_gadgetBuilder = __safeDI_gizmoBuilder.outer_gadgetBuilder(SafeDIScope_Gizmo.outer_gadgetBuilder_Values())
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_5758AE54588F96D3.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIScope_Gadget.DefaultService_Scope.gadget_Values, __safeDI_outer_gadgetBuilder: SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>) -> any Gadget {
		                func __safeDI_gadget() -> DefaultGadget {
		                    let gizmo: any Gizmo = __safeDI_outer_gadgetBuilder.gizmo(SafeDIScope_Gizmo.DefaultGadget_Scope.gizmo_Values())
		                    return DefaultGadget(gizmo: gizmo)
		                }
		                let gadget: any Gadget = __safeDI_gadget()
		                return gadget
		            }
		            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIScope_Gadget.__safeDI_Builder<SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>>) -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values)) })
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(up: Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>>) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, __safeDI_outer_gadgetBuilder: up.gadget(scope)) })
		            }
		            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>>>) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		                .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: up.screenBuilder), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(up: up.service(values_screenBuilder)) })
		            }
		            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>>>) -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		                .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(up: up.service(values_id)) })
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: __safeDI_gizmoBuilder_outer_gadgetBuilder))
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_E07F37CC5AD2056A {}
		}
		"""), ("App", """
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
		        func __safeDI_gizmoBuilder_Top_DefaultGadget_Scope(id: Int?) -> Top.SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo> {
		            .init(gizmo: { _ in
		                let gizmo: any Gizmo = LiveGizmo(id: id)
		                return gizmo
		            })
		        }
		        func __safeDI_gizmoBuilder_Top_Outer(id: Int?) -> Outer.SafeDIScope_Gadget.__safeDI_Builder<Top.SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>> {
		            .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(id: id) })
		        }
		        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<Top.SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>>> {
		            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gizmoBuilder_Top_Outer_DefaultService_Scope(id: id) })
		        }
		        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<Top.SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>>> {
		            .init(service: { values_id in __safeDI_gizmoBuilder_Top_Outer_DefaultService_Scope(id: values_id) })
		        }
		        func __safeDI_gizmoBuilder_Top_Outer_DefaultService_Scope(id: Int?) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<Top.SafeDIScope_Gizmo.DefaultGadget_Scope.__safeDI_Builder<any Gizmo>> {
		            .init(gadget: { _ in __safeDI_gizmoBuilder_Top_DefaultGadget_Scope(id: id) })
		        }
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_E07F37CC5AD2056A.self // If this line does not compile, compile the code SafeDI generates for module Upper into Upper: under Bazel, add Upper’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_gizmoBuilder_Top() -> Top.SafeDIScope_Gizmo.__safeDI_Builder<any Gizmo> {
		                .init(outer_gadgetBuilder: { _ in __safeDI_gizmoBuilder_Top_Outer(id: nil) })
		            }
		            return Top(__safeDI_gizmoBuilder: __safeDI_gizmoBuilder_Top())
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		""")] {
			let generated = output.modules[module]?.generatedFiles["\(module).swift"]
			#expect(generated == generatedFileHeader + expected)
			if let generated, generated != generatedFileHeader + expected {
				Issue.record(Comment(rawValue: "=== \(module).swift\n" + generated.dropFirst(generatedFileHeader.count)))
			}
		}
		guard compileVerificationIsEnabled else { return }
		let inlineModules = modules(feature: inlineFixture(feature), middle: inlineFixture(middle), upper: inlineFixture(upper), app: inlineFixture(app))
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: seamModules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().top.outer.inner.screenBuilder.instantiate(7)")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsNoPayloadOfCallsCase_whenReaderFindsValueOnEveryRouteOfInners() async throws {
		// `Outer`, `Inner` and `Screen` each forward `id`, so every route of `Inner`'s holds one, nearer than `Outer`'s: the
		// case for `innerBuilder` hands the reader's value on and binds no payload of its own.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
			],
			middle: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let innerBuilder: Instantiator<Inner>"]),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: Int"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outerBuilder: Instantiator<Outer>"]),
			],
			probes: [
				DifferentialValueProbe("Root().outerBuilder.instantiate(1).innerBuilder.instantiate(2)"),
				DifferentialValueProbe("Root().outerBuilder.instantiate(1).innerBuilder.instantiate(2).screenBuilder.instantiate(3)"),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct innerBuilder_serviceBuilder_Values {
			            public let id: Int
			        }

			        nonisolated public enum DefaultService_Scope {
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
			            public let innerBuilder_serviceBuilder: (innerBuilder_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(innerBuilder_serviceBuilder: @escaping (innerBuilder_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.innerBuilder_serviceBuilder = innerBuilder_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(innerBuilder_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_id id: Int, __safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_innerBuilder_serviceBuilder = __safeDI_gadgetBuilder.innerBuilder_serviceBuilder(SafeDIScope_Gadget.innerBuilder_serviceBuilder_Values(id: id))
			        func __safeDI_innerBuilder(id: Int) -> Inner {
			            _ = Inner.__safeDI_Inner_2EFF61BDE0ACCBEC.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_id: Int, _ scope_screenBuilder: Instantiator<Screen>, __safeDI_innerBuilder_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_innerBuilder_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_innerBuilder_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_innerBuilder_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: { values_id in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values_id)) }, service: { scope_id, scope_screenBuilder in __safeDI_serviceBuilder_Inner_service(scope_id, scope_screenBuilder, __safeDI_innerBuilder_serviceBuilder: up.service(scope_id, scope_screenBuilder)) })
			            }
			            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_innerBuilder_serviceBuilder: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_id: id, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_innerBuilder_serviceBuilder))
			        }
			        let innerBuilder = Instantiator<Inner> {
			            __safeDI_innerBuilder(id: $0)
			        }
			        self.init(id: id, innerBuilder: innerBuilder)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_BFEC30CB154E8B45 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(innerBuilder_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: { values_id in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() }, service: { values_id, values_screenBuilder in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id) })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id) })
			        }
			        func __safeDI_outerBuilder(id: Int) -> Outer {
			            _ = Outer.__safeDI_Outer_BFEC30CB154E8B45.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_id: id, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outerBuilder = Instantiator<Outer> {
			            __safeDI_outerBuilder(id: $0)
			        }
			        self.init(outerBuilder: outerBuilder)
			    }
			}
			""",
		)
	}

	// MARK: Places a seam the called seam calls passes up

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesCallsCaseAfterSeamThatHoldsPlace_whenCalledSeamPassesUpPlacesOfTwoSeams() async throws {
		// `Inner` builds `service` itself and calls `DeepB` and `DeepA`, which each hold one it passes up. The fill of each holds
		// the scope value of the seam whose tree holds its place – the value every call of that seam hands a fill passed for it
		// – so `Outer` has a case for each seam, named after it: adding a call to `Inner` renames none.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service"]),
				seamFixtureType(named: "DeepB", isSeam: true, declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
				seamFixtureType(named: "DeepA", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let deepB: DeepB", "@Instantiated public let service: any Service", "@Instantiated public let deepA: DeepA"]),
			],
			middle: Self.panelMiddle,
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().outer.inner.deepB.screenBuilder.instantiate(7)")],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
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
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_05A5BD1A78D0E095.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Inner_service(_ scope_deepB: DeepB, _ scope_deepA: DeepA, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Screen_DeepB_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_DeepA_DeepA_service(__safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(deepB: __safeDI_serviceBuilder_DeepB(up: up.deepB), service: { scope_deepB, scope_deepA in __safeDI_serviceBuilder_Inner_service(scope_deepB, scope_deepA, __safeDI_inner_serviceBuilder: up.service(scope_deepB, scope_deepA)) }, deepA: __safeDI_serviceBuilder_DeepA(up: up.deepA))
			            }
			            func __safeDI_serviceBuilder_DeepB(up: DeepB.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> DeepB.__safeDI_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_serviceBuilder_DeepB_Screen_Scope(up: up.screenBuilder))
			            }
			            func __safeDI_serviceBuilder_DeepB_Screen_Scope(up: DeepB.__safeDI_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> DeepB.__safeDI_ServiceCarrier_Screen<any Service> {
			                .init(service: { scope_id in __safeDI_serviceBuilder_Screen_DeepB_Screen_Scope_service(scope_id, __safeDI_inner_serviceBuilder: up.service(scope_id)) })
			            }
			            func __safeDI_serviceBuilder_DeepA(up: DeepA.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> DeepA.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_DeepA_DeepA_service(__safeDI_inner_serviceBuilder: up.service()) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_B0F0C2726CC67185 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(deepB: __safeDI_gadgetBuilder_Outer_DeepB(), service: { values_deepB, values_deepA in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id) }, deepA: __safeDI_gadgetBuilder_Outer_DeepA(id: id))
			        }
			        func __safeDI_gadgetBuilder_Outer_DeepB() -> DeepB.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_DeepB_Screen_Scope())
			        }
			        func __safeDI_gadgetBuilder_Outer_DeepB_Screen_Scope() -> DeepB.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id) })
			        }
			        func __safeDI_gadgetBuilder_Outer_DeepA(id: Int?) -> DeepA.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_B0F0C2726CC67185.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(id: nil) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	// MARK: Fills of one builder that differ in whether they carry the inner scope

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesCaseThatCarriesNoInnerScope_whenOneFillOfBuilderBuildsItsTypeInSendableWrapper() async throws {
		// `Inner`'s `makeService` holds a `DefaultService` in a `SendableErasedInstantiator`, whose `@Sendable` function binds
		// nothing the fill was handed, while the one beneath `Screen` is built in plain code inside `Inner`'s `@Sendable`
		// builder. The two fills of `Outer`'s builder take a case each: only the second carries `Inner`'s scope, which a
		// `@Sendable` function could not capture.
		try await expectPlaceInsideFill(
			feature: [
				"public protocol Service: Sendable {}\npublic protocol Gadget: Sendable {}\npublic struct AnyService: Sendable {\n    public init(_ service: some Service) { self.service = service }\n    public let service: any Service\n}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated(fulfilledByType: \"DefaultService\", erasedToConcreteExistential: true) public let service: AnyService"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let screenBuilder: SendableInstantiator<Screen>", "@Instantiated(fulfilledByType: \"DefaultService\", erasedToConcreteExistential: true) public let makeService: SendableErasedInstantiator<(), AnyService>"], conformances: ", Sendable"),
			],
			middle: [
				seamFixtureType(named: "DefaultService", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Service, Sendable"),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable"),
			],
			app: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?"], conformances: ", Sendable"),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			],
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("Root().outer.inner.screenBuilder.instantiate(7)"),
				DifferentialValueProbe("Root().outer.inner.makeService.instantiate()"),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultService_Scope {
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
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct inner_defaultService_AnyServiceSendableBuilder_Values: Sendable {}

			        nonisolated public struct inner_defaultService_AnyServiceSendableBuilder__Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let inner_defaultService_AnyServiceSendableBuilder: @Sendable (inner_defaultService_AnyServiceSendableBuilder_Values) -> Inner.__safeDI_DefaultService_AnyServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let inner_defaultService_AnyServiceSendableBuilder_: @Sendable (inner_defaultService_AnyServiceSendableBuilder__Values) -> SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(inner_defaultService_AnyServiceSendableBuilder: @escaping @Sendable (inner_defaultService_AnyServiceSendableBuilder_Values) -> Inner.__safeDI_DefaultService_AnyServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, inner_defaultService_AnyServiceSendableBuilder_: @escaping @Sendable (inner_defaultService_AnyServiceSendableBuilder__Values) -> SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.inner_defaultService_AnyServiceSendableBuilder = inner_defaultService_AnyServiceSendableBuilder
			                self.inner_defaultService_AnyServiceSendableBuilder_ = inner_defaultService_AnyServiceSendableBuilder_
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(inner_defaultService_AnyServiceSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, inner_defaultService_AnyServiceSendableBuilder_: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_inner() -> Inner {
			            let __safeDI_gadgetSendableBuilder_inner_defaultService_AnyServiceSendableBuilder = __safeDI_gadgetSendableBuilder.inner_defaultService_AnyServiceSendableBuilder(SafeDISendableScope_Gadget.inner_defaultService_AnyServiceSendableBuilder_Values())
			            _ = Inner.__safeDI_Inner_0568AE4F2C762577.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable nonisolated func __safeDI_defaultService_AnyServiceSendableBuilder_Inner_makeService() -> SendableErasedInstantiator<(), AnyService>.Builder {
			                @Sendable nonisolated func __safeDI_makeService() -> DefaultService {
			                    let __safeDI_gadgetSendableBuilder_inner_defaultService_AnyServiceSendableBuilder_ = __safeDI_gadgetSendableBuilder.inner_defaultService_AnyServiceSendableBuilder_(SafeDISendableScope_Gadget.inner_defaultService_AnyServiceSendableBuilder__Values())
			                    let gadget: any Gadget = __safeDI_gadgetSendableBuilder_inner_defaultService_AnyServiceSendableBuilder_.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                return { _ in AnyService(__safeDI_makeService()) }
			            }
			            @Sendable nonisolated func __safeDI_defaultService_AnyServiceSendableBuilder_Inner_Screen_Scope_service(_ scope_id: Int, __safeDI_inner_defaultService_AnyServiceSendableBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> AnyService {
			                func __safeDI_service() -> DefaultService {
			                    let gadget: any Gadget = __safeDI_inner_defaultService_AnyServiceSendableBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values())
			                    return DefaultService(gadget: gadget)
			                }
			                let service = AnyService(__safeDI_service())
			                return service
			            }
			            @Sendable nonisolated func __safeDI_defaultService_AnyServiceSendableBuilder_Inner(up: Inner.__safeDI_DefaultService_AnyServiceSendableCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_AnyServiceSendableCarrier<AnyService> {
			                .init(screenBuilder: { __safeDI_defaultService_AnyServiceBuilder_Inner_Screen_Scope(up: up.screenBuilder()) }, makeService: { __safeDI_defaultService_AnyServiceSendableBuilder_Inner_makeService() })
			            }
			            @Sendable nonisolated func __safeDI_defaultService_AnyServiceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_DefaultService_AnyServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_AnyServiceCarrier_Screen<AnyService> {
			                .init(service: { scope_id in __safeDI_defaultService_AnyServiceSendableBuilder_Inner_Screen_Scope_service(scope_id, __safeDI_inner_defaultService_AnyServiceSendableBuilder: up.service(scope_id)) })
			            }
			            return Inner(__safeDI_defaultService_AnyServiceSendableBuilder: __safeDI_defaultService_AnyServiceSendableBuilder_Inner(up: __safeDI_gadgetSendableBuilder_inner_defaultService_AnyServiceSendableBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_FDEC3F66328579AB {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget(id: id)
			                return gadget
			            })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner(id: Int?) -> Inner.__safeDI_DefaultService_AnyServiceSendableCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: { __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() }, makeService: { { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id) } })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_DefaultService_AnyServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { values_id in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id) })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_FDEC3F66328579AB.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Outer() -> Outer.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_defaultService_AnyServiceSendableBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(id: nil) }, inner_defaultService_AnyServiceSendableBuilder_: { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: nil) })
			            }
			            return Outer(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_skipsForwardedValueInReadersPattern_whenInnersPlaceIsHeldByInstantiatorThatForwardsValue() async throws {
		// `Inner`'s place is `Screen`'s `serviceBuilder`, an erased instantiator that forwards a `String`, so its case carries
		// the forwarded value after its payload. `Outer` fills it with `DefaultService`, whose `gadget` only `App` can build,
		// and `LiveGadget` reads `id`, which `Screen` forwards: the reader over `Inner`'s `Screen_Scope` binds the payload and
		// skips the forwarded value.
		try await expectPlaceInsideFill(
			feature: Self.forwardingInner(rootDeclarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"]),
			middle: Self.forwardingMiddle,
			app: Self.forwardingApp,
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().outer.inner.screenBuilder.instantiate(4).serviceBuilder.instantiate("n")"#),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_defaultService_ServiceBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct gadget_Values {
			                public let name: String
			            }

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
			            public let inner_defaultService_ServiceBuilder: (inner_defaultService_ServiceBuilder_Values) -> Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_defaultService_ServiceBuilder: @escaping (inner_defaultService_ServiceBuilder_Values) -> Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_defaultService_ServiceBuilder = inner_defaultService_ServiceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_defaultService_ServiceBuilder: { _ in .init(__safeDI_noScope: { _ in .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let tag = Tag()
			        let __safeDI_gadgetBuilder_inner_defaultService_ServiceBuilder = __safeDI_gadgetBuilder.inner_defaultService_ServiceBuilder(SafeDIScope_Gadget.inner_defaultService_ServiceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_05228716944CABE7.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: @escaping ErasedInstantiator<String, SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>.Builder) -> ErasedInstantiator<String, any Service>.Builder {
			                func __safeDI_serviceBuilder(name: String) -> DefaultService {
			                    let __safeDI_inner_defaultService_ServiceBuilder = __safeDI_inner_defaultService_ServiceBuilder(name)
			                    let gadget: any Gadget = __safeDI_inner_defaultService_ServiceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(name: name))
			                    return DefaultService(name: name, gadget: gadget)
			                }
			                return { forwarded in __safeDI_serviceBuilder(name: forwarded) }
			            }
			            func __safeDI_defaultService_ServiceBuilder_Inner(up: Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope(up: up.screenBuilder))
			            }
			            func __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_DefaultService_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_ServiceCarrier_Screen<any Service> {
			                .init(serviceBuilder: { values_id in __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: up.serviceBuilder(values_id)) })
			            }
			            return Inner(__safeDI_defaultService_ServiceBuilder: __safeDI_defaultService_ServiceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_defaultService_ServiceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_A81593A626B0602B {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_defaultService_ServiceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { scope in
			                let name = scope.name
			                let gadget: any Gadget = LiveGadget(id: id, name: name, tag: tag)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_DefaultService_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag))
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.__safeDI_DefaultService_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(serviceBuilder: { values_id in { [level = __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id, tag: tag)] _ in level } })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_A81593A626B0602B.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_skipsForwardedValueInReadersPattern_whenInnerAlsoHoldsPlaceHeldByInstantiatorThatForwardsValueAtItsRoot() async throws {
		// As above, and `Inner` holds the place at its root too, where no level holds `id`: the root's reader returns `nil`
		// there, and `LiveGadget` is handed `nil`, as inline.
		try await expectPlaceInsideFill(
			feature: Self.forwardingInner(rootDeclarations: [
				"@Instantiated public let screenBuilder: Instantiator<Screen>",
				#"@Instantiated(fulfilledByType: "DefaultService") public let serviceBuilder: ErasedInstantiator<String, any Service>"#,
			]),
			middle: Self.forwardingMiddle,
			app: Self.forwardingApp,
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().outer.inner.screenBuilder.instantiate(4).serviceBuilder.instantiate("n")"#),
				DifferentialValueProbe(#"Root().outer.inner.serviceBuilder.instantiate("m")"#),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_defaultService_ServiceBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct gadget_Values {
			                public let name: String
			            }

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
			            public let inner_defaultService_ServiceBuilder: (inner_defaultService_ServiceBuilder_Values) -> Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_defaultService_ServiceBuilder: @escaping (inner_defaultService_ServiceBuilder_Values) -> Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_defaultService_ServiceBuilder = inner_defaultService_ServiceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_defaultService_ServiceBuilder: { _ in .init(__safeDI_noScope: { _ in .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let tag = Tag()
			        let __safeDI_gadgetBuilder_inner_defaultService_ServiceBuilder = __safeDI_gadgetBuilder.inner_defaultService_ServiceBuilder(SafeDIScope_Gadget.inner_defaultService_ServiceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_D4C2754C534E3269.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_defaultService_ServiceBuilder_Inner_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: @escaping ErasedInstantiator<String, SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>.Builder) -> ErasedInstantiator<String, any Service>.Builder {
			                func __safeDI_serviceBuilder(name: String) -> DefaultService {
			                    let __safeDI_inner_defaultService_ServiceBuilder = __safeDI_inner_defaultService_ServiceBuilder(name)
			                    let gadget: any Gadget = __safeDI_inner_defaultService_ServiceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(name: name))
			                    return DefaultService(name: name, gadget: gadget)
			                }
			                return { forwarded in __safeDI_serviceBuilder(name: forwarded) }
			            }
			            func __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: @escaping ErasedInstantiator<String, SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>.Builder) -> ErasedInstantiator<String, any Service>.Builder {
			                func __safeDI_serviceBuilder(name: String) -> DefaultService {
			                    let __safeDI_inner_defaultService_ServiceBuilder = __safeDI_inner_defaultService_ServiceBuilder(name)
			                    let gadget: any Gadget = __safeDI_inner_defaultService_ServiceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(name: name))
			                    return DefaultService(name: name, gadget: gadget)
			                }
			                return { forwarded in __safeDI_serviceBuilder(name: forwarded) }
			            }
			            func __safeDI_defaultService_ServiceBuilder_Inner(up: Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope(up: up.screenBuilder), serviceBuilder: { values_screenBuilder in __safeDI_defaultService_ServiceBuilder_Inner_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: up.serviceBuilder(values_screenBuilder)) })
			            }
			            func __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_DefaultService_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_ServiceCarrier_Screen<any Service> {
			                .init(serviceBuilder: { values_id in __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: up.serviceBuilder(values_id)) })
			            }
			            return Inner(__safeDI_defaultService_ServiceBuilder: __safeDI_defaultService_ServiceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_defaultService_ServiceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_9DC7EC133CA904E6 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int?, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { scope in
			                let name = scope.name
			                let gadget: any Gadget = LiveGadget(id: id, name: name, tag: tag)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(id: Int?, tag: Tag) -> Inner.__safeDI_DefaultService_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag), serviceBuilder: { values_screenBuilder in { _ in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: id, tag: tag) } })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.__safeDI_DefaultService_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(serviceBuilder: { values_id in { [level = __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id, tag: tag)] _ in level } })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_9DC7EC133CA904E6.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_defaultService_ServiceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(id: nil, tag: values.tag) })
			            }
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsInnersMemberWithForwardedTuple_whenInnersPlaceIsHeldByInstantiatorThatForwardsTwoValues() async throws {
		// As above, with `Screen`'s instantiator forwarding `name` and `size`, both of which `DefaultService` forwards: the
		// builder function of the fill hands the function `Inner`'s member returns the labeled tuple the wrapper forwards.
		try await expectPlaceInsideFill(
			feature: Self.forwardingInner(
				rootDeclarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>"],
				serviceBuilderType: "ErasedInstantiator<(name: String, size: Int), any Service>",
			),
			middle: [
				seamFixtureType(named: "DefaultService", isFinalClass: true, declarations: ["@Forwarded public let name: String", "@Forwarded public let size: Int", "@Instantiated public let gadget: any Gadget"], conformances: ", Service")
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Service.self])\n"),
				Self.forwardingMiddle[1],
			],
			app: [
				seamFixtureType(named: "LiveGadget", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) public let id: Int?", "@Received(onlyIfAvailable: true) public let name: String?", "@Received(onlyIfAvailable: true) public let size: Int?", "@Received public let tag: Tag"], conformances: ", Gadget")
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\n"),
				Self.forwardingApp[1],
			],
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().outer.inner.screenBuilder.instantiate(4).serviceBuilder.instantiate((name: "n", size: 2))"#),
			],
			expectedMiddle: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_defaultService_ServiceBuilder_Values {
			            public let tag: Tag
			        }

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct gadget_Values {
			                public let name: String
			                public let size: Int
			            }

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
			            public let inner_defaultService_ServiceBuilder: (inner_defaultService_ServiceBuilder_Values) -> Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_defaultService_ServiceBuilder: @escaping (inner_defaultService_ServiceBuilder_Values) -> Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_defaultService_ServiceBuilder = inner_defaultService_ServiceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_defaultService_ServiceBuilder: { _ in .init(__safeDI_noScope: { _ in .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let tag = Tag()
			        let __safeDI_gadgetBuilder_inner_defaultService_ServiceBuilder = __safeDI_gadgetBuilder.inner_defaultService_ServiceBuilder(SafeDIScope_Gadget.inner_defaultService_ServiceBuilder_Values(tag: tag))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_2C95B4B6EB3E6493.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: @escaping ErasedInstantiator<(name: String, size: Int), SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>.Builder) -> ErasedInstantiator<(name: String, size: Int), any Service>.Builder {
			                func __safeDI_serviceBuilder(name: String, size: Int) -> DefaultService {
			                    let __safeDI_inner_defaultService_ServiceBuilder = __safeDI_inner_defaultService_ServiceBuilder((name: name, size: size))
			                    let gadget: any Gadget = __safeDI_inner_defaultService_ServiceBuilder.gadget(SafeDIScope_Gadget.DefaultService_Scope.gadget_Values(name: name, size: size))
			                    return DefaultService(name: name, size: size, gadget: gadget)
			                }
			                return { forwarded in __safeDI_serviceBuilder(name: forwarded.name, size: forwarded.size) }
			            }
			            func __safeDI_defaultService_ServiceBuilder_Inner(up: Inner.__safeDI_DefaultService_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_ServiceCarrier<any Service> {
			                .init(screenBuilder: __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope(up: up.screenBuilder))
			            }
			            func __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope(up: Inner.__safeDI_DefaultService_ServiceCarrier_Screen<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_DefaultService_ServiceCarrier_Screen<any Service> {
			                .init(serviceBuilder: { values_id in __safeDI_defaultService_ServiceBuilder_Inner_Screen_Scope_serviceBuilder(__safeDI_inner_defaultService_ServiceBuilder: up.serviceBuilder(values_id)) })
			            }
			            return Inner(__safeDI_defaultService_ServiceBuilder: __safeDI_defaultService_ServiceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_defaultService_ServiceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(tag: tag, inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_C8B94190CB69B888 {}
			}
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_defaultService_ServiceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(tag: values.tag) })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: Int, tag: Tag) -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { scope in
			                let name = scope.name
			                let size = scope.size
			                let gadget: any Gadget = LiveGadget(id: id, name: name, size: size, tag: tag)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_DefaultService_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: tag))
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(tag: Tag) -> Inner.__safeDI_DefaultService_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(serviceBuilder: { values_id in { [level = __safeDI_gadgetBuilder_Outer_DefaultService_Scope(id: values_id, tag: tag)] _ in level } })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_C8B94190CB69B888.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
		)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPlaceInsideFillOfCaseOfBothRootEnums_whenInnerBuildsTypeHoldingPlaceInsideAndOutsideSendableFunction(screenInstantiatesMark: Bool) async {
		// `Inner` builds `Panel` at its root and inside the `@Sendable` function of its `screenBuilder`, so `Panel`'s `service`
		// is a case both of `Inner`'s root enums reach. `Outer` fills it with `DefaultService`, whose `gadget` only `App` can
		// build: the one function that fills the case would be handed the values struct of either builder struct, and the
		// member for `gadget` can carry only one, so SafeDI reports the shape.
		let screenDeclarations = ["@Forwarded public let id: Int"] + (screenInstantiatesMark ? ["@Instantiated public let mark: Mark"] : []) + ["@Instantiated public let panel: Panel"]
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			"""
			\(fixtures["Middle"]!["DefaultService.swift"]):9:5: error: SafeDI fills every place of the builder for `Panel`’s `service: any Service` (`service` of `serviceBuilder`) with one function, whose tree builds `DefaultService`’s `gadget: any Gadget`, which no type that module `Middle` can see fulfills. `Inner` builds `Panel` both inside and outside a `@Sendable` function, so that function would be handed the values of either build, and can be handed only one. To fill it, declare an @Instantiable type that fulfills `Gadget` in module `Middle` or a module it lists among its SafeDI dependencies, or declare an @Instantiable type that fulfills `Service` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Panel.swift"]):7:5: note: `Panel` instantiates `service: any Service` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Service: Sendable {}\npublic protocol Gadget: Sendable {}",
						seamFixtureType(named: "Mark", isFinalClass: true, declarations: [], conformances: ", Sendable"),
						seamFixtureType(named: "Panel", declarations: ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
						seamFixtureType(named: "Screen", declarations: screenDeclarations, conformances: ", Sendable"),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let panel: Panel", "@Instantiated public let screenBuilder: SendableInstantiator<Screen>"], conformances: ", Sendable"),
					],
					middle: [
						Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
						seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable"),
					],
					app: [
						Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received(onlyIfAvailable: true) public let id: Int?", "@Received(onlyIfAvailable: true) public let mark: Mark?"], conformances: ", Sendable"),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"], conformances: ", Sendable"),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Inner`, a seam whose `rootDeclarations` build `Panel`, which builds `service`, a hole, at its root, and, through
	/// `screenBuilder`, in the `Screen` it builds, which declares `screenDeclarations` before its own `panel`: one case of
	/// `Inner`'s, `Panel_Scope.service`, stands for both places. Beside it, the protocols `Service` and `Gadget`, and `Session`.
	private static func panelInner(screenDeclarations: [String] = ["@Forwarded public let id: Int"], rootDeclarations: [String]) -> [String] {
		[
			"public protocol Service {}\npublic protocol Gadget {}",
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated public let service: any Service"]),
			seamFixtureType(named: "Screen", declarations: screenDeclarations + ["@Instantiated public let panel: Panel"]),
			seamFixtureType(named: "Inner", isSeam: true, declarations: rootDeclarations),
		]
	}

	/// `Outer`, which calls `Inner`, and `DefaultService`, which fills `Inner`'s `service` and holds `gadget`, a place only
	/// `App` can build.
	private static let panelMiddle = [
		fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
		seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
	]

	/// `Inner`, a seam that builds `service`, a hole, at its root and in the `Screen` its `screenBuilder` builds, which also
	/// declares `screen`; and the protocols `Service` and `Gadget`.
	private static func inner(screen: [String], innerScreenBuilder: String = "Instantiator<Screen>", conformances: String = "") -> [String] {
		[
			"public protocol Service\(conformances.isEmpty ? "" : ": Sendable") {}\npublic protocol Gadget\(conformances.isEmpty ? "" : ": Sendable") {}",
			seamFixtureType(named: "Screen", declarations: screen + ["@Instantiated public let service: any Service"], conformances: conformances),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let screenBuilder: \(innerScreenBuilder)", "@Instantiated public let service: any Service"], conformances: conformances),
		]
	}

	/// `Inner`, a seam whose `Screen` forwards `id` and holds `serviceBuilder`, an erased instantiator of the hole `Service`
	/// that forwards a `String`, or what `serviceBuilderType` forwards, with `rootDeclarations`.
	private static func forwardingInner(rootDeclarations: [String], serviceBuilderType: String = "ErasedInstantiator<String, any Service>") -> [String] {
		[
			"public protocol Service {}\npublic protocol Gadget {}",
			seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded public let id: Int", #"@Instantiated(fulfilledByType: "DefaultService") public let serviceBuilder: "# + serviceBuilderType]),
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: rootDeclarations),
		]
	}

	/// `Outer`, which instantiates `tag` and calls `Inner`, and `DefaultService`, which fills `Inner`'s `serviceBuilder`,
	/// forwards `name` and holds `gadget`, a place only `App` can build.
	private static let forwardingMiddle = [
		seamFixtureType(named: "DefaultService", isFinalClass: true, declarations: ["@Forwarded public let name: String", "@Instantiated public let gadget: any Gadget"], conformances: ", Service")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Service.self])\n"),
		seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
	]

	/// `LiveGadget`, which fills `gadget` and reads `tag`, and `id` and `name` only if available, and `Root`.
	private static let forwardingApp = [
		seamFixtureType(named: "LiveGadget", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) public let id: Int?", "@Received(onlyIfAvailable: true) public let name: String?", "@Received public let tag: Tag"], conformances: ", Gadget")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\n"),
		seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"]),
	]

	/// Six labels, in the order they sort.
	private static let sixLabels = ["uniform", "victor", "whiskey", "xray", "yankee", "zulu"]

	/// `Outer`, which calls `Inner`, and `DefaultService`, which fills `Inner`'s `service` and holds six places of `Gadget`
	/// labeled `labels`, in order, the last spelled `any Gadget` and the others `Gadget`.
	private static func middleSpellingGadgetSixWays(labels: [String]) -> [String] {
		[
			fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: labels.enumerated().map { "@Instantiated public let \($0.element): \($0.offset == labels.count - 1 ? "any Gadget" : "Gadget")" }),
			seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
		]
	}

	/// `LiveGadget`, which fills every place of `Gadget`, and `Root`.
	private static let appFillingGadget = [
		fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: []),
		seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
	]

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String], conformances: String = "") -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)\(conformances)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// `Feature`, which declares `Inner`; `Middle`, which declares `Outer` and what fills `Inner`'s holes; and `App`, which
	/// fills `Outer`'s places inside those fills.
	private static func modules(feature: [String], middle: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}

	/// Expects `Middle`'s and `App`'s generated files to be exactly `expectedMiddle` and `expectedApp`, each after the file
	/// header, and the modules to build, for each of `probes`, the values the same graph builds with no seam, every tree
	/// built inline.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectPlaceInsideFill(
		feature: [String],
		middle: [String],
		app: [String],
		probes: [DifferentialValueProbe],
		expectedMiddle: String,
		expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(feature: feature, middle: middle, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		for (module, expected) in [("Middle", expectedMiddle), ("App", expectedApp)] {
			let generated = output.modules[module]?.generatedFiles["\(module).swift"]
			#expect(generated == generatedFileHeader + expected, sourceLocation: sourceLocation)
			if let generated, generated != generatedFileHeader + expected {
				Issue.record(Comment(rawValue: "=== \(module).swift\n" + generated.dropFirst(generatedFileHeader.count)), sourceLocation: sourceLocation)
			}
		}
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.modules(feature: inlineFixture(feature), middle: inlineFixture(middle), app: inlineFixture(app))
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
