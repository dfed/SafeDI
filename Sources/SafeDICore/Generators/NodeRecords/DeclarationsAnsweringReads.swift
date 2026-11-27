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
/// - Which renames are fulfilled by a wrapper's instance, which the tree binds them from (`ScopeGenerator`'s `aliasCode`),
///   and so their records too; a rename that reads a wrapper's instance through an optional wrapper, beneath a fill,
///   keeps its world's tree (`NodeRecordRefusal.lazy`).
///
/// The nearest node above that declares a label answers a read of it, and a read that is handed that declaration (a
/// required receive's `value`, and a receive only if available's `optionalValue`, which its record passes `nil` for
/// where `OnlyIfAvailableAnswers` finds it unavailable) is of a wrapper's instance where that node's scope declares the
/// instance (`ConstructionScope.declaredLazilyInstantiatedInstanceProperties`). A read no node of the tree answers is
/// answered by what the root is handed: a seam's own root, by its parameters, of which a deferred one is held in a
/// `LazilyInstantiated` under its label and a wrapper offers its instance (`rootLazilyInstantiatedInstanceProperties`),
/// as the tree's root reads them (`DependencyTreeGenerator.seamRootDeclarations(of:seamRoot:)`); any other root is
/// handed nothing. Each variant is resolved once, from the first call a walk from the root meets, and every other call
/// into it is judged against that call (`callsAnswerAVariantApart`): a world in which one answers a read in another form
/// is refused, so that which call resolves a variant never changes what is accepted. For a `value` read the calls share
/// the variant's key, which holds the forms its declaration provides, which tell a wrapper's declaration from a value's,
/// and one wrapper kind from another: a node built beneath a wrapper on one path and a value on another has two
/// variants, which `NodeRecords` refuses (`NodeRecordRefusal.nodeHasSeveralVariants`). An `optionalValue` read keys
/// alike whatever answers it (rule 1), and `OnlyIfAvailableAnswers`, made before this, refuses a world in which two calls
/// of one variant see different declarations of a label some receive only if available reads.
///
/// An edge that opens a `@Sendable` function (`TypeFactsEdge.opens`) builds its child inside that function, so every
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
/// handed none, and that opens no `@Sendable` function. The declaration that answers each read, one ID per key of every variant, lives only while the
/// sets are made.
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
		var lazilyInstantiatedInstancePropertiesByVariant = [Set<Property>](repeating: [], count: world.variantCount)
		// The root's own body reads what it is handed.
		lazilyInstantiatedInstancePropertiesByVariant[0] = rootLazilyInstantiatedInstanceProperties
		var sendableFunctionCapturesWrapper = false
		var renameReadsWrappersInstance = false
		var renamesReadingWrappersInstance = Set<VariantID>()
		var callsAnswerAVariantApart = false
		// A world that declares no lazily instantiated property, whose root is handed none, and that opens no `@Sendable`
		// function reads no wrapper's instance and captures nothing, so only its calls are compared.
		let readsInstancesOrCaptures = !rootLazilyInstantiatedInstanceProperties.isEmpty || (0..<Int32(world.declarationCount)).contains(where: { declaration in
			!world.scope(of: declaration).declaredLazilyInstantiatedInstanceProperties.isEmpty
				|| world.edgeFacts(from: declaration).contains { Self.opensSendableFunction($0) }
		})
		// For each variant reached, the declaration that answers each of its reads, -1 where none does, and whether the
		// call that resolved it opens a `@Sendable` function. No node is above the root, so what the root is handed answers
		// what its tree reads.
		var answeringDeclarations = [[DeclarationID]?](repeating: nil, count: world.variantCount)
		var resolvedInSendableFunction = [Bool](repeating: false, count: world.variantCount)
		// For each rename reached, the form of the answer to its fulfilling label at the call that resolved it. A rename reads
		// that label through its caller, which no read of its own lists, so its calls are compared here.
		var renameAnswers = [VariantID: AnswerForm?]()
		answeringDeclarations[0] = [DeclarationID](repeating: -1, count: world.reads(of: world.declaration(of: 0)).count)
		// Each variant's caller, the call that resolved it, -1 for the root.
		var callerByVariant = [VariantID](repeating: -1, count: world.variantCount)
		// A stack, since a tree can be as deep as the module has types.
		var stack: [VariantID] = [0]
		while let caller = stack.popLast() {
			let callerAnsweringDeclarations = answeringDeclarations[Int(caller)] ?? []
			let callerScope = world.scope(of: world.declaration(of: caller))
			let edgeFacts = world.edgeFacts(from: world.declaration(of: caller))
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() {
				let opensSendableFunction = Self.opensSendableFunction(edgeFacts[edgeFacts.startIndex + edgeIndex])
				let calleeReads = world.reads(of: world.declaration(of: callee))
				var calleeAnsweringDeclarations = [DeclarationID]()
				calleeAnsweringDeclarations.reserveCapacity(calleeReads.count)
				for source in world.sources(ofCall: edgeIndex, of: caller) {
					let answeringDeclaration: DeclarationID = switch source.kind {
					case .none:
						-1
					case .bound:
						source.payload
					case .passedThrough:
						callerAnsweringDeclarations[Int(source.payload)]
					}
					calleeAnsweringDeclarations.append(answeringDeclaration)
				}
				// A rename is a leaf of the scope that declares it, which reads its fulfilling property for it: a wrapper's
				// instance where the scope declares the wrapper itself, or reads the label as one from above. Matched by
				// label, and refined below by the tree's rule. Every call of a rename is read, so that what is reported does
				// not depend on which call resolves it.
				if let rename = Self.rename(world.declaration(of: callee), in: world) {
					if callerScope.declaredLazilyInstantiatedInstanceProperties.contains(where: { $0.label == rename.fulfillingProperty.label })
						|| lazilyInstantiatedInstancePropertiesByVariant[Int(caller)].contains(where: { $0.label == rename.fulfillingProperty.label })
					{
						// The tree's rule (`Scope.createScopeGenerator`'s rename): a rename that keeps its fulfilling property's
						// label reads what is in scope above its scope, and any other reads its scope's declarations first.
						let inheritedProperties = lazilyInstantiatedInstancePropertiesByVariant[Int(caller)]
						let instanceProperties = rename.fulfillingProperty.label == rename.property.label
							? inheritedProperties
							: inheritedProperties.filter { !callerScope.declaredLabels.contains($0.label) }.union(callerScope.declaredLazilyInstantiatedInstanceProperties)
						if instanceProperties.contains(rename.fulfillingProperty.asUnwrappedProperty) {
							renamesReadingWrappersInstance.insert(callee)
						} else {
							// Any other form, the wrapper itself or its optional among them, is bound from its label, as the tree
							// binds it, but for an instance read through an optional wrapper (beneath a fill that takes the
							// wrapper optionally), which the tree reads with `?.instance`.
							renameReadsWrappersInstance = renameReadsWrappersInstance
								|| instanceProperties.contains(rename.fulfillingProperty.asUnwrappedProperty.asOptionalProperty)
						}
					}
					let answer = Self.answerForm(ofLabel: rename.fulfillingProperty.label, readBy: caller, answeredBy: callerAnsweringDeclarations, in: world)
					if let resolvedAnswer = renameAnswers[callee] {
						callsAnswerAVariantApart = callsAnswerAVariantApart || resolvedAnswer != answer
					} else {
						renameAnswers[callee] = answer
					}
				}
				// A variant's record is written from the call that resolved it, so every other call into it must answer each
				// of its reads as that call did; any that does not refuses the world, whatever order the calls come in. A read
				// only if available that one call answers and another does not is the exception: the variant takes it as one
				// optional parameter (`OnlyIfAvailableAnswers`), so it is resolved as the call that answers it does, and read
				// again, with everything it calls.
				var calleeAnswers = calleeAnsweringDeclarations
				if let resolved = answeringDeclarations[Int(callee)] {
					guard !callsAnswerAVariantApart else { continue }
					guard let mergedAnswers = Self.answers(
						merging: resolved,
						inSendableFunction: resolvedInSendableFunction[Int(callee)],
						with: calleeAnsweringDeclarations,
						inSendableFunction: opensSendableFunction,
						reads: calleeReads,
						in: world,
					) else {
						callsAnswerAVariantApart = true
						continue
					}
					guard mergedAnswers != resolved else { continue }
					calleeAnswers = mergedAnswers
				} else {
					resolvedInSendableFunction[Int(callee)] = opensSendableFunction
					callerByVariant[Int(callee)] = caller
				}
				answeringDeclarations[Int(callee)] = calleeAnswers
				stack.append(callee)
				guard readsInstancesOrCaptures else { continue }
				for (answeringDeclaration, readID) in zip(calleeAnswers, calleeReads) {
					let read = world.read(readID)
					guard read.channel.asksAboutLabel else { continue }
					// The scope of the node that answers the read; `nil` where what the root is handed answers it.
					let scope = answeringDeclaration >= 0 ? world.scope(of: answeringDeclaration) : nil
					let instanceProperties = if Self.isHandedNearestDeclaration(read.channel) {
						scope?.declaredLazilyInstantiatedInstanceProperties ?? rootLazilyInstantiatedInstanceProperties
					} else {
						Set<Property>()
					}
					guard opensSendableFunction || !instanceProperties.isEmpty else { continue }
					let label = world.text(ofLabel: read.label)
					for property in instanceProperties where property.label == label {
						lazilyInstantiatedInstancePropertiesByVariant[Int(callee)].insert(property)
					}
					guard opensSendableFunction else { continue }
					let readsNonSendableWrapper = if let scope {
						scope.sortedDeclaredPropertyForms.contains { declared in
							declared.property.label == label && !declared.property.propertyType.isConstant && !declared.property.propertyType.isSendable
						}
					} else {
						rootNonSendableWrapperLabels.contains(label)
					}
					if readsNonSendableWrapper, !Self.isPassedNil(read.channel, of: label, answeredBy: answeringDeclaration, aboveCallOf: callee, by: caller, callerByVariant: callerByVariant, in: world) {
						sendableFunctionCapturesWrapper = true
					}
				}
			}
		}
		self.lazilyInstantiatedInstancePropertiesByVariant = readsInstancesOrCaptures ? lazilyInstantiatedInstancePropertiesByVariant : []
		self.sendableFunctionCapturesWrapper = sendableFunctionCapturesWrapper
		self.renameReadsWrappersInstance = renameReadsWrappersInstance
		self.renamesReadingWrappersInstance = renamesReadingWrappersInstance
		self.callsAnswerAVariantApart = callsAnswerAVariantApart
	}

	/// The by-value properties `variant`'s body reads as a wrapper's instance, of the labels its tree reads from above.
	func lazilyInstantiatedInstanceProperties(readBy variant: VariantID) -> Set<Property> {
		lazilyInstantiatedInstancePropertiesByVariant.isEmpty ? [] : lazilyInstantiatedInstancePropertiesByVariant[Int(variant)]
	}

	/// Whether a `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`.
	let sendableFunctionCapturesWrapper: Bool

	/// Whether a rename of the world reads its fulfilling property's label where a wrapper's instance answers it otherwise
	/// than the tree's rule reads the instance.
	let renameReadsWrappersInstance: Bool

	/// The variants of renames that the tree binds from the instance of a wrapper, which their records read too.
	let renamesReadingWrappersInstance: Set<VariantID>

	/// Whether two calls of one variant answer one of its reads apart: one finds a declaration and the other none, or the
	/// two declarations differ in what the variant's record assumes of the answer (`AnswerForm`). The variant's key was too
	/// coarse to tell them apart, so its one record would be wrong at one of the calls.
	let callsAnswerAVariantApart: Bool

	/// By variant; empty in a world that declares no lazily instantiated property, whose root is handed none, and that
	/// opens no `@Sendable` function.
	private let lazilyInstantiatedInstancePropertiesByVariant: [Set<Property>]

	/// Whether every read of `label` through `channel` that `callee`'s tree makes is passed `nil` where `answeringDeclaration`,
	/// the scope that declares the label, answers it: a read only if available (`optional`, `optionalValue`) of the
	/// declaration still being built around the call, the node of the label that `answeringDeclaration` builds on the path
	/// to `callee`, which captures nothing (`NearestDeclarations.resolvingBinding(of:)`). A required read of the label reads
	/// `value` beside it, which is judged on its own.
	private static func isPassedNil(
		_ channel: ReadChannel,
		of label: String,
		answeredBy answeringDeclaration: DeclarationID,
		aboveCallOf callee: VariantID,
		by caller: VariantID,
		callerByVariant: [VariantID],
		in world: some NodeRecordSources,
	) -> Bool {
		switch channel {
		case .optional, .optionalValue:
			var child = callee
			var parent = caller
			while parent >= 0, world.declaration(of: parent) != answeringDeclaration {
				child = parent
				parent = callerByVariant[Int(parent)]
			}
			return parent >= 0 && world.property(of: world.declaration(of: child))?.label == label
		case .value, .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
			return false
		}
	}

	/// What a variant's record assumes of the answer to one of its reads: the property the answering declaration declares
	/// under the read's label (its form, optional or not, erased or not), whether the read is handed that declaration's
	/// instance of a wrapper, whether the answering node itself is erased, and whether the read is made across a
	/// `@Sendable` function, which captures the answer rather than being passed it.
	private struct AnswerForm: Equatable {
		let declaredProperty: Property?
		let readsInstance: Bool
		let isErased: Bool
		let isCaptured: Bool
	}

	/// The declarations that answer `reads`, a variant's, where one call answers them with `answers` and another with
	/// `otherAnswers`; `nil` where the two do not give each read the same `AnswerForm`. A call that answers a read with
	/// the declaration the other does differs at most in whether it captures it. A read only if available that one of the
	/// calls answers with nothing takes the other's answer.
	private static func answers(
		merging answers: [DeclarationID],
		inSendableFunction isCaptured: Bool,
		with otherAnswers: [DeclarationID],
		inSendableFunction otherIsCaptured: Bool,
		reads: some Collection<ReadID>,
		in world: some NodeRecordSources,
	) -> [DeclarationID]? {
		var mergedAnswers = answers
		for (index, readID) in reads.enumerated() {
			let answer = answers[index]
			let otherAnswer = otherAnswers[index]
			guard answer != otherAnswer || (answer >= 0 && isCaptured != otherIsCaptured) else { continue }
			let read = world.read(readID)
			guard answer >= 0, otherAnswer >= 0 else {
				// A read only if available, which a call may answer with nothing; a read of any other channel that only one
				// call answers keeps the two apart, as before.
				guard read.channel == .optional || read.channel == .optionalValue, isCaptured == otherIsCaptured else { return nil }
				mergedAnswers[index] = max(answer, otherAnswer)
				continue
			}
			guard read.channel.asksAboutLabel else { continue }
			let label = world.text(ofLabel: read.label)
			if answerForm(of: answer, label: label, channel: read.channel, isCaptured: isCaptured, in: world)
				!= answerForm(of: otherAnswer, label: label, channel: read.channel, isCaptured: otherIsCaptured, in: world)
			{
				return nil
			}
		}
		return mergedAnswers
	}

	/// The form of the answer to `label` that `caller` hands a rename it declares: its own declaration of the label, or the
	/// declaration that answers its read of the label (`callerAnsweringDeclarations`); `nil` where neither does.
	private static func answerForm(ofLabel label: String, readBy caller: VariantID, answeredBy callerAnsweringDeclarations: [DeclarationID], in world: some NodeRecordSources) -> AnswerForm? {
		let callerDeclaration = world.declaration(of: caller)
		guard !world.scope(of: callerDeclaration).sortedDeclaredPropertyForms.contains(where: { $0.property.label == label }) else {
			return answerForm(of: callerDeclaration, label: label, channel: .value, isCaptured: false, in: world)
		}
		let answeringReads = zip(callerAnsweringDeclarations, world.reads(of: callerDeclaration)).lazy.map { (answeringDeclaration: $0, read: world.read($1)) }
		return answeringReads.first(where: { answeringDeclaration, read in
			answeringDeclaration >= 0 && isHandedNearestDeclaration(read.channel) && world.text(ofLabel: read.label) == label
		}).map { answerForm(of: $0.answeringDeclaration, label: label, channel: $0.read.channel, isCaptured: false, in: world) }
	}

	private static func answerForm(of declaration: DeclarationID, label: String, channel: ReadChannel, isCaptured: Bool, in world: some NodeRecordSources) -> AnswerForm {
		let scope = world.scope(of: declaration)
		return AnswerForm(
			declaredProperty: scope.sortedDeclaredPropertyForms.first(where: { $0.property.label == label })?.property,
			readsInstance: isHandedNearestDeclaration(channel) && scope.declaredLazilyInstantiatedInstanceProperties.contains(where: { $0.label == label }),
			isErased: world.isErased(declaration),
			isCaptured: isCaptured,
		)
	}

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

	private static func opensSendableFunction(_ edge: TypeFactsEdge) -> Bool {
		switch edge.opens {
		case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
			true
		case .none, .instantiatorBuilder:
			false
		}
	}
}
