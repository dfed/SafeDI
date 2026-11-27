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

extension DependencyTreeGenerator {
	/// A site of a hole the walk of a seam's tree met (`placesWalkingTreeOnce`), in the order the generated code builds the
	/// sites (`buildSites(in:)`): its case in the place graph and the levels the walk took to its owner, root first.
	struct WalkedSite {
		let site: SeamSignature.Hole.Site
		let caseIndex: Int
		let route: SeamSignature.Places.Route
	}

	/// A call in a seam's tree that presents places of the seam it calls, as the walk added it (`placesWalkingTreeOnce`), in
	/// the order the per-site walk meets the calls (`holesPassedUp(in:)`): the case of each place it presents, in the order of
	/// the called seam's passed-up holes, and the route to the call's own level, root first, that level last.
	struct WalkedCall {
		let caseIndices: [Int]
		let route: SeamSignature.Places.Route
	}

	/// A seam's place graph (`SeamSignature.Places`), built by one walk of its generator tree, with every site of its own
	/// tree's places in generation order.
	///
	/// The walk visits each scope of the tree that holds a site once, depth first in the order the code is generated, and
	/// drafts each scope's level once per next property on the way to a site: what the per-site walk (`fields(of:)`) drafts
	/// once per site, by the same rules – binding order, `@Sendable` functions, cycle parameters and the re-entries a cycle
	/// hands, a loop's rebindings, a public mock's receives bound again, fill levels and their base stacks, the places a
	/// buildable tree holds. A level is added to the graph when the walk first meets a site beneath it, so levels, edges and
	/// cases are numbered in the order the sites first reach them, as `SeamPlacesBuilder.addSite` numbers them.
	///
	/// It walks every path's scopes, so it removes the per-site walk's cost of drafting each level once per site beneath it
	/// but still grows with the paths. A scope met again on another path, once a seam's hole subtrees are shared, is to be
	/// skipped where its levels are argued equal, which needs every fact a level beneath reads of the path above (the
	/// declarations and `@Sendable` functions above it, its cycle re-entries) in the key: that waits for the shared trees,
	/// whose tests can show it.
	///
	/// A call that presents places of the seam it calls adds, after every site of the seam's own tree, a level of its own
	/// beneath the level that declares it and a case there for each place it presents, as `SeamPlacesBuilder.addPassedUpPlace`
	/// adds them, the calls taken in the order the per-site walk meets them: depth first in child order, not generation order.
	/// What the calls on a site's path add to its case (`SeamPlacesBuilder.addPresentation`) is the caller's to add, per walked
	/// site and per walked call.
	static func placesWalkingTreeOnce(
		of seam: Instantiable,
		generator: ScopeGenerator,
		bindsReceivesAgain: Bool,
		namesApartAtRoot: PublicMockRootLevel.NamesApart,
		parameters: [SeamSignature.Parameter],
		receiversByParameter: [Property: [SeamSignature.Receiver]],
		seamTypeAccess: AccessLevel,
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
	) -> (builder: SeamPlacesBuilder, sites: [WalkedSite], calls: [WalkedCall]) {
		var walk = SeamPlacesWalk(
			seam: seam,
			bindsReceivesAgain: bindsReceivesAgain,
			namesApartAtRoot: namesApartAtRoot,
			parameters: parameters,
			receiversByParameter: receiversByParameter,
			seamTypeAccess: seamTypeAccess,
			proof: proof,
			instantiables: instantiables,
		)
		walk.walk(from: generator)
		walk.addCallsCases()
		return (walk.builder, walk.sites, walk.calls)
	}

	/// The state of one walk of a seam's tree. It holds its drafts and memos for that walk only.
	private struct SeamPlacesWalk {
		init(
			seam: Instantiable,
			bindsReceivesAgain: Bool,
			namesApartAtRoot: PublicMockRootLevel.NamesApart,
			parameters: [SeamSignature.Parameter],
			receiversByParameter: [Property: [SeamSignature.Receiver]],
			seamTypeAccess: AccessLevel,
			proof: TypeAccessProof,
			instantiables: [TypeDescription: Instantiable],
		) {
			self.seam = seam
			self.bindsReceivesAgain = bindsReceivesAgain
			self.namesApartAtRoot = namesApartAtRoot
			self.parameters = parameters
			self.receiversByParameter = receiversByParameter
			self.seamTypeAccess = seamTypeAccess
			self.proof = proof
			self.instantiables = instantiables
			seamDependencies = DependenciesByProperty(of: seam)
			labelsNoRootChildDeclares = bindsReceivesAgain ? namesApartAtRoot.labels.union(parameters.map(\.property.label)) : []
			let forwardedLabels = Set(seam.dependencies.filter { $0.source == .forwarded }.map(\.property.label))
			receivedLabels = Set(parameters.map(\.property.label)).subtracting(forwardedLabels)
		}

		let seam: Instantiable
		let bindsReceivesAgain: Bool
		let namesApartAtRoot: PublicMockRootLevel.NamesApart
		let parameters: [SeamSignature.Parameter]
		let receiversByParameter: [Property: [SeamSignature.Receiver]]
		let seamTypeAccess: AccessLevel
		let proof: TypeAccessProof
		let instantiables: [TypeDescription: Instantiable]
		let seamDependencies: DependenciesByProperty
		/// A mock's root declares no child of a label its root level's fields hold, or one only names apart bind
		/// (`PublicMockRootLevel`).
		let labelsNoRootChildDeclares: Set<String>
		/// The labels the seam receives from its caller: its parameters but the ones it forwards.
		let receivedLabels: Set<String>

		private(set) var builder = SeamPlacesBuilder()
		private(set) var sites = [WalkedSite]()
		/// For each of `sites`, what a replay of a subtree that holds it needs: the position of each frame's next child on
		/// its path, and its case's family.
		private var siteRecords = [(positions: [Int], isBuiltInSendableFunction: Bool, siteOpensSendableFunction: Bool)]()
		private(set) var calls = [WalkedCall]()

		/// A scope's dependencies by property, and where a cycle re-enters it, by the scope's generator: both are read from the
		/// generator and the tree beneath it, whatever path reaches it. What it declares for its children is the frame's, since
		/// a declaration holds facts of the path (its depth, the path to a tree a type above the seam could build).
		private var dependenciesByGenerator = [ObjectIdentifier: DependenciesByProperty]()
		private var cycleReentriesByGenerator = [ObjectIdentifier: [SeamSignature.Places.CycleReentry]]()
		/// The places each buildable tree holds, by the path to them: a tree's places are read at its own path.
		private var placesByTreePath = [[Property]: [SeamSignature.Hole.Site]]()
		/// A scope on the path from the seam's root to the scope being walked.
		private struct Frame {
			let generator: ScopeGenerator
			let orderedChildren: [ScopeGenerator.OrderedChild]
			/// The position among `orderedChildren` of the child the walk visits next.
			var nextPosition = 0
			/// The scope's position on the path, the seam's root's `0`.
			let depth: Int
			/// For a fill, its hole, the type the scope before it builds, and the called seam's case of the place it fills, where
			/// the call names one; `nil` otherwise.
			let fill: (hole: SeamSignature.Hole, filledType: TypeDescription?, filledCase: SeamSignature.Places.CalledCase?)?
			/// The type it builds, where it is no fill.
			let instantiable: Instantiable?
			/// Whether its scope ends a level: a fill, or a scope that builds a type.
			var endsLevel: Bool {
				fill != nil || instantiable != nil
			}

			/// What the level declares before its children (for a fill, all it declares).
			let headDeclarations: [PathDeclaration]
			let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			let cycleReentries: [SeamSignature.Places.CycleReentry]
			/// The level's path segment: the frames' since the last level ended, this one's last.
			let pathSegment: [Property]
			let pathTypes: [SeamSignature.Hole.PathType]
			let declaredSegment: [SeamSignature.Hole.DeclaredProperty]
			/// Whether no level ends above it.
			let isSeamRoot: Bool
			let isInFill: Bool
			/// The properties from the seam's root to the scope, as a site's path spells them.
			let pathToFrame: [Property]
			/// The index of each scope on the path among its parent's children, the seam's root's left out: the order the per-site
			/// walk meets calls in.
			let childIndexPath: [Int]
			/// Whether every scope on the path passes up a builder of a seam it calls, so the per-site walk visits the scope's
			/// calls (`holesPassedUp(in:)`).
			let isOnPathToCalls: Bool
			/// Whether a call among the children is made inside a `@Sendable` function, as the per-site walk of calls decides it.
			let callsAreInSendableFunction: Bool

			// The state the path hands the scope's children.

			/// Whether a `@Sendable` function encloses the children.
			let childrenAreInSendableFunction: Bool
			/// The type whose scope declares the children's loops, and its dependencies.
			let loopDeclaring: (instantiable: Instantiable, dependencies: DependenciesByProperty)
			/// For a public mock, the nearest declaration of each label beneath the scope.
			let nearestDeclarations: [String: Property]
			/// The path segment the children's level starts with, where the scope ends no level.
			let pendingSegment: (properties: [Property], types: [SeamSignature.Hole.PathType], declared: [SeamSignature.Hole.DeclaredProperty])
			/// The cycle re-entries the next level ending holds, where the scope ends no level.
			let pendingCycleReentries: [SeamSignature.Places.CycleReentry]?

			/// The position whose level is in the graph, and its index there.
			var addedLevel: (position: Int, index: Int)?
			/// What the scope declares for its children, by position, where it builds a type.
			let childDeclarations: [PathDeclaration?]
			/// The levels' declaration list, drafted once, since a scope's declarations do not depend on its next property: a level
			/// of the frame with its first next property, the list's projection, and the buildable trees its declarations hold.
			var drafted: (draft: SeamPlacesBuilder.LevelDraft, listProjection: SeamPlacesBuilder.ListProjection, trees: [BuildableTree])?

			// What a walk of the scope's subtree is kept as (`WalkedSubtree`), for the next path that reaches its declaration.

			/// The key the walk of the subtree is kept by, where it can be kept.
			let subtreeKey: SubtreeKey?
			/// The number of sites and of met calls before the scope's.
			let sitesStart: Int
			let metCallsStart: Int
			/// The declarations above the scope that a cycle in its subtree closes on.
			var closedOnAbove = Set<ScopeGenerator.BuiltDeclaration>()
			/// The declarations its subtree builds.
			var builtInSubtree = Set<ScopeGenerator.BuiltDeclaration>()
			/// Whether a subtree the walk does not enter holds a cycle-closing scope, whose declaration's tree may differ on
			/// another path.
			var holdsUnwalkedCycleClosing = false
			/// Whether the walk replayed the subtree instead of walking it.
			var isReplayed = false
		}

		/// What a frame hands its children that decides what they declare and how their levels and sites are added: two
		/// frames with one key build the same subtree, unless a cycle in it closes differently (`WalkedSubtree`).
		struct SubtreeKey: Hashable {
			let builtType: TypeDescription?
			let property: Property?
			let fillSite: SeamSignature.Hole.Site?
			let filledCase: SeamSignature.Places.CalledCase?
			let isInFill: Bool
			let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			let childrenAreInSendableFunction: Bool
			let isOnPathToCalls: Bool
			let callsAreInSendableFunction: Bool
			let loopDeclaringType: TypeDescription
			let nearestDeclarations: [String: Property]
		}

		/// A walk of a scope's subtree, kept so that the next path that reaches a scope of the same key adds its levels'
		/// parents and replays its sites and calls instead of walking it again. It holds where the path must stand: every
		/// declaration in `closedOnAbove` above the scope, so the subtree's cycles close where they closed, and none of
		/// `builtInSubtree`, so none of them closes where it opened.
		private struct WalkedSubtree {
			struct Site {
				let pathSuffix: [Property]
				let position: Int
				/// The positions of the next children of the frames beneath, for a replay that is kept again.
				let positionsBeneath: [Int]
				let routeSuffix: [Int]
				let caseIndex: Int
				let isBuiltInSendableFunction: Bool
				let siteOpensSendableFunction: Bool
			}

			struct Call {
				let childIndexPathSuffix: [Int]
				let position: Int
				let framesBeneath: [Frame]
				let call: ScopeGenerator
				let property: Property
				let calledSeamType: TypeDescription
				let isInSendableFunction: Bool
			}

			let closedOnAbove: Set<ScopeGenerator.BuiltDeclaration>
			let builtInSubtree: Set<ScopeGenerator.BuiltDeclaration>
			let sites: [Site]
			let calls: [Call]
		}

		private var walkedSubtrees = [SubtreeKey: [WalkedSubtree]]()
		/// How many frames on the path build each declaration.
		private var declarationsOnPath = [ScopeGenerator.BuiltDeclaration: Int]()

		/// A declaration of a level whose tree a type above the seam could build: its index among the level's declarations, the
		/// tree's generator, and the path to the tree's property.
		private struct BuildableTree {
			let declaration: Int
			let generator: ScopeGenerator
			let treePath: [Property]
		}

		private var frames = [Frame]()

		mutating func walk(from root: ScopeGenerator) {
			var rootDeclarations = [PathDeclaration]()
			for parameter in parameters {
				rootDeclarations.append(parameterDeclaration(of: parameter))
			}
			var nearest = [String: Property]()
			if bindsReceivesAgain {
				for declaration in rootDeclarations {
					nearest[declaration.property.label] = declaration.property
				}
			}
			push(
				root,
				orderedChildren: root.orderedChildrenComputedAfresh(propertiesGeneratedLater: []),
				parent: nil,
				childIndex: nil,
				fillIsSendable: false,
				inheritedDeclarations: rootDeclarations,
				nearestAbove: nearest,
			)
			while let frame = frames.last {
				guard frame.nextPosition < frame.orderedChildren.count else {
					pop()
					continue
				}
				frames[frames.count - 1].nextPosition += 1
				let position = frame.nextPosition
				let child = frame.orderedChildren[position]
				if let holeSite = child.generator.holeSite {
					visitSite(holeSite.property)
				} else if child.generator.fillEmitsCode {
					// A fill whose code another fill of its case generates builds no site of its own and makes no call.
					if frame.isOnPathToCalls, child.generator.passesUpBuilder {
						meetCall(child)
					}
					if child.generator.containsBuildSite || child.generator.passesUpBuilder {
						let fillIsSendable = frame.generator.buildsInSendableFunction(ofFill: child.generator)
						push(
							child.generator,
							orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
							parent: frame,
							childIndex: child.index,
							fillIsSendable: fillIsSendable,
							inheritedDeclarations: [],
							nearestAbove: frame.nearestDeclarations,
						)
						if let walk = reusableWalk() {
							replay(walk)
							pop()
						}
					} else {
						noteUnwalked(child.generator)
					}
				} else {
					noteUnwalked(child.generator)
				}
			}
		}

		// MARK: Frames

		/// Enters `generator`'s scope beneath `parent`, drafting what its level declares whatever its next property.
		private mutating func push(
			_ generator: ScopeGenerator,
			orderedChildren: [ScopeGenerator.OrderedChild],
			parent: Frame?,
			childIndex: Int?,
			fillIsSendable: Bool,
			inheritedDeclarations: [PathDeclaration],
			nearestAbove: [String: Property],
		) {
			let depth = parent.map { $0.depth + 1 } ?? 0
			let childIndexPath = (parent?.childIndexPath ?? []) + (childIndex.map { [$0] } ?? [])
			let isOnPathToCalls = parent.map { $0.isOnPathToCalls && generator.passesUpBuilder } ?? true
			let callsAreInSendableFunction = parent.map { $0.callsAreInSendableFunction || $0.generator.buildsInSendableFunction(ofFill: generator) } ?? false
				|| generator.buildsInSendableFunction
			var pathSegment = parent?.pendingSegment.properties ?? []
			var pathTypes = parent?.pendingSegment.types ?? []
			var declaredSegment = parent?.pendingSegment.declared ?? []
			var pathToFrame = parent?.pathToFrame ?? []
			if let parent {
				let segment = generator.fillHole?.pathBeforePropertyInItsFill ?? generator.property.map { [$0] } ?? []
				pathToFrame += segment
				pathSegment += segment
				pathTypes += SeamSignature.Hole.PathType.pathTypes(through: generator)
				declaredSegment += DependencyTreeGenerator.declaredProperties(reaching: generator, from: parent.generator)
			}
			// Where a cycle-closing scope calls the scope's builder function, the declarations between, which the level the scope
			// ends holds, or the next level that ends where it ends none.
			var cycleReentries = parent?.pendingCycleReentries
			if depth > 0, let declaration = generator.declarationACycleClosesOn {
				cycleReentries = cycleReentriesByGenerator[ObjectIdentifier(generator)] ?? DependencyTreeGenerator.declarationsBetween(closedOnScope: generator, closedOnDeclaration: declaration).map { between in
					SeamSignature.Places.CycleReentry(
						property: between.property,
						declaringType: between.declaringType,
						declarationLocation: between.declarationLocation,
						parameterTakingType: between.parameterTakingType,
						closedOnProperty: between.closedOnProperty,
						closedOnBuiltType: declaration.concreteType,
						reenteringType: between.reenteringType,
					)
				}
				cycleReentriesByGenerator[ObjectIdentifier(generator)] = cycleReentries
			}
			let isSeamRoot = parent.map { !$0.endsLevel && $0.isSeamRoot } ?? true
			var isInFill = parent?.isInFill ?? false
			var isInSendableFunction = parent?.childrenAreInSendableFunction ?? false
			var loopDeclaring: (instantiable: Instantiable, dependencies: DependenciesByProperty) = parent?.loopDeclaring ?? (seam, seamDependencies)
			var nearest = nearestAbove
			var declarations = inheritedDeclarations
			var opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			var fill: (hole: SeamSignature.Hole, filledType: TypeDescription?, filledCase: SeamSignature.Places.CalledCase?)?
			var instantiable: Instantiable?
			func declare(_ declaration: PathDeclaration) {
				declarations.append(declaration)
				if bindsReceivesAgain {
					nearest[declaration.property.label] = declaration.property
				}
			}
			var frameChildDeclarations = [PathDeclaration?]()
			if let filledHole = generator.fillHole {
				isInFill = true
				let call = parent?.generator
				let filledType = call?.builtInstantiable?.concreteInstantiable
				// The called seam's case of the place the fill fills, which a call whose seam's graph was not built names none of.
				let filledCase = call?.calledBuilders?.caseIndexBySite[filledHole.site].map {
					SeamSignature.Places.CalledCase(seamType: filledType ?? filledHole.scopeSeamType, isPublicMock: call?.publicMockCall != nil, caseIndex: $0)
				}
				fill = (filledHole, filledType, filledCase)
				let uncarriedLabels = generator.fillLabelsUncarriedOnSomeRoute
				for uncarriedDeclaration in generator.fillUncarriedDeclarations {
					var pathDeclaration = PathDeclaration(
						property: uncarriedDeclaration.property,
						isBoundBeforeSite: false,
						sendableDepth: 0,
						access: seamTypeAccess,
						accessCause: nil,
						declaringType: uncarriedDeclaration.declaringType,
						declarationLocation: uncarriedDeclaration.declarationLocation,
						parameterTakingType: uncarriedDeclaration.parameterTakingType,
					)
					pathDeclaration.builtAfter = uncarriedDeclaration.builtAfter
					pathDeclaration.reason = uncarriedDeclaration.reason
					pathDeclaration.frameLevel = depth
					declare(pathDeclaration)
				}
				if fillIsSendable {
					isInSendableFunction = true
					opensSendableFunction = SeamSignature.Places.SendableFunctionOpened(property: filledHole.property, function: .other)
				}
				for boundField in generator.fillFields where generator.fillStructBoundLabels.contains(boundField.property.label) && !uncarriedLabels.contains(boundField.property.label) {
					let field = generator.fillLabelsHandedAsMemo.contains(boundField.property.label)
						? generator.fillCaseHoles.lazy.flatMap(\.fields).first { $0.property.label == boundField.property.label } ?? boundField
						: boundField
					let fieldAccess = access(of: field.property, declaredBy: instantiables[field.declaringType]?.moduleName)
					var fieldDeclaration = PathDeclaration(
						property: field.property,
						isBoundBeforeSite: true,
						sendableDepth: 0,
						access: fieldAccess.level,
						accessCause: fieldAccess.cause,
						declaringType: field.declaringType,
						declarationLocation: field.declarationLocation,
						isReceivedOnlyIfAvailable: field.isReceivedOnlyIfAvailable,
						parameterTakingType: field.parameterTakingType,
						frameLevel: depth,
					)
					fieldDeclaration.seamParameterOrigin = field.isBoundByPublicMockRoot ? nil : field.seamParameterOrigin
					fieldDeclaration.isFieldOfSeamParameter = field.isSeamParameter
					if field.isSeamParameter {
						fieldDeclaration.fillFieldHiding = SeamSignature.Places.FillFieldHiding(
							calledSeam: filledType ?? filledHole.scopeSeamType,
							receivingSeam: filledHole.scopeSeamType,
						)
					}
					declare(fieldDeclaration)
				}
			} else if let built = generator.builtInstantiable {
				instantiable = built
				let dependencies = dependenciesByGenerator[ObjectIdentifier(generator)] ?? DependenciesByProperty(of: built)
				dependenciesByGenerator[ObjectIdentifier(generator)] = dependencies
				if depth > 0, let property = generator.property, generator.buildsInSendableFunction {
					isInSendableFunction = true
					let function: SeamSignature.Hole.UncarriedDeclaration.SendableFunction = if ScopeGenerator.isBuilder(property) {
						.instantiator(builtType: built.concreteInstantiable)
					} else if case .sendableLazilyInstantiated = property.propertyType {
						.sendableLazyWrapper(builtType: built.concreteInstantiable)
					} else {
						.other
					}
					opensSendableFunction = SeamSignature.Places.SendableFunctionOpened(property: property, function: function)
				}
				if depth > 0 {
					for dependency in built.dependencies where dependency.source == .forwarded {
						var forwardedDeclaration = declaration(of: dependency.property, isBoundBeforeSite: true, declaredBy: built, dependencies: dependencies, depth: depth)
						forwardedDeclaration.isForwarded = true
						declare(forwardedDeclaration)
					}
					for reboundProperty in generator.reboundProperties {
						let reboundAccess = access(of: reboundProperty, declaredBy: loopDeclaring.instantiable.moduleName)
						var reboundDeclaration = PathDeclaration(
							property: reboundProperty,
							isBoundBeforeSite: true,
							sendableDepth: 0,
							access: reboundAccess.level,
							accessCause: reboundAccess.cause,
							declaringType: loopDeclaring.instantiable.concreteInstantiable,
							declarationLocation: loopDeclaring.dependencies.dependencyByProperty[reboundProperty]?.declarationLocation,
							frameLevel: depth,
						)
						reboundDeclaration.isReboundByBuilderFunction = true
						declare(reboundDeclaration)
					}
				}
				if generator.declaresCycleParameters {
					let parametersWithReceivingType = generator.cycleParameters.compactMap { parameter in
						parameter.receiver.chain.last.map { (parameter: parameter, receivingType: $0) }
					}
					for (parameter, receivingType) in parametersWithReceivingType {
						let parameterAccess = access(of: parameter.property, declaredBy: instantiables[receivingType]?.moduleName)
						var parameterDeclaration = PathDeclaration(
							property: parameter.property,
							isBoundBeforeSite: true,
							sendableDepth: 0,
							access: parameterAccess.level,
							accessCause: parameterAccess.cause,
							declaringType: receivingType,
							declarationLocation: parameter.receiver.declarationLocation,
							parameterTakingType: built.concreteInstantiable,
							frameLevel: depth,
						)
						parameterDeclaration.isCycleParameter = true
						parameterDeclaration.cycleParameterOrigin = SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin(
							takingType: built.concreteInstantiable,
							property: parameter.redeclaration.property,
							declaringType: parameter.redeclaration.declaringType,
							declarationLocation: parameter.redeclaration.declarationLocation,
							isForwarded: instantiables[parameter.redeclaration.declaringType]?.dependencies.contains { $0.source == .forwarded && $0.property == parameter.redeclaration.property } ?? false,
						)
						declare(parameterDeclaration)
					}
				}
				if bindsReceivesAgain, depth > 0, !isInFill {
					for dependency in built.dependencies where !namesApartAtRoot.wrappers.contains(dependency.property) {
						let bindsAgain = if let nearestProperty = nearest[dependency.property.label] {
							DependencyTreeGenerator.mockBindsAgain(receiving: dependency, beneath: nearestProperty)
						} else {
							dependency.source.isReceived && namesApartAtRoot.labels.contains(dependency.property.label)
						}
						guard bindsAgain else { continue }
						declare(declaration(of: dependency.property, isBoundBeforeSite: true, declaredBy: built, dependencies: dependencies, depth: depth))
					}
				}
				// What the scope declares for its children does not depend on the next property but for whether each is bound
				// before it, so it is drafted once per frame.
				let childDeclarations = orderedChildren.map { child -> PathDeclaration? in
					guard let childProperty = child.generator.property, depth > 0 || !labelsNoRootChildDeclares.contains(childProperty.label) else { return nil }
					let property = depth == 0 && bindsReceivesAgain ? mockRootBinding(ofChild: childProperty, isDependencyOfMockedType: { dependencies.dependencyByProperty[childProperty] != nil }) : childProperty
					var pathDeclaration = declaration(of: property, isBoundBeforeSite: false, declaredBy: built, dependencies: dependencies, depth: depth)
					pathDeclaration.isBoundByPublicMockRoot = bindsReceivesAgain && depth == 0
						&& !dependencies.labelsNotReceived.contains(property.label)
					let source = dependencies.dependencyByProperty[property]?.source
					if case let .aliased(fulfillingProperty, _, _)? = source {
						pathDeclaration.alias = .init(fulfillingProperty: fulfillingProperty, isSeams: depth == 0)
					} else if child.generator.receivedProperties.allSatisfy({ receivedLabels.contains($0.label) || $0.label == property.label }) {
						pathDeclaration.treeBuildableAboveSeam = (child.generator, pathToFrame)
					}
					pathDeclaration.isBoundFromCallersArgument = bindsReceivesAgain && depth == 0 && source?.isReceived ?? true
					return pathDeclaration
				}
				frameChildDeclarations = childDeclarations
				if bindsReceivesAgain {
					for case let childDeclaration? in childDeclarations {
						nearest[childDeclaration.property.label] = childDeclaration.property
					}
				}
				loopDeclaring = (built, dependencies)
			}
			let endsLevel = fill != nil || instantiable != nil
			frames.append(Frame(
				generator: generator,
				orderedChildren: orderedChildren,
				depth: depth,
				fill: fill,
				instantiable: instantiable,
				headDeclarations: declarations,
				opensSendableFunction: opensSendableFunction,
				cycleReentries: endsLevel ? cycleReentries ?? [] : [],
				pathSegment: pathSegment,
				pathTypes: pathTypes,
				declaredSegment: declaredSegment,
				isSeamRoot: isSeamRoot,
				isInFill: isInFill,
				pathToFrame: pathToFrame,
				childIndexPath: childIndexPath,
				isOnPathToCalls: isOnPathToCalls,
				callsAreInSendableFunction: callsAreInSendableFunction,
				childrenAreInSendableFunction: isInSendableFunction,
				loopDeclaring: loopDeclaring,
				nearestDeclarations: nearest,
				pendingSegment: endsLevel ? ([], [], []) : (pathSegment, pathTypes, declaredSegment),
				pendingCycleReentries: endsLevel ? nil : cycleReentries,
				childDeclarations: frameChildDeclarations,
				subtreeKey: endsLevel && depth > 0 && parent?.endsLevel == true ? SubtreeKey(
					builtType: instantiable?.concreteInstantiable,
					property: generator.property,
					fillSite: fill?.hole.site,
					filledCase: fill?.filledCase,
					isInFill: isInFill,
					opensSendableFunction: opensSendableFunction,
					childrenAreInSendableFunction: isInSendableFunction,
					isOnPathToCalls: isOnPathToCalls,
					callsAreInSendableFunction: callsAreInSendableFunction,
					loopDeclaringType: loopDeclaring.instantiable.concreteInstantiable,
					nearestDeclarations: bindsReceivesAgain ? nearest : [:],
				) : nil,
				sitesStart: sites.count,
				metCallsStart: metCalls.count,
			))
			if let declaration = generator.declaration {
				declarationsOnPath[declaration, default: 0] += 1
				for index in frames.indices.dropLast() {
					frames[index].builtInSubtree.insert(declaration)
				}
			}
		}

		/// The walk of the subtree of the innermost frame's declaration that an earlier path kept and this path can reuse.
		private func reusableWalk() -> WalkedSubtree? {
			guard let key = frames[frames.count - 1].subtreeKey, let walks = walkedSubtrees[key] else { return nil }
			return walks.first { walk in
				walk.closedOnAbove.allSatisfy { declarationsOnPath[$0, default: 0] > 0 }
					&& walk.builtInSubtree.allSatisfy { declarationsOnPath[$0, default: 0] == 0 }
			}
		}

		/// Adds, beneath the innermost frame, what `walk` kept of the subtree of a scope of its key: the frame's levels with this
		/// path's parent, and the sites and calls beneath, with this path's.
		private mutating func replay(_ walk: WalkedSubtree) {
			let frameIndex = frames.count - 1
			frames[frameIndex].isReplayed = true
			let frame = frames[frameIndex]
			for site in walk.sites {
				frames[frameIndex].nextPosition = site.position + 1
				let route = materializeRoute(throughFrameAt: frameIndex) + site.routeSuffix
				let walkedSite = SeamSignature.Hole.Site(seamType: seam.concreteInstantiable, path: frame.pathToFrame + site.pathSuffix)
				let caseIndex = builder.addCase(
					ofSite: walkedSite,
					ownerLevel: route.last ?? 0,
					passedUp: nil,
					isBuiltInSendableFunction: site.isBuiltInSendableFunction,
					siteOpensSendableFunction: site.siteOpensSendableFunction,
				)
				sites.append(WalkedSite(site: walkedSite, caseIndex: caseIndex, route: SeamSignature.Places.Route(levels: route)))
				siteRecords.append((frames.map { $0.nextPosition - 1 } + site.positionsBeneath, site.isBuiltInSendableFunction, site.siteOpensSendableFunction))
			}
			for call in walk.calls {
				frames[frameIndex].nextPosition = call.position + 1
				for index in frames.indices where frames[index].endsLevel {
					_ = drafted(ofFrameAt: index)
				}
				metCalls.append(MetCall(
					childIndexPath: frames[frameIndex].childIndexPath + call.childIndexPathSuffix,
					frames: frames + call.framesBeneath,
					call: call.call,
					property: call.property,
					calledSeamType: call.calledSeamType,
					isInSendableFunction: call.isInSendableFunction,
				))
			}
			mergeIntoAncestors(closedOnAbove: walk.closedOnAbove, builtInSubtree: walk.builtInSubtree)
		}

		/// Records in each frame above the innermost what a subtree beneath it closes on above itself and builds.
		private mutating func mergeIntoAncestors(closedOnAbove: Set<ScopeGenerator.BuiltDeclaration>, builtInSubtree: Set<ScopeGenerator.BuiltDeclaration>) {
			for index in frames.indices.dropLast() {
				frames[index].builtInSubtree.formUnion(builtInSubtree)
				frames[index].closedOnAbove.formUnion(closedOnAbove.filter { declaration in
					// Closes above the frame at `index` where no frame from it down builds the declaration.
					!frames[index...].contains { $0.generator.declaration == declaration }
				})
			}
		}

		/// Notes `child`, a child of the innermost scope the walk does not enter, where its tree holds a cycle-closing scope.
		private mutating func noteUnwalked(_ child: ScopeGenerator) {
			guard child.holdsCycleClosingScope else { return }
			if child.closesPropertyCycle, let declaration = child.closedOnDeclaration {
				// Closes on the nearest frame that builds its declaration: above every frame beneath that one.
				let closedOnIndex = frames.lastIndex { $0.generator.declaration == declaration }
				for index in frames.indices where closedOnIndex.map({ index > $0 }) ?? true {
					frames[index].closedOnAbove.insert(declaration)
				}
			} else {
				for index in frames.indices {
					frames[index].holdsUnwalkedCycleClosing = true
				}
			}
		}

		/// Leaves the innermost scope, keeping the walk of its subtree where another path can reuse it.
		private mutating func pop() {
			let frame = frames.removeLast()
			if let declaration = frame.generator.declaration {
				declarationsOnPath[declaration, default: 0] -= 1
			}
			guard let key = frame.subtreeKey, !frame.holdsUnwalkedCycleClosing else {
				if frame.holdsUnwalkedCycleClosing, !frames.isEmpty {
					frames[frames.count - 1].holdsUnwalkedCycleClosing = true
				}
				return
			}
			guard !frame.isReplayed else { return }
			let prefixLevels = frames.count(where: \.endsLevel)
			let walk = WalkedSubtree(
				closedOnAbove: frame.closedOnAbove,
				builtInSubtree: frame.builtInSubtree,
				sites: sites.indices[frame.sitesStart...].map { index in
					let record = siteRecords[index]
					return WalkedSubtree.Site(
						pathSuffix: Array(sites[index].site.path.dropFirst(frame.pathToFrame.count)),
						position: record.positions[frames.count],
						positionsBeneath: Array(record.positions.dropFirst(frames.count + 1)),
						routeSuffix: Array(sites[index].route.levels.dropFirst(prefixLevels + 1)),
						caseIndex: sites[index].caseIndex,
						isBuiltInSendableFunction: record.isBuiltInSendableFunction,
						siteOpensSendableFunction: record.siteOpensSendableFunction,
					)
				},
				calls: metCalls[frame.metCallsStart...].map { met in
					WalkedSubtree.Call(
						childIndexPathSuffix: Array(met.childIndexPath.dropFirst(frame.childIndexPath.count)),
						position: met.frames[frames.count].nextPosition - 1,
						framesBeneath: Array(met.frames.dropFirst(frames.count + 1)),
						call: met.call,
						property: met.property,
						calledSeamType: met.calledSeamType,
						isInSendableFunction: met.isInSendableFunction,
					)
				},
			)
			walkedSubtrees[key, default: []].append(walk)
		}

		// MARK: Sites and levels

		/// Adds the site of `property`, a child of the innermost scope at `position`: the levels of its path, root first, and
		/// its case.
		private mutating func visitSite(_ property: Property) {
			let owner = frames[frames.count - 1]
			// A site whose owner builds no type is no place (`holes(of:)`).
			guard owner.instantiable != nil else { return }
			let route = materializeRoute(throughFrameAt: frames.count - 1)
			let site = SeamSignature.Hole.Site(seamType: seam.concreteInstantiable, path: owner.pathToFrame + [property])
			let isBuiltInSendableFunction = owner.childrenAreInSendableFunction || property.propertyType.isSendable
			let caseIndex = builder.addCase(
				ofSite: site,
				ownerLevel: route.last ?? 0,
				passedUp: nil,
				isBuiltInSendableFunction: isBuiltInSendableFunction,
				siteOpensSendableFunction: property.propertyType.isSendable,
			)
			sites.append(WalkedSite(site: site, caseIndex: caseIndex, route: SeamSignature.Places.Route(levels: route)))
			siteRecords.append((frames.map { $0.nextPosition - 1 }, isBuiltInSendableFunction, property.propertyType.isSendable))
		}

		/// A call the walk met: the frames from the seam's root to the scope that declares it, that scope's position past the
		/// call, kept to add the call's cases once every own site is added.
		private struct MetCall {
			let childIndexPath: [Int]
			let frames: [Frame]
			let call: ScopeGenerator
			let property: Property
			let calledSeamType: TypeDescription
			let isInSendableFunction: Bool
		}

		private var metCalls = [MetCall]()

		/// Keeps `child`, a child of the innermost scope, where it is a call that presents places of the seam it calls.
		private mutating func meetCall(_ child: ScopeGenerator.OrderedChild) {
			let call = child.generator
			guard let property = call.property, let calledSeamType = call.builtInstantiable?.concreteInstantiable, !call.passedUpHoles.isEmpty else { return }
			// The frames' declaration lists are drafted now, so the calls and sites beneath them share them.
			for index in frames.indices where frames[index].endsLevel {
				_ = drafted(ofFrameAt: index)
			}
			let frame = frames[frames.count - 1]
			metCalls.append(MetCall(
				childIndexPath: frame.childIndexPath + [child.index],
				frames: frames,
				call: call,
				property: property,
				calledSeamType: calledSeamType,
				isInSendableFunction: frame.callsAreInSendableFunction || frame.generator.buildsInSendableFunction(ofFill: call) || call.buildsInSendableFunction,
			))
		}

		/// Adds, for each call met, in the order the per-site walk meets them, the levels of the path to it, its own level, and
		/// a case for each place it presents.
		mutating func addCallsCases() {
			let metCalls = metCalls.sorted { $0.childIndexPath.lexicographicallyPrecedes($1.childIndexPath) }
			self.metCalls = []
			for met in metCalls {
				frames = met.frames
				let route = materializeRoute(throughFrameAt: frames.count - 1)
				// The call's own level, which declares nothing: the called seam's root stands beneath it.
				var opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
				if met.call.buildsInSendableFunction {
					let function: SeamSignature.Hole.UncarriedDeclaration.SendableFunction = if ScopeGenerator.isBuilder(met.property) {
						.instantiator(builtType: met.calledSeamType)
					} else if case .sendableLazilyInstantiated = met.property.propertyType {
						.sendableLazyWrapper(builtType: met.calledSeamType)
					} else {
						.other
					}
					opensSendableFunction = SeamSignature.Places.SendableFunctionOpened(property: met.property, function: function)
				}
				let draft = SeamPlacesBuilder.LevelDraft(
					key: SeamSignature.Places.LevelKey(builtType: met.calledSeamType, nextProperty: nil, isSeamRoot: false, isInFill: frames.last(where: \.endsLevel)?.isInFill ?? false, filledType: nil),
					declarations: [],
					opensSendableFunction: opensSendableFunction,
					cycleReentries: [],
					fillBaseStack: [],
					fillOwnerType: nil,
					pathSegment: [met.property],
					pathTypes: SeamSignature.Hole.PathType.pathTypes(through: met.call),
					declaredSegment: DependencyTreeGenerator.declaredProperties(reaching: met.call, from: frames[frames.count - 1].generator),
					nextPosition: nil,
					nextLoop: nil,
				)
				let callLevel = builder.addLevel(draft, listProjection: builder.listProjection(of: draft), parent: route.last)
				let isPublicMock = met.call.publicMockCall != nil
				let caseIndices = met.call.passedUpHoles.map { hole in
					builder.addCase(
						ofSite: hole.site,
						ownerLevel: callLevel,
						// A call whose seam's graph was not built names no case.
						passedUp: SeamSignature.Places.CalledCase(seamType: met.calledSeamType, isPublicMock: isPublicMock, caseIndex: met.call.calledBuilders?.caseIndexBySite[hole.site] ?? -1),
						isBuiltInSendableFunction: met.isInSendableFunction,
						siteOpensSendableFunction: met.call.buildsInSendableFunction,
					)
				}
				calls.append(WalkedCall(caseIndices: caseIndices, route: SeamSignature.Places.Route(levels: route + [callLevel])))
			}
			frames = []
		}

		/// The level indices of the path to the frame at `frameIndex`, each added to the graph for its frame's current position
		/// where it is not yet, root first.
		private mutating func materializeRoute(throughFrameAt frameIndex: Int) -> [Int] {
			var route = [Int]()
			for index in 0...frameIndex where frames[index].endsLevel {
				let position = frames[index].nextPosition - 1
				if let added = frames[index].addedLevel, added.position == position {
					route.append(added.index)
					continue
				}
				let level = addLevel(ofFrameAt: index, position: position, parent: route.last)
				frames[index].addedLevel = (position, level)
				route.append(level)
			}
			return route
		}

		/// Adds the level of the frame at `frameIndex` whose next property is that of its child at `position`, beneath
		/// `parent`, and returns its index.
		private mutating func addLevel(ofFrameAt frameIndex: Int, position: Int, parent: Int?) -> Int {
			let drafted = drafted(ofFrameAt: frameIndex)
			let frame = frames[frameIndex]
			let next = frame.orderedChildren[position]
			let draft = SeamPlacesBuilder.LevelDraft(
				key: SeamSignature.Places.LevelKey(
					builtType: drafted.draft.key.builtType,
					nextProperty: next.generator.property,
					isSeamRoot: drafted.draft.key.isSeamRoot,
					isInFill: drafted.draft.key.isInFill,
					filledType: drafted.draft.key.filledType,
					filledCase: drafted.draft.key.filledCase,
				),
				declarations: drafted.draft.declarations,
				opensSendableFunction: drafted.draft.opensSendableFunction,
				cycleReentries: drafted.draft.cycleReentries,
				fillBaseStack: drafted.draft.fillBaseStack,
				fillOwnerType: drafted.draft.fillOwnerType,
				pathSegment: drafted.draft.pathSegment,
				pathTypes: drafted.draft.pathTypes,
				declaredSegment: drafted.draft.declaredSegment,
				nextPosition: frame.instantiable != nil ? position : nil,
				nextLoop: frame.instantiable != nil ? frame.generator.receivedBuilderLoops.loopByChildIndex[next.index] : nil,
			)
			let index = builder.addLevel(draft, listProjection: drafted.listProjection, parent: parent)
			// A declaration's tree holds the places of every route through the level, since a place's family, and so its case,
			// can differ by the route above: each route the walk materializes adds its own.
			for tree in drafted.trees {
				let treePlaces = placesByTreePath[tree.treePath] ?? DependencyTreeGenerator.places(inTreeOf: tree.generator, building: tree.treePath[tree.treePath.count - 1], declaredAt: Array(tree.treePath.dropLast()), seamType: seam.concreteInstantiable)
				placesByTreePath[tree.treePath] = treePlaces
				builder.addPlacesInTree(treePlaces, ofDeclaration: tree.declaration, atLevel: index)
			}
			return index
		}

		/// The declaration list of the frame at `frameIndex`, drafted once: what its scope binds, each child of a scope that builds
		/// a type as it is before any next property, with what decides its facts before each (`SeamSignature.Places.ChildFacts`).
		private mutating func drafted(ofFrameAt frameIndex: Int) -> (draft: SeamPlacesBuilder.LevelDraft, listProjection: SeamPlacesBuilder.ListProjection, trees: [BuildableTree]) {
			if let drafted = frames[frameIndex].drafted {
				return drafted
			}
			let frame = frames[frameIndex]
			var declarations = frame.headDeclarations
			if frame.instantiable != nil {
				// The positions of the children by their unwrapped properties, which a child's receives only if available are matched by.
				var positionsByUnwrappedProperty = [Property: [Int]]()
				for (position, child) in frame.orderedChildren.enumerated() {
					if let property = child.generator.property {
						positionsByUnwrappedProperty[property.asUnwrappedProperty, default: []].append(position)
					}
				}
				for (position, child) in frame.orderedChildren.enumerated() {
					guard var pathDeclaration = frame.childDeclarations[position] else { continue }
					pathDeclaration.childFacts = SeamSignature.Places.ChildFacts(
						position: position,
						isBuilder: ScopeGenerator.isBuilder(pathDeclaration.property),
						loop: frame.generator.receivedBuilderLoops.loopByChildIndex[child.index],
						builtType: child.generator.builtInstantiable?.concreteInstantiable,
						isPlace: child.generator.holeSite != nil,
						receivesOnlyIfAvailable: child.generator.onlyIfAvailableUnwrappedReceivedProperties
							.flatMap { positionsByUnwrappedProperty[$0] ?? [] }
							.sorted()
							.compactMap { frame.orderedChildren[$0].generator.property },
						carriers: firstTwoCarriers(among: child.generator.requiredReceivedProperties, of: frame),
					)
					declarations.append(pathDeclaration)
				}
			}
			var trees = [BuildableTree]()
			let draft = SeamPlacesBuilder.LevelDraft(
				key: SeamSignature.Places.LevelKey(
					builtType: frame.instantiable?.concreteInstantiable,
					nextProperty: nil,
					isSeamRoot: frame.isSeamRoot,
					isInFill: frame.isInFill,
					filledType: frame.fill?.filledType,
					filledCase: frame.fill?.filledCase,
				),
				declarations: declarations.enumerated().map { index, declaration in
					var buildability: SeamSignature.Places.Buildability?
					if let tree = declaration.treeBuildableAboveSeam {
						buildability = SeamSignature.Places.Buildability(labelsHeldAboveSeam: receivedLabels.union([declaration.property.label]).sorted(), placesInTree: [])
						trees.append(BuildableTree(declaration: index, generator: tree.generator, treePath: tree.pathToDeclaringScope + [declaration.property]))
					}
					return SeamPlacesBuilder.DeclarationDraft(declaration: placesDeclaration(of: declaration, buildability: buildability), placesInTree: [])
				},
				opensSendableFunction: frame.opensSendableFunction,
				cycleReentries: frame.cycleReentries,
				fillBaseStack: frame.fill.map { zip($0.hole.fillPropertyStack, $0.hole.fillConcreteTypeStack).map { SeamSignature.Places.StackEntry(property: $0, concreteType: $1) } } ?? [],
				fillOwnerType: frame.fill?.hole.ownerType,
				pathSegment: frame.pathSegment,
				pathTypes: frame.pathTypes,
				declaredSegment: frame.declaredSegment,
				nextPosition: nil,
				nextLoop: nil,
			)
			let drafted = (draft: draft, listProjection: builder.listProjection(of: draft), trees: trees)
			frames[frameIndex].drafted = drafted
			return drafted
		}

		/// The first two of the frame's children that start as carriers and that `requiredProperties` holds, in child order
		/// (`ChildDeclarations.firstTwoCarriers(among:)`).
		private func firstTwoCarriers(among requiredProperties: Set<Property>, of frame: Frame) -> [Property] {
			var carriers = [Property]()
			for child in frame.orderedChildren where carriers.count < 2 && frame.generator.startsAsCarrier(child.generator) {
				if let carrier = child.generator.property, requiredProperties.contains(carrier) {
					carriers.append(carrier)
				}
			}
			return carriers
		}

		// MARK: Declarations

		private func access(of property: Property, declaredBy declaringModuleName: String?) -> (level: AccessLevel, cause: TypeAccessProof.Cause?) {
			let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, declaringModuleName]))
			return (min(access.level, seamTypeAccess), access.cause)
		}

		private func declaration(of property: Property, isBoundBeforeSite: Bool, declaredBy instantiable: Instantiable, dependencies: DependenciesByProperty, depth: Int) -> PathDeclaration {
			let propertyAccess = access(of: property, declaredBy: instantiable.moduleName)
			return PathDeclaration(
				property: property,
				isBoundBeforeSite: isBoundBeforeSite,
				sendableDepth: 0,
				access: propertyAccess.level,
				accessCause: propertyAccess.cause,
				declaringType: instantiable.concreteInstantiable,
				declarationLocation: dependencies.dependencyByProperty[property]?.declarationLocation,
				frameLevel: depth,
			)
		}

		private func parameterDeclaration(of parameter: SeamSignature.Parameter) -> PathDeclaration {
			let firstReceiver = parameter.receivers.first
			var parameterDeclaration = PathDeclaration(
				property: parameter.property,
				isBoundBeforeSite: true,
				sendableDepth: 0,
				access: parameter.tierAccess,
				accessCause: parameter.accessCause,
				declaringType: firstReceiver?.declaringType ?? seam.concreteInstantiable,
				declarationLocation: firstReceiver?.declarationLocation ?? seamDependencies.dependencyByProperty[parameter.property]?.declarationLocation ?? seam.declarationLocation,
				isReceivedOnlyIfAvailable: parameter.isOnlyIfAvailable,
			)
			parameterDeclaration.deferral = parameter.deferral
			parameterDeclaration.isBoundByPublicMockRoot = bindsReceivesAgain
			parameterDeclaration.seamParameterOrigin = SeamSignature.Hole.Field.SeamParameterOrigin(
				of: parameter,
				of: seam,
				declaringType: parameterDeclaration.declaringType,
				declarationLocation: parameterDeclaration.declarationLocation,
				receivers: receiversByParameter[parameter.property],
			)
			return parameterDeclaration
		}

		private func placesDeclaration(of declaration: PathDeclaration, buildability: SeamSignature.Places.Buildability?) -> SeamSignature.Places.Declaration {
			let placesDeclaration = SeamSignature.Places.Declaration(
				field: SeamSignature.Hole.Field(
					property: declaration.property,
					access: declaration.access,
					accessCause: declaration.accessCause,
					declaringType: declaration.declaringType,
					declarationLocation: declaration.declarationLocation,
					isReceivedOnlyIfAvailable: declaration.isReceivedOnlyIfAvailable,
					parameterTakingType: declaration.parameterTakingType,
					deferral: declaration.deferral,
					isSeamParameter: declaration.frameLevel < 0,
					isBoundByPublicMockRoot: declaration.isBoundByPublicMockRoot,
					seamParameterOrigin: declaration.seamParameterOrigin,
				),
				isBoundBeforeNextProperty: declaration.isBoundBeforeSite,
				builtAfter: declaration.builtAfter,
				reason: declaration.reason,
				isForwarded: declaration.isForwarded,
				cycleParameterOrigin: declaration.cycleParameterOrigin,
				alias: declaration.alias,
				isBoundFromCallersArgument: declaration.isBoundFromCallersArgument,
				isCycleParameter: declaration.isCycleParameter,
				isReboundByBuilderFunction: declaration.isReboundByBuilderFunction,
				isFieldOfSeamParameter: declaration.isFieldOfSeamParameter,
				fillFieldHiding: declaration.fillFieldHiding,
				buildability: buildability,
			)
			return declaration.childFacts.map(placesDeclaration.asChild) ?? placesDeclaration
		}
	}
}
