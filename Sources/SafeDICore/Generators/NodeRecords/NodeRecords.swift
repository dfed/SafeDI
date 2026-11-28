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

/// Why a world's records are not made from its per-type facts at this stage: the first node, in declaration order, that is
/// of a kind a later stage adds. A refusal is of the whole world, which keeps the tree's path.
enum NodeRecordRefusal: String, Error, CaseIterable {
	/// The node is built by anything but its type's initializer or `instantiate()`: a seam's or a public mock's call, a
	/// hand-written mock, a construction function or a fill.
	case construction
	/// A mock root's node takes a parameter with a default value, which a mock holds in the type's configuration, or its
	/// type has a hand-written mock, whose defaults that configuration takes too.
	case mockDefaultValuedParameter
	/// A mock root's node is an actor, whose arguments a mock sends it.
	case mockActor
	/// A mock root's node whose override is not its parent's field under the node's own label: two children of one node
	/// share a label, which a mock root names apart.
	case mockOverrideNotParentField
	/// A mock root binds a value that is no node of its world before its tree, or names one apart: a parameter of
	/// `mock()`, an override of a value its tree receives only if available, a builder, a wrapper around an instance.
	case mockRootBindsOtherThanNodes
	/// The node is built in a `@Sendable` function of its own: a `SendableInstantiator`, erased or not, or a
	/// `SendableLazilyInstantiated`, which `sendableClaim(of:in:)` discharges: its record is `NodeRecordKind.sendable`'s.
	case sendable
	/// A `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`
	/// (`DeclarationsAnsweringReads.sendableFunctionCapturesWrapper`): an error the tree reports, which the records
	/// cannot, so the world keeps its tree.
	case sendableFunctionCapturesWrapper
	/// The node is built as an `ErasedInstantiator`, or as a constant or an `Instantiator` erased to its property's type,
	/// which `erasedClaim(of:in:)` discharges: its record is `NodeRecordKind.erased`'s.
	case erased
	/// The node's type declares a rename, a hole, or an instantiated dependency its scope does not build.
	case renameOrHole
	/// The node's call passes fills.
	case fill
	/// The node is a hole of a seam's tree, or on the route to one, that the tree reaches along more than one path: the names
	/// a route binds follow its path, so one variant per node cannot hold the place.
	case holeOnSeveralPaths
	/// The node is a hole of a seam's tree held in, or reached through, a wrapper but an `Instantiator`: an erased, lazy or
	/// `@Sendable` one, whose builder function binds what the hole's place reads apart, which hole records do not write yet.
	case holeInWrapper
	/// The node is on a cycle, and no kind that makes a node on a cycle claims it (`cycleClaim(of:in:)`), or the world's
	/// edges close a cycle that `NodeBuildOrder` meets.
	case cycle
	/// A variant of a node on a cycle holds an optional parameter's key (`TypeFactsGraph.optionalParameterKey`, a value
	/// or `nil`), or a cycle's identity is twinned (a value and a lazily instantiated wrapper of it), where the facts'
	/// variants and today's bodies may partition the cycle's places apart.
	case cycleVariantsPartitionApart
	/// A node on a cycle is built at two places whose trees close the cycle on different places above them, so that one
	/// place of its variant cannot stand for both.
	case cycleMemberBuiltTwoWays
	/// The function a call closes a cycle on takes a parameter of a label some declaration holds lazily, which a call can
	/// find as the wrapper at its site where the records read the callee's view.
	case cycleTakesParameters
	/// Two bodies of a world with a cycle name one variant's function apart, or hand the functions its body refers to
	/// different names (`CycleFunctionNames`), where its one place cannot stand for both.
	case cycleBuilderNameShared
	/// The node is built as a `LazilyInstantiated`, which `lazyClaim(of:in:)` discharges: its record is
	/// `NodeRecordKind.lazy`'s. Also a world whose records read a wrapper's instance where no record does yet: a rename
	/// fulfilled by one (`DeclarationsAnsweringReads.renameReadsWrappersInstance`), a rename in a seam's own tree of one
	/// its root is handed, and a mock root's scope that declares or forwards a lazily instantiated property.
	case lazy
	/// The node's type receives a property only if available.
	case onlyIfAvailable
	/// The node stands for an unavailable dependency, or a seam built inline.
	case unavailableOrInlineSeam
	/// The node's type has no initializer to build it with.
	case noInitializer
	/// Two of a node's children wait on each other, or a child's tree receives the child's own property: a loop of builders.
	case builderLoop
	/// A node has more than one variant, so its record would not be a function of the node alone.
	case nodeHasSeveralVariants
	/// A declaration whose answers a producer of the facts still owes (`TypeFactsWorld.owedFacts(of:)`): two places of one
	/// of its variants can answer a read apart, which one record per variant cannot write. The whole world is refused,
	/// whatever its kinds, until each producer lands and clears its bit.
	case readAnsweredTwoWays
	/// The engine could not lay the root out from the records.
	case notLaidOut
	/// A loop of builders in a seam's own tree, whose levels the tree holds in a box and whose members bind its holes'
	/// payloads, which node records do not write.
	case builderLoopBoxed
	/// A member of a loop of builders whose function takes cycle parameters, or that closes a cycle on a function that
	/// does, which the tree wraps through a `__safeDI_<label>_received` function its loop's parent declares, where the
	/// tree names that function apart from another function of its name, which these records do not, or where the
	/// member's place is no construction these records build.
	case builderLoopTakesCycleParameters
	/// A cycle whose closed-on function, or a function between it and the call that closes it, makes a member of a loop of
	/// builders again: the type key engine declares the cycle's functions together where the cycle is first entered,
	/// where the tree nests each in the body that builds it.
	case cycleHoldsLoopRebinding
	/// Making the records, or laying the root out from them, threw something other than a refusal
	/// (`NodeRecords.refusingWhatRecordsThrow(_:)`). The world keeps its tree, which reports whatever it reports.
	case recordsThrew
}

/// What a world's records read of a node beside the frozen interface (`TypeFactsWorld`): the scope it builds and the
/// property it builds as, from which a node's construction facts come until the facts' columns hold them.
protocol NodeRecordSources: TypeFactsWorld {
	func scope(of declaration: DeclarationID) -> ConstructionScope
	/// The property the declaration is built as, `nil` for the root.
	func property(of declaration: DeclarationID) -> Property?
	/// Whether the declaration's built value is erased to its property's type (`erasedToConcreteExistential`).
	func isErased(_ declaration: DeclarationID) -> Bool
	/// The text of a label a read asks about (`Read.label`).
	func text(ofLabel label: WorldLabelID) -> String
	/// Whether the world is a mock root's, each of whose nodes reads its override.
	var isMockWorld: Bool { get }
}

extension TypeFactsGraph: NodeRecordSources {
	func scope(of declaration: DeclarationID) -> ConstructionScope {
		graph.nodes[Int(declaration)].scope
	}

	func property(of declaration: DeclarationID) -> Property? {
		graph.nodes[Int(declaration)].property
	}

	func isErased(_ declaration: DeclarationID) -> Bool {
		graph.nodes[Int(declaration)].key.erasedToConcreteExistential
	}

	func text(ofLabel label: WorldLabelID) -> String {
		labelTexts[Int(label)]
	}
}

/// The records of one world's places, made from its per-type facts (`TypeFactsWorld`) with no `ScopeGenerator`: one
/// `BuiltPlaceRecord` per variant, and the root's body as the places it builds, in order. A variant's place is made once
/// and shared by every call of it, so the engine reads it once per view (`TypeKeyLayout.read(_:)`).
///
/// Records are made only for a world each of whose nodes is built by its type's initializer, off every cycle, with one
/// variant, as a constant or in any of SafeDI's wrappers, erased or not (`NodeRecordKind`); any other world is refused
/// with the first kind it holds, and so is a world the tree reports an error of that the records cannot: a `@Sendable`
/// function that captures a wrapper that is not `Sendable` (`NodeRecordRefusal.sendableFunctionCapturesWrapper`).
///
/// One variant per node is enough here because a record reads only answers every call into a variant gives alike. Each
/// `PlaceRead.source` is the label `createInitializerArguments` names, which the engine resolves per view, or the
/// instance of a lazily instantiated property declared above the node, which a receive by value reads
/// (`DeclarationsAnsweringReads`). That holds only while both key projections are inert: no receive only if available,
/// and no cycle, so nothing is still being built where it is read. A node that receives a property only if available
/// (`receivesOnlyIfAvailable`) reads what each call of its variant finds (`OnlyIfAvailableAnswers`, from the calls and
/// `TypeFactsEdge.buildPosition`, since the world's answers do not model sibling order), never a variant's keys, and a
/// world whose calls of one variant find different answers is refused. Records still carry today's `functionName`, which
/// the engine's allocator names apart.
struct NodeRecords: Sendable {
	/// What `body`, which makes records or lays a root out from them, returns, or the refusal it throws; anything else it
	/// throws is `NodeRecordRefusal.recordsThrew`. While the tree exists, the records' path never rejects a world: a world
	/// the records cannot make keeps its tree, which reports the world's errors as it always has. Each call that throws
	/// is fixed, and this rule goes, once no accepted graph reports `recordsThrew` and the tree goes.
	static func refusingWhatRecordsThrow<Value>(_ body: () throws -> Value) -> Result<Value, NodeRecordRefusal> {
		do {
			return try .success(body())
		} catch {
			return .failure(error as? NodeRecordRefusal ?? .recordsThrew)
		}
	}

	/// - Parameters:
	///   - world: A production root's world.
	///   - seamTree: What a seam's own root is handed: its parameters, the nearest declarations of their labels, the
	///     instances of `LazilyInstantiated` properties among them, a deferred parameter's memo included, which its tree
	///     reads through their wrappers, and the labels of those held in a wrapper a `@Sendable` function cannot capture.
	///     `nil` for any other root.
	///   - seamHoles: A seam's holes, by path, which its holes' places read (`seamHolePlace(of:in:seamHoles:rootLazilyInstantiatedInstanceProperties:)`);
	///     `nil` for any other root, whose holes are passed `nil`.
	///   - declaredTypeNames: The names the modules SafeDI read declare types by at file scope, which the check of an erased
	///     instantiator's first generic argument reads (`checkForwardsBuiltTypesProperties(_:in:declaredTypeNames:)`).
	///     `nil` for a mock root's world, where no kind claims an erased instantiator and the mock's own tree reports it.
	/// - Throws: A `NodeRecordRefusal` where the world holds a kind node records do not make, or what an initializer's
	///   arguments throw.
	init(world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree? = nil, seamHoles: SeamHoles? = nil, declaredTypeNames: DeclaredTypeNames?) throws {
		let declarationCount = world.declarationCount
		var kinds = [NodeRecordKind]()
		kinds.reserveCapacity(declarationCount)
		for declaration in 0..<Int32(declarationCount) {
			try kinds.append(Self.kind(of: declaration, in: world))
			try Self.checkReadsNoSeamRootValue(of: seamTree, declaration, in: world)
			try Self.checkMakesNoLoopMemberAgain(inSeamTree: seamTree, declaration, in: world)
			try Self.checkForwardsBuiltTypesProperties(declaration, in: world, declaredTypeNames: declaredTypeNames)
		}
		let rootLazilyInstantiatedInstanceProperties = seamTree?.rootLazilyInstantiatedInstanceProperties ?? []
		// A seam's tree binds the payloads of its holes before the scopes on their routes (`placeOnRouteToHole`).
		let bindsHolesPayloads = seamHoles != nil && kinds.contains(.seamHole)
		let holdsCycle = (0..<Int32(declarationCount)).contains(where: world.isOnCycle)
		// A world with a cycle makes a record per variant, each read of its own calls; any other world, one per node.
		if holdsCycle {
			try Self.checkVariantsPartitionAlike(inWorldWithCycle: world)
		} else {
			var variantByDeclaration = [VariantID](repeating: -1, count: declarationCount)
			for variant in 0..<Int32(world.variantCount) {
				let declaration = Int(world.declaration(of: variant))
				guard variantByDeclaration[declaration] < 0 else { throw NodeRecordRefusal.nodeHasSeveralVariants }
				variantByDeclaration[declaration] = variant
			}
		}
		// A world whose edges close a cycle builds each node's children in the order step 0's sibling-order fixed point gives
		// them (`TypeFactsEdge.buildPosition`), which `NodeBuildOrder` stands in for only off every cycle.
		let order: NodeBuildOrder? = holdsCycle ? nil : try NodeBuildOrder(world: world)
		let onlyIfAvailableAnswers = try OnlyIfAvailableAnswers(world: world, rootParameters: seamTree?.parameters ?? [])
		let answeringDeclarations = DeclarationsAnsweringReads(
			world: world,
			rootLazilyInstantiatedInstanceProperties: seamTree?.rootLazilyInstantiatedInstanceProperties ?? [],
			rootNonSendableWrapperLabels: seamTree?.rootNonSendableWrapperLabels ?? [],
		)
		// The tree reports the capture as an error, which the records cannot.
		guard !answeringDeclarations.sendableFunctionCapturesWrapper else { throw NodeRecordRefusal.sendableFunctionCapturesWrapper }
		// A rename's record binds it from its fulfilling property's label, or from a wrapper's instance as the tree's rule
		// reads it, never from an instance read otherwise.
		guard !answeringDeclarations.renameReadsWrappersInstance else { throw NodeRecordRefusal.lazy }
		func edgeIndices(of declaration: DeclarationID) -> [Int] {
			order?.edgeIndices(of: declaration) ?? world.edgeFacts(from: declaration).enumerated().sorted { $0.element.buildPosition < $1.element.buildPosition }.map(\.offset)
		}
		// The place of `variant`, made of its children's places, its record (none for a hole's place, which is its site's
		// code), and the types its function spells `@escaping`.
		func makePlace(
			of variant: VariantID,
			declaration: DeclarationID,
			children: [GeneratedCode],
			childrensEscaping: Set<TypeDescription>,
			functionName: String?,
			isMadeSendable: Bool,
			cycleParameters: [Property],
			callCycleArguments: [PlaceRead],
			instanceProperties: Set<Property>,
			receivedFunction: (name: String, arguments: [PlaceRead], parent: DeclarationID)?,
			receivedFunctionNames: [DeclarationID: String],
		) throws -> (place: GeneratedCode, record: PlaceRecord?, escaping: Set<TypeDescription>) {
			// A hole's place is its site's code, written as text, and the payloads bound before it: places, not one record.
			guard kinds[Int(declaration)] != .seamHole else {
				return (Self.seamHolePlace(of: declaration, in: world, seamHoles: seamHoles ?? SeamHoles(), rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties), nil, [])
			}
			let scope = world.scope(of: declaration)
			let instantiable = scope.instantiable
			var escaping = Set(instantiable.initializer?.typesDeclaredEscaping ?? [])
			escaping.formUnion(instantiable.mockInitializer?.typesDeclaredEscaping ?? [])
			// A call of a seam spells the builder types its signature declares `@escaping` so, as its tree does.
			escaping.formUnion(scope.seamCall?.typesDeclaredEscaping ?? [])
			escaping.formUnion(childrensEscaping)
			// A member of a loop of builders first makes again the members its tree receives, whatever its kind
			// (`NodeRecords+Loops.swift`): a call of a seam, before its guard. A label its function takes is that parameter.
			let loopRebindings = Self.loopRebindings(
				of: variant,
				functionName: functionName,
				cycleParameters: cycleParameters,
				hiddenLabels: Set(instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property.label) + cycleParameters.map(\.label)),
				receivedFunctionNames: receivedFunctionNames,
				in: world,
			)
			let calleeChildren = children
			let children = loopRebindings + children
			let madeRecord: PlaceRecord = switch kinds[Int(declaration)] {
			// A hole's place is made above, from no record.
			case .builtByInitializer, .erased, .lazy, .sendable, .seamHole:
				// One record serves the four: what tells them apart, it reads of the node.
				try .built(Self.builtByInitializerRecord(of: declaration, variant: variant, in: world, lazilyInstantiatedInstanceProperties: instanceProperties, typesDeclaredEscaping: escaping, children: children))
			case .inlineSeam:
				try .built(Self.inlineSeamRecord(of: declaration, variant: variant, in: world, lazilyInstantiatedInstanceProperties: instanceProperties, typesDeclaredEscaping: escaping, children: children))
			case .seamCall:
				try .alias(Self.seamCallRecord(of: declaration, variant: variant, in: world, routes: seamCallRoutes, lazilyInstantiatedInstanceProperties: instanceProperties, typesDeclaredEscaping: escaping, loopRebindings: loopRebindings, children: calleeChildren))
			case .receivesOnlyIfAvailable:
				try .built(Self.receivesOnlyIfAvailableRecord(
					of: declaration,
					variant: variant,
					in: world,
					answers: onlyIfAvailableAnswers,
					lazilyInstantiatedInstanceProperties: instanceProperties,
					typesDeclaredEscaping: escaping,
					children: children,
				))
			case .unavailableDependency:
				try .alias(Self.unavailableDependencyRecord(of: declaration, in: world))
			case .rename:
				try .alias(Self.renameRecord(of: declaration, variant: variant, in: world, answers: onlyIfAvailableAnswers, readsWrappersInstance: answeringDeclarations.renamesReadingWrappersInstance.contains(variant)))
			case .cycle:
				try .built(Self.cycleRecord(of: declaration, variant: variant, in: world, lazilyInstantiatedInstanceProperties: instanceProperties, typesDeclaredEscaping: escaping, children: children))
			case .mockConstruction:
				try .built(Self.mockConstructionRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: escaping, children: children))
			}
			var record = Self.record(madeRecord, functionName: functionName, isMadeSendable: isMadeSendable, cycleParameters: cycleParameters, callCycleArguments: callCycleArguments)
			// A member wrapped through a `_received` function declares only its builder function: the statement after it, which
			// declares that function, binds it.
			var receivedFunctionPlace: GeneratedCode?
			if let receivedFunction {
				guard case var .built(built) = record else { throw NodeRecordRefusal.builderLoopTakesCycleParameters }
				built.bindsProperty = false
				record = .built(built)
				receivedFunctionPlace = Self.receivedFunctionPlace(
					of: declaration,
					property: built.property,
					named: receivedFunction.name,
					callingFunctionNamed: built.functionName,
					parameters: cycleParameters,
					arguments: receivedFunction.arguments,
					isSendable: built.isSendable || built.property.propertyType.isSendable,
					typesDeclaredEscaping: escaping,
					receivedFunctionNames: receivedFunctionNames,
					inBodyOf: receivedFunction.parent,
					in: world,
				)
			}
			let recordPlace: GeneratedCode = switch record {
			case let .alias(aliasRecord):
				// A place written as text: the engine copies it as written.
				.place(PlacePlan(code: .text(aliasRecord.text), record: record))
			case .built, .closer:
				.place(PlacePlan(code: .empty, record: record))
			}
			let place = receivedFunctionPlace.map { GeneratedCode.sequence([recordPlace, $0]) } ?? recordPlace
			if bindsHolesPayloads, let seamHoles {
				return (Self.placeOnRouteToHole(place, of: declaration, in: world, seamHoles: seamHoles, rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties), record, escaping)
			} else {
				return (place, record, escaping)
			}
		}
		let seamCallRoutes = seamTree.map { SeamCallRoutes(world: world, seamTree: $0) } ?? SeamCallRoutes()
		// What each place's body holds, found by a walk from the root with a stack, since a tree can be as deep as the
		// module has types: the places of the variants it calls, and the calls that close a cycle on a place being built
		// above them. A variant's place is made once and shared, which holds only where every place that reads it closes on
		// the same places above: each place notes the variants on a cycle its tree closes on above it and those it builds,
		// and a second place of the variant must have the first on its path and none of the second.
		// What arrives at each read of each variant, which types a function's parameters (rule 3): folded only in a world
		// whose walk meets a call that closes a cycle, the only one whose functions take parameters, and kept while the
		// records are made.
		var readArrivals: TypeFactsReadArrivals?
		func arrivals() -> TypeFactsReadArrivals {
			if let readArrivals {
				return readArrivals
			} else {
				let folded = TypeFactsReadArrivals(world: world)
				readArrivals = folded
				return folded
			}
		}
		var entries = [[BodyEntry]](repeating: [], count: world.variantCount)
		var postOrder = [VariantID]()
		var isWalked = [Bool](repeating: false, count: world.variantCount)
		var variantsClosedOn = [Set<VariantID>](repeating: [], count: world.variantCount)
		var cycleVariantsBuilt = [Set<VariantID>](repeating: [], count: world.variantCount)
		var isOnPath = [Bool](repeating: false, count: world.variantCount)
		var labelsDeclaredBetween = [Set<String>](repeating: [], count: world.variantCount)
		var variantsBetween = [Set<VariantID>](repeating: [], count: world.variantCount)
		var twins = TwinsOnPath(world: world, holdsCycle: holdsCycle)
		var stack = [PlaceFrame(variant: 0, edgeIndices: edgeIndices(of: 0))]
		isOnPath[0] = true
		while let top = stack.last {
			if top.next < top.edgeIndices.count {
				stack[stack.count - 1].next += 1
				let calls = world.calls(of: top.variant)
				let callee = calls[calls.startIndex + top.edgeIndices[top.next]]
				if isOnPath[Int(callee)] {
					// The places between the place the call closes on and the call: what they declare, and the parameters of
					// their own functions, are what the closed-on function takes as parameters rather than capturing.
					if let closedOn = stack.lastIndex(where: { $0.variant == callee }) {
						for frame in stack[(closedOn + 1)...] {
							let declared = Self.labelsDeclared(by: world.declaration(of: frame.variant), in: world)
							labelsDeclaredBetween[Int(callee)].formUnion(declared)
							variantsBetween[Int(callee)].insert(frame.variant)
						}
					}
					stack[stack.count - 1].entries.append(.closer(closingOn: callee))
					stack[stack.count - 1].variantsClosedOn.insert(callee)
				} else if isWalked[Int(callee)] {
					guard variantsClosedOn[Int(callee)].allSatisfy({ isOnPath[Int($0)] }), !cycleVariantsBuilt[Int(callee)].contains(where: { isOnPath[Int($0)] }) else {
						throw NodeRecordRefusal.cycleMemberBuiltTwoWays
					}
					// Today's tree closes the cycle on a place of the declaration, or of its twin, above, where the shared place
					// builds it again.
					guard !cycleVariantsBuilt[Int(callee)].contains(where: { twins.holdsPlaceOfItOrItsTwin(world.declaration(of: $0)) }) else {
						throw NodeRecordRefusal.cycleVariantsPartitionApart
					}
					stack[stack.count - 1].entries.append(.place(callee))
					stack[stack.count - 1].variantsClosedOn.formUnion(variantsClosedOn[Int(callee)])
					stack[stack.count - 1].cycleVariantsBuilt.formUnion(cycleVariantsBuilt[Int(callee)])
				} else {
					try twins.enter(world.declaration(of: callee))
					isOnPath[Int(callee)] = true
					stack.append(PlaceFrame(variant: callee, edgeIndices: edgeIndices(of: world.declaration(of: callee))))
				}
				continue
			}
			stack.removeLast()
			isOnPath[Int(top.variant)] = false
			twins.leave(world.declaration(of: top.variant))
			entries[Int(top.variant)] = top.entries
			guard let parent = stack.indices.last else { continue }
			isWalked[Int(top.variant)] = true
			postOrder.append(top.variant)
			var closedOn = top.variantsClosedOn
			closedOn.remove(top.variant)
			variantsClosedOn[Int(top.variant)] = closedOn
			var built = top.cycleVariantsBuilt
			if world.isOnCycle(world.declaration(of: top.variant)) {
				built.insert(top.variant)
			}
			cycleVariantsBuilt[Int(top.variant)] = built
			stack[parent].entries.append(.place(top.variant))
			stack[parent].variantsClosedOn.formUnion(closedOn)
			stack[parent].cycleVariantsBuilt.formUnion(built)
		}
		// The names each body gives the functions it declares and refers to, as today's tree names them.
		let functionNames = try holdsCycle ? CycleFunctionNames(entries: entries, variantsClosedOn: variantsClosedOn, in: world) : nil
		// Each place, made after the places its body holds.
		// Every place a body holds is made before it (`postOrder`), so none reads `.empty`.
		var places = [GeneratedCode](repeating: .empty, count: world.variantCount)
		var records = [PlaceRecord?](repeating: nil, count: world.variantCount)
		var typesDeclaredEscaping = [Set<TypeDescription>](repeating: [], count: world.variantCount)
		var closedOnFromSendableFunction = [Set<VariantID>](repeating: [], count: world.variantCount)
		// The parameters of the function of each variant a call beneath it closes a cycle on, and what each call of it passes
		// them, made once per variant (`NodeRecords+CycleParameters.swift`).
		var cycleParametersByVariant = [[TypeFactsParameter]?](repeating: nil, count: world.variantCount)
		func cycleParameters(of variant: VariantID) -> [TypeFactsParameter] {
			if let parameters = cycleParametersByVariant[Int(variant)] {
				return parameters
			}
			// The facts list every read their outcomes fold marks a parameter, which holds today's parameters in their order
			// and also values today's function captures where a call nested in its scope closes on it. Today's function
			// takes a label as a parameter only where a place between it and a call that closes on it declares that label,
			// or takes it as a parameter of its own function (`CycleParameter`).
			cycleParametersByVariant[Int(variant)] = []
			// Where a production function takes the wrapper that answers a read of its value, today's tree takes the value, and
			// so do the records while they are compared with the tree's: the generator's form, as check 35 projects it in
			// `TypeFactsChecks`. Once the tree goes, the records take the fact's wrapper unchanged.
			let parameters = world.parameters(of: variant, arrivals: arrivals()).filter { parameter in
				let label = parameter.property.label
				return labelsDeclaredBetween[Int(variant)].contains(label)
					|| variantsBetween[Int(variant)].contains { $0 != variant && cycleParameters(of: $0).contains { $0.property.label == label } }
			}.map { parameter in
				parameter.generatorProperty.map { TypeFactsParameter(property: $0, readsInstanceOfWrapper: false) } ?? parameter
			}
			cycleParametersByVariant[Int(variant)] = parameters
			return parameters
		}
		// What a receive by value reads as a wrapper's instance (`lazilyInstantiatedInstanceProperties`), at each place's
		// own construction and at the call of its function. The declarations above answer it (`DeclarationsAnsweringReads`),
		// but inside a function a lazy cycle closes on, the function's parameter is the nearest declaration of its label, as
		// today's tree has it (`CycleParameter`): a parameter by value hides a wrapper above, and a wrapper parameter offers
		// its instance, read through the optional where `nil` arrives. Found by a walk from the root with a stack; a place
		// shared by two bodies must see one set from both, or the world keeps its tree.
		// Every variant of `postOrder` is a place the walk from the root reaches, so the walk resolves each.
		var instancePropertiesAtCall = [Set<Property>](repeating: [], count: world.variantCount)
		var isResolved = [Bool](repeating: false, count: world.variantCount)
		var instancePropertiesInFunction = [Set<Property>](repeating: [], count: world.variantCount)
		func applying(_ parameters: [String: TypeFactsParameter], to properties: Set<Property>) -> Set<Property> {
			guard !parameters.isEmpty else { return properties }
			var applied = properties.filter { parameters[$0.label] == nil }
			for parameter in parameters.values {
				let wrapper = parameter.property.asUnwrappedProperty
				guard wrapper.propertyType.isLazilyInstantiated, let instance = wrapper.asLazilyInstantiatedInstanceProperty else { continue }
				applied.insert(parameter.property.typeDescription.isOptional ? instance.asOptionalProperty : instance)
			}
			return applied
		}
		var placesToResolve: [(variant: VariantID, parametersInScope: [String: TypeFactsParameter])] = [(0, [:])]
		while let (variant, parametersInScope) = placesToResolve.popLast() {
			// Only the labels the variant's own function takes are read at its call (`cycleArguments`), so a parameter of an
			// enclosing function the variant does not take never sets two places of it apart.
			let labelsTaken = Set(cycleParameters(of: variant).map(\.property.label))
			let atCall = applying(parametersInScope, to: answeringDeclarations.lazilyInstantiatedInstanceProperties(readBy: variant)).filter { labelsTaken.contains($0.label) }
			if isResolved[Int(variant)] {
				guard instancePropertiesAtCall[Int(variant)] == atCall else { throw NodeRecordRefusal.cycleTakesParameters }
				continue
			}
			instancePropertiesAtCall[Int(variant)] = atCall
			isResolved[Int(variant)] = true
			var parametersInFunction = parametersInScope
			for parameter in cycleParameters(of: variant) {
				parametersInFunction[parameter.property.label] = parameter
			}
			// Rule 3: a variant keyed with a wrapper where some call passes `nil` takes the optional wrapper, which its own
			// construction reads through (`theme?.instance`), whichever call resolved it. Its children read their own.
			var parametersOfConstruction = parametersInFunction
			let keys = world.keys(of: variant)
			if keys.contains(TypeFactsGraph.optionalLazilyInstantiatedParameterKey) || keys.contains(TypeFactsGraph.optionalSendableLazilyInstantiatedParameterKey) {
				for parameter in world.parameters(of: variant, arrivals: arrivals()) where parameter.readsInstanceOfWrapper && parameter.property.typeDescription.isOptional {
					parametersOfConstruction[parameter.property.label] = parameter
				}
			}
			instancePropertiesInFunction[Int(variant)] = applying(parametersOfConstruction, to: answeringDeclarations.lazilyInstantiatedInstanceProperties(readBy: variant))
			// A label the place declares is its own children's nearest declaration.
			for label in Self.labelsDeclared(by: world.declaration(of: variant), in: world) {
				parametersInFunction[label] = nil
			}
			for case let .place(callee) in entries[Int(variant)].reversed() {
				placesToResolve.append((callee, parametersInFunction))
			}
		}
		// A loop member whose function takes cycle parameters, or whose place closes a cycle on such a function, is wrapped
		// through a `__safeDI_<label>_received` function its parent's body declares after it (`ScopeGenerator`'s loop
		// rebindings), named in that body by the member's declaration: a call's that closes a cycle, the one it closes on.
		var receivedFunctionNames = [VariantID: [DeclarationID: String]]()
		var parentByVariant = [VariantID: VariantID]()
		// Every function a place of the world declares: a `_received` name the tree would name apart from one of them, which
		// these records do not.
		var functionNamesInWorld = Set<String>()
		for variant in postOrder {
			if let property = world.property(of: world.declaration(of: variant)) {
				functionNamesInWorld.insert(functionNames?.functionName(of: variant) ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
			}
		}
		// The root's body is no place of the walk's order.
		for parent in [0] + postOrder {
			let loopEdges = world.edgeFacts(from: world.declaration(of: parent)).filter { $0.loop >= 0 }
			let loopMembers = Set(loopEdges.map(\.child))
			// A call that closes a cycle receives what the function it closes on receives, less what that function binds,
			// its own wrapper made again among them: it is on a loop of the tree's only beside another member.
			let membersWithMates = Set(loopEdges.filter { edge in loopEdges.contains { $0.loop == edge.loop && $0.child != edge.child } }.map(\.child))
			for entry in entries[Int(parent)] where !loopMembers.isEmpty {
				// A place's own function takes parameters only where a cycle closes on it.
				let callee: VariantID
				let functionName: String?
				let takesParameters: Bool
				switch entry {
				case let .place(placed):
					parentByVariant[placed] = parent
					callee = placed
					functionName = functionNames?.functionName(of: placed)
					takesParameters = !variantsBetween[Int(placed)].isEmpty
				case let .closer(closingOn: closedOn):
					callee = closedOn
					functionName = functionNames?.closedOnFunctionName(of: closedOn, inBodyOf: parent)
					takesParameters = membersWithMates.contains(world.declaration(of: closedOn))
				}
				let declaration = world.declaration(of: callee)
				guard takesParameters,
				      loopMembers.contains(declaration),
				      !cycleParameters(of: callee).isEmpty,
				      let property = world.property(of: declaration)
				else { continue }
				let name = ReservedName.receivedBuilderFunctionName(of: functionName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
				guard !functionNamesInWorld.contains(name), receivedFunctionNames[parent]?.values.contains(name) != true else {
					throw NodeRecordRefusal.builderLoopTakesCycleParameters
				}
				receivedFunctionNames[parent, default: [:]][declaration] = name
			}
		}
		// Any other loop member a cycle closes on, or a function a loop's member closes a cycle on, reads nothing of the body
		// around it but its loop's functions, and the type key engine lays its function out further out than the tree
		// nests it: refused until the engine keeps the tree's nesting.
		let receivedFunctionDeclarations = Set(receivedFunctionNames.values.flatMap(\.keys))
		for variant in postOrder where !variantsBetween[Int(variant)].isEmpty && !receivedFunctionDeclarations.contains(world.declaration(of: variant)) {
			let declaration = world.declaration(of: variant)
			let isLoopMember = world.parents(of: declaration).contains { parent in
				world.edgeFacts(from: parent.parent).contains { $0.child == declaration && $0.loop >= 0 }
			}
			let closesFromLoopMember = variantsBetween[Int(variant)].contains { between in
				entries[Int(between)].contains { entry in
					guard case let .closer(closingOn: callee) = entry, callee == variant else { return false }
					return world.edgeFacts(from: world.declaration(of: between)).contains { $0.child == declaration && $0.loop >= 0 }
				}
			}
			guard !isLoopMember, !closesFromLoopMember else {
				throw NodeRecordRefusal.builderLoopTakesCycleParameters
			}
			guard !([variant] + variantsBetween[Int(variant)]).contains(where: { !world.madeAgain(of: $0).isEmpty }) else {
				throw NodeRecordRefusal.cycleHoldsLoopRebinding
			}
		}
		// What the body of `variant` reads as a wrapper's instance, where a call in it closes a cycle: its function's, but for
		// the labels it declares itself, whose own declarations are nearer.
		func instancePropertiesInBody(of variant: VariantID) -> Set<Property> {
			let scope = world.scope(of: world.declaration(of: variant))
			return instancePropertiesInFunction[Int(variant)].filter { !scope.declaredLabels.contains($0.label) }.union(scope.declaredLazilyInstantiatedInstanceProperties)
		}
		// Each call of a function passes each parameter what the nearest declaration of its label at the call is: the place's
		// own call what the body around it holds, and a call that closes a cycle on it what the body holding that call holds,
		// so a call that holds the wrapper and another that holds the value each pass their own.
		func cycleArguments(of variant: VariantID, holding instanceProperties: Set<Property>) -> [PlaceRead] {
			Self.cycleArguments(
				of: cycleParameters(of: variant),
				unavailableProperties: onlyIfAvailableAnswers.unavailableProperties(of: variant),
				lazilyInstantiatedInstanceProperties: instanceProperties,
			)
		}
		func body(of variant: VariantID) throws -> (children: [GeneratedCode], escaping: Set<TypeDescription>, closedOnFromSendableFunction: Set<VariantID>, closedOn: Set<VariantID>) {
			let indentation = variant == 0 ? TypeKeyBody.rootStatementIndentation : ScopeGenerator.standardIndent
			var children = [GeneratedCode]()
			var escaping = Set<TypeDescription>()
			var fromSendableFunction = Set<VariantID>()
			var closedOn = Set<VariantID>()
			for entry in entries[Int(variant)] {
				switch entry {
				case let .closer(closingOn: callee):
					let closedOnDeclaration = world.declaration(of: callee)
					let functionName = functionNames?.closedOnFunctionName(of: callee, inBodyOf: variant)
					let arguments = cycleArguments(of: callee, holding: instancePropertiesInBody(of: variant))
					if let name = receivedFunctionNames[variant]?[closedOnDeclaration], let property = world.property(of: closedOnDeclaration) {
						// A loop member's call wraps the function it closes on through its `_received` function, which spells what the
						// type's own initializers and the seam it calls declare `@escaping`.
						let scope = world.scope(of: closedOnDeclaration)
						var escaping = Set(scope.instantiable.initializer?.typesDeclaredEscaping ?? [])
						escaping.formUnion(scope.instantiable.mockInitializer?.typesDeclaredEscaping ?? [])
						escaping.formUnion(scope.seamCall?.typesDeclaredEscaping ?? [])
						children.append(.indented(Self.receivedFunctionPlace(
							of: closedOnDeclaration,
							property: property,
							named: name,
							callingFunctionNamed: functionName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
							parameters: cycleParameters(of: callee).map(\.property),
							arguments: arguments,
							isSendable: property.propertyType.isSendable || Self.buildsInSendableFunction(closedOnDeclaration, in: world),
							typesDeclaredEscaping: escaping,
							receivedFunctionNames: receivedFunctionNames[variant] ?? [:],
							inBodyOf: world.declaration(of: variant),
							in: world,
						), by: indentation))
					} else {
						let closer = try Self.closingRecord(
							closingOn: closedOnDeclaration,
							from: variant,
							functionName: functionName,
							cycleArguments: arguments,
							in: world,
						)
						children.append(.indented(.place(PlacePlan(code: .empty, record: closer)), by: indentation))
					}
					closedOn.insert(callee)
					// A call that hands a `Sendable` wrapper its function refers to the function it closes on from a
					// `@Sendable` function.
					if Self.buildsInSendableFunction(closedOnDeclaration, in: world) {
						fromSendableFunction.insert(callee)
					}
				case let .place(callee):
					children.append(.indented(places[Int(callee)], by: indentation))
					escaping.formUnion(typesDeclaredEscaping[Int(callee)])
					closedOn.formUnion(variantsClosedOn[Int(callee)])
					fromSendableFunction.formUnion(closedOnFromSendableFunction[Int(callee)])
				}
			}
			return (children, escaping, fromSendableFunction, closedOn)
		}
		for variant in postOrder {
			let declaration = world.declaration(of: variant)
			let body = try body(of: variant)
			// A place's function is `@Sendable` where its wrapper is, or where a call beneath it that closes a cycle on it
			// refers to it from a `@Sendable` function; such a function holds every reference its tree makes to the
			// functions enclosing it, which must then be `@Sendable` too.
			var fromSendableFunction = body.closedOnFromSendableFunction
			let isMadeSendable = fromSendableFunction.contains(variant)
			if isMadeSendable || Self.buildsInSendableFunction(declaration, in: world) {
				fromSendableFunction.formUnion(body.closedOn)
			}
			fromSendableFunction.remove(variant)
			closedOnFromSendableFunction[Int(variant)] = fromSendableFunction
			// A loop member wrapped through a `_received` function is called by that function, which passes its parameters.
			let receivedFunction = parentByVariant[variant].flatMap { parent in
				receivedFunctionNames[parent]?[declaration].map { name in
					(name: name, arguments: cycleArguments(of: variant, holding: instancePropertiesAtCall[Int(variant)]), parent: world.declaration(of: parent))
				}
			}
			let (place, record, escaping) = try makePlace(
				of: variant,
				declaration: declaration,
				children: body.children,
				childrensEscaping: body.escaping,
				functionName: functionNames?.functionName(of: variant),
				isMadeSendable: isMadeSendable,
				// Only a function a cycle closes on takes parameters; every other captures what it reads.
				cycleParameters: body.closedOn.contains(variant) ? cycleParameters(of: variant).map(\.property) : [],
				callCycleArguments: body.closedOn.contains(variant) && receivedFunction == nil ? cycleArguments(of: variant, holding: instancePropertiesAtCall[Int(variant)]) : [],
				instanceProperties: instancePropertiesInFunction[Int(variant)],
				receivedFunction: receivedFunction,
				receivedFunctionNames: parentByVariant[variant].flatMap { receivedFunctionNames[$0] } ?? [:],
			)
			records[Int(variant)] = record
			places[Int(variant)] = place
			typesDeclaredEscaping[Int(variant)] = escaping
		}
		let rootBody = try body(of: 0).children
		// Last, so that a world refused for a kind reports that kind first.
		for declaration in 0..<Int32(declarationCount) where Self.owesFacts(declaration, in: world) {
			throw NodeRecordRefusal.readAnsweredTwoWays
		}
		self.rootBody = rootBody
		self.records = records
		declarationByVariant = (0..<Int32(world.variantCount)).map(world.declaration(of:))
	}

	/// The record of `declaration`'s place in `variant`'s body. The root, variant 0, has none.
	func record(of _: DeclarationID, variant: VariantID) -> PlaceRecord? {
		records[Int(variant)]
	}

	/// The root's body: a place for each of the root's children, in the order the root builds them, indented as a root's
	/// statements are.
	let rootBody: [GeneratedCode]

	/// How many variants have a record, which is every variant but the root's.
	var recordCount: Int {
		declarationByVariant.indices.dropFirst().count { record(of: declarationByVariant[$0], variant: VariantID($0)) != nil }
	}

	/// Each variant's declaration.
	private let declarationByVariant: [DeclarationID]

	/// By variant.
	private let records: [PlaceRecord?]

	/// A place `init(world:seamTree:seamHoles:declaredTypeNames:)`'s walk is making: its variant, its node's edges in build
	/// order and the next to walk, what its body holds so far, and what the places walked beneath it hand it.
	private struct PlaceFrame {
		let variant: VariantID
		let edgeIndices: [Int]
		var next = 0
		var entries = [BodyEntry]()
		/// The variants on a cycle above the place that its tree closes on.
		var variantsClosedOn = Set<VariantID>()
		/// The variants on a cycle the place's tree builds.
		var cycleVariantsBuilt = Set<VariantID>()
	}

	/// Every refusal `world` holds, each once, in the order of `NodeRecordRefusal`'s cases: what a test reports of a world, so
	/// that each stage counts the worlds it frees.
	static func refusals(in world: some NodeRecordSources, seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree? = nil, declaredTypeNames: DeclaredTypeNames?) -> [NodeRecordRefusal] {
		var refusals = Set<NodeRecordRefusal>()
		for declaration in 0..<Int32(world.declarationCount) {
			refusals.formUnion(kindAndRefusals(of: declaration, in: world).refusals)
			if owesFacts(declaration, in: world) {
				refusals.insert(.readAnsweredTwoWays)
			}
			do {
				try checkReadsNoSeamRootValue(of: seamTree, declaration, in: world)
			} catch {
				refusals.insert(error)
			}
			do {
				try checkMakesNoLoopMemberAgain(inSeamTree: seamTree, declaration, in: world)
			} catch {
				refusals.insert(error)
			}
			do {
				try checkForwardsBuiltTypesProperties(declaration, in: world, declaredTypeNames: declaredTypeNames)
			} catch {
				refusals.insert(error)
			}
		}
		var declarationsWithAVariant = Set<DeclarationID>()
		let holdsCycle = (0..<Int32(world.declarationCount)).contains(where: world.isOnCycle)
		for variant in 0..<Int32(world.variantCount) where !holdsCycle && !declarationsWithAVariant.insert(world.declaration(of: variant)).inserted {
			refusals.insert(.nodeHasSeveralVariants)
		}
		if holdsCycle {
			// A world with a cycle is built in step 0's order, and its walk refuses what its places' closing needs.
			if refusals.isEmpty, case let .failure(refusal as NodeRecordRefusal) = Result(catching: { try NodeRecords(world: world, seamTree: seamTree, declaredTypeNames: declaredTypeNames) }) {
				refusals.insert(refusal)
			}
		} else {
			do {
				_ = try NodeBuildOrder(world: world)
			} catch {
				refusals.insert(error)
			}
		}
		do {
			_ = try OnlyIfAvailableAnswers(world: world, rootParameters: seamTree?.parameters ?? [])
		} catch {
			refusals.insert(error)
		}
		let answeringDeclarations = DeclarationsAnsweringReads(
			world: world,
			rootLazilyInstantiatedInstanceProperties: seamTree?.rootLazilyInstantiatedInstanceProperties ?? [],
			rootNonSendableWrapperLabels: seamTree?.rootNonSendableWrapperLabels ?? [],
		)
		if answeringDeclarations.sendableFunctionCapturesWrapper {
			refusals.insert(.sendableFunctionCapturesWrapper)
		}
		if answeringDeclarations.renameReadsWrappersInstance {
			refusals.insert(.lazy)
		}
		return NodeRecordRefusal.allCases.filter(refusals.contains)
	}

	/// Whether a producer of the facts still owes `declaration`'s answers (`TypeFactsWorld.owedFacts(of:)`), which refuses
	/// its world as `readAnsweredTwoWays`. The mock root's bits are not owed where a test lays mock roots out from their
	/// records (`NodeRecordsObservation.laysOutMockRoots`), a mode no run of `generate` turns on; every run of it refuses
	/// every mock world.
	private static func owesFacts(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		let owedOnlyOutsideTests: TypeFactsOwedFacts = NodeRecordsObservation.laysOutMockRoots ? [.mockRootPin, .mockRootRecord, .mockRootBinding] : []
		return !world.owedFacts(of: declaration).subtracting(owedOnlyOutsideTests).isEmpty
	}

	/// Refuses `declaration`'s world where its type reads what a seam's root is handed as node records do not write it: as
	/// `lazy`, a rename of one of the instances of `LazilyInstantiated` properties the root is handed, which its
	/// tree binds from the wrapper's instance and a rename's record would bind from the label; as `renameOrHole`, the seam's own
	/// rename that keeps a deferred parameter's label, which the tree binds from the parameter's autoclosure and writes no
	/// record of. A receive of such an instance is answered (`DeclarationsAnsweringReads`).
	private static func checkReadsNoSeamRootValue(of seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree?, _ declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) {
		guard let seamTree else { return }
		let renamesAnInstance = world.scope(of: declaration).instantiable.dependencies.contains { dependency in
			switch dependency.source {
			case let .aliased(fulfillingProperty, _, _):
				seamTree.rootLazilyInstantiatedInstanceProperties.contains(fulfillingProperty.asUnwrappedProperty)
			case .received, .instantiated, .forwarded:
				false
			}
		}
		guard !renamesAnInstance else { throw .lazy }
		// The root declares no rename through a variant of its own, so it is the scope of each rename among its edges.
		guard declaration == 0 else { return }
		let readsAnAutoclosure = world.edges(from: declaration).contains { edge in
			world.kind(of: edge) == .alias && world.property(of: edge).map { seamTree.autoclosureLabels.contains($0.label) } == true
		}
		guard !readsAnAutoclosure else { throw .renameOrHole }
	}

	/// Refuses `declaration`'s world as `builderLoopBoxed` where it is a seam's own and `declaration` makes a member of a
	/// loop of builders again.
	private static func checkMakesNoLoopMemberAgain(inSeamTree seamTree: DependencyTreeGenerator.RootScopeInfo.SeamTree?, _ declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) {
		guard seamTree == nil || world.madeAgain(from: declaration).isEmpty && !world.loopMembersSharedApart.contains(declaration) else { throw .builderLoopBoxed }
	}

	/// Refuses `declaration`'s world where it is an `ErasedInstantiator` or a `SendableErasedInstantiator` whose first
	/// generic argument is not the `@Forwarded` properties of the type it builds: an error the tree reports where it builds
	/// the place (`ErasedInstantiatorForwardedPropertiesMismatchError`), which the records cannot, so the world keeps its
	/// tree, in a run no test observes too, which builds no tree beside a root's records. A fill's place, which the tree
	/// checks seeing through its hole's modules, is checked here without them: its world is refused as a fill's already.
	private static func checkForwardsBuiltTypesProperties(_ declaration: DeclarationID, in world: some NodeRecordSources, declaredTypeNames: DeclaredTypeNames?) throws(NodeRecordRefusal) {
		switch world.kind(of: declaration) {
		case .erasedInstantiator, .sendableErasedInstantiator:
			guard let declaredTypeNames, let property = world.property(of: declaration) else { return }
			let forwardsBuiltTypesProperties = property.firstGenericMatchesForwardedProperties(of: world.scope(of: declaration).instantiable, declaringModuleNames: [], declaredTypeNames: declaredTypeNames)
			guard forwardsBuiltTypesProperties else { throw .erased }
		case .constant, .instantiator, .sendableInstantiator, .lazy, .sendableLazy, .alias, .hole:
			break
		}
	}

	/// The kind of record `declaration` is made as, or the first refusal it holds (`kindAndRefusals(of:in:)`).
	private static func kind(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> NodeRecordKind {
		let (kind, refusals) = kindAndRefusals(of: declaration, in: world)
		if let refusal = refusals.first {
			throw refusal
		}
		return kind
	}

	/// The kind `declaration` is made as, and every refusal it holds: those of the claim a kind makes of it, and
	/// every check of `builtByInitializer` the claim does not discharge (`refusalsOfBuiltByInitializer(_:in:)`). A node of two kinds,
	/// one claimed, is still refused for the other.
	private static func kindAndRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> (kind: NodeRecordKind, refusals: [NodeRecordRefusal]) {
		let claim = claim(of: declaration, in: world)
		var discharged = claim?.discharges ?? []
		// A production node on a cycle that a lane's kind claims is that kind's record, and the walk closes the cycle on it
		// as on a node of kind `cycle` (`NodeRecords+Cycle.swift`).
		if claim != nil, !world.isMockWorld, world.isOnCycle(declaration) {
			discharged.insert(.cycle)
		}
		let refusals = (claim?.refusals ?? []) + refusalsOfBuiltByInitializer(declaration, in: world).filter { !discharged.contains($0) } + loopRefusals(of: declaration, in: world)
		return (claim?.kind ?? .builtByInitializer, refusals)
	}

	/// What a kind claims of `declaration`, or `nil` where none does. Each production kind is one term of the production
	/// chain, after the test's, in the order of `NodeRecordKind`'s cases, calling its file's classifier, which returns
	/// `nil` for a node not of its kind: `?? <kind>Claim(of: declaration, in: world)`. A mock world's nodes are the
	/// mock writer's alone, so no production kind's record, which reads no override, is made of one.
	private static func claim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		// A test's claim comes first, so that it can claim a node another kind would.
		guard !world.isMockWorld else {
			return testClaim(of: declaration, in: world) ?? mockConstructionClaim(of: declaration, in: world)
		}
		// A hole is claimed apart from the chains below, which the compiler cannot type-check as one.
		guard let claim = testClaim(of: declaration, in: world) ?? seamHoleClaim(of: declaration, in: world) else {
			let seamClaim = inlineSeamClaim(of: declaration, in: world)
				?? seamCallClaim(of: declaration, in: world)
			let answerReadingClaim = seamClaim
				?? unavailableDependencyClaim(of: declaration, in: world)
				?? receivesOnlyIfAvailableClaim(of: declaration, in: world)
				?? renameClaim(of: declaration, in: world)
			return answerReadingClaim
				?? erasedClaim(of: declaration, in: world)
				?? lazyClaim(of: declaration, in: world)
				?? sendableClaim(of: declaration, in: world)
				?? cycleClaim(of: declaration, in: world)
		}
		return claim
	}

	/// The claim a test makes of `declaration` by its type's name (`NodeRecordsObservation.claimsForTesting`).
	private static func testClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		NodeRecordsObservation.claimsForTesting[world.scope(of: declaration).instantiable.concreteInstantiable.asSource].map { discharged in
			NodeRecordClaim(kind: .builtByInitializer, discharges: Set(discharged.compactMap(NodeRecordRefusal.init(rawValue:))))
		}
	}
}

/// What a kind claims of a node (`NodeRecords.claim(of:in:)`): the kind its record is made as, the refusals of
/// `refusalsOfBuiltByInitializer(_:in:)` the kind discharges, which are the kinds it makes, and any refusal of its own the node holds, of its
/// kind but a shape it does not make yet.
struct NodeRecordClaim: Sendable {
	let kind: NodeRecordKind
	let discharges: Set<NodeRecordRefusal>
	var refusals = [NodeRecordRefusal]()
}

/// The kinds of node `NodeRecords` makes a record of. Each is made by one file of this folder, `NodeRecords+<Kind>.swift`,
/// which holds its classifier (whether a node is of the kind) and its record. A world holding a node of no kind is
/// refused whole.
enum NodeRecordKind: Sendable {
	/// A constant or an `Instantiator` built by its type's initializer or `instantiate()`, off every cycle, with nothing
	/// received only if available, renamed or filled in its scope.
	case builtByInitializer
	/// A seam of another module built inline, because no module SafeDI knows generates its initializer, and otherwise a
	/// node `builtByInitializer` makes: its line ends with the comment that says why (`NodeRecords+InlineSeam.swift`).
	case inlineSeam
	/// A call of another module's seam that passes it no builder, made as a node `builtByInitializer` makes the seam's leaf,
	/// whose builder function begins with the call's guard line (`NodeRecords+SeamCall.swift`).
	case seamCall
	/// A property instantiated only if available that no declaration fulfills, bound to `nil` and written as text
	/// (`NodeRecords+UnavailableDependency.swift`).
	case unavailableDependency
	/// A node that would be of kind `builtByInitializer` but that its type receives a property only if available, which its
	/// construction is passed where the variant's calls find it available, and `nil` where not (`OnlyIfAvailableAnswers`).
	case receivesOnlyIfAvailable
	/// A rename a scope declares (`@Received(fulfilledByDependencyNamed:ofType:)`), written as text: bound from its fulfilling
	/// property, or, only if available, to `nil` where no declaration it reads is available (`NodeRecords+Rename.swift`).
	case rename
	/// An `ErasedInstantiator`, or a constant or an `Instantiator` erased to its property's type (`NodeRecords+Erased.swift`).
	case erased
	/// A `LazilyInstantiated`, erased or not (`NodeRecords+Lazy.swift`).
	case lazy
	/// A `SendableInstantiator`, erased or not, or a `SendableLazilyInstantiated` (`NodeRecords+Sendable.swift`).
	case sendable
	/// A hole a seam's tree declares, whose place is its site's code, or a property passed `nil` in any other world
	/// (`NodeRecords+SeamHole.swift`).
	case seamHole
	/// A node on a cycle, otherwise of stage 1's kinds, whose children's places include the closing place of each call back
	/// to a place being built above it (`NodeRecords+Cycle.swift`).
	case cycle
	/// A node of a mock root's world that `builtByInitializer` would make in a production root's, which reads its override before it
	/// calls its type's initializer (`NodeRecords+MockConstruction.swift`).
	case mockConstruction
}
