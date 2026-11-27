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

/// What the declarations above each variant answer its tree's reads with, of the three answers a record or a refusal
/// reads, made from what each call hands its callee (`TypeFactsWorld.sources(ofCall:of:)`) with no walk of a place:
///
/// - The by-value properties each variant's body reads as the instance of a `LazilyInstantiated` or a
///   `SendableLazilyInstantiated` declared above it: what the tree hands each place as its
///   `lazilyInstantiatedInstanceProperties` (`Scope.createScopeGenerator`).
/// - Whether a `@Sendable` function reads a wrapper that is not `Sendable`, declared outside it, which the tree reports
///   as an error (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`): such a world keeps its tree
///   (`NodeRecordRefusal.sendableFunctionCapturesWrapper`).
/// - Which renames are fulfilled by a wrapper's instance, which the tree binds them from (`ScopeGenerator`'s `aliasCode`)
///   and their records too (`NodeRecords.renameRecord`): the instance the tree hands the rename holds its fulfilling
///   property (`Scope.addAliasGenerator`), the nearest declaration above for a rename that keeps its label, which is not
///   in scope where its own value is read, and otherwise the scope's own declaration of the label, else the nearest above.
///
/// The nearest node above that declares a label answers a read of it, and a read that is handed that declaration (a
/// required receive's `value`, and a receive only if available's `optionalValue`, which its record passes `nil` for
/// where `OnlyIfAvailableAnswers` finds it unavailable) is of a wrapper's instance where that node's scope declares the
/// instance (`ConstructionScope.declaredLazilyInstantiatedInstanceProperties`). A read no node of the tree answers is
/// answered by what the root is handed: a seam's own root, by its parameters, of which a deferred one is held in a
/// `LazilyInstantiated` under its label and a wrapper offers its instance (`rootLazilyInstantiatedInstanceProperties`),
/// as the tree's root reads them (`DependencyTreeGenerator.seamRootDeclarations(of:seamRoot:)`); any other root is
/// handed nothing. Each variant is resolved once, from the
/// first call a walk from the root meets, and every other call into it answers alike. For a `value` read the calls share
/// the variant's key, which holds the forms its declaration provides, which tell a wrapper's declaration from a value's,
/// and one wrapper kind from another: a node built beneath a wrapper on one path and a value on another has two
/// variants, which `NodeRecords` refuses (`NodeRecordRefusal.nodeHasSeveralVariants`). An `optionalValue` read keys
/// alike whatever answers it (rule 1), and `OnlyIfAvailableAnswers`, made before this, refuses a world in which two calls
/// of one variant see different declarations of a label some receive only if available reads.
///
/// An edge that opens a `@Sendable` function (`TypeFactsEdge.opens`) builds its child inside that function, and a call of
/// a seam's tier hands each parameter the seam defers `@Sendable` to a `@Sendable` autoclosure, which reads it there. So
/// every read of a parameter the call defers `@Sendable`, and every
/// read of the child's tree that a declaration above the child answers is made from outside the function: a capture
/// where that declaration is an `Instantiator`, an `ErasedInstantiator` or a `LazilyInstantiated`, read as itself or as
/// its instance, a parameter of a seam's own root included (`rootNonSendableWrapperLabels`), which its generated
/// initializer declares outside every function. A read a declaration inside the function answers is none of the call's
/// sources. A read of any channel
/// counts, so a stage that admits a receive passed `nil`, which captures nothing, keeps the tree of more worlds than the
/// tree reports until it reads that answer here.
///
/// Memory: a set per variant, each empty unless the variant's tree reads a wrapper's instance, for as long as
/// `NodeRecords.init` makes the records; none in a world that declares no lazily instantiated property, whose root is
/// handed none, that opens no `@Sendable` function, and that calls no seam that defers a parameter `@Sendable`. The
/// declaration that answers each read, one ID per key of every variant, lives only while the sets are made.
///
/// A bridge: a private copy of two of the tree's rules about the answer a read finds, which the facts' answers do not
/// carry: whether it is a wrapper's instance, and whether a `@Sendable` function captures it. It goes in the change that
/// has each answer of the facts carry the form it is read as and whether it is read across a `@Sendable` function,
/// which records then read instead.
struct DeclarationsAnsweringReads: Sendable {
	/// - Parameters:
	///   - world: A production root's world.
	///   - rootLazilyInstantiatedInstanceProperties: The by-value properties the root is handed through a wrapper, which
	///     its tree reads as the wrapper's instance. Empty unless the root is a seam's own.
	///   - rootNonSendableWrapperLabels: The labels of what the root is handed in an `Instantiator`, an
	///     `ErasedInstantiator` or a `LazilyInstantiated`. Empty unless the root is a seam's own.
	init(world: some NodeRecordSources, rootLazilyInstantiatedInstanceProperties: Set<Property> = [], rootNonSendableWrapperLabels: Set<String> = []) {
		let declarations = 0..<Int32(world.declarationCount)
		guard !rootLazilyInstantiatedInstanceProperties.isEmpty || declarations.contains(where: { declaration in
			!world.scope(of: declaration).declaredLazilyInstantiatedInstanceProperties.isEmpty
				|| world.edgeFacts(from: declaration).contains { Self.opensSendableFunction($0) }
				|| !Self.labelsDeferredSendable(by: world.scope(of: declaration)).isEmpty
		}) else {
			self.lazilyInstantiatedInstancePropertiesByVariant = []
			self.sendableFunctionCapturesWrapper = false
			self.renamesReadingWrappersInstance = []
			self.renamesReadDifferentInstances = false
			return
		}
		var lazilyInstantiatedInstancePropertiesByVariant = [Set<Property>](repeating: [], count: world.variantCount)
		// The root's own body reads what it is handed.
		lazilyInstantiatedInstancePropertiesByVariant[0] = rootLazilyInstantiatedInstanceProperties
		var sendableFunctionCapturesWrapper = false
		var renamesReadingWrappersInstance = Set<VariantID>()
		var renamesReadDifferentInstances = false
		// The labels the world's renames are fulfilled by.
		let renamedLabels = Set(declarations.compactMap { Self.rename($0, in: world)?.fulfillingProperty.label })
		// For each variant reached, the declaration that answers each of its reads, -1 where none does. No node is above
		// the root, so what the root is handed answers what its tree reads.
		var answeringDeclarations = [[DeclarationID]?](repeating: nil, count: world.variantCount)
		answeringDeclarations[0] = [DeclarationID](repeating: -1, count: world.reads(of: world.declaration(of: 0)).count)
		// A stack, since a tree can be as deep as the module has types.
		var stack: [VariantID] = [0]
		while let caller = stack.popLast() {
			let callerAnsweringDeclarations = answeringDeclarations[Int(caller)] ?? []
			let callerScope = world.scope(of: world.declaration(of: caller))
			let edgeFacts = world.edgeFacts(from: world.declaration(of: caller))
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() {
				// Calls into one variant can answer a read that keys no variant (a rename's, or one only if available)
				// differently: where one call hands a label a rename is fulfilled by as a wrapper's instance and another does
				// not, the tree binds the rename two ways, and one record cannot.
				if let calleeAnsweringDeclarations = answeringDeclarations[Int(callee)] {
					if !renamesReadDifferentInstances, Self.handsRenamesDifferentInstances(
						calleeAnsweringDeclarations,
						and: world.sources(ofCall: edgeIndex, of: caller).map { source in
							Self.answeringDeclaration(of: source, among: callerAnsweringDeclarations)
						},
						readBy: callee,
						renamedLabels: renamedLabels,
						rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties,
						in: world,
					) {
						renamesReadDifferentInstances = true
					}
					continue
				}
				// A rename is a leaf of the scope that declares it, which reads its fulfilling property for it.
				if let rename = Self.rename(world.declaration(of: callee), in: world),
				   Self.readsWrappersInstance(
				   	rename,
				   	declaredBy: callerScope,
				   	answeredAbove: Self.declaration(answering: rename.fulfillingProperty.label, readBy: caller, among: callerAnsweringDeclarations, in: world),
				   	rootLazilyInstantiatedInstanceProperties: rootLazilyInstantiatedInstanceProperties,
				   	in: world,
				   )
				{
					renamesReadingWrappersInstance.insert(callee)
				}
				let opensSendableFunction = Self.opensSendableFunction(edgeFacts[edgeFacts.startIndex + edgeIndex])
				// A call of a seam's tier hands each parameter the seam defers `@Sendable` to a `@Sendable` autoclosure, which
				// captures what it reads (`NonSendableWrapperCapture.capturingSeamType`).
				let labelsDeferredSendable = Self.labelsDeferredSendable(by: world.scope(of: world.declaration(of: callee)))
				var calleeAnsweringDeclarations = [DeclarationID]()
				for (source, readID) in zip(world.sources(ofCall: edgeIndex, of: caller), world.reads(of: world.declaration(of: callee))) {
					let answeringDeclaration = Self.answeringDeclaration(of: source, among: callerAnsweringDeclarations)
					calleeAnsweringDeclarations.append(answeringDeclaration)
					let read = world.read(readID)
					guard read.channel.asksAboutLabel else { continue }
					// The scope of the node that answers the read; `nil` where what the root is handed answers it.
					let scope = answeringDeclaration >= 0 ? world.scope(of: answeringDeclaration) : nil
					let instanceProperties = if Self.isHandedNearestDeclaration(read.channel) {
						scope?.declaredLazilyInstantiatedInstanceProperties ?? rootLazilyInstantiatedInstanceProperties
					} else {
						Set<Property>()
					}
					guard opensSendableFunction || !instanceProperties.isEmpty || !labelsDeferredSendable.isEmpty else { continue }
					let label = world.text(ofLabel: read.label)
					for property in instanceProperties where property.label == label {
						lazilyInstantiatedInstancePropertiesByVariant[Int(callee)].insert(property)
					}
					guard opensSendableFunction || labelsDeferredSendable.contains(label) else { continue }
					let readsNonSendableWrapper = if let scope {
						scope.sortedDeclaredPropertyForms.contains { declared in
							declared.property.label == label && !declared.property.propertyType.isConstant && !declared.property.propertyType.isSendable
						}
					} else {
						rootNonSendableWrapperLabels.contains(label)
					}
					if readsNonSendableWrapper {
						sendableFunctionCapturesWrapper = true
					}
				}
				answeringDeclarations[Int(callee)] = calleeAnsweringDeclarations
				stack.append(callee)
			}
		}
		self.lazilyInstantiatedInstancePropertiesByVariant = lazilyInstantiatedInstancePropertiesByVariant
		self.sendableFunctionCapturesWrapper = sendableFunctionCapturesWrapper
		self.renamesReadingWrappersInstance = renamesReadingWrappersInstance
		self.renamesReadDifferentInstances = renamesReadDifferentInstances
	}

	/// The by-value properties `variant`'s body reads as a wrapper's instance, of the labels its tree reads from above.
	func lazilyInstantiatedInstanceProperties(readBy variant: VariantID) -> Set<Property> {
		lazilyInstantiatedInstancePropertiesByVariant.isEmpty ? [] : lazilyInstantiatedInstancePropertiesByVariant[Int(variant)]
	}

	/// Whether a `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`.
	let sendableFunctionCapturesWrapper: Bool

	/// Whether `variant`, a rename, is fulfilled by a property its scope reads as a wrapper's instance, which its record binds
	/// it from.
	func renameReadsWrappersInstance(_ variant: VariantID) -> Bool {
		renamesReadingWrappersInstance.contains(variant)
	}

	/// Whether two calls into one variant hand a rename beneath it its label differently: one as a wrapper's instance, the
	/// other not.
	let renamesReadDifferentInstances: Bool

	/// The renames fulfilled by a wrapper's instance; empty in a world that declares no lazily instantiated property, whose
	/// root is handed none, that opens no `@Sendable` function, and that calls no seam that defers a parameter `@Sendable`.
	private let renamesReadingWrappersInstance: Set<VariantID>

	/// By variant; empty in a world that declares no lazily instantiated property, whose root is handed none, that
	/// opens no `@Sendable` function, and that calls no seam that defers a parameter `@Sendable`.
	private let lazilyInstantiatedInstancePropertiesByVariant: [Set<Property>]

	/// Whether a read of `channel` is handed the nearest declaration of its label, in the form that declaration has: a
	/// required receive, and a receive only if available where it is handed a value.
	private static func isHandedNearestDeclaration(_ channel: ReadChannel) -> Bool {
		switch channel {
		case .value, .optionalValue:
			true
		case .optional, .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
			false
		}
	}

	/// The property `declaration`, a rename, declares and the property it is fulfilled by; `nil` for any other declaration.
	private static func rename(_ declaration: DeclarationID, in world: some NodeRecordSources) -> (property: Property, fulfillingProperty: Property)? {
		guard world.kind(of: declaration) == .alias, let property = world.property(of: declaration) else { return nil }
		return world.scope(of: declaration).instantiable.dependencies.lazy.compactMap { dependency in
			if dependency.property == property, case let .aliased(fulfillingProperty, _, _) = dependency.source {
				(property, fulfillingProperty)
			} else {
				nil
			}
		}.first
	}

	/// The declaration that answers a read the call hands from `source`, of the caller's answers `answers`; -1 where no node
	/// does, and what the root is handed answers it.
	private static func answeringDeclaration(of source: AnswerSource, among answers: [DeclarationID]) -> DeclarationID {
		switch source.kind {
		case .none:
			-1
		case .bound:
			source.payload
		case .passedThrough:
			answers[Int(source.payload)]
		}
	}

	/// Whether `answers` and `otherAnswers`, two calls' answers to `variant`'s reads, differ in whether a read of one of
	/// `renamedLabels` is answered by a declaration of a wrapper's instance of its label.
	private static func handsRenamesDifferentInstances(
		_ answers: [DeclarationID],
		and otherAnswers: [DeclarationID],
		readBy variant: VariantID,
		renamedLabels: Set<String>,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
		in world: some NodeRecordSources,
	) -> Bool {
		func declaresInstance(_ declaration: DeclarationID, of label: String) -> Bool {
			let instanceProperties = declaration >= 0 ? world.scope(of: declaration).declaredLazilyInstantiatedInstanceProperties : rootLazilyInstantiatedInstanceProperties
			return instanceProperties.contains { $0.label == label }
		}
		for (index, readID) in world.reads(of: world.declaration(of: variant)).enumerated() where index < answers.count && index < otherAnswers.count && answers[index] != otherAnswers[index] {
			let read = world.read(readID)
			let label = world.text(ofLabel: read.label)
			guard read.channel.asksAboutLabel, renamedLabels.contains(label) else { continue }
			if declaresInstance(answers[index], of: label) != declaresInstance(otherAnswers[index], of: label) {
				return true
			}
		}
		return false
	}

	/// The declaration that answers `variant`'s read of `label` from above: a declaration of the world, or -1 where none
	/// does, and what the root is handed answers it.
	private static func declaration(answering label: String, readBy variant: VariantID, among answers: [DeclarationID], in world: some NodeRecordSources) -> DeclarationID {
		for (index, readID) in world.reads(of: world.declaration(of: variant)).enumerated() where index < answers.count {
			let read = world.read(readID)
			guard read.channel.asksAboutLabel, world.text(ofLabel: read.label) == label else { continue }
			return answers[index]
		}
		return -1
	}

	/// Whether the tree binds `rename`, declared by `scope`, from a wrapper's instance (`Scope.addAliasGenerator`): whether
	/// the instance it is handed holds the fulfilling property, unwrapped. A rename that keeps its label is handed what the
	/// nearest declaration above provides; any other is handed what its scope declares of the label, where it declares it,
	/// and what is above otherwise.
	private static func readsWrappersInstance(
		_ rename: (property: Property, fulfillingProperty: Property),
		declaredBy scope: ConstructionScope,
		answeredAbove answeringDeclaration: DeclarationID,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
		in world: some NodeRecordSources,
	) -> Bool {
		let instance = rename.fulfillingProperty.asUnwrappedProperty
		return if rename.fulfillingProperty.label != rename.property.label, scope.declaredLabels.contains(rename.fulfillingProperty.label) {
			scope.declaredLazilyInstantiatedInstanceProperties.contains(instance)
		} else if answeringDeclaration >= 0 {
			world.scope(of: answeringDeclaration).declaredLazilyInstantiatedInstanceProperties.contains(instance)
		} else {
			rootLazilyInstantiatedInstanceProperties.contains(instance)
		}
	}

	/// The labels of the parameters a call of a seam's tier, `scope`'s construction, hands a `@Sendable` autoclosure: those
	/// the seam defers `@Sendable`. Empty for any other construction.
	private static func labelsDeferredSendable(by scope: ConstructionScope) -> Set<String> {
		guard let seamCall = scope.seamCall else { return [] }
		var labels = Set<String>()
		for parameter in seamCall.parameters where parameter.deferral == .deferred(isSendable: true) {
			labels.insert(parameter.property.label)
		}
		return labels
	}

	private static func opensSendableFunction(_ edge: TypeFactsEdge) -> Bool {
		switch edge.opens {
		case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
			true
		case .none, .instantiatorBuilder:
			false
		}
	}
}
