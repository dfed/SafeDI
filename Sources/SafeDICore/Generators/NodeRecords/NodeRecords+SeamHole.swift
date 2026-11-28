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

extension NodeRecords {
	/// The claim of `declaration` as a hole its scope declares, `nil` for any other node. A hole's place is its own
	/// node's, so it discharges the refusal of a hole (`renameOrHole`). A hole beside a sibling on a cycle is refused: a
	/// cycle-closing scope beneath that sibling can rename the hole's builder function apart
	/// (`ScopeGenerator.builderFunctionNames(for:enclosingFunctionNames:)`), which the cycle stage decides. So is one the
	/// tree reaches along more than one path (`holeOnSeveralPaths`). A hole is never a member of a loop of builders: it
	/// receives nothing.
	static func seamHoleClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.kind(of: declaration) == .hole else { return nil }
		var refusals = [NodeRecordRefusal]()
		let besideACycle = world.parents(of: declaration).contains { parent in
			world.edgeFacts(from: parent.parent).contains { world.isOnCycle($0.child) || $0.isCallEdge }
		}
		if besideACycle {
			refusals.append(.cycle)
		}
		if !reachesRootAlongOnePath(declaration, in: world) {
			refusals.append(.holeOnSeveralPaths)
		}
		return NodeRecordClaim(kind: .seamHole, discharges: [.renameOrHole], refusals: refusals)
	}

	/// Whether every node from `declaration`, a hole, up to the world's root has one parent. A hole held in, or reached
	/// through, a lazy, erased or `@Sendable` wrapper is written as any other: its site's text declares the wrapper's
	/// function (`HoleSitePlaces.buildSiteCode`), and the payloads its route binds are places of the nodes on the route.
	private static func reachesRootAlongOnePath(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		var node = declaration
		while node != 0 {
			let parents = world.parents(of: node)
			guard parents.count == 1, let parent = parents.first else { return false }
			node = parent.parent
		}
		return true
	}

	/// The place of `declaration`, a hole: its site's code, as a seam's tree writes it (`HoleSitePlaces`), from the site and
	/// what the tree binds at its path, which `seamHoles` holds by path (`pathFacts(of:in:rootLazilyInstantiatedInstanceProperties:)`).
	/// The place is text, one alias record for the site and one for each payload bound before it, so it is held as a place,
	/// not as one `PlaceRecord`.
	static func seamHolePlace(
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
		seamHoles: SeamHoles,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
	) -> GeneratedCode {
		let (sitePath, lazilyInstantiatedInstanceProperties) = pathFacts(of: declaration, in: world, rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties)
		let carrierSite = seamHoles.carrierSite(at: sitePath)
		// A hole is a leaf its scope declares, built as its property (`TypeFactsDeclaration.init(leafOf:...)`). Only a seam's
		// own tree holds one, whose local functions are `@inline(never)` (`LocalFunctionInlining`), as the function a wrapper
		// that holds the hole is built around.
		return world.property(of: declaration).map { property in
			LocalFunctionInlining.$isNeverInlined.withValue(true) {
				HoleSitePlaces.place(
					of: property,
					at: seamHoles.site(at: sitePath),
					routeMembers: seamHoles.routeMembers(at: sitePath),
					functionName: nil,
					valuesBindings: carrierSite?.formations ?? [],
					carrierUse: carrierSite?.use,
					readingInstancesOf: lazilyInstantiatedInstanceProperties,
					loopBindsPayloads: false,
				)
			}
		} ?? .empty
	}

	/// The place of a node built on the route to a hole's place, `builtPlace`, after the payloads the seam's tree binds just
	/// before building it (`SeamHoles.valuesBindings(at:)`), each a place of its own, as a scope's place is written
	/// (`HoleSitePlaces.valuesBindingPlaces(of:readingInstancesOf:)`); `builtPlace` alone off every route.
	static func placeOnRouteToHole(
		_ builtPlace: GeneratedCode,
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
		seamHoles: SeamHoles,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
	) -> GeneratedCode {
		let (path, lazilyInstantiatedInstanceProperties) = pathFacts(of: declaration, in: world, rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties)
		guard let bindingPlaces = HoleSitePlaces.valuesBindingPlaces(of: seamHoles.valuesBindings(at: path), readingInstancesOf: lazilyInstantiatedInstanceProperties) else { return builtPlace }
		return .sequence(bindingPlaces + [builtPlace])
	}

	/// The member calls of builder structs the seam's tree makes at the top of `declaration`'s builder function, a
	/// `@Sendable` one on a route to a hole's place (`SeamHoles.memberCallsInsideFunction(at:)`), each a place of its own,
	/// the first statements of the function's body, as the tree writes them (`ScopeGenerator.memberCallPlaces`); empty off
	/// every such route.
	static func memberCallPlaces(
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
		seamHoles: SeamHoles,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
	) -> [GeneratedCode] {
		guard seamHoles.makesMemberCallsInsideFunctions else { return [] }
		let (path, lazilyInstantiatedInstanceProperties) = pathFacts(of: declaration, in: world, rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties)
		return seamHoles.memberCallsInsideFunction(at: path).map { binding in
			let line = binding.line(readingInstancesOf: lazilyInstantiatedInstanceProperties)
			let record = AliasPlaceRecord(
				property: Property(label: binding.bindingName, typeDescription: binding.boundType),
				fulfillingProperty: nil,
				text: line,
				reads: binding.reads(readingInstancesOf: lazilyInstantiatedInstanceProperties),
			)
			return .indented(.place(PlacePlan(code: .text("\(line)\n"), record: .alias(record))), by: ScopeGenerator.standardIndent)
		}
	}

	/// The properties from the world's root to `declaration`'s, by each node's first parent, and what the scope that builds
	/// it holds only as the instance of a `LazilyInstantiated`: each scope on the path hides what its declarations shadow and
	/// adds what it declares lazily, as a scope's generator hands its children (`ScopeGeneratorUnderConstruction`'s
	/// `childLazilyInstantiatedInstanceProperties`). A hole and each node on its route reach the root along one path, or the
	/// world is refused (`holeOnSeveralPaths`), since the names a route binds follow its path; any other node binds nothing,
	/// so the first path the world reaches it by is read, and no other is walked.
	private static func pathFacts(
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
	) -> (path: [Property], lazilyInstantiatedInstanceProperties: Set<Property>) {
		var path = [Property]()
		var scopesAbove = [DeclarationID]()
		var node = declaration
		while node != 0, let property = world.property(of: node), let parent = world.parents(of: node).first {
			path.append(property)
			node = parent.parent
			scopesAbove.append(node)
		}
		var lazilyInstantiatedInstanceProperties = rootLazilyInstantiatedInstanceProperties
		for scopeNode in scopesAbove.reversed() {
			let scope = world.scope(of: scopeNode)
			lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
				.filter { !scope.declaredLabels.contains($0.label) }
				.union(scope.declaredLazilyInstantiatedInstanceProperties)
		}
		return (path.reversed(), lazilyInstantiatedInstanceProperties)
	}
}

extension NodeRecords {
	/// The label of each hole of `world` that its root reaches along more than one route of calls, sorted: empty wherever
	/// node records accept the world, which refuses a hole on several paths (`NodeRecordRefusal.holeOnSeveralPaths`). A
	/// hole's leaf reads nothing (`TypeFactsDeclaration.Leaf.hole`), so one variant of it, or of a node above it, could
	/// stand for routes whose places hand its fill different forms; a single route is what lets the hole's one record stand
	/// for its place. A test checks it of every world node records accept (`NodeRecordsObservation`).
	static func holesReachedOnSeveralRoutes(in world: some NodeRecordSources) -> [String] {
		// Each variant's count of calls into it, and one caller: a variant is reached on one route where it and every
		// variant above it is called once.
		var callCounts = [Int](repeating: 0, count: world.variantCount)
		var callers = [VariantID](repeating: -1, count: world.variantCount)
		for caller in 0..<VariantID(world.variantCount) {
			for callee in world.calls(of: caller) + world.madeAgainCalls(of: caller) {
				callCounts[Int(callee)] += 1
				callers[Int(callee)] = caller
			}
		}
		let root = world.rootVariant(0)
		return (0..<VariantID(world.variantCount)).filter { variant in
			guard world.kind(of: world.declaration(of: variant)) == .hole else { return false }
			// At most one step a variant: a cycle of variants each called once is reached from no root.
			var node = variant
			for _ in 0..<world.variantCount where node != root && node >= 0 && callCounts[Int(node)] == 1 {
				node = callers[Int(node)]
			}
			return node != root
		}.compactMap { world.property(of: world.declaration(of: $0))?.label }.sorted()
	}
}
