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
	/// `.cycle` where `declaration` is on a cycle and holds no kind a later stage makes, `nil` where it is on none.
	/// - Throws: The first kind stage 1 does not make, other than the cycle itself, that a node on a cycle is of.
	static func cycleKind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind? {
		guard world.isOnCycle(declaration) else { return nil }
		if let refusal = refusalsOfBuiltByInitializer(declaration, in: world).first(where: { $0 != .cycle }) {
			throw refusal
		}
		return .cycle
	}

	/// The record of `declaration`'s place, a node of kind `cycle`: built by its initializer as a stage-1 node is, its
	/// children's places among which a call back to a place being built above it is that call's closing place
	/// (`closingRecord(closingOn:in:)`).
	static func cycleRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> PlaceRecord {
		try .built(builtByInitializerRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: typesDeclaredEscaping, children: children))
	}

	/// The labels the types of `world`, which holds a cycle, receive: read from above wherever they are, a superset of what
	/// the function a call closes a cycle on reads from above it. Every alias is a node of kind `alias`, and every value
	/// received only if available is the `onlyIfAvailable` of the node receiving it, which the kinds `init(world:)` reads
	/// first refuse (`refusalsOfBuiltByInitializer(_:in:)`), so the world reads from above only what it receives plainly.
	/// - Throws: `cycleReceivesBuilder` where a type receives a builder.
	static func labelsReceived(inWorldWithCycle world: some NodeRecordSources) throws(NodeRecordRefusal) -> Set<String> {
		var labels = Set<String>()
		for declaration in 0..<Int32(world.declarationCount) {
			for dependency in world.scope(of: declaration).instantiable.dependencies where dependency.source == .received(onlyIfAvailable: false) {
				guard dependency.property.propertyType.isConstant else { throw .cycleReceivesBuilder }
				labels.insert(dependency.property.label)
			}
		}
		return labels
	}

	/// The labels `declaration`'s body declares: what it instantiates, what it is forwarded and the names it gives aliases.
	static func labelsDeclared(by declaration: DeclarationID, in world: some NodeRecordSources) -> [String] {
		world.scope(of: declaration).instantiable.dependencies.compactMap { dependency in
			switch dependency.source {
			case .instantiated, .forwarded, .aliased:
				dependency.property.label
			case .received:
				nil
			}
		}
	}

	/// The record of the place at which a call closes a cycle on `declaration`, whose place is being built above the call:
	/// a call of the function that place declares, which forwards what that place's wrapper forwards. The walk refuses a
	/// cycle whose function could take a parameter for the cycle (`cycleTakesParameters`), so the function takes none
	/// (`BuiltPlaceRecord.cycleParameters`), and the call passes none.
	static func closingRecord(closingOn declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> PlaceRecord {
		// Every node a call reaches is built as a property: the root is called by none.
		guard let property = world.property(of: declaration) else { throw .noInitializer }
		let instantiable = world.scope(of: declaration).instantiable
		return .closer(ClosingPlaceRecord(
			property: property,
			isErased: false,
			isExtension: instantiable.declarationType.isExtension,
			closedOnFunctionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			cycleArguments: [],
		))
	}
}
