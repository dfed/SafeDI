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

// MARK: - Builder parameters

/// How a seam's generated initializer takes a builder for each place its tree builds a type no production
/// `@Instantiable` declaration the seam's module can see fulfills – a hole – and how the module that calls the seam
/// fills it. Kept apart from the rest of the seam computation, which a seam without holes runs exactly as before.
extension DependencyTreeGenerator {
	/// The holes of `seam`'s signature, read from `generator`, the generator of its tree, whose parameters are
	/// `parameters`: one per site of a hole in the tree (a hole's generator), and one per hole of a seam the tree calls
	/// that the module computing the signature cannot fill, which the seam passes up, shared by every call of that
	/// seam. In builder-label order.
	///
	/// A site's fields are the values whose nearest declaration on the site's path is bound before the site in the
	/// code the seam's module generates: the seam's parameters, then each scope's on the path, outermost first, each
	/// in the order it binds them – its forwarded properties, then its children in generation order. A declaration
	/// bound after the site, the property still being built, and an `onlyIfAvailable` alias that is not created carry
	/// no field, and hide the farther declarations of their label, which Swift would bind instead.
	/// - Parameter scopeTypeNamePrefix: What each scope struct's name begins with: `SafeDIScope` for a seam's, and
	///   `SafeDIMockScope` for a public mock's, whose type may be a seam too.
	static func holes(
		of seam: Instantiable,
		generator: ScopeGenerator,
		parameters: [SeamSignature.Parameter],
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
		scopeTypeNamePrefix: String = "SafeDIScope",
	) -> [SeamSignature.Hole] {
		guard generator.containsBuildSite || generator.passesUpBuilder else { return [] }
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		let sites = buildSites(in: generator)
		let (passedUpHoles, ownSiteAdditions) = holesPassedUp(in: generator, seamType: seam.concreteInstantiable, ownSitePaths: sites.map(\.sitePath))

		// Every site's fields, stages and what it does not carry.
		struct SiteContent {
			let site: BuildSite
			let owner: Instantiable
			let dependency: Dependency?
			let stages: [[SeamSignature.Hole.Field]]
			let stageBoundaryDepths: [Int]
			let uncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration]
		}
		let siteContents = sites.compactMap { site -> SiteContent? in
			guard let owner = site.frames.last?.generator.builtInstantiable else { return nil }
			let content = fields(of: site, seam: seam, parameters: parameters, seamTypeAccess: seamTypeAccess, proof: proof, instantiables: instantiables)
			return SiteContent(
				site: site,
				owner: owner,
				dependency: owner.dependencies.first { $0.property == site.property },
				stages: content.stages,
				stageBoundaryDepths: content.stageBoundaryDepths,
				uncarriedDeclarations: content.uncarriedDeclarations,
			)
		}

		// Names. A builder is labeled `<label>Builder`; holes whose labels collide with one another or with a parameter
		// are named apart by their owner, their declared type simplified, their declared type, and their site path, a
		// parameter keeping its label. A scope struct is named after the owner and the property, with the site path
		// appended for a property built at several sites, and an underscore appended while it equals an earlier one.
		struct Candidate {
			let label: String
			let suffixTypes: [TypeDescription]
		}
		let candidates = siteContents.map { content in
			Candidate(
				label: "\(content.site.property.label)Builder".spelledAsJoinedIdentifier,
				suffixTypes: [
					content.owner.concreteInstantiable,
					content.site.property.typeDescription.simplified,
					content.site.property.typeDescription,
					.simple(name: content.site.pathLabels, generics: []),
				],
			)
		} + passedUpHoles.map { passedUp in
			Candidate(
				label: passedUp.hole.builderLabel,
				suffixTypes: [
					passedUp.hole.ownerType,
					passedUp.hole.property.typeDescription.simplified,
					passedUp.hole.property.typeDescription,
					.simple(name: SeamSignature.Hole.pathLabels(of: passedUp.hole.sitePath), generics: []),
				],
			)
		}
		let parameterLabels = Set(parameters.map(\.property.label))
		var candidateIndicesByLabel = [String: [Int]]()
		for (index, candidate) in candidates.enumerated() {
			candidateIndicesByLabel[candidate.label, default: []].append(index)
		}
		var builderLabels = candidates.map(\.label)
		let collidingIndices = candidates.indices.filter { index in
			parameterLabels.contains(candidates[index].label) || candidateIndicesByLabel[candidates[index].label, default: []].count > 1
		}
		let keptLabels = Set(candidates.indices.filter { !collidingIndices.contains($0) }.map { candidates[$0].label })
		let collidingNames = ScopeGenerator.identifierSafeNames(
			for: collidingIndices.map { (label: candidates[$0].label, suffixTypes: candidates[$0].suffixTypes) },
			reservedNames: parameterLabels.union(keptLabels),
		)
		for (index, name) in zip(collidingIndices, collidingNames) {
			builderLabels[index] = name
		}
		// A builder's name inside the initializer is renamed while a property of the tree would have a builder function
		// of that name, which would shadow it.
		let builderFunctionNames = builderFunctionNamesOfProperties(in: generator)
		func internalName(ofBuilderLabeled builderLabel: String) -> String {
			var name = ScopeGenerator.functionName(toBuildPropertyNamed: builderLabel)
			while builderFunctionNames.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			return name
		}
		var siteCountByProperty = [OwnedProperty: Int]()
		for content in siteContents {
			siteCountByProperty[OwnedProperty(owner: content.owner.concreteInstantiable, property: content.site.property), default: 0] += 1
		}
		var scopeTypeNames = Set<String>()
		var holes = [SeamSignature.Hole]()
		for (index, content) in siteContents.enumerated() {
			let property = content.site.property
			var scopeTypeName = "\(scopeTypeNamePrefix)_\(content.owner.concreteInstantiable.asIdentifier)_\(property.label)".spelledAsJoinedIdentifier
			if siteCountByProperty[OwnedProperty(owner: content.owner.concreteInstantiable, property: property), default: 0] > 1 {
				scopeTypeName = "\(scopeTypeName)_\(content.site.pathLabels)".spelledAsJoinedIdentifier
			}
			while !scopeTypeNames.insert(scopeTypeName).inserted {
				scopeTypeName = "\(scopeTypeName)_".spelledAsJoinedIdentifier
			}
			// The struct is declared in this seam's extension, at its type's access, which caps the tier anyway; the hole's
			// owner receives the property, so its module's declarations prove the property's type too.
			let builderAccess = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, content.owner.moduleName]))
			let siteHole = SeamSignature.Hole(
				ownerType: content.owner.concreteInstantiable,
				property: property,
				instantiatedType: content.dependency?.asInstantiatedType ?? property.typeDescription.asInstantiatedType,
				declarationLocation: content.dependency?.declarationLocation,
				erasedToConcreteExistential: content.site.erasedToConcreteExistential,
				sitePath: content.site.sitePath,
				sitePathDeclarationLocations: content.site.sitePathDeclarationLocations,
				fillPropertyStack: content.site.fillPropertyStack,
				builderLabel: builderLabels[index],
				internalName: internalName(ofBuilderLabeled: builderLabels[index]),
				scopeSeamType: seam.concreteInstantiable,
				scopeTypeName: scopeTypeName,
				stages: content.stages,
				stageBoundaryDepths: content.stageBoundaryDepths,
				// No tier is wider than the seam's type.
				tierAccess: min(builderAccess.level, seamTypeAccess),
				accessCause: builderAccess.cause,
				uncarriedDeclarations: content.uncarriedDeclarations,
			)
			// A call the tree makes of this seam, or of a seam that passes this site back, is handed this builder.
			let additions = ownSiteAdditions[content.site.sitePath, default: SiteAdditions()]
			holes.append(siteHole.addingUncarriedDeclarations(additions.declarations(besides: siteHole.uncarriedDeclarations), isSendable: additions.isSendable))
		}
		for (offset, passedUp) in passedUpHoles.enumerated() {
			let builderLabel = builderLabels[siteContents.count + offset]
			let inner = passedUp.hole
			// The builder's type names the inner seam's scope struct, as visible as that seam's type, and the property's
			// type, which this seam's declarations prove again, its owner's module among those admitted.
			let builderAccess = proof.access(
				ofParameterTyped: .closure(arguments: [inner.scopeSeamType], isAsync: false, doesThrow: false, returnType: inner.property.typeDescription),
				mentionedFrom: .declaration(seam),
				admittedModules: Set([seam.moduleName, instantiables[inner.ownerType]?.moduleName]),
			)
			holes.append(SeamSignature.Hole(
				ownerType: inner.ownerType,
				property: inner.property,
				instantiatedType: inner.instantiatedType,
				declarationLocation: inner.declarationLocation,
				erasedToConcreteExistential: inner.erasedToConcreteExistential,
				sitePath: inner.sitePath,
				sitePathDeclarationLocations: inner.sitePathDeclarationLocations,
				fillPropertyStack: inner.fillPropertyStack,
				builderLabel: builderLabel,
				internalName: internalName(ofBuilderLabeled: builderLabel),
				scopeSeamType: inner.scopeSeamType,
				scopeTypeName: inner.scopeTypeName,
				stages: inner.stages,
				stageBoundaryDepths: [],
				tierAccess: min(builderAccess.level, seamTypeAccess),
				accessCause: builderAccess.cause,
				uncarriedDeclarations: inner.uncarriedDeclarations,
				innerSeamType: passedUp.innerSeamType,
				isSendable: inner.isSendable,
			))
		}
		return holes.sorted { $0.builderLabel < $1.builderLabel }
	}

	/// The type that fulfills `hole` in `instantiables`, the declarations a module calling the seam sees, or `nil`
	/// when none does: no declaration, or only a `mockOnly` one, which is used only to generate mocks.
	static func fulfillingInstantiable(of hole: SeamSignature.Hole, in instantiables: [TypeDescription: Instantiable]) -> Instantiable? {
		instantiables[hole.instantiatedType].flatMap { $0.mockOnly ? nil : $0 }
	}

	/// Whether `dependency`, an `@Instantiated` one, is a hole in a seam's tree when no production declaration fulfills
	/// its type: any type a nominal type could be. A function type, a tuple, an array, a dictionary, a metatype, or
	/// `Void` is not, since only hand-written code could build one: it stays `noInstantiableFound`.
	static func canBeHole(_ dependency: Dependency) -> Bool {
		switch dependency.asInstantiatedType {
		case .simple, .nested, .any, .composition:
			true
		case .void, .optional, .implicitlyUnwrappedOptional, .some, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .unknown:
			false
		}
	}

	// MARK: Private

	/// A property its owner declares, by which a scope struct is named.
	private struct OwnedProperty: Hashable {
		let owner: TypeDescription
		let property: Property
	}

	/// A scope on the path from a seam's root to a build site, with its children in the order its code is generated
	/// and the position among them of the next scope on the path, or of the site.
	private struct PathFrame {
		let generator: ScopeGenerator
		let orderedChildren: [ScopeGenerator.OrderedChild]
		var nextPosition: Int
	}

	/// A build site of a hole: the generator that builds the hole's property, reached through `frames`.
	private struct BuildSite {
		/// The scopes from the seam's root to the hole's owner, each with the position of the next on the path.
		let frames: [PathFrame]
		let property: Property
		let erasedToConcreteExistential: Bool
		/// The properties from the root of the seam whose tree holds the site to the owner's property, innermost first,
		/// each lazily instantiated one preceded by its instance, as `Scope.createScopeGenerator` stacks them: the stack
		/// the owner's scope was built with, which inside a fill this seam generates is the filled seam's.
		let fillPropertyStack: [Property]

		/// The properties from the root to the hole's property: the site's identity in the tree.
		var sitePath: [Property] {
			frames.dropFirst().compactMap(\.generator.property) + [property]
		}

		/// Where each property of `sitePath` is declared, by the type that builds it.
		var sitePathDeclarationLocations: [Dependency.DeclarationLocation?] {
			var locations = [Dependency.DeclarationLocation?]()
			var declaringInstantiable = frames.first?.generator.builtInstantiable
			for frame in frames.dropFirst() {
				guard let property = frame.generator.property else { continue }
				locations.append(declaringInstantiable?.dependencies.first { $0.property == property }?.declarationLocation)
				declaringInstantiable = frame.generator.builtInstantiable
			}
			locations.append(declaringInstantiable?.dependencies.first { $0.property == property }?.declarationLocation)
			return locations
		}

		/// The labels of the properties from the root to the owner's property, joined with `_`.
		var pathLabels: String {
			SeamSignature.Hole.pathLabels(of: sitePath)
		}
	}

	/// The build sites in the tree `generator` roots, in the order the generated code builds them, found by walking
	/// only the subtrees that hold one.
	private static func buildSites(in generator: ScopeGenerator) -> [BuildSite] {
		var sites = [BuildSite]()
		var frames = [PathFrame(generator: generator, orderedChildren: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []), nextPosition: 0)]
		while let frame = frames.last {
			guard frame.nextPosition < frame.orderedChildren.count else {
				frames.removeLast()
				continue
			}
			frames[frames.count - 1].nextPosition += 1
			let child = frame.orderedChildren[frame.nextPosition]
			if let holeSite = child.generator.holeSite {
				sites.append(BuildSite(frames: frames, property: holeSite.property, erasedToConcreteExistential: holeSite.erasedToConcreteExistential, fillPropertyStack: child.generator.ownerPropertyStack))
			} else if child.generator.containsBuildSite {
				frames.append(PathFrame(
					generator: child.generator,
					orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
					nextPosition: 0,
				))
			}
		}
		return sites
	}

	/// The holes of the seams the tree `generator` roots calls whose builders it passes up, one per site whatever route
	/// presents it, each with the seam whose call presented it first, in the order the tree first presents the site, and
	/// what the calls that present each site of the seam's own tree add to its builder. A site is never passed up twice,
	/// nor is a site of the seam's own tree, which a call of the seam itself or of a seam that passes the site back
	/// presents: the seam hands that call the builder it takes. A builder the seam takes for a site holds, beside its own
	/// uncarried declarations, the declarations the tree binds on every path to a call that presents the site and the
	/// uncarried declarations each presented copy holds, the first of each label: inline, a fill's receive of one of
	/// their labels would read it, and the caller that fills the builder does not hold it. It is `@Sendable` when a call
	/// that presents its site is made in a `@Sendable` builder function, which captures it, or takes it `@Sendable`, since
	/// the seam passes it to that call.
	private static func holesPassedUp(
		in generator: ScopeGenerator,
		seamType: TypeDescription,
		ownSitePaths: [[Property]],
	) -> (passedUpHoles: [(innerSeamType: TypeDescription, hole: SeamSignature.Hole)], ownSiteAdditions: [[Property]: SiteAdditions]) {
		var passedUpHoles = [(innerSeamType: TypeDescription, hole: SeamSignature.Hole)]()
		var takenSites = Set(ownSitePaths.map { SeamSignature.Hole.Site(seamType: seamType, path: $0) })
		var additionsBySite = [SeamSignature.Hole.Site: SiteAdditions]()
		var generatorsToVisit = [(generator: generator, pathDeclarations: [SeamSignature.Hole.UncarriedDeclaration](), isInSendableFunction: false)]
		while let (visited, pathDeclarations, isInSendableFunction) = generatorsToVisit.popLast() {
			// The call is made in its scope's builder function, inside every builder function above it.
			let callIsInSendableFunction = isInSendableFunction || visited.buildsInSendableFunction
			if let innerSeamType = visited.builtInstantiable?.concreteInstantiable {
				for hole in visited.passedUpHoles {
					if takenSites.insert(hole.site).inserted {
						passedUpHoles.append((innerSeamType, hole))
					}
					// The call captures the builder when it is made in a `@Sendable` builder function, and takes it `@Sendable`
					// when the presented copy is.
					additionsBySite[hole.site, default: SiteAdditions()].add(pathDeclarations + hole.uncarriedDeclarations, isSendable: callIsInSendableFunction || hole.isSendable)
				}
			}
			// The seam's own forwarded properties come from its caller, which fills the builder.
			let childPathDeclarations = pathDeclarations + declarationsBound(by: visited, includingForwardedProperties: visited !== generator, reason: .boundByPassingUpSeam(seam: seamType))
			let children = visited.children.filter(\.passesUpBuilder)
			generatorsToVisit.append(contentsOf: children.reversed().map { ($0, childPathDeclarations, callIsInSendableFunction) })
		}
		var ownSiteAdditions = [[Property]: SiteAdditions]()
		for path in ownSitePaths {
			ownSiteAdditions[path] = additionsBySite[SeamSignature.Hole.Site(seamType: seamType, path: path)]
		}
		return (
			passedUpHoles.map { innerSeamType, hole in
				let additions = additionsBySite[hole.site, default: SiteAdditions()]
				return (innerSeamType, hole.addingUncarriedDeclarations(additions.declarations(besides: hole.uncarriedDeclarations), isSendable: additions.isSendable))
			},
			ownSiteAdditions,
		)
	}

	/// What the calls a seam's tree makes that present one site add to the builder the seam takes for it.
	private struct SiteAdditions {
		/// The declarations a fill of the site cannot read, the first of each label, in the order the calls present them.
		private var declarations = [SeamSignature.Hole.UncarriedDeclaration]()
		/// Whether a call that presents the site is made in a `@Sendable` builder function, or takes the builder `@Sendable`.
		private(set) var isSendable = false

		/// Adds `newDeclarations`, those of labels not yet added, from a call that needs the builder `@Sendable` when
		/// `isSendable`.
		mutating func add(_ newDeclarations: [SeamSignature.Hole.UncarriedDeclaration], isSendable: Bool) {
			for declaration in newDeclarations where !declarations.contains(where: { $0.property.label == declaration.property.label }) {
				declarations.append(declaration)
			}
			self.isSendable = self.isSendable || isSendable
		}

		/// The declarations added of labels none of `existing` has.
		func declarations(besides existing: [SeamSignature.Hole.UncarriedDeclaration]) -> [SeamSignature.Hole.UncarriedDeclaration] {
			let existingLabels = Set(existing.map(\.property.label))
			return declarations.filter { !existingLabels.contains($0.property.label) }
		}
	}

	/// The declarations the scope of `generator` binds for the scopes beneath it, each with `reason`: its children and
	/// aliases, its forwarded properties when `includingForwardedProperties`, and, for a fill, every field of the filled
	/// seam's struct and what that seam's path declares beside them, which together are what the filled seam's tree
	/// binds or is building where the fill is called.
	private static func declarationsBound(
		by generator: ScopeGenerator,
		includingForwardedProperties: Bool,
		reason: SeamSignature.Hole.UncarriedDeclaration.Reason,
	) -> [SeamSignature.Hole.UncarriedDeclaration] {
		var declarations = [SeamSignature.Hole.UncarriedDeclaration]()
		if let filledHole = generator.fillHole {
			for declaration in filledHole.uncarriedDeclarations.map({ ($0.property, $0.declaringType, $0.declarationLocation) })
				+ filledHole.stages.joined().map({ ($0.property, $0.declaringType, $0.declarationLocation) })
			{
				declarations.append(SeamSignature.Hole.UncarriedDeclaration(
					property: declaration.0,
					declaringType: declaration.1,
					declarationLocation: declaration.2,
					builtAfter: nil,
					reason: reason,
				))
			}
		}
		if let instantiable = generator.builtInstantiable {
			for dependency in instantiable.dependencies {
				switch dependency.source {
				case .instantiated, .aliased:
					break
				case .forwarded:
					guard includingForwardedProperties else { continue }
				case .received:
					continue
				}
				declarations.append(SeamSignature.Hole.UncarriedDeclaration(
					property: dependency.property,
					declaringType: instantiable.concreteInstantiable,
					declarationLocation: dependency.declarationLocation,
					builtAfter: nil,
					reason: reason,
				))
			}
		}
		return declarations
	}

	/// The names of the builder functions the properties of the tree `generator` roots would have, which a builder's
	/// name inside the generated initializer must not equal.
	private static func builderFunctionNamesOfProperties(in generator: ScopeGenerator) -> Set<String> {
		var names = Set<String>()
		var generatorsToVisit = [generator]
		while let visited = generatorsToVisit.popLast() {
			if let property = visited.property {
				names.insert(ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
			}
			generatorsToVisit.append(contentsOf: visited.children)
		}
		return names
	}

	/// A declaration on a site's path: the value it binds and whether it is bound before the site.
	private struct PathDeclaration {
		let property: Property
		let isBoundBeforeSite: Bool
		let stage: Int
		let access: AccessLevel
		let accessCause: TypeAccessProof.Cause?
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		var isReceivedOnlyIfAvailable = false
		var builtAfter: Property?
		var reason = SeamSignature.Hole.UncarriedDeclaration.Reason.other
	}

	/// The fields of `site`'s scope struct, by stage, the path lengths at which its stages start, and the declarations
	/// on its path that carry no field.
	private static func fields(
		of site: BuildSite,
		seam: Instantiable,
		parameters: [SeamSignature.Parameter],
		seamTypeAccess: AccessLevel,
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
	) -> (stages: [[SeamSignature.Hole.Field]], stageBoundaryDepths: [Int], uncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration]) {
		// A field is as visible as the narrowest type it names, which the declarations of the seam's module and of the
		// module of the type that declares the value prove, capped at the seam's type.
		func access(of property: Property, declaredBy declaringModuleName: String?) -> (level: AccessLevel, cause: TypeAccessProof.Cause?) {
			let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, declaringModuleName]))
			return (min(access.level, seamTypeAccess), access.cause)
		}
		// The nearest declaration of each label, and the order in which the labels are bound.
		var nearestDeclarations = [String: PathDeclaration]()
		var labelsInBindingOrder = [String]()
		func declare(_ declaration: PathDeclaration) {
			let label = declaration.property.label
			if nearestDeclarations.updateValue(declaration, forKey: label) != nil {
				labelsInBindingOrder.removeAll { $0 == label }
			}
			labelsInBindingOrder.append(label)
		}
		for parameter in parameters {
			// A pass-through is declared, as far as a fill's reader is told, by the first type in the tree that receives it.
			let firstReceiver = parameter.receivers.first
			declare(PathDeclaration(
				property: parameter.property,
				isBoundBeforeSite: true,
				stage: 0,
				access: parameter.tierAccess,
				accessCause: parameter.accessCause,
				declaringType: firstReceiver?.declaringType ?? seam.concreteInstantiable,
				declarationLocation: firstReceiver?.declarationLocation ?? seam.dependencies.first { $0.property == parameter.property }?.declarationLocation ?? seam.declarationLocation,
				isReceivedOnlyIfAvailable: parameter.defaultsToNil
					|| seam.dependencies.contains { $0.property == parameter.property && $0.source == .received(onlyIfAvailable: true) },
			))
		}
		var stage = 0
		var stageBoundaryDepths = [Int]()
		var depth = 0
		for (level, frame) in site.frames.enumerated() {
			// A fill the seam generates for a seam it calls binds every field of that seam's struct a site inside it carries,
			// which is every field: what the struct carries is what inline holds there. A declaration the struct does not
			// carry is on the called seam's path too, bound after its site or still being built, and hides the farther
			// declarations of its label.
			if let filledHole = frame.generator.fillHole {
				for uncarriedDeclaration in filledHole.uncarriedDeclarations {
					var pathDeclaration = PathDeclaration(
						property: uncarriedDeclaration.property,
						isBoundBeforeSite: false,
						stage: stage,
						access: seamTypeAccess,
						accessCause: nil,
						declaringType: uncarriedDeclaration.declaringType,
						declarationLocation: uncarriedDeclaration.declarationLocation,
					)
					pathDeclaration.builtAfter = uncarriedDeclaration.builtAfter
					pathDeclaration.reason = uncarriedDeclaration.reason
					declare(pathDeclaration)
				}
				for field in filledHole.stages.joined() {
					let fieldAccess = access(of: field.property, declaredBy: instantiables[field.declaringType]?.moduleName)
					declare(PathDeclaration(
						property: field.property,
						isBoundBeforeSite: true,
						stage: stage,
						access: fieldAccess.level,
						accessCause: fieldAccess.cause,
						declaringType: field.declaringType,
						declarationLocation: field.declarationLocation,
						isReceivedOnlyIfAvailable: field.isReceivedOnlyIfAvailable,
					))
				}
				continue
			}
			guard let instantiable = frame.generator.builtInstantiable else { continue }
			if level > 0, frame.generator.property != nil {
				depth += 1
				// A `@Sendable` builder function on the path starts a stage: what it binds is in that stage's struct.
				if frame.generator.buildsInSendableFunction {
					stage += 1
					stageBoundaryDepths.append(depth)
				}
			}
			func declaration(of property: Property, isBoundBeforeSite: Bool) -> PathDeclaration {
				let propertyAccess = access(of: property, declaredBy: instantiable.moduleName)
				return PathDeclaration(
					property: property,
					isBoundBeforeSite: isBoundBeforeSite,
					stage: stage,
					access: propertyAccess.level,
					accessCause: propertyAccess.cause,
					declaringType: instantiable.concreteInstantiable,
					declarationLocation: instantiable.dependencies.first { $0.property == property }?.declarationLocation,
				)
			}
			// The root's forwarded properties are parameters, declared above.
			if level > 0 {
				for dependency in instantiable.dependencies where dependency.source == .forwarded {
					declare(declaration(of: dependency.property, isBoundBeforeSite: true))
				}
			}
			let pathPosition = frame.nextPosition - 1
			let pathProperty = frame.orderedChildren[pathPosition].generator.property
			let carrierProperties = frame.orderedChildren.compactMap { $0.generator.containsBuildSite ? $0.generator.property : nil }
			for (position, child) in frame.orderedChildren.enumerated() {
				guard let property = child.generator.property else { continue }
				let isCreated = child.generator.uncreatedAliasProperty(unavailableProperties: child.unavailableProperties) == nil
				var pathDeclaration = declaration(of: property, isBoundBeforeSite: position < pathPosition && isCreated)
				if position > pathPosition, let pathProperty, let childType = child.generator.builtInstantiable?.concreteInstantiable {
					// A sibling built after the scope on the path depends on a carrier: the start order builds every other
					// one first.
					pathDeclaration.builtAfter = pathProperty
					if child.generator.onlyIfAvailableUnwrappedReceivedProperties.contains(pathProperty.asUnwrappedProperty) {
						pathDeclaration.reason = .receivesPathScopeOnlyIfAvailable(type: childType)
					} else if let carrier = carrierProperties.first(where: { $0 != pathProperty && child.generator.requiredReceivedProperties.contains($0) }) {
						pathDeclaration.reason = .requiresOtherCarrier(type: childType, carrier: carrier)
					}
				}
				declare(pathDeclaration)
			}
		}
		var stages = Array(repeating: [SeamSignature.Hole.Field](), count: stage + 1)
		var uncarriedDeclarations = [SeamSignature.Hole.UncarriedDeclaration]()
		for label in labelsInBindingOrder {
			guard let declaration = nearestDeclarations[label] else { continue }
			if declaration.isBoundBeforeSite {
				stages[declaration.stage].append(SeamSignature.Hole.Field(
					property: declaration.property,
					access: declaration.access,
					accessCause: declaration.accessCause,
					declaringType: declaration.declaringType,
					declarationLocation: declaration.declarationLocation,
					isReceivedOnlyIfAvailable: declaration.isReceivedOnlyIfAvailable,
				))
			} else {
				uncarriedDeclarations.append(SeamSignature.Hole.UncarriedDeclaration(
					property: declaration.property,
					declaringType: declaration.declaringType,
					declarationLocation: declaration.declarationLocation,
					builtAfter: declaration.builtAfter,
					reason: declaration.reason,
				))
			}
		}
		return (stages, stageBoundaryDepths, uncarriedDeclarations)
	}
}

extension SeamSignature.Hole {
	/// The labels of the properties of `sitePath` but the last, the hole's own, without backticks, joined with `_`.
	static func pathLabels(of sitePath: [Property]) -> String {
		sitePath.dropLast().map(\.label.spelledWithoutBackticks).joined(separator: "_")
	}
}

// MARK: - Unfilled holes

extension DependencyTreeGenerator {
	/// Throws `unfilledHoles` for every hole a root's tree calls a seam with and cannot fill – no production declaration
	/// the root's module sees fulfills it, so the seam call would pass the builder up, which a root cannot – once per
	/// declaration of the hole's property per root, naming the first chain a declaration-order walk of the root's tree
	/// meets, the fills the root's module generates included.
	static func validateRootsFillEveryHole(
		roots: [Scope],
		callerModuleName: String?,
		instantiables: [TypeDescription: Instantiable],
		isReadableFile: (@Sendable (String) -> Bool)?,
	) throws {
		var unfilledHoles = [DependencyTreeGeneratorError.UnfilledHole]()
		for root in roots {
			var reportedDeclarations = Set<HoleDeclaration>()
			var visitedScopes = Set<ObjectIdentifier>()
			// Each scope to visit with the chain of types to it and the root's dependency through which the tree reaches it.
			var scopesToVisit: [(scope: Scope, chain: [TypeDescription], rootDependency: Dependency?)] = [(root, [root.instantiable.concreteInstantiable], nil)]
			while let (scope, chain, rootDependency) = scopesToVisit.popLast() {
				guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
				var childrenToVisit = [(scope: Scope, chain: [TypeDescription], rootDependency: Dependency?)]()
				for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
					let childRootDependency = rootDependency ?? root.instantiable.dependencies.first { $0.property == property }
					let childChain = chain + [childScope.instantiable.concreteInstantiable]
					for holeArgument in childScope.holeArguments {
						let hole = holeArgument.hole
						let holeChain = childChain
							+ (hole.innerSeamType == nil ? [] : [hole.scopeSeamType])
							+ hole.sitePath.dropLast().map(\.typeDescription.asInstantiatedType)
						switch holeArgument {
						case let .fill(_, fulfillingScope):
							childrenToVisit.append((fulfillingScope, holeChain + [fulfillingScope.instantiable.concreteInstantiable], childRootDependency))
						case .passUp:
							guard reportedDeclarations.insert(HoleDeclaration(owner: hole.ownerType, property: hole.property)).inserted else { continue }
							unfilledHoles.append(DependencyTreeGeneratorError.UnfilledHole(
								hole: hole,
								rootType: root.instantiable.concreteInstantiable,
								chain: holeChain,
								location: childRootDependency?.declarationLocation,
								noteLocation: hole.declarationLocation.flatMap { location in isReadableFile.map { $0(location.filePath) } ?? true ? location : nil },
								callerModuleName: callerModuleName,
								seamModuleName: instantiables[hole.scopeSeamType]?.moduleName,
								fulfilledByMockOnlyDeclaration: instantiables[hole.instantiatedType]?.mockOnly == true,
							))
						}
					}
					if childScope.seamCall == nil {
						childrenToVisit.append((childScope, childChain, childRootDependency))
					}
				}
				scopesToVisit.append(contentsOf: childrenToVisit.reversed())
			}
		}
		if !unfilledHoles.isEmpty {
			throw DependencyTreeGeneratorError.unfilledHoles(unfilledHoles)
		}
	}

	/// The declaration of a hole's property, by which a hole is reported once however many sites it has.
	private struct HoleDeclaration: Hashable {
		let owner: TypeDescription
		let property: Property
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError {
	/// A hole whose builder a root's tree cannot fill: no production declaration the root's module sees fulfills it.
	struct UnfilledHole {
		let hole: SeamSignature.Hole
		let rootType: TypeDescription
		/// The types from the root to the hole's owner.
		let chain: [TypeDescription]
		/// The root's dependency through which its tree reaches the seam.
		let location: Dependency.DeclarationLocation?
		/// The hole's declaration, where its file can be read.
		let noteLocation: Dependency.DeclarationLocation?
		let callerModuleName: String?
		let seamModuleName: String?
		let fulfilledByMockOnlyDeclaration: Bool

		var sourceDiagnostics: [SourceDiagnostic] {
			let typeName = "`\(hole.instantiatedType.asSource)`"
			let seamName = "`\(hole.scopeSeamType.asSource)`"
			let callerModule = callerModuleName.map { "module `\($0)`" } ?? "this module"
			let reference = "\(typeName), which @\(Dependency.Source.instantiatedRawValue) property `\(hole.property.asSource)` instantiates in chain: \(chain.map(\.asSource).joined(separator: " -> "))"
			let seamModule = if let seamModuleName, seamModuleName != callerModuleName {
				"in module `\(seamModuleName)`, which cannot see one either"
			} else {
				"in this module"
			}
			let fill = "\(seamName) generates its dependency tree \(seamModule), so the initializer SafeDI generated for it takes a builder for `\(hole.property.label)`, and `\(rootType.asSource)`, a root, must fill it."
			let message = if fulfilledByMockOnlyDeclaration {
				"No production @\(InstantiableVisitor.macroName) declaration that \(callerModule) can see fulfills \(reference). \(fill) A `mockOnly: true` declaration fulfills it, but is used only to generate mocks. Add a production @\(InstantiableVisitor.macroName) declaration that fulfills \(typeName)."
			} else {
				"No @\(InstantiableVisitor.macroName) type or extension that \(callerModule) can see fulfills \(reference). \(fill) Decorate \(typeName), or an extension of it, with @\(InstantiableVisitor.macroName); list \(typeName) in the `fulfillingAdditionalTypes` of an @\(InstantiableVisitor.macroName) type that conforms to it; \(DependencyTreeGenerator.DependencyTreeGeneratorError.fulfillingDeclarationInAnotherModuleRemedy)"
			}
			return [SourceDiagnostic(severity: .error, location: location, message: message)]
				+ (noteLocation.map { [SourceDiagnostic(severity: .note, location: $0, message: "`\(hole.ownerType.asSource)` instantiates `\(hole.property.asSource)` here.")] } ?? [])
		}
	}
}

// MARK: - What a fill cannot do

extension DependencyTreeGenerator {
	/// Throws `fillFindings` for every receive in a fill of the trees `generators` root that no value the fill holds gives
	/// inline's value for – the nearest declaration of its label on the site's path is bound after the site, the scope
	/// struct carries it at an access the caller cannot read, or carries it only as an optional value while the receive
	/// requires it – and for every scope in a fill that closes a cycle on a property of the seam's path, which code
	/// generated outside the seam's module cannot refer to. Each finding once, by kind and location.
	static func validateFills(
		inTreesRootedAt generators: [ScopeGenerator],
		callerModule: ModuleIdentity,
		seamModule: (TypeDescription) -> ModuleIdentity,
	) throws {
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		var findingKeys = Set<String>()
		func record(_ finding: DependencyTreeGeneratorError.FillFinding) {
			if findingKeys.insert(finding.key).inserted {
				findings.append(finding)
			}
		}
		for root in generators {
			// Each generator with what the calls inside every fill of its seam call hide from it, when it is such a fill.
			var generatorsToVisit = [(generator: root, hidden: FillReentryHidings?.none)]
			while let (generator, hidden) = generatorsToVisit.popLast() {
				if let hole = generator.fillHole, let child = generator.children.first {
					let module = seamModule(hole.scopeSeamType)
					findingsOfFill(of: hole, child: child, hidden: hidden ?? FillReentryHidings(), requirement: AccessLevel.required(toConstructFrom: callerModule, declaredIn: module, isOwnFile: false), callerModule: callerModule, seamModule: module, moduleOfSeam: seamModule).forEach(record)
				}
				// A seam call's children are its fills, which are judged against the calls inside any of them.
				let hiddenByFillKey = generator.seamCall == nil ? [:] : hiddenByReenteringCalls(ofFillsOf: generator)
				generatorsToVisit.append(contentsOf: generator.children.reversed().map { child in
					(child, child.fillKey.flatMap { hiddenByFillKey[$0] })
				})
			}
		}
		if !findings.isEmpty {
			throw DependencyTreeGeneratorError.fillFindings(findings)
		}
	}

	/// The findings of the fill of `hole` whose tree `child` roots, in the order the tree declares them. The membership
	/// test of a repeated property against the seam's path runs on this generator tree, where a seam the fill calls is a
	/// leaf, so a property re-entered through such a call is never matched; the cycle walk of
	/// `validateCyclesFromRootsOfForeignSeamsWithHoles`, which inlines every seam, judges those.
	/// - Parameter hidden: What the calls inside the fills of the seam call that declares this fill hide from it.
	private static func findingsOfFill(
		of hole: SeamSignature.Hole,
		child: ScopeGenerator,
		hidden: FillReentryHidings,
		requirement: AccessRequirement,
		callerModule: ModuleIdentity,
		seamModule: ModuleIdentity,
		moduleOfSeam: (TypeDescription) -> ModuleIdentity,
	) -> [DependencyTreeGeneratorError.FillFinding] {
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		let fields = Array(hole.stages.joined())
		let seamPathProperties = Set(hole.fillPropertyStack)
		typealias Frame = (generator: ScopeGenerator, parent: Instantiable?, providedProperties: Set<Property>, fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor])
		var framesToVisit: [Frame] = [(child, nil, [], [])]
		func isProvided(_ property: Property, by providedProperties: Set<Property>) -> Bool {
			providedProperties.contains(property)
				|| (property.typeDescription.isOptional && providedProperties.contains(property.asUnwrappedProperty))
		}
		func checkReceive(of property: Property, by instantiable: Instantiable, declaredAt declarationLocation: Dependency.DeclarationLocation?, onlyIfAvailable: Bool) {
			let reader = DependencyTreeGeneratorError.FillFinding.Reader(property: property, type: instantiable.concreteInstantiable, declarationLocation: declarationLocation)
			let sameLabelFields = fields.filter { $0.property.label == property.label }
			if let field = sameLabelFields.first(where: { field in
				field.property == property
					|| (property.typeDescription.isOptional && field.property == property.asUnwrappedProperty)
					|| field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding.map { $0 == property || (property.typeDescription.isOptional && $0 == property.asUnwrappedProperty) } == true
			}) {
				if !field.access.satisfies(requirement) {
					findings.append(.init(hole: hole, kind: .fieldNotReadable(reader: reader, field: field, callerModule: callerModule, seamModule: seamModule, requirement: requirement)))
				}
			} else if !onlyIfAvailable, let field = sameLabelFields.first(where: { $0.property.typeDescription.isOptional && $0.property.asUnwrappedProperty == property }) {
				findings.append(.init(hole: hole, kind: .fieldHeldOnlyOptionally(reader: reader, field: field, seamModule: seamModule)))
			} else if sameLabelFields.isEmpty, let declaration = hole.uncarriedDeclarations.first(where: { $0.property.label == property.label })
				// A call inside a fill that passes it to a seam passing the site up hands it that seam's copy of the hole,
				// which does not carry what that seam binds on its path to the call presenting the site.
				?? hidden.calledCopyDeclarations[property.label]
			{
				let module = if case let .boundByPassingUpSeam(passingUpSeam) = declaration.reason {
					moduleOfSeam(passingUpSeam)
				} else {
					seamModule
				}
				findings.append(.init(hole: hole, kind: .declarationBoundAfterSite(reader: reader, declaration: declaration, seamModule: module)))
			} else if sameLabelFields.isEmpty, let hiding = hidden.pathDeclarations[property.label] {
				findings.append(.init(hole: hole, kind: .declarationBoundOnPathToReenteringCall(
					reader: reader,
					declaration: hiding.declaration,
					pathHole: hiding.pathHole,
					callingType: hiding.callingType,
					callProperty: hiding.callProperty,
					calledSeam: hiding.calledSeam,
					callerModule: callerModule,
					seamModule: seamModule,
				)))
			}
			// A field of the label with another type is the inline hidden-label error, which validation reported.
		}
		while let (generator, parent, providedProperties, fillAncestors) = framesToVisit.popLast() {
			if generator.closesPropertyCycle, let property = generator.property {
				// A scope in the fill that closes a cycle on a property of the seam's path refers to a builder function
				// the seam's initializer declares, which code generated outside the seam's module cannot refer to.
				if !fillAncestors.contains(where: { $0.property == property }), seamPathProperties.contains(property) {
					findings.append(.init(hole: hole, kind: .closesCycleInSeamTree(
						closingProperty: property,
						closingType: parent?.concreteInstantiable,
						declarationLocation: parent?.dependencies.first { $0.property == property }?.declarationLocation,
						fillAncestors: fillAncestors,
						seamModule: seamModule,
					)))
				}
				continue
			}
			if let instantiable = generator.builtInstantiable {
				for dependency in instantiable.dependencies {
					switch dependency.source {
					case let .received(onlyIfAvailable):
						guard !isProvided(dependency.property, by: providedProperties) else { continue }
						checkReceive(of: dependency.property, by: instantiable, declaredAt: dependency.declarationLocation, onlyIfAvailable: onlyIfAvailable)
					case let .aliased(fulfillingProperty, _, onlyIfAvailable):
						guard !isProvided(fulfillingProperty, by: providedProperties.union(generator.providedProperties)) else { continue }
						checkReceive(of: fulfillingProperty, by: instantiable, declaredAt: dependency.declarationLocation, onlyIfAvailable: onlyIfAvailable)
					case .instantiated, .forwarded:
						continue
					}
				}
			}
			let childProvidedProperties = providedProperties.union(generator.providedProperties)
			let childFillAncestors = fillAncestors + (generator.property.map { [DependencyTreeGeneratorError.FillFinding.FillAncestor(property: $0, builtType: generator.builtInstantiable?.concreteInstantiable)] } ?? [])
			framesToVisit.append(contentsOf: generator.children.reversed().map { ($0, generator.builtInstantiable, childProvidedProperties, childFillAncestors) })
		}
		return findings
	}
}

extension DependencyTreeGenerator {
	/// A declaration on the path from a fill's root to a call inside the fill that re-enters a fill of the same seam call,
	/// with that call.
	fileprivate struct DeclarationOnPathToReenteringCall {
		let declaration: SeamSignature.Hole.UncarriedDeclaration
		/// The hole of the fill whose tree holds the path.
		let pathHole: SeamSignature.Hole
		/// The type whose scope makes the call.
		let callingType: TypeDescription
		let callProperty: Property
		let calledSeam: TypeDescription
	}

	/// What the calls inside the fills of one seam call hide from a fill of that call they pass on: inline, the seam such a
	/// call re-enters hands its fill's reads from the caller's scope the nearest declaration of their label at the call,
	/// and a seam that passes the site up hands it what it binds on its path to the call presenting the site; the fill,
	/// one function, reads the outer call's values.
	fileprivate struct FillReentryHidings {
		/// The declarations of the scopes on the paths from a fill's root to each call inside it that passes this fill on,
		/// by label, the first met for each.
		var pathDeclarations = [String: DeclarationOnPathToReenteringCall]()
		/// The declarations the copies of this fill's hole that those calls' seams take do not carry, by label, the first
		/// met for each.
		var calledCopyDeclarations = [String: SeamSignature.Hole.UncarriedDeclaration]()
	}

	/// What the calls inside the fills of `leaf`'s seam call hide from each of those fills, by the fill's key: each fill's
	/// tree, from the scope of its fulfiller, is walked depth first in declaration order, and at each call inside it that
	/// passes on a fill of `leaf`'s call (a call of a seam that holds the fill's site or passes its builder up), whichever
	/// fill's tree holds the call, that fill is hidden the declarations of the scopes on the path to the call – the fill's
	/// root and the calling scope included, the called seam excluded – and the declarations the called seam's copy of
	/// the hole does not carry. What a path declares is what `holesPassedUp` collects (`declarationsBound(by:…)`), the
	/// root's forwarded properties included. A cycle-closing scope declares nothing.
	fileprivate static func hiddenByReenteringCalls(ofFillsOf leaf: ScopeGenerator) -> [String: FillReentryHidings] {
		var hiddenByFillKey = [String: FillReentryHidings]()
		for case let (pathHole?, fulfiller?) in leaf.children.map({ ($0.fillHole, $0.children.first) }) {
			var generatorsToVisit = [(generator: fulfiller, callingType: TypeDescription?.none, pathDeclarations: [SeamSignature.Hole.UncarriedDeclaration]())]
			while let (generator, callingType, pathDeclarations) = generatorsToVisit.popLast() {
				guard !generator.closesPropertyCycle else { continue }
				for (fillKey, calledHole) in generator.enclosingFillsPassed {
					var hidden = hiddenByFillKey[fillKey, default: FillReentryHidings()]
					for declaration in calledHole.uncarriedDeclarations where hidden.calledCopyDeclarations[declaration.property.label] == nil {
						hidden.calledCopyDeclarations[declaration.property.label] = declaration
					}
					// The fill's root declares what is on every path, so a call that is the root itself has no scope above it.
					if let callingType, let callProperty = generator.property, let calledSeam = generator.builtInstantiable?.concreteInstantiable {
						for declaration in pathDeclarations where hidden.pathDeclarations[declaration.property.label] == nil {
							hidden.pathDeclarations[declaration.property.label] = DeclarationOnPathToReenteringCall(declaration: declaration, pathHole: pathHole, callingType: callingType, callProperty: callProperty, calledSeam: calledSeam)
						}
					}
					hiddenByFillKey[fillKey] = hidden
				}
				let childPathDeclarations = pathDeclarations + declarationsBound(by: generator, includingForwardedProperties: true, reason: .other)
				let childCallingType = generator.builtInstantiable?.concreteInstantiable ?? callingType
				generatorsToVisit.append(contentsOf: generator.children.reversed().map { ($0, childCallingType, childPathDeclarations) })
			}
		}
		return hiddenByFillKey
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError {
	/// What a fill of `hole` cannot do.
	struct FillFinding {
		/// A scope on the path from a fill's root down to a scope that closes a cycle: the property it builds, and the
		/// type it builds it with, which declares the next property on the path.
		struct FillAncestor {
			let property: Property
			let builtType: TypeDescription?
		}

		/// A receive in a fill's tree.
		struct Reader {
			let property: Property
			let type: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
		}

		enum Kind {
			/// The scope struct carries the value the reader receives at an access the caller's module cannot read.
			case fieldNotReadable(reader: Reader, field: SeamSignature.Hole.Field, callerModule: ModuleIdentity, seamModule: ModuleIdentity, requirement: AccessRequirement)
			/// The scope struct carries the value only as an optional value, which the reader requires.
			case fieldHeldOnlyOptionally(reader: Reader, field: SeamSignature.Hole.Field, seamModule: ModuleIdentity)
			/// The nearest declaration of the reader's label on the site's path is bound after the site, or the seam
			/// that passes the builder up binds it; `seamModule` is the module that must see a fulfilling declaration.
			case declarationBoundAfterSite(reader: Reader, declaration: SeamSignature.Hole.UncarriedDeclaration, seamModule: ModuleIdentity)
			/// A scope of the fill of `pathHole` – this fill, or another of the same seam call – declares the reader's label on
			/// the path from that fill's root to `callingType`'s call of `calledSeam` (`callProperty`), which passes this fill
			/// on: inline, the re-entered seam would read that declaration, and the fill reads the outer call's value.
			case declarationBoundOnPathToReenteringCall(
				reader: Reader,
				declaration: SeamSignature.Hole.UncarriedDeclaration,
				pathHole: SeamSignature.Hole,
				callingType: TypeDescription,
				callProperty: Property,
				calledSeam: TypeDescription,
				callerModule: ModuleIdentity,
				seamModule: ModuleIdentity,
			)
			/// A scope in the fill closes a cycle on `closingProperty`, a property of the seam's path, declared by
			/// `closingType` beneath `fillAncestors`.
			case closesCycleInSeamTree(closingProperty: Property, closingType: TypeDescription?, declarationLocation: Dependency.DeclarationLocation?, fillAncestors: [FillAncestor], seamModule: ModuleIdentity)
		}

		let hole: SeamSignature.Hole
		let kind: Kind

		/// What identifies the finding: its kind and where it is reported.
		var key: String {
			let location = sourceDiagnostics.first?.location.map { "\($0.filePath):\($0.line):\($0.column)" } ?? ""
			return switch kind {
			case .fieldNotReadable:
				"fieldNotReadable \(location)"
			case .fieldHeldOnlyOptionally:
				"fieldHeldOnlyOptionally \(location)"
			case .declarationBoundAfterSite:
				"declarationBoundAfterSite \(location)"
			case .declarationBoundOnPathToReenteringCall:
				"declarationBoundOnPathToReenteringCall \(location)"
			case .closesCycleInSeamTree:
				"closesCycleInSeamTree \(location)"
			}
		}

		var sourceDiagnostics: [SourceDiagnostic] {
			func builderDescription(of hole: SeamSignature.Hole) -> String {
				"the builder for `\(hole.ownerType.asSource)`'s `\(hole.property.asSource)`"
			}
			let builder = builderDescription(of: hole)
			let scope = "the scope SafeDI hands \(builder)"
			let seamName = "`\(hole.scopeSeamType.asSource)`"
			func module(_ identity: ModuleIdentity) -> String {
				identity.moduleName.map { "module `\($0)`" } ?? "this module"
			}
			func builderOfDeclaration(_ declaration: SeamSignature.Hole.UncarriedDeclaration) -> String {
				declaration.declaringType == hole.scopeSeamType ? "\(seamName)'s dependency tree" : "`\(declaration.declaringType.asSource)`"
			}
			func fulfillRemedy(_ seamModule: ModuleIdentity) -> String {
				"make an @\(InstantiableVisitor.macroName) declaration that fulfills `\(hole.instantiatedType.asSource)` one \(module(seamModule)) reads"
			}
			switch kind {
			case let .fieldNotReadable(reader, field, callerModule, seamModule, requirement):
				let level = "`\(field.access.spelledOnGeneratedDeclaration)`"
				let reach = if field.access == .package, let packageName = seamModule.packageName {
					"\(module(callerModule)) is not in package `\(packageName)`"
				} else {
					"\(module(callerModule)) is not \(module(seamModule))"
				}
				// How the field's type is proven, and what proves it as widely as the filler needs, as the shared formatter
				// explains a seam parameter's access. A filler is never in the seam's own module, which then has no hole.
				let neededLevel: AccessLevel = requirement == .public ? .public : .package
				let causeText = field.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: []) } ?? ""
				let remedies = SeamAccessExplanation.causeRemedies(field.accessCause, neededLevel: neededLevel)
					+ [SeamAccessExplanation.fulfillRemedy(fulfilling: hole.instantiatedType, seam: hole.scopeSeamType, seamModuleName: seamModule.moduleName, isPassedUp: false)]
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(scope) carries only at \(level) access, and \(reach).\(causeText) \(SeamAccessExplanation.joined(remedies))"),
				] + SeamAccessExplanation.declarationNotes(for: field.accessCause, neededLevel: neededLevel) + [
					SourceDiagnostic(severity: .note, location: field.declarationLocation, message: "`\(field.declaringType.asSource)` declares `\(field.property.asSource)` here."),
				]
			case let .fieldHeldOnlyOptionally(reader, field, _):
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(scope) carries only as `\(field.property.asSource)`, since \(seamName)'s tree receives it only if available. Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on \(seamName), or receive it on `\(reader.type.asSource)` with `@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true) let \(field.property.asSource)`."),
					SourceDiagnostic(severity: .note, location: field.declarationLocation, message: "`\(field.declaringType.asSource)` receives `\(field.property.asSource)` here."),
				]
			case let .declarationBoundAfterSite(reader, declaration, seamModule):
				let note = SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "`\(declaration.declaringType.asSource)` declares `\(declaration.property.asSource)` here.")
				let pathScope = "`\(declaration.builtAfter?.label ?? "")`"
				let message = switch declaration.reason {
				case let .boundByPassingUpSeam(seam):
					// The seam that holds the site binds the label on a path to a call that hands its builder back to it.
					(seam == hole.scopeSeamType
						? "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(seamName)'s tree builds where it instantiates \(seamName) again, but that call passes the builder \(seamName) takes for `\(hole.ownerType.asSource)`'s `\(hole.property.asSource)` on unchanged, so the caller that fills it cannot hand it those values."
						: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(declaration.declaringType == seam ? "`\(seam.asSource)` builds where it calls \(seamName)" : "`\(declaration.declaringType.asSource)` builds on the path where `\(seam.asSource)` calls \(seamName)"), but `\(seam.asSource)` passes \(builder) on from its own caller, which cannot hand it \(declaration.declaringType == seam ? "`\(seam.asSource)`'s values" : "that value").")
						+ " Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on \(seamName), so the builder's scope carries it, or \(fulfillRemedy(seamModule)), so `\(seam.asSource)` fills the builder itself."
				case let .receivesPathScopeOnlyIfAvailable(type):
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(builderOfDeclaration(declaration)) builds after \(pathScope), since `\(type.asSource)` receives \(pathScope) only if available, so \(scope) does not carry it. Receive \(pathScope) on `\(type.asSource)` some other way, or \(fulfillRemedy(seamModule))."
				case let .requiresOtherCarrier(type, carrier):
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(builderOfDeclaration(declaration)) builds after \(pathScope), since `\(type.asSource)` requires `\(carrier.label)`, which carries another builder, so \(scope) does not carry it. Declare `\(declaration.property.label)` before \(pathScope) in `\(declaration.declaringType.asSource)`, or \(fulfillRemedy(seamModule))."
				case .other:
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(builderOfDeclaration(declaration)) builds after the scope that builds \(builder), so \(scope) does not carry it. \(fulfillRemedy(seamModule).prefix(1).uppercased())\(fulfillRemedy(seamModule).dropFirst())."
				}
				return [SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: message), note]
			case let .declarationBoundOnPathToReenteringCall(reader, declaration, pathHole, callingType, callProperty, calledSeam, callerModule, seamModule):
				let declaringType = "`\(declaration.declaringType.asSource)`"
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(declaringType) declares on the path from \(builderDescription(of: pathHole)) to the call by which `\(callingType.asSource)` instantiates `\(calledSeam.asSource)` again (`\(callProperty.label)`), but that call passes the builder on as \(module(callerModule)) fills it, which cannot hand it \(declaringType)'s values. Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on \(seamName), so the builder's scope carries it, or \(fulfillRemedy(seamModule))."),
					SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "\(declaringType) declares `\(declaration.property.asSource)` here."),
				]
			case let .closesCycleInSeamTree(closingProperty, closingType, declarationLocation, fillAncestors, seamModule):
				let closingTypeName = closingType.map { "`\($0.asSource)`" } ?? "a type"
				// The type that fills the builder is the fill's root; a closer beneath it is named beneath it.
				let closer = fillAncestors.count > 1 ? "\(closingTypeName), beneath `\(fillAncestors.first?.builtType?.asSource ?? "")`, which fills it," : "\(closingTypeName), which fills it,"
				let pathIndex = hole.sitePath.firstIndex(of: closingProperty) ?? hole.sitePath.startIndex
				let pathOwner = pathIndex == hole.sitePath.startIndex ? hole.scopeSeamType : hole.sitePath[pathIndex - 1].typeDescription.asInstantiatedType
				var chain = [hole.scopeSeamType.asSource]
				for property in hole.sitePath.dropLast() {
					chain += [property.label, property.typeDescription.asInstantiatedType.asSource]
				}
				chain.append(hole.property.label)
				// Each property beneath the fill's root, after the type that builds it: the one its ancestor built.
				for (ancestor, property) in zip(fillAncestors, fillAncestors.dropFirst()) {
					chain += [ancestor.builtType?.asSource ?? "", property.property.label]
				}
				chain += [closingType?.asSource ?? "", closingProperty.label]
				let renameRemedy = hole.property.propertyType.isConstant ? "" : "; or give `\(closingProperty.label)` on \(closingTypeName) another label, so the cycle closes at `\(hole.property.label)` itself"
				return [
					SourceDiagnostic(severity: .error, location: declarationLocation, message: "SafeDI cannot fill \(builder) in \(seamName)'s dependency tree: \(closer) instantiates `\(closingProperty.asSource)`, which \(seamName)'s tree is building where it builds `\(hole.property.label)` (\(chain.joined(separator: " -> "))). Code generated outside \(module(seamModule)) cannot refer to the function \(seamName)'s initializer builds `\(closingProperty.typeDescription.asInstantiatedType.asSource)` with, and building it again would hand it other values than \(seamName)'s tree holds. Instantiate the seam where \(closingTypeName) builds `\(closingProperty.typeDescription.asInstantiatedType.asSource)` (`@Instantiated let \(hole.scopeSeamType.asSource.prefix(1).lowercased() + hole.scopeSeamType.asSource.dropFirst())Builder: Instantiator<\(hole.scopeSeamType.asSource)>`), so the cycle re-enters through the initializer SafeDI generates for \(seamName); \(fulfillRemedy(seamModule))\(renameRemedy)."),
				] + (hole.sitePathDeclarationLocations.indices.contains(pathIndex) ? [SourceDiagnostic(severity: .note, location: hole.sitePathDeclarationLocations[pathIndex], message: "`\(pathOwner.asSource)` instantiates `\(closingProperty.asSource)` here.")] : [])
			}
		}
	}
}

extension SeamSignature.Hole {
	/// This hole with `declarations` among the declarations a fill cannot read.
	func addingUncarriedDeclarations(_ declarations: [UncarriedDeclaration], isSendable: Bool) -> SeamSignature.Hole {
		guard !declarations.isEmpty || isSendable != self.isSendable else { return self }
		return SeamSignature.Hole(
			ownerType: ownerType,
			property: property,
			instantiatedType: instantiatedType,
			declarationLocation: declarationLocation,
			erasedToConcreteExistential: erasedToConcreteExistential,
			sitePath: sitePath,
			sitePathDeclarationLocations: sitePathDeclarationLocations,
			fillPropertyStack: fillPropertyStack,
			builderLabel: builderLabel,
			internalName: internalName,
			scopeSeamType: scopeSeamType,
			scopeTypeName: scopeTypeName,
			stages: stages,
			stageBoundaryDepths: stageBoundaryDepths,
			tierAccess: tierAccess,
			accessCause: accessCause,
			uncarriedDeclarations: uncarriedDeclarations + declarations,
			innerSeamType: innerSeamType,
			isSendable: isSendable,
		)
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError {
	/// A hole in the tree of a seam whose module SafeDI does not know – a run without a module name, as a target the
	/// Xcode project plugin builds is – so the initializer it generates cannot take a builder: what the module's callers
	/// see is unknown, and they build the seam inline. The message leads with the remedies every build can apply, and
	/// names the module last, for a build that can name it. It never suggests reading a module that depends on this
	/// one, whose files the generated code could not see.
	struct HoleInSeamOfUnnamedModule {
		let seam: TypeDescription
		let owner: TypeDescription
		let dependency: Dependency

		var sourceDiagnostic: SourceDiagnostic {
			let seamName = "`\(seam.asSource)`"
			let typeName = "`\(dependency.asInstantiatedType.asSource)`"
			let label = "`\(dependency.property.label)`"
			return SourceDiagnostic(
				severity: .error,
				location: dependency.declarationLocation,
				message: "\(seamName) generates its dependency tree, and `\(owner.asSource)`'s @\(Dependency.Source.instantiatedRawValue) property `\(dependency.property.asSource)` in it instantiates \(typeName), which no @\(InstantiableVisitor.macroName) declaration this module reads fulfills. SafeDI does not know which module declares \(seamName), so it cannot know what that module's callers see, and the initializer it generates cannot take a builder for \(label). Declare an @\(InstantiableVisitor.macroName) type that fulfills \(typeName) in this module or in a module it depends on, declare \(seamName) without `generateDependencyTree: true`, or, in a build that can name this module, run SafeDITool with its name (`--module-name`, Bazel's `module_name`).",
			)
		}
	}
}
