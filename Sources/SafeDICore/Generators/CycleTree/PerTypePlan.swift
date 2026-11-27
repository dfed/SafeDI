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

/// What one place of a root's tree builds, without the path that reaches it: the scope and the property it is built as.
/// Every place of one declaration builds the same children, so a tree has as many declarations as its types have
/// properties, however many paths its cycles open. Two declarations are equal when they build the same scope's record as
/// the same property, erased alike.
struct Declaration: Hashable, Sendable {
	/// The property a scope is built as.
	struct Built: Sendable {
		let property: Property
		/// The property exactly as `ConstructionMemo.Key` holds it.
		let id: PropertyID
		let erasedToConcreteExistential: Bool
	}

	/// The record of the scope built, which the declaration keeps alive.
	let record: ScopeRecord
	/// `nil` for the tree's root, which is built as no property.
	let built: Built?

	static func == (lhs: Declaration, rhs: Declaration) -> Bool {
		lhs.record === rhs.record
			&& lhs.built?.id == rhs.built?.id
			&& lhs.built?.erasedToConcreteExistential == rhs.built?.erasedToConcreteExistential
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(ObjectIdentifier(record))
		hasher.combine(built?.id)
		hasher.combine(built?.erasedToConcreteExistential)
	}
}

/// The pair generation closes a cycle on (`ContextStack.entryClosedOn(byPropertyID:concreteTypeID:interner:)`): the
/// property as cycle validation sees it, and the concrete type built, each by its class.
struct CycleIdentity: Hashable, Sendable {
	let propertyClass: PropertyClassID
	let concreteTypeClass: TypeClassID
}

/// The declarations of one root's tree and the cycles among them, read from the frozen table without unfolding a path.
/// Nothing reads it to generate code yet: it is built only where a test observes it (`PerTypePlanObservation`), beside the
/// tree each path builds, to be compared with it.
///
/// It holds one node per declaration the root reaches and one entry per property each builds, and each scope's record,
/// for as long as its owner keeps it; nothing of it is stored between runs or handed to another module's run.
struct PerTypePlan: Sendable {
	/// `nil` where no declaration the root reaches is on a cycle, so each path of its tree is built once.
	init?(root: ConstructionScope) {
		let table = root.table
		let graph = OrderedGraph(root: Declaration(record: root.identity, built: nil)) { declaration in
			var targets = [Declaration]()
			for case let .instantiated(property, scopeID, erasedToConcreteExistential, propertyID) in declaration.record.propertiesToGenerate {
				targets.append(Declaration(
					record: table[scopeID],
					built: Declaration.Built(property: property, id: propertyID, erasedToConcreteExistential: erasedToConcreteExistential),
				))
			}
			return targets
		}
		guard graph.nodes.indices.contains(where: { graph.isOnCycle($0) }) else { return nil }
		self.graph = graph
		interner = table.interner
	}

	/// The declarations in the order a walk of the root's properties, in the order each scope generates them, first reaches
	/// each, with an edge for each property a declaration's scope instantiates.
	let graph: OrderedGraph<Declaration>

	/// The pair a cycle closes on at a scope built as `built`.
	func cycleIdentity(of built: Declaration.Built, record: ScopeRecord) -> CycleIdentity {
		CycleIdentity(
			propertyClass: interner.classID(of: interner.asValidatedForDependencyCycles(built.id)),
			concreteTypeClass: interner.classID(of: record.concreteTypeID),
		)
	}

	/// The declarations on a cycle that share their cycle identity with another declaration of their component, such as a
	/// constant and a `LazilyInstantiated` of one label built for one type, in position order: a path closes on whichever
	/// it built first, so what such a declaration builds differs between paths.
	var twins: [Int] {
		var declarationsByIdentity = [TwinKey: [Int]]()
		for (index, declaration) in graph.nodes.enumerated() where graph.isOnCycle(index) {
			if let built = declaration.built {
				let key = TwinKey(component: graph.component(of: index), identity: cycleIdentity(of: built, record: declaration.record))
				declarationsByIdentity[key, default: []].append(index)
			}
		}
		return declarationsByIdentity.values.filter { $0.count > 1 }.flatMap(\.self).sorted()
	}

	/// The plan as text, a line per declaration: its position, the type built, the property it is built as, `cycle` and its
	/// component's number where it is on a cycle, `twin` where it is one of `twins`, and the positions its properties build.
	var projection: String {
		let twins = Set(twins)
		var lines = [String]()
		for (index, declaration) in graph.nodes.enumerated() {
			var line = "\(index): \(declaration.record.instantiable.concreteInstantiable.asSource)"
			if let built = declaration.built {
				line.append(" as \(built.property.asSource)")
				if built.erasedToConcreteExistential {
					line.append(" erased")
				}
			}
			if graph.isOnCycle(index) {
				line.append(" cycle \(graph.component(of: index))")
			}
			if twins.contains(index) {
				line.append(" twin")
			}
			for target in graph.targets(from: index) {
				line.append(" -> \(target)")
			}
			lines.append(line)
		}
		return lines.joined(separator: "\n")
	}

	private struct TwinKey: Hashable {
		let component: Int
		let identity: CycleIdentity
	}

	private let interner: ConstructionInterner
}

/// What the tests read of each tree's plan: set by the tests, never by the tool.
public enum PerTypePlanObservation {
	/// Called with the plan of each tree a root builds that reaches a cycle, as text (`PerTypePlan.projection`).
	@TaskLocal public static var observer: (@Sendable (_ projection: String) -> Void)?
	/// Handed the projection of the bodies each plan's declarations are built as (`PlanVariants.projection`), after
	/// `observer` is handed the plan's own, where both are set.
	@TaskLocal public static var variantsObserver: (@Sendable (_ projection: String) -> Void)?
}
