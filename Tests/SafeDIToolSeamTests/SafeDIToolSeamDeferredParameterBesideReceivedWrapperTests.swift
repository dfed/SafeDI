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

/// A place a seam passes up from inside its fill of a place of a seam it calls, which defers a parameter, while the seam
/// that passes the place up receives the label as its own property. The place's field is that property, and a route hands
/// a fill of the place the deferring seam's memo, which the fill binds: a read of the label's optional wrapper only if
/// available was once handed `nil` there, while inline the place sits in the deferring seam's tree, which then receives the
/// label in two forms, as one module reports.
struct SafeDIToolSeamDeferredParameterBesideReceivedWrapperTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: The fill takes the deferring seam's memo

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtDeferringSeam_whenPlacePassedUpBySeamReceivingSendableWrapperIsFilledReadingValueAndOptionalSendableWrapper() async {
		// `Outer` receives `token` as the `SendableLazilyInstantiated` `Root` declares and fills `Inner`'s place, inside which
		// `App` fills the place `Outer` passes up. `Inner` defers `token`, which `Leaf` receives, so the fill of `Gizmo`, whose
		// `GizmoImpl` reads the value, takes `Inner`'s memo, which gave `WrapperReader`'s optional read `nil`. Built in one
		// module, `Inner`'s tree receives `token` in two forms (the twin below), so `App` reports that error, at `Inner`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtSeam_whenGraphOfPlacePassedUpBySeamReceivingSendableWrapperIsBuiltInOneModule() async {
		// The graph of the cell above with every module's declarations in one module, which builds `Inner`'s tree whole.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["App"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):47:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):41:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.oneModule(of: Self.modules()), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtDeferringSeam_whenDeferringSeamBuildsReceiverInSendableInstantiator() async {
		// `Inner` builds `Leaf` in a `SendableInstantiator`, so it defers `token` `@Sendable` and the memo the fill takes is a
		// `SendableLazilyInstantiated`; the fill still gave `WrapperReader`'s optional read `nil`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(innerLeaf: "SendableInstantiator<Leaf>"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtSeam_whenGraphWhoseDeferringSeamBuildsReceiverInSendableInstantiatorIsBuiltInOneModule() async {
		// The graph of the cell above in one module.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["App"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):47:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):41:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.oneModule(of: Self.modules(innerLeaf: "SendableInstantiator<Leaf>")), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtDeferringSeam_whenDeferringSeamBuildsReceiverInInstantiator() async {
		// `Inner` builds `Leaf` in an `Instantiator`: the same memo as by value, and the same error.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(innerLeaf: "Instantiator<Leaf>"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtDeferringSeam_whenPassingUpSeamReceivesLazyWrapperAndFillReadsOptionalLazyWrapper() async {
		// `Outer` receives the plain `LazilyInstantiated`, and `WrapperReader` reads its optional: a memo of the reader's own
		// kind, which the fill still gave the reader as `nil`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: LazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: LazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: LazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(wrapper: "LazilyInstantiated"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtInnermostDeferringSeam_whenSeamThatPassesPlaceUpReceivesWrapperTwoSeamsAbove() async {
		// `Top` receives the wrapper and fills the place `Outer` passes up from its fill of `Inner`'s place, then passes up the
		// place of that fill. `Outer` passes `token` on to `Inner`, whose tree, built in one module, receives it in two forms:
		// `Inner` is reported, as one module reports it, not `Outer`, whose own tree receives it in one.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):15:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):9:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modulesTwoSeamsAbove, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtSeam_whenGraphWhoseSeamTwoSeamsAboveReceivesWrapperIsBuiltInOneModule() async {
		// The graph of the cell above in one module.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["App"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):67:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):61:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.oneModule(of: Self.modulesTwoSeamsAbove), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtDeferringSeamOnce_whenFillReadsOptionalSendableWrapperInTwoTypes() async {
		// `GizmoImpl` builds `SecondWrapperReader` too, which reads the optional wrapper as `WrapperReader` does: one error
		// for `Inner`, naming both readers, as one module names every receive of its tree.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader` and `token: SendableLazilyInstantiated<Token>?` on `SecondWrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):20:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `SecondWrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(gizmoBuildsSecondWrapperReader: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtSeam_whenGraphWhoseFillReadsOptionalSendableWrapperInTwoTypesIsBuiltInOneModule() async {
		// The graph of the cell above in one module.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader` and `token: SendableLazilyInstantiated<Token>?` on `SecondWrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["App"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):53:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):41:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			\(fixtures["App"]!["Token.swift"]):47:2: note: `SecondWrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.oneModule(of: Self.modules(gizmoBuildsSecondWrapperReader: true)), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtEachDeferringSeam_whenPlaceOfCaseNestedByTypeIsReachedThroughTwoDeferringSeams() async {
		// `Outer` builds `InnerB` too, which builds `Leaf` by value, and fills its place with `ServiceImpl` as well, so one
		// fill of `Gizmo`, the first place's, fills the place on both routes and takes a memo of `token`. Built in one module,
		// each seam's tree receives `token` in two forms, so each is reported, as one module reports each.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			\(fixtures["Core"]!["Token.swift"]):23:1: error: SafeDI cannot generate the dependency tree of `InnerB`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `InnerB` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(innerLeaf: "SendableInstantiator<Leaf>", buildsSecondInner: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtEachSeam_whenGraphOfPlaceReachedThroughTwoDeferringSeamsIsBuiltInOneModule() async {
		// The graph of the cell above in one module.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["App"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):55:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):49:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			\(fixtures["App"]!["Token.swift"]):23:1: error: SafeDI cannot generate the dependency tree of `InnerB`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `InnerB` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["App"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):55:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["Token.swift"]):49:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.oneModule(of: Self.modules(innerLeaf: "SendableInstantiator<Leaf>", buildsSecondInner: true)), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtDeferringSeam_whenOneParameterWouldTakeEveryFormOfDeferringSeamsTree() async throws {
		// `GizmoImpl` builds `RequiredReader` too, which requires the `SendableLazilyInstantiated`: built in one module,
		// `Inner` takes `token` as that wrapper, which provides every form its tree receives, so one module accepts the graph.
		// The fill of `Gizmo` takes `Inner`'s memo, which gives `WrapperReader`'s optional read `nil`, so `App` reports
		// `Inner`'s two forms, as it does where the place's field is a declaration further out: a wrong value turned into an
		// error whose remedy, `Inner` receiving the wrapper, both builds accept.
		let modules = Self.modules(innerLeaf: "SendableInstantiator<Leaf>", gizmoBuildsRequiredReader: true)
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.oneModule(of: modules), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Token.swift"]):16:1: error: SafeDI cannot generate the dependency tree of `Inner`: its tree receives `token` as `token: Token` on `Leaf` and `token: Token` on `GizmoImpl` and `token: SendableLazilyInstantiated<Token>?` on `WrapperReader` and `token: SendableLazilyInstantiated<Token>` on `RequiredReader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `token` the same way in every type of the tree, or declare it on `Inner` as the form that provides the others: `@Received let token: SendableLazilyInstantiated<Token>`.
			\(fixtures["Core"]!["Token.swift"]):11:2: note: `Leaf` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):20:2: note: `GizmoImpl` receives `token: Token` here.
			\(fixtures["App"]!["WrapperReader.swift"]):8:2: note: `WrapperReader` receives `token: SendableLazilyInstantiated<Token>?` here.
			\(fixtures["App"]!["WrapperReader.swift"]):14:2: note: `RequiredReader` receives `token: SendableLazilyInstantiated<Token>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		let remedied = Self.modules(innerLeaf: "SendableInstantiator<Leaf>", innerReceivesToken: true, gizmoBuildsRequiredReader: true)
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.oneModule(of: remedied), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		_ = try await executeSafeDIToolMultiModuleTest(modules: remedied, integration: .moduleInfo, filesToDelete: &filesToDelete)
	}

	// MARK: The remedy

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsPassingUpSeamsWrapper_whenDeferringSeamReceivesWrapperItsTwoFormsErrorOffers() async throws {
		// The remedy of the errors above: `Inner` receives `token` as the `SendableLazilyInstantiated` that provides both
		// forms, so both builds accept the graph, and `WrapperReader` holds `Root`'s wrapper, as inline.
		let modules = Self.modules(innerReceivesToken: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let oneModule = Self.oneModule(of: modules)
		let oneModuleOutput = try await executeSafeDIToolMultiModuleTest(modules: oneModule, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: oneModuleOutput, modules: oneModule),
			probes: [DifferentialValueProbe(name: "the reader’s wrapper", expression: "{ () -> [Bool] in\n\tlet root = Root()\n\tlet gizmo = (root.outer.inner.service as! ServiceImpl).gizmo as! GizmoImpl\n\treturn [gizmo.wrapperReader.token == nil, gizmo.wrapperReader.token?.instance === root.token.instance]\n}()")],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Three modules. `Core`'s seam `Inner` holds the place `service` and builds `Leaf`, which receives `token`, as `innerLeaf`,
	/// so it defers `token`, or, where `innerReceivesToken`, receives `token` as the `SendableLazilyInstantiated` itself.
	/// `Session`'s seam `Outer` receives `token` as a `wrapper` and builds `Inner`, whose place it fills with `ServiceImpl`,
	/// which holds the place `gizmo`, which `Outer` passes up. `App` fills it with `GizmoImpl`, which receives `token` and
	/// builds `WrapperReader`, which receives the optional `wrapper` only if available, under `Root`, which declares `token`
	/// as a `wrapper`.
	/// Where `buildsSecondInner`, `Core` declares `InnerB` too, which holds `service` and builds `Leaf` by value, and
	/// `Outer` builds it after `Inner`; where `gizmoBuildsRequiredReader`, `GizmoImpl` builds `RequiredReader` too, which
	/// receives the `SendableLazilyInstantiated`, and where `gizmoBuildsSecondWrapperReader`, `SecondWrapperReader`, which
	/// receives the optional `wrapper` only if available as `WrapperReader` does.
	private static func modules(innerLeaf: String = "Leaf", wrapper: String = "SendableLazilyInstantiated", innerReceivesToken: Bool = false, buildsSecondInner: Bool = false, gizmoBuildsRequiredReader: Bool = false, gizmoBuildsSecondWrapperReader: Bool = false) -> [ModuleFixture] {
		let leafLabel = innerLeaf == "Leaf" ? "leaf" : "leafBuilder"
		let innerToken = innerReceivesToken ? "token: SendableLazilyInstantiated<Token>, " : ""
		let innerTokenAssignment = innerReceivesToken ? "self.token = token; " : ""
		let innerTokenDeclaration = innerReceivesToken ? "\n\t@Received public let token: SendableLazilyInstantiated<Token>" : ""
		let secondInner = buildsSecondInner ? """


		@Instantiable(generateDependencyTree: true)
		public final class InnerB: Instantiable, @unchecked Sendable {
			public init(leaf: Leaf, service: any Service) { self.leaf = leaf; self.service = service }
			@Instantiated public let leaf: Leaf
			@Instantiated public let service: any Service
		}
		""" : ""
		let outerInnerB = buildsSecondInner ? ", innerB: InnerB" : ""
		let outerInnerBAssignment = buildsSecondInner ? "; self.innerB = innerB" : ""
		let outerInnerBDeclaration = buildsSecondInner ? "\n\t@Instantiated public let innerB: InnerB" : ""
		let secondWrapperReader = gizmoBuildsSecondWrapperReader ? """


		@Instantiable
		public final class SecondWrapperReader: Instantiable, @unchecked Sendable {
			public init(token: \(wrapper)<Token>?) { self.token = token }
			@Received(onlyIfAvailable: true) public let token: \(wrapper)<Token>?
		}
		""" : ""
		let requiredReader = gizmoBuildsRequiredReader ? """


		@Instantiable
		public final class RequiredReader: Instantiable, @unchecked Sendable {
			public init(token: SendableLazilyInstantiated<Token>) { self.token = token }
			@Received public let token: SendableLazilyInstantiated<Token>
		}
		""" : ""
		var gizmoRequiredReader = gizmoBuildsRequiredReader ? ", requiredReader: RequiredReader" : ""
		var gizmoRequiredReaderAssignment = gizmoBuildsRequiredReader ? "; self.requiredReader = requiredReader" : ""
		var gizmoRequiredReaderDeclaration = gizmoBuildsRequiredReader ? "\n\t@Instantiated public let requiredReader: RequiredReader" : ""
		if gizmoBuildsSecondWrapperReader {
			gizmoRequiredReader += ", secondWrapperReader: SecondWrapperReader"
			gizmoRequiredReaderAssignment += "; self.secondWrapperReader = secondWrapperReader"
			gizmoRequiredReaderDeclaration += "\n\t@Instantiated public let secondWrapperReader: SecondWrapperReader"
		}
		return [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			@Instantiable
			public final class Token: Instantiable, Sendable {
				public init() {}
			}

			@Instantiable
			public final class Leaf: Instantiable, Sendable {
				public init(token: Token) { self.token = token }
				@Received let token: Token
			}

			public protocol Service: Sendable {}

			@Instantiable(generateDependencyTree: true)
			public final class Inner: Instantiable, @unchecked Sendable {
				public init(\(innerToken)\(leafLabel): \(innerLeaf), service: any Service) { \(innerTokenAssignment)self.\(leafLabel) = \(leafLabel); self.service = service }\(innerTokenDeclaration)
				@Instantiated public let \(leafLabel): \(innerLeaf)
				@Instantiated public let service: any Service
			}\(secondInner)
			"""]),
			ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			public protocol Gizmo: Sendable {}

			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public final class ServiceImpl: Instantiable, Service, @unchecked Sendable {
				public init(gizmo: any Gizmo) { self.gizmo = gizmo }
				@Instantiated public let gizmo: any Gizmo
			}

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable, @unchecked Sendable {
				public init(token: \(wrapper)<Token>, inner: Inner\(outerInnerB)) { self.token = token; self.inner = inner\(outerInnerBAssignment) }
				@Received public let token: \(wrapper)<Token>
				@Instantiated public let inner: Inner\(outerInnerBDeclaration)
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI
			import Session

			@Instantiable
			public final class WrapperReader: Instantiable, @unchecked Sendable {
				public init(token: \(wrapper)<Token>?) { self.token = token }
				@Received(onlyIfAvailable: true) public let token: \(wrapper)<Token>?
			}\(requiredReader)\(secondWrapperReader)

			@Instantiable(fulfillingAdditionalTypes: [Gizmo.self])
			public final class GizmoImpl: Instantiable, Gizmo, @unchecked Sendable {
				public init(token: Token, wrapperReader: WrapperReader\(gizmoRequiredReader)) { self.token = token; self.wrapperReader = wrapperReader\(gizmoRequiredReaderAssignment) }
				@Received public let token: Token
				@Instantiated public let wrapperReader: WrapperReader\(gizmoRequiredReaderDeclaration)
			}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable, @unchecked Sendable {
				public init(token: \(wrapper)<Token>, outer: Outer) { self.token = token; self.outer = outer }
				@Instantiated public let token: \(wrapper)<Token>
				@Instantiated public let outer: Outer
			}
			"""], dependencies: ["Core", "Session"]),
		]
	}

	/// Four modules. `Core`'s seam `Inner` holds the place `service` and builds `Leaf`, which receives `token`, in an
	/// `Instantiator`, so it defers `token`. `Session`'s seam `Outer` builds `Inner`, whose place it fills with
	/// `ServiceImpl`, which holds the place `gadget`, which `Outer` passes up. `Feature`'s seam `Top` receives `token` as a
	/// `SendableLazilyInstantiated`, builds `Outer` and fills `gadget` with `GadgetImpl`, which builds `Worker`, which holds
	/// the place `gizmo`, which `Top` passes up. `App` fills it with `GizmoImpl`, which receives `token` and builds
	/// `WrapperReader`, which receives the optional `SendableLazilyInstantiated` only if available, under `Root`, which
	/// declares `token`.
	private static let modulesTwoSeamsAbove = [
		ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
		import SafeDI

		@Instantiable
		public final class Token: Instantiable, Sendable {
			public init() {}
		}

		@Instantiable
		public final class Leaf: Instantiable, Sendable {
			public init(token: Token) { self.token = token }
			@Received let token: Token
		}

		public protocol Service: Sendable {}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable, @unchecked Sendable {
			public init(leafBuilder: Instantiator<Leaf>, service: any Service) { self.leafBuilder = leafBuilder; self.service = service }
			@Instantiated public let leafBuilder: Instantiator<Leaf>
			@Instantiated public let service: any Service
		}
		"""]),
		ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: ["""
		import Core
		import SafeDI

		public protocol Gadget: Sendable {}

		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class ServiceImpl: Instantiable, Service, @unchecked Sendable {
			public init(gadget: any Gadget) { self.gadget = gadget }
			@Instantiated public let gadget: any Gadget
		}

		@Instantiable(generateDependencyTree: true)
		public final class Outer: Instantiable, @unchecked Sendable {
			public init(inner: Inner) { self.inner = inner }
			@Instantiated public let inner: Inner
		}
		"""], dependencies: ["Core"]),
		ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
		import Core
		import SafeDI
		import Session

		public protocol Gizmo: Sendable {}

		@Instantiable
		public final class Worker: Instantiable, Sendable {
			public init(gizmo: any Gizmo) { self.gizmo = gizmo }
			@Instantiated let gizmo: any Gizmo
		}

		@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
		public final class GadgetImpl: Instantiable, Gadget, @unchecked Sendable {
			public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder }
			@Instantiated public let workerBuilder: Instantiator<Worker>
		}

		@Instantiable(generateDependencyTree: true)
		public final class Top: Instantiable {
			public init(token: SendableLazilyInstantiated<Token>, outer: Outer) { self.token = token; self.outer = outer }
			@Received public let token: SendableLazilyInstantiated<Token>
			@Instantiated public let outer: Outer
		}
		"""], dependencies: ["Core", "Session"]),
		ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["""
		import Core
		import Feature
		import SafeDI
		import Session

		@Instantiable
		public final class WrapperReader: Instantiable, Sendable {
			public init(token: SendableLazilyInstantiated<Token>?) { self.token = token }
			@Received(onlyIfAvailable: true) public let token: SendableLazilyInstantiated<Token>?
		}

		@Instantiable(fulfillingAdditionalTypes: [Gizmo.self])
		public final class GizmoImpl: Instantiable, Gizmo {
			public init(token: Token, wrapperReader: WrapperReader) { self.token = token; self.wrapperReader = wrapperReader }
			@Received public let token: Token
			@Instantiated public let wrapperReader: WrapperReader
		}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
			public init(token: SendableLazilyInstantiated<Token>, top: Top) { self.token = token; self.top = top }
			@Instantiated public let token: SendableLazilyInstantiated<Token>
			@Instantiated public let top: Top
		}
		"""], dependencies: ["Core", "Session", "Feature"]),
	]

	/// Every module's declarations of `modules` in one module, `App`, which builds every seam inline.
	private static func oneModule(of modules: [ModuleFixture]) -> [ModuleFixture] {
		let declarations = modules.map { module in
			module.swiftFileContent.joined(separator: "\n\n").components(separatedBy: "\n").filter { !$0.hasPrefix("import ") }.joined(separator: "\n")
		}
		return [ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["import SafeDI\n" + declarations.joined(separator: "\n")])]
	}
}
