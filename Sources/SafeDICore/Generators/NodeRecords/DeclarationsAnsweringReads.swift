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
/// instance (`ConstructionScope.declaredLazilyInstantiatedInstanceProperties`). Each variant is resolved once, from the
/// first call a walk from the root meets, and every other call into it answers alike. For a `value` read the calls share
/// the variant's key, which holds the forms its declaration provides, which tell a wrapper's declaration from a value's,
/// and one wrapper kind from another: a node built beneath a wrapper on one path and a value on another has two
/// variants, which `NodeRecords` refuses (`NodeRecordRefusal.nodeHasSeveralVariants`). An `optionalValue` read keys
/// alike whatever answers it (rule 1), and `OnlyIfAvailableAnswers`, made before this, refuses a world in which two calls
/// of one variant see different declarations of a label some receive only if available reads.
///
/// An edge that opens a `@Sendable` function (`TypeFactsEdge.opens`) builds its child inside that function, so every
/// read of the child's tree that a declaration above the child answers is made from outside the function: a capture
/// where that declaration is an `Instantiator`, an `ErasedInstantiator` or a `LazilyInstantiated`, read as itself or as
/// its instance. A read a declaration inside the function answers is none of the call's sources. A read of any channel
/// counts, so a stage that admits a receive passed `nil`, which captures nothing, keeps the tree of more worlds than the
/// tree reports until it reads that answer here.
///
/// A seam's own root is handed what its initializer binds above its tree (`rootInstanceProperties`): the memo of each
/// deferred parameter and the instance of each non-optional wrapper parameter, which the tree reads through those
/// wrappers (`DependencyTreeGenerator.seamRootDeclarations(of:seamRoot:)`). A seam's parameters are reads of the root,
/// which no declaration of the world binds, so the root answers each of its reads of such a label with the memo
/// (`rootMemo`), and a read handed it is of the wrapper's instance, as a read a declared wrapper answers is; a declaration
/// nearer the reader binds the read itself, so it hides the memo, as the nearer `let` does in the tree.
///
/// Memory: a set per variant, each empty unless the variant's tree reads a wrapper's instance, for as long as
/// `NodeRecords.init` makes the records; none in a world that declares no lazily instantiated property and opens no
/// `@Sendable` function. The declaration that answers each read, one ID per key of every variant, lives only while the
/// sets are made.
struct DeclarationsAnsweringReads: Sendable {
	/// - Parameters:
	///   - world: The world whose reads are answered.
	///   - rootInstanceProperties: The by-value properties a seam's own root reads through the wrappers its initializer
	///     binds above its tree (`DependencyTreeGenerator.RootScopeInfo.SeamTree.rootLazilyInstantiatedInstanceProperties`);
	///     empty for any other root.
	init(world: some NodeRecordSources, rootInstanceProperties: Set<Property> = []) {
		let declarations = 0..<Int32(world.declarationCount)
		guard !rootInstanceProperties.isEmpty || declarations.contains(where: { declaration in
			!world.scope(of: declaration).declaredLazilyInstantiatedInstanceProperties.isEmpty
				|| world.edgeFacts(from: declaration).contains { Self.opensSendableFunction($0) }
		}) else {
			self.lazilyInstantiatedInstancePropertiesByVariant = []
			self.sendableFunctionCapturesWrapper = false
			self.renamesReadingWrappersInstance = []
			return
		}
		var lazilyInstantiatedInstancePropertiesByVariant = [Set<Property>](repeating: [], count: world.variantCount)
		// The root's body reads what the seam's initializer binds above it as those wrappers' instances, so a rename the
		// root declares of one is found below as a rename of a wrapper's instance is.
		lazilyInstantiatedInstancePropertiesByVariant[0] = rootInstanceProperties
		var sendableFunctionCapturesWrapper = false
		var renamesReadingWrappersInstance = Set<VariantID>()
		// For each variant reached, the declaration that answers each of its reads, -1 where none does. Nothing is above
		// the root, so nothing answers what its tree reads.
		var answeringDeclarations = [[DeclarationID]?](repeating: nil, count: world.variantCount)
		// What a seam's initializer binds above its tree answers the root's reads of its labels.
		let rootMemoLabels = Set(rootInstanceProperties.map(\.label))
		answeringDeclarations[0] = world.reads(of: world.declaration(of: 0)).map { readID in
			let read = world.read(readID)
			return read.channel.asksAboutLabel && rootMemoLabels.contains(world.text(ofLabel: read.label)) ? Self.rootMemo : -1
		}
		// A stack, since a tree can be as deep as the module has types.
		var stack: [VariantID] = [0]
		while let caller = stack.popLast() {
			let callerAnsweringDeclarations = answeringDeclarations[Int(caller)] ?? []
			let callerScope = world.scope(of: world.declaration(of: caller))
			let edgeFacts = world.edgeFacts(from: world.declaration(of: caller))
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() where answeringDeclarations[Int(callee)] == nil {
				// A rename is a leaf of the scope that declares it, which reads its fulfilling property for it.
				if let rename = Self.rename(world.declaration(of: callee), in: world),
				   Self.readsWrappersInstance(
				   	rename,
				   	declaredBy: callerScope,
				   	answeredAbove: Self.declaration(answering: rename.fulfillingProperty.label, readBy: caller, among: callerAnsweringDeclarations, in: world),
				   	rootInstanceProperties: rootInstanceProperties,
				   	in: world,
				   )
				{
					renamesReadingWrappersInstance.insert(callee)
				}
				let opensSendableFunction = Self.opensSendableFunction(edgeFacts[edgeFacts.startIndex + edgeIndex])
				var calleeAnsweringDeclarations = [DeclarationID]()
				for (source, readID) in zip(world.sources(ofCall: edgeIndex, of: caller), world.reads(of: world.declaration(of: callee))) {
					let answeringDeclaration: DeclarationID = switch source.kind {
					case .none:
						-1
					case .bound:
						source.payload
					case .passedThrough:
						callerAnsweringDeclarations[Int(source.payload)]
					}
					calleeAnsweringDeclarations.append(answeringDeclaration)
					let read = world.read(readID)
					// The caller passes the read through to the root's own, which asks about this label (`rootMemoLabels`).
					guard answeringDeclaration != Self.rootMemo else {
						let label = world.text(ofLabel: read.label)
						if Self.isHandedNearestDeclaration(read.channel) {
							for property in rootInstanceProperties where property.label == label {
								lazilyInstantiatedInstancePropertiesByVariant[Int(callee)].insert(property)
							}
						}
						// A memo read inside a `@Sendable` function is a `SendableLazilyInstantiated`; a wrapper parameter that is not
						// `Sendable` read there is the seam's own error, which its tree reports before any code is made.
						continue
					}
					guard answeringDeclaration >= 0, read.channel.asksAboutLabel else { continue }
					let scope = world.scope(of: answeringDeclaration)
					let instanceProperties = Self.isHandedNearestDeclaration(read.channel) ? scope.declaredLazilyInstantiatedInstanceProperties : []
					guard opensSendableFunction || !instanceProperties.isEmpty else { continue }
					let label = world.text(ofLabel: read.label)
					for property in instanceProperties where property.label == label {
						lazilyInstantiatedInstancePropertiesByVariant[Int(callee)].insert(property)
					}
					if opensSendableFunction, scope.sortedDeclaredPropertyForms.contains(where: { declared in
						declared.property.label == label && !declared.property.propertyType.isConstant && !declared.property.propertyType.isSendable
					}) {
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

	/// The renames fulfilled by a wrapper's instance; empty in a world that declares no lazily instantiated property and
	/// opens no `@Sendable` function.
	private let renamesReadingWrappersInstance: Set<VariantID>

	/// The declaration that answers a seam root's read with what its initializer binds above its tree, which is no
	/// declaration of the world.
	private static let rootMemo: DeclarationID = -2

	/// By variant; empty in a world that declares no lazily instantiated property and opens no `@Sendable` function.
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

	/// The declaration that answers `variant`'s read of `label` from above: a declaration of the world, `rootMemo`, or -1
	/// where none does or the variant reads no such label.
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
		rootInstanceProperties: Set<Property>,
		in world: some NodeRecordSources,
	) -> Bool {
		let instance = rename.fulfillingProperty.asUnwrappedProperty
		if rename.fulfillingProperty.label != rename.property.label, scope.declaredLabels.contains(rename.fulfillingProperty.label) {
			return scope.declaredLazilyInstantiatedInstanceProperties.contains(instance)
		} else if answeringDeclaration == rootMemo {
			return rootInstanceProperties.contains(instance)
		} else if answeringDeclaration >= 0 {
			return world.scope(of: answeringDeclaration).declaredLazilyInstantiatedInstanceProperties.contains(instance)
		} else {
			return false
		}
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
