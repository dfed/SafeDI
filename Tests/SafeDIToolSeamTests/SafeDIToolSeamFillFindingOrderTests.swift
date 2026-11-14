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

/// When several fills of one seam call give the same kind of finding at one receive, the one reported is the one whose
/// other diagnostics come first in the source, never the one a walk in builder order, which labels and type names decide,
/// meets first.
struct SafeDIToolSeamFillFindingOrderTests: ~Copyable {
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
	mutating func generate_throwsFillFindingOfBuilderDeclaredFirst_whenStagedPlacesAreRelabeled() async {
		// `Home` takes one staged builder per `SendableInstantiator`, in label order, and each fill hands `LiveApi` a scope
		// that does not carry `rBuilder`. Renaming `pBuilder` to `zBuilder` puts `Q`'s builder first.
		for firstLabel in ["pBuilder", "zBuilder"] {
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `P` builds only after `Home`’s tree calls the builder for `P`’s `api: any Api`, so that builder’s scope does not carry it. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` declares `rBuilder: Instantiator<R>` here.
				\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `Home`’s tree is building where it calls the builder for `R`’s `api: any Api`. Inline, `LiveApi` can get an instantiator of its own, made from the function `Home`’s initializer declares for `rBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` instantiates `rBuilder: Instantiator<R>` here.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api {}",
							seamFixtureType(named: "R", declarations: ["@Instantiated let api: any Api"]),
							seamFixtureType(named: "P", declarations: ["@Instantiated let api: any Api", "@Instantiated let rBuilder: Instantiator<R>"]),
							seamFixtureType(named: "Q", declarations: ["@Instantiated let api: any Api", "@Instantiated let rBuilder: Instantiator<R>"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let \(firstLabel): SendableInstantiator<P>", "@Instantiated let qBuilder: SendableInstantiator<Q>"]),
						],
						app: [Self.liveApi, Self.root],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillFindingOfBuilderDeclaredFirst_whenHoleTypeIsRenamed() async {
		// `Home` takes one builder per hole type, in label order, and both fills reach `Shared`, which receives `rBuilder`.
		// Renaming `Api` to `Zapi` puts the builder for `Log`, which fills `Q`'s place, first.
		for api in ["Api", "Zapi"] {
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(fixtures["App"]!["Shared.swift"]):9:5: error: `Shared` receives `rBuilder: Instantiator<R>?`, which `P` builds only after `Home`’s tree calls the builder for `P`’s `first: any \(api)` (case `pBuilder_first` of `\(api.lowercased())Builder`), so that builder’s scope does not carry it. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `\(api)` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` declares `rBuilder: Instantiator<R>` here.
				\(fixtures["App"]!["Shared.swift"]):9:5: error: `Shared` receives `rBuilder: Instantiator<R>?`, which `Home`’s tree is building where it calls the builder for `R`’s `leaf: any \(api)` (case `pBuilder_rBuilder_leaf` of `\(api.lowercased())Builder`). Inline, `Shared` can get an instantiator of its own, made from the function `Home`’s initializer declares for `rBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `\(api)` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` instantiates `rBuilder: Instantiator<R>` here.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol \(api) {}",
							"public protocol Log {}",
							seamFixtureType(named: "R", declarations: ["@Instantiated let leaf: any \(api)"]),
							seamFixtureType(named: "P", declarations: ["@Instantiated let first: any \(api)", "@Instantiated let rBuilder: Instantiator<R>"]),
							seamFixtureType(named: "Q", declarations: ["@Instantiated let second: any Log", "@Instantiated let rBuilder: Instantiator<R>"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let qBuilder: Instantiator<Q>"]),
						],
						app: [
							seamFixtureType(named: "Shared", declarations: ["@Received(onlyIfAvailable: true) let rBuilder: Instantiator<R>?"]),
							SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: api, declarations: ["@Instantiated let shared: Shared"]),
							SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveLog", fulfilling: "Log", declarations: ["@Instantiated let shared: Shared"]),
							Self.root,
						],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillFindingOfBuilderDeclaredFirstInFile_whenSixBuildersAreDeclaredInPermutedOrders() async {
		// Six types in one file, each filled through a staged builder of its own, in an order that neither their names nor
		// the labels `Home` takes them under follows: the finding names the type declared first in the file.
		let typeNames = ["Amber", "Birch", "Cedar", "Dune", "Ember", "Fjord"]
		let labelLetters = ["u", "v", "w", "x", "y", "z"]
		let cases: [(declarationOrder: [Int], labelLetterIndices: [Int])] = [
			([3, 0, 5, 1, 4, 2], [0, 1, 2, 3, 4, 5]),
			([5, 2, 0, 4, 1, 3], [4, 0, 3, 5, 1, 2]),
			([1, 4, 2, 5, 3, 0], [5, 3, 0, 2, 4, 1]),
			([4, 5, 3, 2, 0, 1], [2, 5, 1, 0, 3, 4]),
		]
		for (declarationOrder, labelLetterIndices) in cases {
			let builders = declarationOrder.map { typeIndex in
				seamFixtureType(named: typeNames[typeIndex], declarations: ["@Instantiated let api: any Api", "@Instantiated let rBuilder: Instantiator<R>"])
			}
			let firstDeclared = typeNames[declarationOrder[0]]
			let homeDeclarations = typeNames.indices.map { typeIndex in
				"@Instantiated let \(labelLetters[labelLetterIndices[typeIndex]])Builder: SendableInstantiator<\(typeNames[typeIndex])>"
			}
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `\(firstDeclared)` builds only after `Home`’s tree calls the builder for `\(firstDeclared)`’s `api: any Api`, so that builder’s scope does not carry it. Instantiate `rBuilder` on a type above `Home`, and receive it on `\(firstDeclared)` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["Builders.swift"]):9:5: note: `\(firstDeclared)` declares `rBuilder: Instantiator<R>` here.
				\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `Home`’s tree is building where it calls the builder for `R`’s `api: any Api`. Inline, `LiveApi` can get an instantiator of its own, made from the function `Home`’s initializer declares for `rBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `rBuilder` on a type above `Home`, and receive it on `\(firstDeclared)` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["Builders.swift"]):9:5: note: `\(firstDeclared)` instantiates `rBuilder: Instantiator<R>` here.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api {}",
							seamFixtureType(named: "R", declarations: ["@Instantiated let api: any Api"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: homeDeclarations),
						],
						app: [Self.liveApi, Self.root],
						featureConfiguration: ["Builders.swift": builders.joined(separator: "\n\n")],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillFindingOfPathDeclaredFirst_whenSixParentsBuildOneTypeUnderPermutedLabels() async {
		// Six parents of `Home` each build `P`, so one fill reaches the one place in `R` through six paths that differ only
		// in the property of `Home` they start at: the finding names the path through the property `Home` declares first,
		// whichever label sorts first.
		let typeNames = ["Amber", "Birch", "Cedar", "Dune", "Ember", "Fjord"]
		let labelLetters = ["u", "v", "w", "x", "y", "z"]
		let cases: [(declarationOrder: [Int], labelLetterIndices: [Int])] = [
			([3, 0, 5, 1, 4, 2], [0, 1, 2, 3, 4, 5]),
			([5, 2, 0, 4, 1, 3], [4, 0, 3, 5, 1, 2]),
			([1, 4, 2, 5, 3, 0], [5, 3, 0, 2, 4, 1]),
			([4, 5, 3, 2, 0, 1], [2, 5, 1, 0, 3, 4]),
		]
		for (declarationOrder, labelLetterIndices) in cases {
			let parents = typeNames.map { typeName in
				seamFixtureType(named: typeName, declarations: ["@Instantiated let pBuilder: Instantiator<P>"])
			}
			let homeDeclarations = declarationOrder.map { typeIndex in
				"@Instantiated let \(labelLetters[labelLetterIndices[typeIndex]])Parent: \(typeNames[typeIndex])"
			}
			let firstDeclaredLabel = "\(labelLetters[labelLetterIndices[declarationOrder[0]]])Parent"
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `P` builds only after `Home`’s tree calls the builder for `P`’s `api: any Api` (case `\(firstDeclaredLabel)_pBuilder_api` of `apiBuilder`), so that builder’s scope does not carry it. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` declares `rBuilder: Instantiator<R>` here.
				\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `Home`’s tree is building where it calls the builder for `R`’s `api: any Api` (case `\(firstDeclaredLabel)_pBuilder_rBuilder_api` of `apiBuilder`). Inline, `LiveApi` can get an instantiator of its own, made from the function `Home`’s initializer declares for `rBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` instantiates `rBuilder: Instantiator<R>` here.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api {}",
							seamFixtureType(named: "R", declarations: ["@Instantiated let api: any Api"]),
							seamFixtureType(named: "P", declarations: ["@Instantiated let api: any Api", "@Instantiated let rBuilder: Instantiator<R>"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: homeDeclarations),
						],
						app: [Self.liveApi, Self.root],
						featureConfiguration: ["Parents.swift": parents.joined(separator: "\n\n")],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let liveApi = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) let rBuilder: Instantiator<R>?"])
	private static let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"])
}
