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

/// The scope values a call that fills builders hands down its levels (step 3, row 1): the struct of each level of the
/// calling seam's own enums that a fill inside the call reads (`SeamHoles.innerScopes(at:innerKey:)`), made from the
/// calling seam's signature and the call's node, with no `Scope` and no name the call allocates. Empty for a call a root
/// that is no seam makes, whose tree holds no hole.
struct FillInnerScopes: Sendable {
	/// What each fill of the call takes after its case's values: one parameter per struct of the calling seam's levels that
	/// the inner seam hands the fill, in the order of their names. One entry per case the call fills, in the order of the
	/// call's hole arguments, keyed by the case (`ScopeGenerator.fillCaseKey(of:)`).
	let fills: [Fill]
	/// For each enum of the called seam, in the order the called seam declares them, the name of the scope value its
	/// dispatcher is handed, and the structs a level function of it takes where the call's case returns the called
	/// seam's struct (`FillDispatcher.innerScopeName`, `FillDispatcher.carriedInnerScopes`); an enum with neither is left out.
	let enums: [Enum]
	/// The path of the call from the root of the calling seam's tree, and that seam's holes, which the dispatchers read
	/// the structs a call hands its root dispatcher from (`FillDispatchers`); `nil` for a call a root that is no seam makes.
	fileprivate let callingSeam: (callPath: [Property], seamHoles: SeamHoles)?

	struct Fill: Equatable, Sendable {
		let caseKey: String
		/// The key of the fill of the case's first place (`ScopeGenerator.fillKey(of:)`), which the dispatchers' cases name.
		let fillKey: String
		let innerScopeParameters: [Field]
	}

	struct Enum: Equatable, Sendable {
		let key: SeamSignature.ScopeEnum.Key
		let innerScopeName: String?
		/// `nil` where the call's case returns no struct of the called seam.
		let carriedInnerScopes: [Field]?
	}

	/// A parameter, compared by its label and type.
	struct Field: Equatable, Sendable {
		let label: String
		let type: TypeDescription
	}

	/// The inner scope levels of `call`, a node of `world` whose construction fills a builder of the seam it calls.
	/// - Parameter seamTree: What `world`'s root, where it is a seam, is handed: its signature, whose holes the fills' places
	///   are; `nil` for a root that is no seam.
	/// - Throws: `NodeRecordRefusal.fill` where the call is inside a fill, or is of a public mock, or is reached along several
	///   paths from the root of a seam's tree, each of which may hand its fills other levels.
	static func of(call: DeclarationID, in world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree?) throws(NodeRecordRefusal) -> FillInnerScopes {
		let scope = world.scope(of: call)
		// A call inside a fill, which may re-enter an enclosing call's dispatchers, and a call of a public mock, whose caller
		// declares level functions, are a later step's.
		let callers = Self.callers(in: world)
		guard scope.publicMockCall == nil, !Self.isInsideFill(call, callers: callers, in: world) else { throw .fill }
		var fills = [Fill]()
		var seenCaseKeys = Set<String>()
		let calledBuilders = scope.seamCall?.calledBuilders
		guard let seamTree, !seamTree.signature.holes.isEmpty else {
			for case let .fill(hole, _, _) in scope.holeArguments where seenCaseKeys.insert(ScopeGenerator.fillCaseKey(of: hole)).inserted {
				fills.append(Fill(caseKey: ScopeGenerator.fillCaseKey(of: hole), fillKey: ScopeGenerator.fillKey(of: hole), innerScopeParameters: []))
			}
			return FillInnerScopes(fills: fills, enums: [], callingSeam: nil)
		}
		guard let callPath = Self.onlyPath(to: call, callers: callers, in: world) else { throw .fill }
		let seamHoles = SeamHoles(of: seamTree.seamRoot, seamType: seamTree.seamType)
		for case let .fill(hole, _, _) in scope.holeArguments where seenCaseKeys.insert(ScopeGenerator.fillCaseKey(of: hole)).inserted {
			let calledRootKey = calledBuilders?.keyOfFirstBuilderReaching(hole)
			let innerKey = calledRootKey.flatMap { seamHoles.carriesStruct(at: callPath, innerKey: $0) ? $0 : nil } ?? SeamSignature.ScopeEnum.rootKey(of: hole)
			fills.append(Fill(
				caseKey: ScopeGenerator.fillCaseKey(of: hole),
				fillKey: ScopeGenerator.fillKey(of: hole),
				innerScopeParameters: seamHoles.innerScopes(at: callPath, innerKey: innerKey).map { Field(label: $0.name, type: $0.enumType) },
			))
		}
		var enums = [Enum]()
		var seenEnumKeys = Set<SeamSignature.ScopeEnum.Key>()
		for scopeEnum in calledBuilders?.scopeEnums ?? [] where seenEnumKeys.insert(scopeEnum.key).inserted {
			let innerScopeName = seamHoles.innerScope(at: callPath, innerKey: scopeEnum.key)?.name
			let carriedInnerScopes = seamHoles.carriesStruct(at: callPath, innerKey: scopeEnum.key)
				? seamHoles.innerScopes(at: callPath, innerKey: scopeEnum.key).map { Field(label: $0.name, type: $0.enumType) }
				: nil
			guard innerScopeName != nil || carriedInnerScopes != nil else { continue }
			enums.append(Enum(key: scopeEnum.key, innerScopeName: innerScopeName, carriedInnerScopes: carriedInnerScopes))
		}
		return FillInnerScopes(fills: fills, enums: enums, callingSeam: (callPath, seamHoles))
	}

	/// The nodes that build each node of `world`, by node.
	private static func callers(in world: some NodeRecordSources) -> [DeclarationID: [DeclarationID]] {
		var callers = [DeclarationID: [DeclarationID]]()
		var visited: Set<DeclarationID> = [0]
		var stack: [DeclarationID] = [0]
		while let caller = stack.popLast() {
			for callee in world.edges(from: caller) {
				callers[callee, default: []].append(caller)
				if visited.insert(callee).inserted {
					stack.append(callee)
				}
			}
		}
		return callers
	}

	/// Whether some node above `declaration` along some path from the root is a fill.
	private static func isInsideFill(_ declaration: DeclarationID, callers: [DeclarationID: [DeclarationID]], in world: some NodeRecordSources) -> Bool {
		var visited = Set<DeclarationID>()
		var stack = callers[declaration] ?? []
		while let ancestor = stack.popLast() {
			guard visited.insert(ancestor).inserted else { continue }
			if world.construction(of: ancestor) == .fill {
				return true
			}
			stack.append(contentsOf: callers[ancestor] ?? [])
		}
		return false
	}

	/// The properties on the one path from `world`'s root to `declaration`, or `nil` where several paths reach it.
	private static func onlyPath(to declaration: DeclarationID, callers: [DeclarationID: [DeclarationID]], in world: some NodeRecordSources) -> [Property]? {
		var path = [Property]()
		var current = declaration
		while current != 0 {
			guard let parents = callers[current], parents.count == 1, let property = world.property(of: current) else { return nil }
			path.append(property)
			current = parents[0]
		}
		return path.reversed()
	}
}

/// The dispatchers a call that fills builders declares (step 3, row 3): one per level of the called seam's enums that leads
/// to a place the call fills, each with the parameters it takes, found as a fixed point over what the fills take
/// (`ScopeGenerator.FillDispatcher.dispatchers` and `dispatcherParameters(of:fillReads:)`), and what the call passes each
/// builder it fills. Keyed by dispatcher key and fill key, never by name: each dispatcher and fill is named by a placeholder
/// until names are asked for by key.
struct FillDispatchers: Sendable {
	/// Every dispatcher the call declares, in the order its builders first reach them. Whether a dispatcher is `@Sendable` is
	/// decided later (row 4), so each record says it is not.
	let dispatchers: [DispatcherRecord]
	/// What the call passes each builder it fills, in the order of the called seam's builders.
	let builtClosures: [Closure]

	/// What a call passes a builder it fills: the call of its root dispatcher, handed the structs of the calling seam's levels
	/// the fills take (`BuiltClosure`).
	struct Closure: Equatable, Sendable {
		/// The builder's argument label, as the call passes it.
		let label: String
		let rootDispatcherKey: String
		/// The dispatchers the root dispatcher's cases reach, itself first, in the order the call declares them.
		let dispatcherKeys: [String]
		/// The fills those dispatchers' cases reach, in the order the call declares the dispatchers and their cases.
		let fillKeys: [String]
		let carriedStructs: [BuiltClosure.CarriedStructRead]
	}

	/// The dispatchers of `call`, a node of `world` whose construction fills a builder of the seam it calls.
	/// - Parameters:
	///   - fillParameters: What each fill of the call takes after its case's values, by the fill's key
	///     (`ScopeGenerator.fillKey(of:)`), in the order of the call's hole arguments.
	///   - innerScopes: `FillInnerScopes.of(call:in:seamTree:)` of the call.
	///   - names: The call's names (`FillNames`), which its dispatchers and their cases' targets are named by; placeholders
	///     where `nil`, which no record's identity reads.
	static func of(call: DeclarationID, in world: some NodeRecordSources, fillParameters: [(fillKey: String, parameters: [SeamSignature.Hole.Field])], innerScopes: FillInnerScopes, names callNames: FillNames? = nil) -> FillDispatchers {
		let scope = world.scope(of: call)
		guard let calledBuilders = scope.seamCall?.calledBuilders else { return FillDispatchers(dispatchers: [], builtClosures: []) }
		var filledSites = Set<SeamSignature.Hole.Site>()
		var fillNames = [String: String]()
		for case let .fill(hole, _, _) in scope.holeArguments {
			filledSites.insert(hole.site)
			let fillKey = ScopeGenerator.fillKey(of: hole)
			fillNames[fillKey] = callNames?.functionName(ofFill: ScopeGenerator.fillCaseKey(of: hole)) ?? "fill \(fillKey)"
		}
		var innerScopeNameByKey = [SeamSignature.ScopeEnum.Key: String]()
		var carriedInnerScopesByKey = [SeamSignature.ScopeEnum.Key: [(name: String, type: TypeDescription)]]()
		for scopeEnum in innerScopes.enums {
			innerScopeNameByKey[scopeEnum.key] = scopeEnum.innerScopeName
			carriedInnerScopesByKey[scopeEnum.key] = scopeEnum.carriedInnerScopes?.map { (name: $0.label, type: $0.type) }
		}
		// The call's names claim its fills' functions before its dispatchers', each dispatcher's in the order the call declares
		// them, which `FillDispatcher.dispatchers` claims them in: an allocator holding the fills' names claims the same.
		// Placeholder names otherwise: no name reaches a record's identity.
		var names = GeneratedNameAllocator(reserving: callNames.map { Set($0.reservedNames).union($0.fills.map(\.functionName)) } ?? [])
		let dispatchers = ScopeGenerator.FillDispatcher.dispatchers(
			of: calledBuilders,
			filledSites: filledSites,
			enclosingDispatchers: [:],
			fillNames: fillNames,
			names: &names,
			innerScopeNameByKey: innerScopeNameByKey,
			carriedInnerScopesByKey: carriedInnerScopesByKey,
		)
		var fillReads = [String: [SeamSignature.Hole.Field]]()
		for (fillKey, parameters) in fillParameters {
			fillReads[fillKey] = parameters
		}
		let parametersByKey = ScopeGenerator.FillDispatcher.dispatcherParameters(of: dispatchers, fillReads: fillReads)
		let dispatcherByKey = Dictionary(dispatchers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		var builtClosures = [Closure]()
		let filledSiteNumbers = calledBuilders.siteNumbers(of: filledSites)
		for builder in calledBuilders.builders where calledBuilders.reaches(anyOf: filledSiteNumbers, from: builder.enumKey, onRoutesOf: nil) {
			// As the call's builder argument decides it: a builder that takes the called seam's struct is handed its root
			// level's struct, unless a level of the called seam's hole type keeps its enum form to pass a scope value on.
			let returnsBuilderStruct = builder.takesBuilderStruct && !calledBuilders.builders.contains { calledBuilder in
				calledBuilder.enumKey.holeType == builder.enumKey.holeType
					&& innerScopes.enums.contains { $0.key == calledBuilder.enumKey && $0.innerScopeName != nil && $0.carriedInnerScopes == nil }
			}
			let rootDispatcherKey = ScopeGenerator.FillDispatcher.key(of: builder.enumKey, returnsBuilderStruct: returnsBuilderStruct)
			var dispatcherKeys = [String]()
			var fillKeys = [String]()
			var keysToVisit = [rootDispatcherKey]
			var visited = Set<String>()
			while let key = keysToVisit.popLast() {
				guard visited.insert(key).inserted, let dispatcher = dispatcherByKey[key] else { continue }
				keysToVisit.append(contentsOf: dispatcher.cases.reversed().compactMap(\.target?.key).filter { dispatcherByKey[$0] != nil })
			}
			for dispatcher in dispatchers where visited.contains(dispatcher.key) {
				dispatcherKeys.append(dispatcher.key)
				for target in dispatcher.cases.compactMap(\.target) where dispatcherByKey[target.key] == nil && !fillKeys.contains(target.key) {
					fillKeys.append(target.key)
				}
			}
			let carriedStructs = (dispatcherByKey[rootDispatcherKey]?.carriedInnerScopes ?? []).compactMap { carriedInnerScope -> BuiltClosure.CarriedStructRead? in
				guard let callingSeam = innerScopes.callingSeam,
				      callingSeam.seamHoles.carriedStruct(at: callingSeam.callPath, innerKey: builder.enumKey, innerScopeName: carriedInnerScope.name) != nil
				else { return nil }
				return BuiltClosure.CarriedStructRead(upName: carriedInnerScope.upName, structType: carriedInnerScope.type)
			}
			builtClosures.append(Closure(label: builder.generatedOnlyArgumentLabel, rootDispatcherKey: rootDispatcherKey, dispatcherKeys: dispatcherKeys, fillKeys: fillKeys, carriedStructs: carriedStructs))
		}
		return FillDispatchers(
			dispatchers: dispatchers.map { DispatcherRecord(dispatcher: $0, parameters: parametersByKey[$0.key, default: []], isSendable: false) },
			builtClosures: builtClosures,
		)
	}
}

/// A call's inner scope levels and dispatchers as the tree makes them, handed to a test beside node records'
/// (`FillInnerScopes`, `FillDispatchers`): the call's property, its fills that emit code, in its children's order, what
/// each fill takes beyond its case's payload, by key, its dispatchers through `projection(of:parameters:)`, and what it
/// passes each builder it fills. Names a call allocates are left out.
struct FillLevelsObservation: Sendable {
	let call: Property
	/// The tree's fills of the call, each with the levels it takes.
	let fills: [FillInnerScopes.Fill]
	/// The keys of the fills whose trees read the levels they are offered (`ScopeGenerator.readsFillInnerScopes`): a fact of
	/// the fill's subtree, which row 1 does not decide; every other fill takes none of the levels row 1 offers it.
	let fillKeysReadingInnerScopes: Set<String>
	let fillParameters: [(fillKey: String, parameters: [SeamSignature.Hole.Field])]
	let dispatchers: [String]
	let builtClosures: [Closure]

	struct Closure: Equatable, Sendable {
		let label: String
		let rootDispatcherKey: String
		let carriedStructs: [BuiltClosure.CarriedStructRead]
	}

	/// Called with each call's observation as the tree writes its dispatchers, when set: by the node records hook in a test,
	/// never by the tool.
	@TaskLocal static var observer: (@Sendable (FillLevelsObservation) -> Void)?

	/// `dispatcher` and `parameters`, what it takes, as text for meaning: every field but the names a call allocates
	/// (the dispatcher's function name, its targets' names, the names it takes carried structs under).
	static func projection(of dispatcher: ScopeGenerator.FillDispatcher, parameters: [SeamSignature.Hole.Field]) -> String {
		var parts = [
			dispatcher.key,
			dispatcher.enumType.asSource,
			dispatcher.returnType.asSource,
			"sendableFamily \(dispatcher.isSendableFamily)",
			"passUp \(dispatcher.takesPassUp)",
			"outer \(dispatcher.takesValuesOfOuterTypes)",
			"seam \(dispatcher.seamType?.asSource ?? "")",
			"innerScope \(dispatcher.innerScopeName ?? "")",
			"perRoute \(dispatcher.decidesPerRoute)",
			"builderStruct \(dispatcher.returnsBuilderStruct)",
			"carried \(dispatcher.carriedInnerScopes.map { "\($0.name): \($0.type.asSource)" }.joined(separator: ", "))",
			"parameters \(parameters.map(\.property.asSource).joined(separator: ", "))",
		]
		for dispatcherCase in dispatcher.cases {
			parts.append([
				"case \(dispatcherCase.name)",
				"target \(dispatcherCase.target.map { "\($0.key) passUp \($0.takesPassUp) reused \($0.reusedCarriedInnerScopes.map { "\($0.name): \($0.type.asSource)" })" } ?? "none")",
				"payload \(dispatcherCase.carriesPayload) forwarded \(dispatcherCase.hasForwardedValue) wrapperBuilder \(dispatcherCase.returnsWrapperBuilder)",
				"values \(dispatcherCase.values.map { $0.map(\.property.asSource).joined(separator: ", ") } ?? "none")",
				"fillCase \(dispatcherCase.isFillCase) carriedInnerKey \(dispatcherCase.carriedInnerKey?.spelling ?? "")",
				"boundLater \(dispatcherCase.labelsBoundLater.sorted())",
				"letChild \(dispatcherCase.isLetChild) carrierUse \(dispatcherCase.carrierUse.map { "\($0)" } ?? "none") deferred \(dispatcherCase.carriesDeferredFields)",
			].joined(separator: "; "))
		}
		return parts.joined(separator: "\n")
	}

	/// The ways node records' rows 1 and 3 for `call`, a node of `world`, differ from this observation of the tree's, or `nil`
	/// where node records refuse the call's levels.
	func differences(fromRecordsOf call: DeclarationID, in world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree?) -> [String]? {
		let path = "\(self.call.asSource)"
		let innerScopes: FillInnerScopes
		let dispatchers: FillDispatchers
		do {
			innerScopes = try FillInnerScopes.of(call: call, in: world, seamTree: seamTree)
		} catch {
			return nil
		}
		dispatchers = FillDispatchers.of(call: call, in: world, fillParameters: fillParameters, innerScopes: innerScopes)
		var differences = [String]()
		// Fills are compared by case key: the tree declares them in the order it builds them, node records in the order of
		// the call's hole arguments.
		let recordFills = innerScopes.fills.map { fill in
			fillKeysReadingInnerScopes.contains(fill.fillKey) ? fill : FillInnerScopes.Fill(caseKey: fill.caseKey, fillKey: fill.fillKey, innerScopeParameters: [])
		}.sorted { $0.caseKey < $1.caseKey }
		if recordFills != fills.sorted(by: { $0.caseKey < $1.caseKey }) {
			differences.append("\(path): fills’ inner scope levels \(recordFills) in node records, \(fills) in the tree")
		}
		let recordDispatchers = dispatchers.dispatchers.map { Self.projection(of: $0.dispatcher, parameters: $0.parameters) }
		if recordDispatchers != self.dispatchers {
			differences.append("\(path): dispatchers\n\(recordDispatchers.joined(separator: "\n--\n"))\nin node records, the tree’s\n\(self.dispatchers.joined(separator: "\n--\n"))")
		}
		let recordClosures = dispatchers.builtClosures.map { Closure(label: $0.label, rootDispatcherKey: $0.rootDispatcherKey, carriedStructs: $0.carriedStructs) }
		if recordClosures != builtClosures {
			differences.append("\(path): built closures \(recordClosures) in node records, \(builtClosures) in the tree")
		}
		return differences
	}
}

extension FillLevelsObservation {
	/// The ways node records' rows 1 and 3 differ from `observations`, the tree's of `world`'s calls: each observation is
	/// compared with every node of the world that calls a seam as its property and fills a builder, and one whose levels
	/// node records make must agree with it. A call no such node's levels are made for is not compared.
	static func differences(of observations: [FillLevelsObservation], in world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree?) -> [String] {
		let filledCalls = (0..<Int32(world.declarationCount)).filter { declaration in
			world.scope(of: declaration).holeArguments.contains { holeArgument in
				switch holeArgument {
				case .fill:
					true
				case .passUp:
					false
				}
			}
		}
		var differences = [String]()
		for observation in observations {
			let compared = filledCalls.filter { world.property(of: $0) == observation.call }.compactMap { observation.differences(fromRecordsOf: $0, in: world, seamTree: seamTree) }
			guard !compared.contains(where: \.isEmpty), let first = compared.first else { continue }
			differences += first
		}
		return differences
	}
}
