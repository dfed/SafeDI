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
	/// `.hole` of its property for a hole its scope declares, `nil` for any other node. A hole beside a sibling on a cycle is refused: a
	/// cycle-closing scope beneath that sibling can rename the hole's builder function apart
	/// (`ScopeGenerator.builderFunctionNames(for:enclosingFunctionNames:)`), which the cycle stage decides; so is one the
	/// tree reaches along more than one path. A hole is never a member of a loop of builders: it receives nothing.
	static func holeKind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind? {
		guard world.kind(of: declaration) == .hole, let property = world.property(of: declaration) else { return nil }
		for parent in world.parents(of: declaration) {
			for edge in world.edgeFacts(from: parent.parent) where world.isOnCycle(edge.child) || edge.isCallEdge {
				throw .cycle
			}
		}
		var node = declaration
		while node != 0 {
			let parents = world.parents(of: node)
			guard parents.count == 1, let parent = parents.first else { throw .holeOnSeveralPaths }
			node = parent.parent
		}
		return .hole(property)
	}

	/// The place of `declaration`, a hole: its site's code, as a seam's tree writes it (`HoleSitePlaces`), from the site and
	/// what the tree binds at its path, which `seamHoles` holds by path (`pathFacts(of:in:rootLazilyInstantiatedInstanceProperties:)`).
	static func holePlace(
		of declaration: DeclarationID,
		property: Property,
		in world: some NodeRecordSources,
		seamHoles: SeamHoles,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
	) -> GeneratedCode {
		let (sitePath, lazilyInstantiatedInstanceProperties) = pathFacts(of: declaration, in: world, rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties)
		let carrierSite = seamHoles.carrierSite(at: sitePath)
		return HoleSitePlaces.place(
			of: property,
			at: seamHoles.site(at: sitePath),
			functionName: nil,
			valuesBindings: carrierSite?.formations ?? [],
			carrierUse: carrierSite?.use,
			readingInstancesOf: lazilyInstantiatedInstanceProperties,
			loopBindsPayloads: false,
		)
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

	/// The properties from the world's root to `declaration`'s, by each node's first parent, and what the scope that builds
	/// it holds only as the instance of a `LazilyInstantiated`: each scope on the path hides what its declarations shadow and
	/// adds what it declares lazily, as a scope's generator hands its children (`ScopeGeneratorUnderConstruction`'s
	/// `childLazilyInstantiatedInstanceProperties`). Every path to one node gives its place one code: its case and payload are
	/// the node's, and the names its route binds are one per node of the seam's graph (`seam-generation.md`), so the first
	/// path the world reaches it by is read, and no other is walked.
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
