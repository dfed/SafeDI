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

/// The levels of a seam's places (`SeamPlaceLevels`): what each type on a place's path binds before the next property,
/// which read nearest first hold the place's scope struct, and which are the same on every build of the type, because a
/// type's children start in an order that is a fact of the type (`SeamDeclarationGraph`).
struct SafeDIToolSeamPlaceLevelTests: ~Copyable {
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
	mutating func holes_holdEachPlacesScopeStructInItsLevelsNearestFirst_whenAnInnerDeclarationHidesAnOuterOne() async throws {
		let (placeLevels, _) = try await placeLevels(of: [
			"public protocol Gadget {}",
			seamFixtureType(named: "Identifier", declarations: []),
			seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received let session: Session", "@Instantiated let id: Identifier", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", declarations: ["@Instantiated let title: Title", "@Instantiated let panelBuilder: Instantiator<Panel>", "@Instantiated let footer: Footer"]),
			seamFixtureType(named: "Panel", declarations: ["@Forwarded let id: Identifier", "@Instantiated let gadget: any Gadget"]),
			seamFixtureType(named: "Session", declarations: []),
			seamFixtureType(named: "Title", declarations: []),
			seamFixtureType(named: "Footer", declarations: []),
		])

		// The outer `id` is in `Host`'s level, beneath the inner one `Panel` forwards, which the scope struct carries. A
		// sibling that holds no place starts first, so `Screen` binds `footer` before `panelBuilder`.
		#expect(placeLevels.map(Self.rendered) == [
			"""
			Host
			screen.panelBuilder.gadget:
			  Panel before gadget: id: Identifier, gadget: any Gadget (later)
			  Screen before panelBuilder: title: Title, footer: Footer, panelBuilder: Instantiator<Panel> (later)
			  Host before screen: session: Session, id: Identifier, screen: Screen (later)
			  fields: session: Session, title: Title, footer: Footer, id: Identifier
			  uncarried: screen: Screen, panelBuilder: Instantiator<Panel>, gadget: any Gadget
			""",
		])
		#expect(placeLevels.flatMap(\.pathStructMismatches) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func holes_giveEveryBuildOfATypeTheSameLevels_whenOnlyOneBuildOfTheTypeTakesACycleParameter() async throws {
		let (placeLevels, _) = try await placeLevels(of: Self.tangledCycleFilesWithMarkReader)

		// `C`'s `tBuilder` closes the cycle on the function that builds `Hub`'s `T`, whose `reader` receives `mark`, which `C`
		// declares between, so that function takes `mark`; the `T` that `Hub`'s `C` builds takes none and reads `C`'s. The
		// parameter is a fact of the function, which `T`'s levels leave out, and they agree.
		let typeLevels = placeLevels.flatMap(\.places).flatMap(\.levels).filter { $0.builtType == .simple(name: "T", generics: []) && $0.nextProperty?.label == "api" }
		#expect(typeLevels.map { $0.fields.map(\.label) }.contains(["mark", "reader"]))
		#expect(typeLevels.map { $0.fields.map(\.label) }.contains(["reader"]))
		#expect(placeLevels.flatMap { $0.levelDisagreements() } == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func holes_giveEveryBuildOfATypeTheSameLevels_whenTwoInstantiatorsCloseEachOthersCycle() async throws {
		let (placeLevels, _) = try await placeLevels(of: Self.tangledCycleFiles)

		// `T`'s `cBuilder` holds a place, the `C` it builds holding `api`, also on the path where it closes the cycle on
		// `Hub`'s `cBuilder`, so `T` binds nothing before `api` on either path; `C`'s `tBuilder` likewise.
		#expect(placeLevels.map(Self.rendered) == [
			"""
			Hub
			tBuilder.api:
			  T before api: api: any Api (later), cBuilder: Instantiator<C> (later)
			  Hub before tBuilder: tBuilder: Instantiator<T> (later), cBuilder: Instantiator<C> (later)
			  fields: \("")
			  uncarried: tBuilder: Instantiator<T>, api: any Api, cBuilder: Instantiator<C>
			tBuilder.cBuilder.api:
			  C before api: api: any Api (later), tBuilder: Instantiator<T> (later)
			  T before cBuilder: api: any Api, cBuilder: Instantiator<C> (later)
			  Hub before tBuilder: tBuilder: Instantiator<T> (later), cBuilder: Instantiator<C> (later)
			  fields: \("")
			  uncarried: cBuilder: Instantiator<C>, api: any Api, tBuilder: Instantiator<T>
			cBuilder.api:
			  C before api: api: any Api (later), tBuilder: Instantiator<T> (later)
			  Hub before cBuilder: tBuilder: Instantiator<T>, cBuilder: Instantiator<C> (later)
			  fields: \("")
			  uncarried: cBuilder: Instantiator<C>, api: any Api, tBuilder: Instantiator<T>
			cBuilder.tBuilder.api:
			  T before api: api: any Api (later), cBuilder: Instantiator<C> (later)
			  C before tBuilder: api: any Api, tBuilder: Instantiator<T> (later)
			  Hub before cBuilder: tBuilder: Instantiator<T>, cBuilder: Instantiator<C> (later)
			  fields: \("")
			  uncarried: tBuilder: Instantiator<T>, api: any Api, cBuilder: Instantiator<C>
			""",
		])
		#expect(placeLevels.flatMap { $0.levelDisagreements() } == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAPlaceBeforeASiblingThatClosesACycle_whenTheSiblingHoldsAPlaceOnAnotherPath() async throws {
		let (_, output) = try await placeLevels(of: Self.tangledCycleFiles)

		// Each type builds `api` first on every path, so no place is handed the instantiator a sibling closes the cycle with.
		#expect(output.dependencyTreeFiles["Hub+SafeDI.swift"] == generatedFileHeader + """
		extension Hub {
		    @frozen public enum SafeDIScope_Api {
		        case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)
		        case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)

		        public struct tBuilder_Values {}

		        public struct cBuilder_Values {
		            public let tBuilder: Instantiator<T>
		        }

		        @frozen public enum T_Scope {
		            case api(api_Values)
		            indirect case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)

		            public struct api_Values {}

		            public struct cBuilder_Values {
		                public let api: any Api
		            }
		        }

		        @frozen public enum C_Scope {
		            case api(api_Values)
		            indirect case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)

		            public struct api_Values {}

		            public struct tBuilder_Values {
		                public let api: any Api
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
		        let __safeDI_apiValues_tBuilder = SafeDIScope_Api.tBuilder_Values()
		        func __safeDI_tBuilder() -> T {
		            let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values())))
		            let __safeDI_apiValues_cBuilder = SafeDIScope_Api.T_Scope.cBuilder_Values(api: api)
		            func __safeDI_cBuilder() -> C {
		                let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .cBuilder(__safeDI_apiValues_cBuilder, .api(SafeDIScope_Api.C_Scope.api_Values()))))
		                let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		                return C(api: api, tBuilder: tBuilder)
		            }
		            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		            return T(api: api, cBuilder: cBuilder)
		        }
		        let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		        let __safeDI_apiValues_cBuilder = SafeDIScope_Api.cBuilder_Values(tBuilder: tBuilder)
		        func __safeDI_cBuilder() -> C {
		            let api: any Api = __safeDI_apiBuilder(.cBuilder(__safeDI_apiValues_cBuilder, .api(SafeDIScope_Api.C_Scope.api_Values())))
		            let __safeDI_apiValues_tBuilder = SafeDIScope_Api.C_Scope.tBuilder_Values(api: api)
		            func __safeDI_tBuilder() -> T {
		                let api: any Api = __safeDI_apiBuilder(.cBuilder(__safeDI_apiValues_cBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values()))))
		                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                return T(api: api, cBuilder: cBuilder)
		            }
		            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		            return C(api: api, tBuilder: tBuilder)
		        }
		        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		        self.init(tBuilder: tBuilder, cBuilder: cBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_EE5F6BBBC85519A5 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func holes_handAPlaceTheSiblingThatClosesACycle_whenTheSiblingClosesItOnEveryBuild() async throws {
		let (placeLevels, _) = try await placeLevels(of: [
			"public protocol Api {}",
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let api: any Api"]),
		])

		// `Detail`'s `screenBuilder` closes the cycle on every build, `Screen` being above every `Detail`, so it holds no place
		// and starts first, and `Detail`'s `api` is handed it.
		#expect(placeLevels.map(Self.rendered) == [
			"""
			Hub
			screenBuilder.api:
			  Screen before api: api: any Api (later), detail: Detail (later)
			  Hub before screenBuilder: screenBuilder: Instantiator<Screen> (later)
			  fields: \("")
			  uncarried: screenBuilder: Instantiator<Screen>, api: any Api, detail: Detail
			screenBuilder.detail.api:
			  Detail before api: screenBuilder: Instantiator<Screen>, api: any Api (later)
			  Screen before detail: api: any Api, detail: Detail (later)
			  Hub before screenBuilder: screenBuilder: Instantiator<Screen> (later)
			  fields: screenBuilder: Instantiator<Screen>
			  uncarried: detail: Detail, api: any Api
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func holes_giveEveryBuildOfATypeTheSameLevels_whenOneDeclarationOfTheTypeIsAlwaysInsideACycleItsPropertyCloses() async throws {
		let (placeLevels, _) = try await placeLevels(of: Self.typeBuiltInsideAndOutsideACycleFiles)

		// `T`'s `uBuilder` holds a place, the `U` it builds holding `api`, also on the build of `U`'s `otherT`, where it
		// closes the cycle on every build, so both builds of `T` bind `q` before `r`, and nothing else.
		#expect(placeLevels.map(Self.rendered) == [
			"""
			Hub
			tBuilder.r.api:
			  R before api: api: any Api (later)
			  T before r: q: Q, r: R (later), uBuilder: Instantiator<U> (later)
			  Hub before tBuilder: tBuilder: Instantiator<T> (later)
			  fields: q: Q
			  uncarried: tBuilder: Instantiator<T>, r: R, uBuilder: Instantiator<U>, api: any Api
			tBuilder.uBuilder.api:
			  U before api: api: any Api (later), otherT: Instantiator<T> (later)
			  T before uBuilder: q: Q, r: R, uBuilder: Instantiator<U> (later)
			  Hub before tBuilder: tBuilder: Instantiator<T> (later)
			  fields: q: Q, r: R
			  uncarried: tBuilder: Instantiator<T>, uBuilder: Instantiator<U>, api: any Api, otherT: Instantiator<T>
			tBuilder.uBuilder.otherT.r.api:
			  R before api: api: any Api (later)
			  T before r: q: Q, r: R (later), uBuilder: Instantiator<U> (later)
			  U before otherT: api: any Api, otherT: Instantiator<T> (later)
			  T before uBuilder: q: Q, r: R, uBuilder: Instantiator<U> (later)
			  Hub before tBuilder: tBuilder: Instantiator<T> (later)
			  fields: q: Q
			  uncarried: tBuilder: Instantiator<T>, otherT: Instantiator<T>, r: R, uBuilder: Instantiator<U>, api: any Api
			""",
		])
		#expect(placeLevels.flatMap { $0.levelDisagreements() } == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAPlaceBeforeASiblingThatClosesACycle_whenAnotherDeclarationOfItsTypeBuildsTheSiblingOutsideTheCycle() async throws {
		let (_, output) = try await placeLevels(of: Self.typeBuiltInsideAndOutsideACycleFiles)

		// The `T` that `otherT` builds builds `r`, and so `api`, before the `uBuilder` that closes the cycle, as the `T` that
		// `tBuilder` builds does, so the place `api` beneath `otherT` is handed `q` alone.
		#expect(output.dependencyTreeFiles["Hub+SafeDI.swift"] == generatedFileHeader + """
		extension Hub {
		    @frozen public enum SafeDIScope_Api {
		        case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)

		        public struct tBuilder_Values {}

		        @frozen public enum T_Scope {
		            case r(r_Values, SafeDIScope_Api.R_Scope)
		            indirect case uBuilder(uBuilder_Values, SafeDIScope_Api.U_Scope)

		            public struct r_Values {
		                public let q: Q
		            }

		            public struct uBuilder_Values {
		                public let q: Q
		                public let r: R
		            }
		        }

		        @frozen public enum R_Scope {
		            case api(api_Values)

		            public struct api_Values {}
		        }

		        @frozen public enum U_Scope {
		            case api(api_Values)
		            indirect case otherT(otherT_Values, SafeDIScope_Api.T_Scope)

		            public struct api_Values {}

		            public struct otherT_Values {
		                public let api: any Api
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
		        let __safeDI_apiValues_tBuilder = SafeDIScope_Api.tBuilder_Values()
		        func __safeDI_tBuilder() -> T {
		            let q = Q()
		            let __safeDI_apiValues_r = SafeDIScope_Api.T_Scope.r_Values(q: q)
		            func __safeDI_r() -> R {
		                let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .r(__safeDI_apiValues_r, .api(SafeDIScope_Api.R_Scope.api_Values()))))
		                return R(api: api)
		            }
		            let r: R = __safeDI_r()
		            let __safeDI_apiValues_uBuilder = SafeDIScope_Api.T_Scope.uBuilder_Values(q: q, r: r)
		            func __safeDI_uBuilder() -> U {
		                let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .uBuilder(__safeDI_apiValues_uBuilder, .api(SafeDIScope_Api.U_Scope.api_Values()))))
		                let __safeDI_apiValues_otherT = SafeDIScope_Api.U_Scope.otherT_Values(api: api)
		                func __safeDI_otherT() -> T {
		                    let q = Q()
		                    let __safeDI_apiValues_r = SafeDIScope_Api.T_Scope.r_Values(q: q)
		                    func __safeDI_r() -> R {
		                        let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .uBuilder(__safeDI_apiValues_uBuilder, .otherT(__safeDI_apiValues_otherT, .r(__safeDI_apiValues_r, .api(SafeDIScope_Api.R_Scope.api_Values()))))))
		                        return R(api: api)
		                    }
		                    let r: R = __safeDI_r()
		                    let uBuilder = Instantiator<U>(__safeDI_uBuilder)
		                    return T(r: r, uBuilder: uBuilder, q: q)
		                }
		                let otherT = Instantiator<T>(__safeDI_otherT)
		                return U(api: api, otherT: otherT)
		            }
		            let uBuilder = Instantiator<U>(__safeDI_uBuilder)
		            return T(r: r, uBuilder: uBuilder, q: q)
		        }
		        let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		        self.init(tBuilder: tBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_2594C468261123AE {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func collectingPlaceLevelDisagreements_reportsNone_whenAFillsTreeHoldsATangleOfCycles() async throws {
		// `App` fills `Hub`'s `api` with `DefaultApi`, whose tree is built with `Hub`'s stack: in it, `T` and `C` close each
		// other's cycle, a tangle, and each holds `App`'s hole `gadget`. A place inside a fill is a place of the type the fill
		// builds, so the fill's tree starts each type's children in the type's order, as any tree does, and every build of a
		// type binds the same values before `gadget`.
		let (_, disagreements) = try await collectingPlaceLevelDisagreements {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let api: any Api"]),
					],
					app: [
						"public protocol Gadget {}",
						seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated public let gadget: any Gadget", "@Instantiated public let cBuilder: Instantiator<C>"]),
						seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated public let gadget: any Gadget", "@Instantiated public let tBuilder: Instantiator<T>"]),
						seamFixtureType(named: "DefaultApi", declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"], conformances: ", Api")
							.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
						seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated public let hub: Hub"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}

		#expect(disagreements == [])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Hub`'s `tBuilder` builds `T`, whose `uBuilder` builds `U`, whose `otherT` builds `T` again, in which `uBuilder`
	/// closes the cycle on every build: `U` encloses it, so no cycle is tangled, but `T` is built by two declarations, one
	/// of them always inside the cycle. `R` and `U` hold the place `api`; `q` holds none.
	private static let typeBuiltInsideAndOutsideACycleFiles = [
		"public protocol Api {}",
		seamFixtureType(named: "Hub", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>"]),
		seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let r: R", "@Instantiated let uBuilder: Instantiator<U>", "@Instantiated let q: Q"]),
		seamFixtureType(named: "U", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated let otherT: Instantiator<T>"]),
		seamFixtureType(named: "R", isFinalClass: true, declarations: ["@Instantiated let api: any Api"]),
		seamFixtureType(named: "Q", isFinalClass: true, declarations: []),
	]

	/// `Hub`'s `tBuilder` builds `T`, whose `cBuilder` builds `C`, whose `tBuilder` closes the cycle on `Hub`'s; and the
	/// reverse from `Hub`'s `cBuilder`. Neither type is above the other on every path: a tangle of cycles. Both hold the
	/// place `api`.
	/// `tangledCycleFiles` with a `mark` that `C` instantiates and `T`'s `reader` receives.
	private static let tangledCycleFilesWithMarkReader = [
		"public protocol Api {}",
		seamFixtureType(named: "Mark", declarations: []),
		seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) let mark: Mark?"]),
		seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let reader: MarkReader", "@Instantiated let api: any Api", "@Instantiated let cBuilder: Instantiator<C>"]),
		seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let mark: Mark", "@Instantiated let api: any Api", "@Instantiated let tBuilder: Instantiator<T>"]),
		seamFixtureType(named: "Hub", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>", "@Instantiated let cBuilder: Instantiator<C>"]),
	]

	private static let tangledCycleFiles = [
		"public protocol Api {}",
		seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated let cBuilder: Instantiator<C>"]),
		seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated let tBuilder: Instantiator<T>"]),
		seamFixtureType(named: "Hub", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>", "@Instantiated let cBuilder: Instantiator<C>"]),
	]

	/// The distinct levels the tool computes for the seams of `files`, a module named `Feature`, in the order it first
	/// computes them, with what the run outputs. A seam's holes are computed once per pass of its signature, each time
	/// with the same levels.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func placeLevels(of files: [String]) async throws -> ([SeamPlaceLevels], TestOutput) {
		let (stream, continuation) = AsyncStream.makeStream(of: SeamPlaceLevels.self)
		let output = try await SeamPlaceLevels.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: files,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "Feature"],
			)
		}
		continuation.finish()
		var placeLevels = [SeamPlaceLevels]()
		for await computedPlaceLevels in stream where !placeLevels.contains(computedPlaceLevels) {
			placeLevels.append(computedPlaceLevels)
		}
		return (placeLevels, output)
	}

	/// `placeLevels` as text: the seam, then each place's path, its levels nearest first, each declaration bound after the
	/// next property marked `(later)`, and its scope struct's fields and the declarations it carries none of.
	private static func rendered(_ placeLevels: SeamPlaceLevels) -> String {
		var lines = [placeLevels.seamType.asSource]
		for place in placeLevels.places {
			lines.append(place.sitePath.map(\.label).joined(separator: ".") + ":")
			for level in place.levels {
				let declarations = level.declarations.map { $0.property.asSource + ($0.isBoundBeforeNextProperty ? "" : " (later)") }.joined(separator: ", ")
				lines.append("  \(level.builtType?.asSource ?? "fill") before \(level.nextProperty?.label ?? "fill")\(level.isInFill ? " in fill" : ""): \(declarations)")
			}
			lines.append("  fields: " + place.fields.map(\.asSource).joined(separator: ", "))
			lines.append("  uncarried: " + place.uncarriedProperties.map(\.asSource).joined(separator: ", "))
		}
		return lines.joined(separator: "\n")
	}
}
