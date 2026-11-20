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
	/// Whether code in every module can construct `instantiable` with its hand-written mock method when
	/// `withMockMethod` is set, and otherwise with its initializer or `instantiate()` method, among `extendedTypes`,
	/// which bound a type declared in or by an extension.
	static func isPubliclyConstructible(_ instantiable: Instantiable, withMockMethod: Bool, extendedTypes: ExtendedTypeDeclarations) -> Bool {
		(instantiable.accessNeeds(constructingWithMockMethod: withMockMethod) + extendedTypeAccessNeeds(of: instantiable, in: extendedTypes))
			.allSatisfy { $0.level.satisfies(.public) }
	}

	/// The outermost `public` type another module declares on the path to a construction in a mock's tree, which a
	/// mock of this module builds inline (see `Construction.publicMockCandidate`).
	enum PublicMockCandidate: Hashable {
		/// The type has neither a hand-written nor a public mock: one would spare this module building its tree.
		/// - `declaringModuleName`: The module that declares the type and would generate its public mock.
		/// - `needsPublicDeclaration`: Whether the type is narrower than `public`, which a public mock requires.
		/// - `isSeam`: Whether the type is a seam (`generateDependencyTree: true`), whose tree a mock builds inline.
		case withoutMock(TypeDescription, declaringModuleName: String?, needsPublicDeclaration: Bool, isSeam: Bool)
		/// The type has a public mock, but SafeDI does not know which module declares it, and therefore cannot call it: the
		/// type was read from a file no target graph or module name assigns to a module – as a target the Xcode project
		/// plugin builds reads every other target's types, and as a directory a `#SafeDIConfiguration` adds is read.
		/// `emittingModuleIsUnknown`, whether this run names no module, decides only the error's wording.
		case publicMockOfUnknownModule(TypeDescription, emittingModuleIsUnknown: Bool)
	}

	/// A type the generated code constructs, with how it constructs it.
	struct Construction {
		/// - Parameter extendedTypes: The declarations the module reads, among which the declaration of a type an
		///   extension extends bounds the types declared in or by that extension.
		init(
			instantiable: Instantiable,
			usesMockMethod: Bool,
			referenceLocation: Dependency.DeclarationLocation?,
			isSeamLeaf: Bool,
			extendedTypes: ExtendedTypeDeclarations,
			publicMockCandidate: PublicMockCandidate? = nil,
			seamCandidateOnPaths: SeamCandidateOnPaths = .agreed(nil),
			inlineSeam: DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam? = nil,
		) {
			self.instantiable = instantiable
			self.usesMockMethod = usesMockMethod
			self.referenceLocation = referenceLocation
			self.isSeamLeaf = isSeamLeaf
			self.publicMockCandidate = publicMockCandidate
			extendedTypeAccessNeeds = DependencyTreeGenerator.extendedTypeAccessNeeds(of: instantiable, in: extendedTypes)
			self.seamCandidateOnPaths = seamCandidateOnPaths
			self.inlineSeam = inlineSeam
		}

		/// In a mock's tree, what the outermost type on the path to the construction that another module declares
		/// offers instead of building its tree here, which an error about the construction says.
		let publicMockCandidate: PublicMockCandidate?

		let instantiable: Instantiable
		/// Whether the type is constructed with its hand-written mock method rather than with its initializer or
		/// `instantiate()` method.
		let usesMockMethod: Bool
		/// Where this module refers to what leads to the construction: the first, in source order, of the dependencies
		/// declared in the module's own files on a path to it, or the declaration of the tree's root. An error about
		/// the construction is reported there when the declaration that must change cannot be read.
		let referenceLocation: Dependency.DeclarationLocation?
		/// Whether the construction calls an initializer SafeDI generates for a seam, which is at most as visible as the
		/// seam's type: only the type's declaration, and those enclosing it, can keep it from compiling.
		let isSeamLeaf: Bool
		/// The declarations of the type an extension extends that bound the constructed type, when it is declared in or
		/// by that extension (`extendedTypeAccessNeeds(of:in:)`): code that names the type names the extended type too.
		let extendedTypeAccessNeeds: [AccessNeed]

		/// In a production tree, what the paths to the construction decide about the type whose generated initializer
		/// the tree could call instead of building the type's tree, were the type declared with
		/// `generateDependencyTree: true`: see `SeamCandidateOnPaths`.
		let seamCandidateOnPaths: SeamCandidateOnPaths
		/// In a production tree of a module SafeDI cannot name, the outermost seam on the path to the construction that
		/// another module declares, which the tree builds inline because it cannot call the seam's generated initializer.
		/// The path with the earliest reference location decides it, as it decides `referenceLocation`.
		let inlineSeam: DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam?

		/// The declarations whose access decides whether the construction compiles, which the check of every
		/// construction reads.
		var accessNeeds: [AccessNeed] {
			(isSeamLeaf
				? DependencyTreeGenerator.seamLeafAccessNeeds(of: instantiable)
				: instantiable.accessNeeds(constructingWithMockMethod: usesMockMethod)) + extendedTypeAccessNeeds
		}
	}

	/// The declarations of the type an extension extends that bound a type the extension declares – a type declared
	/// inside the extension, or the type an `@Instantiable` extension declares – when the extended type is declared in
	/// the same module: the code that names the declared type names the extended type too, so the extended type's
	/// declaration, and those enclosing it in its file, must be as visible as the construction needs, and so must the
	/// declarations that bound the extended type when it is declared inside an extension itself, and so on
	/// (`ExtendedTypeDeclarations.accessNeeds(boundingTypesAnExtensionOf:declaresInModuleNamed:fromFileAt:)`), outermost
	/// first. Empty for any other declaration.
	static func extendedTypeAccessNeeds(of instantiable: Instantiable, in extendedTypes: ExtendedTypeDeclarations) -> [AccessNeed] {
		guard let extendedType = instantiable.extendedType, let moduleName = instantiable.moduleName else { return [] }
		return extendedTypes.accessNeeds(boundingTypesAnExtensionOf: extendedType, declaresInModuleNamed: moduleName, fromFileAt: instantiable.sourceFilePath)
	}

	/// The declarations whose access decides whether a call of a seam's generated initializer compiles: the seam's type
	/// and the types enclosing it, never the generated initializer, whose access is at most the type's, nor the seam's
	/// own initializer, which the generated initializer calls inside the seam's module.
	fileprivate static func seamLeafAccessNeeds(of leaf: Instantiable) -> [AccessNeed] {
		leaf.accessNeeds(constructingWithMockMethod: false).filter { $0.declaration.declaredType != nil }
	}

	/// What the paths from a production tree's root to a construction decide about its seam candidate: on each path,
	/// the outermost type – the first met from the root, the construction's own type included – that a module SafeDI
	/// knows, other than this one, declares. Declaring that type with `generateDependencyTree: true` has its module
	/// build the type's tree, and this module call the initializer generated for it, so it keeps the construction out
	/// of this module only when every path passes through it, and only when that module's own run of `generate` reads
	/// the declaration of every type on each path from the candidate to the construction, the construction's own type
	/// included (`EmittingModule.modulesReadByRunOfModule`): it builds the tree from those declarations, as this
	/// run computes the seam's signature from them, and takes a builder for a type it does not see, which this module
	/// fills, building that type and its tree itself. That initializer's widest tier is at the candidate type's
	/// access, and it builds the tree, calls the candidate's own initializer, and takes each property the tree receives
	/// from above the candidate as a parameter as visible as the types it names, capped at the candidate's type, so
	/// every initializer of the tree, the one of a type that receives such a property included, is called inside the
	/// candidate's module (`seamRemedy(offeredBy:toWiden:declaredIn:extendedTypes:)`). Nothing beneath a type is
	/// constructed unless the type instantiates it, which neither a seam whose module SafeDI knows (this module calls its
	/// generated initializer and builds none of its tree), a leaf, nor a type an extension declares (whose dependencies
	/// are all received) does, so none of them is ever a candidate for another construction, and none needs excluding,
	/// though the macro rejects `generateDependencyTree` on an extension. A leaf or a type an extension declares can be
	/// its own construction's candidate, but it builds no tree, so SafeDI would generate no initializer for it, and its
	/// construction's errors offer no remedy. A `mockOnly` declaration is in no production tree. Mocks build every tree
	/// inline, so a mock's constructions have no candidate.
	enum SeamCandidateOnPaths: Equatable {
		/// Every path walked so far has this candidate, whose module reads every type on the path from it, or none has
		/// one (`nil`).
		case agreed(Instantiable?)
		/// Two paths have different candidates, one has a candidate and another none, or a path from its candidate builds
		/// a type whose declaration the candidate's module does not read.
		case disagreed

		/// The candidate every path has, if any.
		var candidate: Instantiable? {
			switch self {
			case let .agreed(candidate):
				candidate
			case .disagreed:
				nil
			}
		}

		/// What the paths through a scope decide for its child `child`, which is a candidate on a path that has none
		/// above it when `childIsCandidate` is set, and whose declaration a candidate's module reads when
		/// `candidatesModuleReads` says so.
		func extended(
			to child: Instantiable,
			childIsCandidate: Bool,
			candidatesModuleReads: (_ child: Instantiable, _ candidate: Instantiable) -> Bool,
		) -> SeamCandidateOnPaths {
			switch self {
			case let .agreed(.some(candidate)):
				candidatesModuleReads(child, candidate) ? self : .disagreed
			case .agreed(.none):
				.agreed(childIsCandidate ? child : nil)
			case .disagreed:
				.disagreed
			}
		}

		/// What the paths of this and of `other` together decide. Candidates compare as declarations, so two map entries
		/// of one type would disagree, which withholds the remedy and never offers a wrong one.
		func merged(with other: SeamCandidateOnPaths) -> SeamCandidateOnPaths {
			switch (self, other) {
			case let (.agreed(candidate), .agreed(otherCandidate)) where candidate == otherCandidate:
				.agreed(candidate)
			case (.agreed, .agreed), (.agreed, .disagreed), (.disagreed, .agreed), (.disagreed, .disagreed):
				.disagreed
			}
		}
	}

	/// The seam an error about `accessNeed`, declared in `declaringModule`, offers when `candidate` is the seam candidate
	/// of every construction that needs it, or `nil` when declaring the candidate a seam would not let this module
	/// leave the declaration alone. That is so when the declaration is one a call of the initializer generated for the
	/// candidate relies on, as `Construction.accessNeeds` reads it for a seam leaf: the candidate's type, a type
	/// enclosing it, an extension one of those takes its level from, or the type an extension that declares the
	/// candidate extends, of which the generated initializer is no more visible. It is so for any declaration when the
	/// candidate builds no tree (`buildsTree(_:)`): SafeDI then generates no initializer for it, and its callers call its
	/// own; such a candidate, a leaf or a type an extension declares, is the candidate of its own construction alone. And
	/// it is so for a declaration the candidate's module cannot reach. A path from the candidate through a type whose
	/// declaration the candidate's module does not read, such as an implementation of a protocol that a module depending
	/// on it provides, decides no candidate (`SeamCandidateOnPaths`): the seam would take a builder for that type, which
	/// this module fills. Any other declaration – the candidate's own initializer, or one of a type in its tree, in the
	/// candidate's module or another it reads, including one that receives a property from above the candidate – is
	/// called only inside the candidate's module. A required parameter whose type
	/// is narrower than the candidate's type makes the declared seam an error in its own module
	/// (`tierOmitsRequiredParameter`), which says what to narrow or widen, never at this declaration.
	/// - Parameter extendedTypes: The declarations the module reads, among which the declaration of a type an extension
	///   extends bounds the types declared in or by that extension.
	static func seamRemedy(
		offeredBy candidate: Instantiable,
		toWiden accessNeed: AccessNeed,
		declaredIn declaringModule: ModuleIdentity,
		extendedTypes: ExtendedTypeDeclarations,
	) -> DependencyTreeGeneratorError.InaccessibleConstruction.SeamRemedy? {
		guard buildsTree(candidate),
		      let moduleName = candidate.moduleName,
		      !(seamLeafAccessNeeds(of: candidate) + extendedTypeAccessNeeds(of: candidate, in: extendedTypes)).contains(where: { $0.access == accessNeed.access }),
		      accessNeed.level.satisfies(AccessLevel.required(
		      	toConstructFrom: ModuleIdentity(moduleName: moduleName, packageName: candidate.packageName),
		      	declaredIn: declaringModule,
		      	isOwnFile: false,
		      ))
		else { return nil }
		return .init(type: candidate.concreteInstantiable, moduleName: moduleName)
	}

	/// What identifies a construction while walking a tree: the scope that builds it, and how it builds it.
	private struct ConstructionKey: Hashable {
		let scope: ObjectIdentifier
		let usesMockMethod: Bool
	}

	/// The constructions the code generated for the tree rooted at `rootScope` emits: the root's own, and each scope
	/// the tree instantiates, transitively – the trees of the fills of each seam call it makes included – once each, in
	/// no particular order.
	/// - Parameters:
	///   - rootIsConstructedWithMockMethod: Whether the root is constructed with its hand-written mock method.
	///   - rootReferenceLocation: Where this module refers to the root.
	///   - isMock: Whether the tree is a mock's, which constructs each type it builds with its hand-written mock method
	///     where that method returns a type the property accepts, as `ScopeGenerator` builds it.
	///   - emittingModule: The module the generated code compiles in, whose own files hold the dependencies that refer
	///     to a construction.
	///   - extendedTypes: The declarations the module reads, among which the declaration of a type an extension
	///     extends bounds the types declared in or by that extension.
	static func constructions(
		inTreeRootedAt rootScope: Scope,
		rootIsConstructedWithMockMethod: Bool,
		rootReferenceLocation: Dependency.DeclarationLocation?,
		isMock: Bool,
		emittingModule: EmittingModule,
		extendedTypes: ExtendedTypeDeclarations,
		leavingOut typesLeftOut: Set<TypeDescription> = [],
	) -> [Construction] {
		var constructionsByKey = [ConstructionKey: Construction]()
		// A scope can be reached along several paths, and the first reference location in source order is kept,
		// whichever path is walked first, with that path's public mock candidate, while every path has its say in the
		// seam candidate. A scope is walked again only when it is reached with an earlier reference location or what its
		// paths decide about the seam candidate changes, which only narrows, so the walk ends, and a worklist rather than
		// recursion walks it, since a tree can be as deep as the module has types.
		/// Whether `instantiable` is a seam candidate on a path that has none above it: see `SeamCandidateOnPaths`.
		func isSeamCandidate(_ instantiable: Instantiable) -> Bool {
			guard !isMock, let moduleName = instantiable.moduleName else { return false }
			return moduleName != emittingModule.identity.moduleName
		}
		var moduleNamesReadByModuleName = [String: Set<String>]()
		/// Whether the run of `generate` for `candidate`'s module reads the declaration of `child`, a type on a path from
		/// `candidate`: see `SeamCandidateOnPaths`. A type whose module SafeDI does not know is read by no other module.
		func candidatesModuleReads(_ child: Instantiable, _ candidate: Instantiable) -> Bool {
			guard let childModuleName = child.moduleName, let candidateModuleName = candidate.moduleName else { return false }
			let moduleNamesRead = moduleNamesReadByModuleName[candidateModuleName] ?? emittingModule.modulesReadByRunOfModule?(candidateModuleName).moduleNames ?? []
			moduleNamesReadByModuleName[candidateModuleName] = moduleNamesRead
			return moduleNamesRead.contains(childModuleName)
		}
		/// The seam that `scope` builds inline, referred to at `referenceLocation`, when the tree is a production tree of a
		/// module SafeDI cannot name and another module declares the seam: see `Construction.inlineSeam`.
		func inlineSeam(builtBy scope: Scope, referencedAt referenceLocation: Dependency.DeclarationLocation?) -> DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam? {
			guard !isMock,
			      emittingModule.identity.moduleName == nil,
			      scope.instantiable.generatesDependencyTree,
			      scope.seamCall == nil,
			      !(scope.instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false)
			else { return nil }
			return .init(type: scope.instantiable.concreteInstantiable, referenceLocation: referenceLocation)
		}
		/// What a type another module declares, `instantiable`, offers a mock of this module that builds its tree: `nil`
		/// for a type with a hand-written mock, which the mock calls, one this module declares, or one that cannot have a
		/// public mock as it is declared: an extension's, which the macro rejects `generateMock: .public` on, or one an
		/// enclosing type, or the type an enclosing extension extends, keeps narrower than `public`.
		func candidate(of instantiable: Instantiable) -> PublicMockCandidate? {
			guard isMock,
			      !instantiable.declarationType.isExtension,
			      instantiable.mockInitializer == nil,
			      !(instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false),
			      instantiable.enclosingTypeAccess.enumerated().allSatisfy({ enclosingType in
			      	AccessLevel.ownLevel(of: enclosingType.element, directlyInside: enclosingType.offset == 0 ? instantiable.enclosingExtensionAccess : nil).satisfies(.public)
			      }),
			      Self.extendedTypeAccessNeeds(of: instantiable, in: extendedTypes).allSatisfy({ $0.level.satisfies(.public) })
			else { return nil }
			let isPublic = AccessLevel.effective(ofTypeDeclaredBy: instantiable).satisfies(.public)
			if let moduleName = instantiable.moduleName {
				// A public mock of a type of a module SafeDI knows is called wherever the tree cannot be built; a type narrower
				// than `public` – a seam under adoption is usually `package` – needs that declaration widened too.
				return moduleName != emittingModule.identity.moduleName && instantiable.generateMock != .public
					? .withoutMock(instantiable.concreteInstantiable, declaringModuleName: moduleName, needsPublicDeclaration: !isPublic, isSeam: instantiable.generatesDependencyTree)
					: nil
			} else {
				guard isPublic else { return nil }
				return instantiable.generateMock == .public
					? .publicMockOfUnknownModule(instantiable.concreteInstantiable, emittingModuleIsUnknown: emittingModule.identity.moduleName == nil)
					: .withoutMock(instantiable.concreteInstantiable, declaringModuleName: nil, needsPublicDeclaration: false, isSeam: instantiable.generatesDependencyTree)
			}
		}
		// The root is the module's own, or a mock's, so it is neither a seam candidate nor a seam built inline.
		var scopesToWalk = [(scope: rootScope, usesMockMethod: rootIsConstructedWithMockMethod, referenceLocation: rootReferenceLocation, seamCandidateOnPaths: SeamCandidateOnPaths.agreed(nil), inlineSeamOnPath: DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam?.none, publicMockCandidate: candidate(of: rootScope.instantiable))]
		while let (scope, usesMockMethod, referenceLocation, seamCandidateOnPaths, inlineSeamOnPath, publicMockCandidate) = scopesToWalk.popLast() {
			let key = ConstructionKey(scope: ObjectIdentifier(scope), usesMockMethod: usesMockMethod)
			let walkedConstruction = constructionsByKey[key]
			let isEarliestPath = walkedConstruction.map { Dependency.DeclarationLocation.precedesInSourceOrder(referenceLocation, $0.referenceLocation) } ?? true
			let mergedSeamCandidateOnPaths = walkedConstruction.map { $0.seamCandidateOnPaths.merged(with: seamCandidateOnPaths) } ?? seamCandidateOnPaths
			guard isEarliestPath || mergedSeamCandidateOnPaths != walkedConstruction?.seamCandidateOnPaths else {
				continue
			}
			constructionsByKey[key] = Construction(
				instantiable: scope.instantiable,
				usesMockMethod: usesMockMethod,
				referenceLocation: isEarliestPath ? referenceLocation : walkedConstruction?.referenceLocation,
				isSeamLeaf: scope.seamCall != nil,
				extendedTypes: extendedTypes,
				publicMockCandidate: isEarliestPath ? publicMockCandidate : walkedConstruction?.publicMockCandidate,
				seamCandidateOnPaths: mergedSeamCandidateOnPaths,
				inlineSeam: isEarliestPath ? inlineSeamOnPath : walkedConstruction?.inlineSeam,
			)
			let isDeclaredInOwnFile = scope.instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate
				where !typesLeftOut.contains(childScope.instantiable.concreteInstantiable)
			{
				// A dependency the mock promotes to its root, or retypes there, is declared by no type of the tree.
				let childReferenceLocation = isDeclaredInOwnFile
					? scope.instantiable.dependencies.first(where: { $0.property == property })?.declarationLocation ?? referenceLocation
					: referenceLocation
				scopesToWalk.append((
					scope: childScope,
					usesMockMethod: isMock && childScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType),
					referenceLocation: childReferenceLocation,
					// Every path to the child through this scope extends a path to this scope.
					seamCandidateOnPaths: mergedSeamCandidateOnPaths.extended(to: childScope.instantiable, childIsCandidate: isSeamCandidate(childScope.instantiable), candidatesModuleReads: candidatesModuleReads),
					inlineSeamOnPath: inlineSeamOnPath ?? inlineSeam(builtBy: childScope, referencedAt: childReferenceLocation),
					publicMockCandidate: publicMockCandidate ?? candidate(of: childScope.instantiable),
				))
			}
			// A seam call's fills are constructions of this module's code: the fulfilling type and its tree, built with
			// their initializers as the type's own module builds them, reached where the call is. A mock's tree calls no
			// seam's generated initializer, and fills another module's public mock's builder only where every construction
			// of the fill is one this module can reach (`holesFilled(byCallsOf:in:)`), so only a production tree's fills
			// are walked. A fill starts a path of its own, whose candidate is the fill's type when another module SafeDI
			// knows declares it: declared a seam, that module builds the type's tree and the fill calls the initializer
			// generated for it. No candidate above the seam reaches the fill: a type above the seam declared a seam would
			// pass the builder up to this module whenever its own module cannot see the fulfilling type, so it would keep
			// the fill out of this module for no path.
			if !isMock {
				for case let .fill(_, fillScope) in scope.holeArguments {
					scopesToWalk.append((
						scope: fillScope,
						usesMockMethod: false,
						referenceLocation: referenceLocation,
						seamCandidateOnPaths: SeamCandidateOnPaths.agreed(nil).extended(to: fillScope.instantiable, childIsCandidate: isSeamCandidate(fillScope.instantiable), candidatesModuleReads: candidatesModuleReads),
						inlineSeamOnPath: inlineSeamOnPath ?? inlineSeam(builtBy: fillScope, referencedAt: referenceLocation),
						publicMockCandidate: nil,
					))
				}
			}
		}
		return Array(constructionsByKey.values)
	}
}

extension DependencyTreeGenerator {
	/// The declarations among which the declaration of a type an extension extends bounds the types declared in or by
	/// that extension: the `@Instantiable` declarations the module reads, and the plain type declarations of each
	/// module that declares them.
	struct ExtendedTypeDeclarations: Sendable {
		/// - Parameters:
		///   - instantiables: Every type the `@Instantiable` declarations the module reads fulfill, mapped to the
		///     declaration that fulfills it.
		///   - plainTypeDeclarations: The plain type declarations of the modules whose declarations the module reads,
		///     each module's in the order of its files and, within a file, in source order.
		init(instantiables: [TypeDescription: Instantiable], plainTypeDeclarations: [PlainTypeDeclaration]) {
			self.instantiables = instantiables
			var plainTypeDeclarationsByModuleAndType = [ModuleAndType: [PlainTypeDeclaration]]()
			for plainTypeDeclaration in plainTypeDeclarations {
				// A declaration whose module SafeDITool does not know bounds no extension's types, as an `@Instantiable`
				// declaration of the extended type does not.
				guard let moduleName = plainTypeDeclaration.moduleName else { continue }
				plainTypeDeclarationsByModuleAndType[ModuleAndType(moduleName: moduleName, type: plainTypeDeclaration.typeDescription), default: []].append(plainTypeDeclaration)
			}
			self.plainTypeDeclarationsByModuleAndType = plainTypeDeclarationsByModuleAndType
		}

		let instantiables: [TypeDescription: Instantiable]

		/// The declarations whose access bounds the types an extension of `extendedType` in the module named `moduleName`,
		/// in the file at `sourceFilePath`, declares, outermost first: those of `extendedType`'s declaration in that module
		/// and the type declarations enclosing it in its file – its `@Instantiable` declaration when it has one, and
		/// otherwise its plain declaration (`plainTypeDeclaration(of:inModuleNamed:preferringFileAt:)`) – and, when that
		/// declaration is itself inside an extension, the declarations that bound the types that extension declares, found
		/// the same way from the declaration's file, and so on. A type the module does not declare ends the walk, and the
		/// compiler checks it: an extension of a type another module declares narrower than the extension's module can see
		/// cannot be written, and a declaration of the type's name in another module could be a namesake of the extended
		/// type, the narrowest of which would then fail a construction that compiles. Each type the walk follows is the one
		/// before it without at least its last name, so the walk ends.
		func accessNeeds(boundingTypesAnExtensionOf extendedType: TypeDescription, declaresInModuleNamed moduleName: String, fromFileAt sourceFilePath: String?) -> [AccessNeed] {
			var accessNeeds = [AccessNeed]()
			var link: (type: TypeDescription, sourceFilePath: String?)? = (extendedType, sourceFilePath)
			while case let (type, sourceFilePath)? = link {
				if let extended = instantiables[type], extended.concreteInstantiable == type, !extended.declarationType.isExtension {
					// An `@Instantiable` extended type of another module ends the walk too.
					guard extended.moduleName == moduleName else { break }
					accessNeeds = extended.accessNeeds(constructingWithMockMethod: false).filter { $0.declaration.declaredType != nil } + accessNeeds
					link = extended.extendedType.map { ($0, extended.sourceFilePath) }
				} else if let declaration = plainTypeDeclaration(of: type, inModuleNamed: moduleName, preferringFileAt: sourceFilePath) {
					accessNeeds = declaration.accessNeeds + accessNeeds
					link = declaration.extendedType.map { ($0, declaration.sourceFilePath) }
				} else {
					link = nil
				}
			}
			return accessNeeds
		}

		/// The plain declaration of `type` in the module named `moduleName`: among those in the file at `sourceFilePath`
		/// when that file declares one, as a `private` type of one file can share its name with a type of another,
		/// and otherwise among those visible outside their file (`PlainTypeDeclaration.isVisibleOutsideItsFile`): a
		/// `private` type of another file cannot be what the extension extends, while an imported type of its name can.
		/// Of several, which clauses of a platform-conditioned block declare, the narrowest, which every clause the
		/// compiler may select must allow, and of equally narrow ones the first, in the order of the module's files and
		/// within a file in source order. `nil` when there is none, which leaves the extended type to the compiler, as an
		/// unrecorded one is.
		func plainTypeDeclaration(of type: TypeDescription, inModuleNamed moduleName: String, preferringFileAt sourceFilePath: String?) -> PlainTypeDeclaration? {
			let candidates = plainTypeDeclarationsByModuleAndType[ModuleAndType(moduleName: moduleName, type: type)] ?? []
			// Two declarations whose files are unknown are not known to share one.
			let inPreferredFile = candidates.filter { sourceFilePath != nil && $0.sourceFilePath == sourceFilePath }
			return (inPreferredFile.isEmpty ? candidates.filter(\.isVisibleOutsideItsFile) : inPreferredFile)
				.enumerated()
				.min { lhs, rhs in
					(AccessLevel.normalized(lhs.element.levelBeforeExtendedTypeCap), lhs.offset) < (AccessLevel.normalized(rhs.element.levelBeforeExtendedTypeCap), rhs.offset)
				}?
				.element
		}

		/// A module and a type, by the key a plain declaration of the type is recorded under
		/// (`TypeDescription.plainDeclarationKey`).
		struct ModuleAndType: Hashable {
			init(moduleName: String, type: TypeDescription) {
				self.moduleName = moduleName
				typeKey = type.plainDeclarationKey
			}

			let moduleName: String
			let typeKey: String
		}

		private let plainTypeDeclarationsByModuleAndType: [ModuleAndType: [PlainTypeDeclaration]]
	}
}

extension DependencyTreeGenerator.EmittingModule {
	/// The module that declares `accessNeed`, a declaration that constructing `instantiable` relies on: the module
	/// that declares the type's hand-written mock method for that method, or the extension it takes its level from,
	/// and the module that declares the type otherwise.
	func declaringModule(of accessNeed: AccessNeed, constructing instantiable: Instantiable) -> ModuleIdentity {
		if accessNeed.isDeclaredWithMockMethod {
			ModuleIdentity(moduleName: instantiable.mockDeclarationModuleName, packageName: instantiable.mockDeclarationPackageName)
		} else {
			ModuleIdentity(moduleName: instantiable.moduleName, packageName: instantiable.packageName)
		}
	}

	/// The access `accessNeed`, a declaration that constructing `instantiable` relies on, needs for this module's
	/// generated code to construct `instantiable`.
	func requirement(of accessNeed: AccessNeed, constructing instantiable: Instantiable) -> AccessRequirement {
		let declarationFilePath = accessNeed.isDeclaredWithMockMethod ? instantiable.mockDeclarationLocation?.filePath : instantiable.sourceFilePath
		return AccessLevel.required(
			toConstructFrom: identity,
			declaredIn: declaringModule(of: accessNeed, constructing: instantiable),
			isOwnFile: declarationFilePath.map(isOwnFile) ?? false,
		)
	}
}
