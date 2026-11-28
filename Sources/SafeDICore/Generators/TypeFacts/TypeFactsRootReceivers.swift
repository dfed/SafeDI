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

/// One receive that leaves a world's root, with where it is declared, by the world's IDs: what a seam's parameter calls
/// its receivers (`SeamSignature.Receiver`), as `DependencyTreeGenerator.receivers(in:of:instantiables:)` finds them on its
/// tree. A receive inside a seam the world calls stands for itself where the call passes it on, as that seam's signature
/// carries it. Trivially copyable.
struct TypeFactsRootReceiver: Hashable, Sendable {
	/// The node whose own type makes the receive, or the seam call node a receive inside the called seam is passed through.
	let node: Int32
	/// The world's ID of the property received: the `@Received` property, or an alias's fulfilling property as declared.
	let property: Int32
	/// The world's ID of the alias's own property, or -1 for a `@Received` declaration.
	let aliasProperty: Int32
	/// The index in `TypeFactsGraph.receiverSpellings` of the property as the receiver spells it: an alias's fulfilling
	/// property spelled as the alias's type spells it (`ValueSpellings.fulfillingProperty(_:spelledAsAlias:)`), which the
	/// world's property IDs, equal under `any`, cannot tell apart.
	let spelling: Int32
	/// The world's ID of the type that declares the receive.
	let declaringType: Int32
	/// The index of the declaration's location in `TypeFactsGraph.declarationLocations`, or -1 for none.
	let declarationLocation: Int32
	/// The world's ID of the declaring type's module, or -1 where SafeDI knows none.
	let declaringModule: Int32
}

extension TypeFactsGraph {
	/// The receives that leave the root of `graph`, in the order of the nodes that make them, each node's in declaration
	/// order, each declaration – declaring type, location, property – once, at the first node that makes it.
	///
	/// A receive leaves the root where some route from the root to its node passes no node that provides it (exactly, or,
	/// for an optional receive, its unwrapped form: `ScopeGenerator.provides`), as the walk of each path finds it; an
	/// alias's receive where its own node does not provide it either. Per node, not per path: what a route can still bring
	/// a node is a union over its parents of what they let through (`openColumns`), a least fixed point over the graph,
	/// in which a route around a cycle lets through no more than the route that entered the cycle. Built once per world,
	/// over the columns of the properties own receives name, never over every property.
	static func receiversLeavingRoot(
		of graph: OrderedGraph<TypeFactsDeclaration>,
		fillHoles: [(edge: Int32, hole: SeamSignature.Hole)],
		properties: inout TypeFactsInterner<Property>,
		types: inout TypeFactsInterner<TypeDescription>,
		modules: inout TypeFactsInterner<String>,
		locations: inout TypeFactsInterner<Dependency.DeclarationLocation>,
		spellings: inout TypeFactsInterner<String>,
	) -> [TypeFactsRootReceiver] {
		let nodes = graph.nodes
		/// One own receive of a node, in its type's declaration order.
		struct Candidate {
			let dependency: Dependency
			let property: Property
			let aliasProperty: Property?
			let column: Int
		}
		var columnProperties = [Property]()
		var columnByProperty = [Property: Int]()
		var columnsByLabel = [String: [Int]]()
		func column(of property: Property) -> Int {
			if let column = columnByProperty[property] {
				return column
			}
			let column = columnProperties.count
			columnProperties.append(property)
			columnByProperty[property] = column
			columnsByLabel[property.label, default: []].append(column)
			return column
		}
		var candidatesByNode = [[Candidate]]()
		candidatesByNode.reserveCapacity(nodes.count)
		for node in nodes {
			var candidates = [Candidate]()
			// An alias or a hole declares no dependency of its own.
			if node.key.leaf == .none {
				for dependency in node.scope.instantiable.dependencies {
					switch dependency.source {
					case .received:
						candidates.append(Candidate(dependency: dependency, property: dependency.property, aliasProperty: nil, column: column(of: dependency.property)))
					case let .aliased(fulfillingProperty, _, _):
						candidates.append(Candidate(dependency: dependency, property: fulfillingProperty, aliasProperty: dependency.property, column: column(of: fulfillingProperty)))
					case .instantiated, .forwarded:
						continue
					}
				}
			}
			candidatesByNode.append(candidates)
		}
		let wordCount = (columnProperties.count + 63) / 64
		// The columns each node provides to the nodes beneath it: what it declares and is forwarded, with the instances.
		var provided = [UInt64](repeating: 0, count: nodes.count * wordCount)
		for (index, node) in nodes.enumerated() where node.key.leaf == .none && wordCount > 0 {
			let providedProperties = node.scope.propertiesToDeclare.union(node.scope.instantiable.forwardedReceivableProperties)
			for providedProperty in providedProperties {
				for column in columnsByLabel[providedProperty.label] ?? [] {
					let received = columnProperties[column]
					if received == providedProperty || (received.typeDescription.isOptional && received.asUnwrappedProperty == providedProperty) {
						provided[index * wordCount + column / 64] |= 1 << UInt64(column % 64)
					}
				}
			}
		}
		/// Whether the tree of the node `root` reads `field` as a fill binds it: some node it reaches before a node that provides
		/// the field receives the field, its optional form, or its instance (`ScopeGenerator.reads(_:)`).
		func treeReads(_ field: Property, beneath root: Int) -> Bool {
			var readForms: Set<Property> = [field, field.asOptionalProperty]
			if let instance = field.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				readForms.insert(instance)
				readForms.insert(instance.asOptionalProperty)
			}
			var nodesToVisit = [root]
			var isVisited = Set(nodesToVisit)
			while let index = nodesToVisit.popLast() {
				guard !candidatesByNode[index].contains(where: { readForms.contains($0.property) }) else { return true }
				let node = nodes[index]
				guard node.key.leaf == .none, !node.scope.propertiesToDeclare.union(node.scope.instantiable.forwardedReceivableProperties).contains(field) else { continue }
				for edge in graph.edgeIndices(from: index) where isVisited.insert(Int(graph.edgeTargets[edge])).inserted {
					nodesToVisit.append(Int(graph.edgeTargets[edge]))
				}
			}
			return false
		}
		// The columns each fill provides to the fulfiller it builds: the fields of the hole's struct it binds, and the property
		// it builds (`ScopeGenerator.init(fill:…)`'s declarations).
		var providedByFill = [Int: [UInt64]]()
		if wordCount > 0 {
			for fill in fillDeclarations(of: fillHoles, in: graph) {
				var bits = [UInt64](repeating: 0, count: wordCount)
				for declaredProperty in fill.declared {
					for column in columnsByLabel[declaredProperty.label] ?? [] {
						let received = columnProperties[column]
						if received == declaredProperty || (received.typeDescription.isOptional && received.asUnwrappedProperty == declaredProperty) {
							bits[column / 64] |= 1 << UInt64(column % 64)
						}
					}
				}
				// A wrapper read the memo of a deferred field the fill binds serves, of the read's own kind and of the field's
				// value, where the fill's tree reads the value (`ScopeGenerator.fillBoundMemo(servingWrapperRead:)`).
				for field in fill.memoFields {
					for column in columnsByLabel[field.property.label] ?? [] {
						let received = columnProperties[column]
						guard let instance = received.asLazilyInstantiatedInstanceProperty,
						      field.deferral == .deferred(isSendable: received.propertyType == .sendableLazilyInstantiated),
						      field.property.asUnwrappedProperty == instance.asUnwrappedProperty,
						      treeReads(field.property, beneath: Int(graph.edgeTargets[fill.edge]))
						else { continue }
						bits[column / 64] |= 1 << UInt64(column % 64)
					}
				}
				providedByFill[fill.edge] = bits
			}
		}
		// The columns some route from the root brings each node without a node on it providing them.
		var openColumns = [UInt64](repeating: 0, count: nodes.count * wordCount)
		for word in 0..<wordCount {
			openColumns[word] = ~0
		}
		var pending = nodes.isEmpty ? [] : [0]
		var isPending = [Bool](repeating: false, count: nodes.count)
		while let index = pending.popLast() {
			isPending[index] = false
			for edge in graph.edgeIndices(from: index) {
				let target = Int(graph.edgeTargets[edge])
				let providedByEdge = providedByFill[edge]
				var changed = false
				for word in 0..<wordCount {
					let passed = openColumns[index * wordCount + word] & ~provided[index * wordCount + word] & ~(providedByEdge?[word] ?? 0)
					let joined = openColumns[target * wordCount + word] | passed
					if joined != openColumns[target * wordCount + word] {
						openColumns[target * wordCount + word] = joined
						changed = true
					}
				}
				if changed, !isPending[target] {
					isPending[target] = true
					pending.append(target)
				}
			}
		}
		func holds(_ bits: [UInt64], _ index: Int, _ column: Int) -> Bool {
			bits[index * wordCount + column / 64] & (1 << UInt64(column % 64)) != 0
		}

		var receivers = [TypeFactsRootReceiver]()
		var kept = Set<ReceiverDeclaration>()
		func keep(node: Int, property: Property, aliasProperty: Property?, declaringType: TypeDescription, location: Dependency.DeclarationLocation?, moduleName: String?) {
			let receiver = TypeFactsRootReceiver(
				node: Int32(node),
				property: properties.id(of: property),
				aliasProperty: aliasProperty.map { properties.id(of: $0) } ?? -1,
				spelling: spellings.id(of: (aliasProperty.map { ValueSpellings.fulfillingProperty(property, spelledAsAlias: $0) } ?? property).asSource),
				declaringType: types.id(of: declaringType),
				declarationLocation: location.map { locations.id(of: $0) } ?? -1,
				declaringModule: moduleName.map { modules.id(of: $0) } ?? -1,
			)
			if kept.insert(ReceiverDeclaration(declaringType: receiver.declaringType, declarationLocation: receiver.declarationLocation, property: receiver.property)).inserted {
				receivers.append(receiver)
			}
		}
		for (index, node) in nodes.enumerated() {
			let instantiable = node.scope.instantiable
			let seamCall = node.scope.seamCall
			// The parameters a nested seam's call passes `nil` for, by label, the first of each: the tier's omissions, then
			// those no tier takes.
			var omittedByLabel = [String: SeamSignature.Parameter]()
			for parameter in (seamCall?.omittedParameters ?? []) + (seamCall?.noTierParameters ?? []) where omittedByLabel[parameter.property.label] == nil {
				omittedByLabel[parameter.property.label] = parameter
			}
			for candidate in candidatesByNode[index] where holds(openColumns, index, candidate.column) {
				// A nested seam's pass-through stands for the receives inside that seam, which its signature carries.
				let passedOn = candidate.aliasProperty == nil
					? omittedByLabel[candidate.property.label] ?? seamCall?.parameters.first(where: { $0.property == candidate.property })
					: nil
				if let aliasProperty = candidate.aliasProperty {
					// An alias is bound in its own scope's code, where the scope's own declarations provide its property too.
					guard !holds(provided, index, candidate.column) else { continue }
					keep(node: index, property: candidate.property, aliasProperty: aliasProperty, declaringType: instantiable.concreteInstantiable, location: candidate.dependency.declarationLocation, moduleName: instantiable.moduleName)
				} else if let passedOn, !passedOn.receivers.isEmpty {
					for receiver in passedOn.receivers {
						keep(node: index, property: receiver.property, aliasProperty: receiver.aliasProperty, declaringType: receiver.declaringType, location: receiver.declarationLocation, moduleName: node.scope.moduleName(ofTypeHeldUnder: receiver.declaringType))
					}
				} else {
					keep(node: index, property: candidate.property, aliasProperty: nil, declaringType: instantiable.concreteInstantiable, location: candidate.dependency.declarationLocation, moduleName: instantiable.moduleName)
				}
			}
		}
		return receivers
	}

	/// What each fill of `fillHoles` declares, by its edge: the fields it binds from the hole's struct, every field but one
	/// bound from a deferred parameter, which it reads from the caller's scope unless the hole is passed up from a seam the
	/// called seam calls (`Scope.fillUnderConstruction`), with the property the fill builds.
	/// The one fill that generates the code of a case nested by type binds the fields of every place of the case
	/// (`ScopeGenerator.caseFields(of:)`), and the others their hole's own. With them, the deferred fields it binds as their
	/// memos.
	private static func fillDeclarations(of fillHoles: [(edge: Int32, hole: SeamSignature.Hole)], in graph: OrderedGraph<TypeFactsDeclaration>) -> [(edge: Int, declared: Set<Property>, memoFields: [SeamSignature.Hole.Field])] {
		var placesByCaseKey = [Int: [String: [SeamSignature.Hole]]]()
		for (edge, hole) in fillHoles where hole.enumPlace != nil {
			placesByCaseKey[source(ofEdge: Int(edge), in: graph), default: [:]][ScopeGenerator.fillCaseKey(of: hole), default: []].append(hole)
		}
		var emittedCaseKeys = Set<[String]>()
		return fillHoles.map { edge, hole in
			let source = source(ofEdge: Int(edge), in: graph)
			var fields = hole.fields
			if hole.enumPlace != nil {
				let caseKey = ScopeGenerator.fillCaseKey(of: hole)
				if emittedCaseKeys.insert([String(source), caseKey]).inserted {
					fields = ScopeGenerator.caseFields(of: placesByCaseKey[source]?[caseKey] ?? [hole]).fields
				}
			}
			let readsDeferredFieldsFromStruct = hole.innerSeamType != nil && graph.nodes[source].scope.publicMockCall == nil
			let boundLabels = Set(fields.filter { !$0.isDeferredParameter || readsDeferredFieldsFromStruct }.map(\.property.label))
			// A deferred field the fill binds from the struct it binds as the field's memo (`SeamSignature.Hole.Field.bindingItsMemo`).
			let memoFields = readsDeferredFieldsFromStruct ? fields.filter(\.isDeferredParameter) : []
			return (Int(edge), ScopeGenerator.fieldForms(of: fields, boundLabels: boundLabels).union(ScopeGenerator.propertiesBeingBuilt(byFillOf: hole)), memoFields)
		}
	}

	/// A receive's declaration, by the world's IDs, which a receive that leaves the root by several nodes keeps once.
	private struct ReceiverDeclaration: Hashable {
		let declaringType: Int32
		let declarationLocation: Int32
		let property: Int32
	}

	/// The text of a receive that leaves a seam's root, which a test compares with the receivers the walk of the seam's tree
	/// finds (`TypeFactsRootReceiversObservation`): the declaring type, the property as the receiver spells it, the alias's
	/// own property, where the receive is declared and in which module.
	static func receiverText(declaringType: TypeDescription, property: Property, aliasProperty: Property?, location: Dependency.DeclarationLocation?, moduleName: String?) -> String {
		let spelled = aliasProperty.map { ValueSpellings.fulfillingProperty(property, spelledAsAlias: $0) } ?? property
		return receiverText(declaringType: declaringType, spelledAs: spelled.asSource, aliasProperty: aliasProperty, location: location, moduleName: moduleName)
	}

	/// `receiverText(declaringType:property:aliasProperty:location:moduleName:)` of each receive that leaves the root, in
	/// the column's order.
	var rootReceiverTexts: [String] {
		rootReceivers.map(receiverText(of:))
	}

	func receiverText(of receiver: TypeFactsRootReceiver) -> String {
		Self.receiverText(
			declaringType: typeTable[Int(receiver.declaringType)],
			spelledAs: receiverSpellings[Int(receiver.spelling)],
			aliasProperty: receiver.aliasProperty >= 0 ? propertyTable[Int(receiver.aliasProperty)] : nil,
			location: receiver.declarationLocation >= 0 ? declarationLocations[Int(receiver.declarationLocation)] : nil,
			moduleName: receiver.declaringModule >= 0 ? moduleNames[Int(receiver.declaringModule)] : nil,
		)
	}

	private static func receiverText(declaringType: TypeDescription, spelledAs spelling: String, aliasProperty: Property?, location: Dependency.DeclarationLocation?, moduleName: String?) -> String {
		var text = "\(declaringType.asSource) receives \(spelling)"
		if let aliasProperty {
			text.append(" as alias \(aliasProperty.asSource)")
		}
		if let location {
			switch location.placement {
			case let .here(line, column):
				text.append(" at \(location.filePath):\(line):\(column)")
			case .storedElsewhere:
				text.append(" at \(location.filePath), location \(location.order)")
			}
		}
		text.append(" in \(moduleName ?? "no module")")
		return text
	}
}

/// The receives that leave each seam's root as the facts find them beside those the walk of the seam's generator tree
/// finds (`DependencyTreeGenerator.receivers(in:of:instantiables:)`), handed to `comparesWalk`, which the tests set, never
/// the tool: the two must be equal, in order, on every test and fuzzer graph. The facts are built, and the walk run again,
/// only where it is set, uncounted by `GenerationWork`.
public enum TypeFactsRootReceiversObservation {
	@TaskLocal public static var comparesWalk: (@Sendable (TypeFactsRootReceiversComparison) -> Void)?
}

/// One seam's receivers of one signature pass, from the facts and from the walk, as `TypeFactsGraph.receiverText` spells
/// them.
public struct TypeFactsRootReceiversComparison: Sendable {
	/// The seam's type.
	public let seam: String
	/// What the world's column holds.
	public let facts: [String]
	/// What the walk of the seam's generator tree finds.
	public let walked: [String]
}
