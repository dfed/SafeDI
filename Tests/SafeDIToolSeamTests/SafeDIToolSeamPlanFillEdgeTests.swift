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

import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The edge a plan by declaration has from a call of another module's seam to each fill the call passes
/// (`FillEdges`): a fill's tree reads what its place's struct does not carry from the declarations enclosing the call.
struct SafeDIToolSeamPlanFillEdgeTests: ~Copyable {
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
	mutating func generate_plansFillAsTargetOfCall_whenCallInsideCyclePassesFill() async throws {
		// `A` opens itself again and calls `Service`, whose hole `userService` `App` fills with `DefaultUserService`: the
		// call's declaration has an edge to the fill's, after the edges of the properties it instantiates.
		let projections = try await planProjections(of: Self.modules(
			service: ["@Instantiated let userService: any UserService"],
			userService: [],
		))

		#expect(projections == [
			"""
			0: Root -> 1 -> 2
			1: Theme as theme: Theme
			2: A as aBuilder: Instantiator<A> cycle 3 -> 3 -> 2
			3: Service as service: Service -> fill 4
			4: DefaultUserService as userService: any UserService
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_plansCallAsReadingWhatItsFillReceives_whenFillInsideCycleReceivesCallersValue() async throws {
		// `A` opens itself again and calls `Service`, whose hole `userService` `App` fills with `DefaultUserService`, which
		// receives `Root`'s `theme` only if available. The fill reads `theme` from the declarations enclosing the call, so the
		// call's place and every place above it on the cycle read it from above, and the plan, through the fill's edge, keys
		// their bodies by it.
		let reads = try await reads(of: Self.modules(
			service: ["@Instantiated let userService: any UserService"],
			userService: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
		))

		// The place that closes the cycle on `aBuilder` builds nothing beneath it, so it reads nothing.
		#expect(reads == [
			Reads(type: "Theme", property: "theme: Theme", labelsRead: [], labelsPlanned: []),
			Reads(type: "DefaultUserService", property: "userService: any UserService", labelsRead: ["theme"], labelsPlanned: ["theme"]),
			Reads(type: "Service", property: "service: Service", labelsRead: ["theme", "userService"], labelsPlanned: ["theme", "userService"]),
			Reads(type: "A", property: "aBuilder: Instantiator<A>", labelsRead: [], labelsPlanned: ["theme", "userService"]),
			Reads(type: "A", property: "aBuilder: Instantiator<A>", labelsRead: ["theme", "userService"], labelsPlanned: ["theme", "userService"]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersFillsReadOfFieldWithField_whenPlaceStructCarriesLabelFillReceives() async throws {
		// `Service` builds `theme` before `userService`, so the place's struct carries `theme`, which `DefaultUserService`
		// receives: the fill's body reads the field, which hides `Root`'s `theme`, and the call reads no `theme` from above.
		let projections = try await variantsProjections(of: Self.modules(
			service: ["@Instantiated let theme: Theme", "@Instantiated let userService: any UserService"],
			userService: ["@Received let theme: Theme"],
		))

		#expect(projections == [
			"""
			0: Root [userService = nil] -> 1 -> 2
			1: Theme as theme: Theme
			2: A as aBuilder: Instantiator<A> [userService = nil] -> 3 -> 2
			3: Service as service: Service [userService = nil] -> 4
			4: DefaultUserService as userService: any UserService [theme = theme: Theme]
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillInBodyBeneathAnswersOfFillsReads_whenFillInsideCycleReceivesCallersValue() async throws {
		// `App` is a seam world: its `A` calls `Service`, whose fill `DefaultUserService` receives `Root`'s `theme` only if
		// available. The body of each place above the call is keyed by what the call's fills read of the declarations
		// enclosing it, so its fill reads `Root`'s `theme`, as today's place does, rather than passing it `nil`.
		let bodies = try await bodies(of: Self.modules(
			service: ["@Instantiated let userService: any UserService"],
			userService: ["@Received(onlyIfAvailable: true) let theme: Theme?"],
		))

		#expect(bodies == [
			Bodies(place: "\"theme: Theme\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"aBuilder: Instantiator<A>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"service: Service\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"userService: any UserService\" in a fill of \"service: Service\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"aBuilder: Instantiator<A>\" called by \"aBuilder: Instantiator<A>\" in \"aBuilder: Instantiator<A>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"service: Service\" called by \"aBuilder: Instantiator<A>\" in \"aBuilder: Instantiator<A>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"userService: any UserService\" in a fill of \"service: Service\" called by \"aBuilder: Instantiator<A>\" in \"aBuilder: Instantiator<A>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	// MARK: Private

	private struct Reads: Equatable {
		let type: String
		let property: String
		let labelsRead: [String]
		let labelsPlanned: [String]
	}

	private struct Bodies: Equatable {
		let place: String
		let todaysUnavailableProperties: [String]
		let bodysUnavailableProperties: [String]
	}

	private var filesToDelete: [URL]

	/// `Feature`, which declares `Service`, a seam with `service`'s declarations whose hole `userService` only `App` can see a
	/// fulfilling type of, and `App`, whose `Root` builds `theme` and then `A`, which calls `Service` and opens itself again,
	/// and whose `DefaultUserService`, with `userService`'s declarations, fills the hole.
	private static func modules(service: [String], userService: [String]) -> [ModuleFixture] {
		let feature = [
			"public protocol UserService {}",
			seamFixtureType(named: "Theme", declarations: []),
			seamFixtureType(named: "Service", isSeam: true, declarations: service),
		]
		let app = [
			seamFixtureType(named: "DefaultUserService", declarations: userService, conformances: ", UserService")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [UserService.self])\n"),
			seamFixtureType(named: "A", declarations: ["@Instantiated let service: Service", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
		]
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// Each distinct comparison of a place's reads with its plan the tool hands on while it generates `modules`, in the
	/// order first handed on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func reads(of modules: [ModuleFixture]) async throws -> [Reads] {
		let (stream, continuation) = AsyncStream.makeStream(of: Reads.self)
		try await PlaceReadsObservation.$observer.withValue({ type, property, labelsRead, labelsPlanned in
			continuation.yield(Reads(type: type, property: property, labelsRead: labelsRead, labelsPlanned: labelsPlanned))
		}) {
			_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reads = [Reads]()
		for await read in stream where !reads.contains(read) {
			reads.append(read)
		}
		return reads
	}

	/// Each distinct projection of a plan (`PerTypePlan.projection`) the tool hands on while it generates `modules`, in the
	/// order first handed on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func planProjections(of modules: [ModuleFixture]) async throws -> [String] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		try await PerTypePlanObservation.$observer.withValue({ projection in
			continuation.yield(projection)
		}) {
			_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var projections = [String]()
		for await projection in stream where !projections.contains(projection) {
			projections.append(projection)
		}
		return projections
	}

	/// Each distinct projection of a plan's bodies (`PlanVariants.projection`) the tool hands on while it generates
	/// `modules`, in the order first handed on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func variantsProjections(of modules: [ModuleFixture]) async throws -> [String] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		try await PerTypePlanObservation.$variantsObserver.withValue({ projection in
			continuation.yield(projection)
		}) {
			_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var projections = [String]()
		for await projection in stream where !projections.contains(projection) {
			projections.append(projection)
		}
		return projections
	}

	/// Each distinct comparison of a place of a root's tree with its body (`VariantBodyObservation`) the tool hands on while
	/// it generates `modules`, in the order first handed on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func bodies(of modules: [ModuleFixture]) async throws -> [Bodies] {
		let (stream, continuation) = AsyncStream.makeStream(of: Bodies.self)
		try await VariantBodyObservation.$observer.withValue({ place, todaysUnavailableProperties, bodysUnavailableProperties in
			continuation.yield(Bodies(place: place, todaysUnavailableProperties: todaysUnavailableProperties, bodysUnavailableProperties: bodysUnavailableProperties))
		}) {
			_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var bodies = [Bodies]()
		for await body in stream where !bodies.contains(body) {
			bodies.append(body)
		}
		return bodies
	}
}
