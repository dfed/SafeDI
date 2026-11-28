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
/// Whether a `@Sendable` function of a world reads a wrapper that is not `Sendable`, declared outside it, which the tree
/// reports as an error (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`): such a world keeps its tree
/// (`NodeRecordRefusal.sendableFunctionCapturesWrapper`). A check that refuses a world, never an input of a record: it
/// follows what each call hands its callee (`TypeFactsWorld.sources(ofCall:of:)`), which no record reads.
///
/// An edge that opens a `@Sendable` function (`TypeFactsEdge.opens`) builds its child inside that function, so every
/// read of the child's tree that a declaration above the child answers is made from outside the function: a capture
/// where that declaration is an `Instantiator`, an `ErasedInstantiator` or a `LazilyInstantiated`, read as itself or as
/// its instance, a parameter of a seam's own root included (`rootNonSendableWrapperLabels`), which its generated
/// initializer declares outside every function. A read a declaration inside the function answers is none of the call's
/// sources. A read of any channel counts, but for a read only if available of the declaration still being built around
/// the call, which is passed `nil` and captures nothing (`isPassedNil`).
///
/// Each variant is resolved once, from the first call a walk from the root meets: a second call's capture is found only
/// where its key differs, which makes a variant of its own. The check goes when the facts fold captures per variant
/// (`TypeFactsOutcome`), the per-type facts' form of `nonSendableWrapperCaptures`.
///
/// Memory: the declaration that answers each read, one ID per key of every variant, while the check runs; none in a world
/// that opens no `@Sendable` function.
struct DeclarationsAnsweringReads: Sendable {
	/// - Parameters:
	///   - world: A production root's world.
	///   - rootNonSendableWrapperLabels: The labels of what the root is handed in an `Instantiator`, an
	///     `ErasedInstantiator` or a `LazilyInstantiated`. Empty unless the root is a seam's own.
	///   - mockRootParameters: What a mock root takes from `mock()` for receives its tree makes that nothing in the tree
	///     declares, by label and type. A receive of a label the root also declares in a form that answers no receive of
	///     its type (neither the type nor a lazy wrapper's instance) is one of them, named apart, so a read of the label
	///     the root answers resolves by label and type: each receive beneath the call reads the parameter of its own form
	///     where `mock()` takes one, and the root's declaration otherwise. Empty unless the root is a mock root.
	init(world: some NodeRecordSources, rootNonSendableWrapperLabels: Set<String> = [], mockRootParameters: Set<Property> = []) {
		guard (0..<Int32(world.declarationCount)).contains(where: { world.edgeFacts(from: $0).contains { Self.opensSendableFunction($0) } }) else {
			sendableFunctionCapturesWrapper = false
			return
		}
		var sendableFunctionCapturesWrapper = false
		let receiveTypes = mockRootParameters.isEmpty ? [] : Self.receiveTypesReadFromAbove(in: world, labels: Set(mockRootParameters.map(\.label)))
		let root = world.declaration(of: 0)
		// For each variant reached, the declaration that answers each of its reads, -1 where none does. No node is above
		// the root, so what the root is handed answers what its tree reads.
		var answeringDeclarations = [[DeclarationID]?](repeating: nil, count: world.variantCount)
		answeringDeclarations[0] = [DeclarationID](repeating: -1, count: world.reads(of: world.declaration(of: 0)).count)
		// Each variant's caller, the first call a walk from the root meets, -1 for the root.
		var callerByVariant = [VariantID](repeating: -1, count: world.variantCount)
		// A stack, since a tree can be as deep as the module has types.
		var stack: [VariantID] = [0]
		while let caller = stack.popLast() {
			let callerAnsweringDeclarations = answeringDeclarations[Int(caller)] ?? []
			let edgeFacts = world.edgeFacts(from: world.declaration(of: caller))
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() where answeringDeclarations[Int(callee)] == nil {
				let opensSendableFunction = Self.opensSendableFunction(edgeFacts[edgeFacts.startIndex + edgeIndex])
				var calleeAnsweringDeclarations = [DeclarationID]()
				callerByVariant[Int(callee)] = caller
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
					guard opensSendableFunction, read.channel.asksAboutLabel else { continue }
					let label = world.text(ofLabel: read.label)
					// A read the mock root answers resolves by each form the receives beneath the call read it in
					// (`mockRootParameters`): a receive reads the root's declaration of its form, or of its instance where that
					// is a lazy wrapper; else the parameter `mock()` takes of a lazy wrapper whose instance it is; else the
					// parameter of its form. A receive none of them answers is read by label, as any other world reads.
					var capturesMockRootParameter = false
					var resolvedReadsWrapper: Bool?
					if !receiveTypes.isEmpty, answeringDeclaration < 0 || answeringDeclaration == root {
						let types = receiveTypes[Int(world.declaration(of: callee))][label] ?? []
						let rootForms = world.scope(of: root).sortedDeclaredPropertyForms.map(\.property).filter { $0.label == label }
						let parameters = mockRootParameters.filter { $0.label == label }.sorted()
						var readsByLabel = types.isEmpty && world.property(of: world.declaration(of: callee))?.label != label
						var readsWrapper = false
						for type in types {
							let receive = Property(label: label, typeDescription: type).asUnwrappedProperty
							if let declared = rootForms.first(where: { $0 == receive || $0.asLazilyInstantiatedInstanceProperty == receive }) {
								readsWrapper = readsWrapper || Self.isNonSendableWrapper(declared)
							} else if let parameter = parameters.first(where: { $0.asUnwrappedProperty.asLazilyInstantiatedInstanceProperty == receive }) ?? parameters.first(where: { $0.asUnwrappedProperty == receive }) {
								capturesMockRootParameter = capturesMockRootParameter || Self.isNonSendableWrapper(parameter)
							} else {
								readsByLabel = true
							}
						}
						// The callee's own label, which it reads only to rebind it, is no receive: a world that reads nothing
						// else of the label beneath the call reads nothing the root binds.
						resolvedReadsWrapper = readsByLabel ? nil : readsWrapper
					}
					let readsNonSendableWrapper = resolvedReadsWrapper ?? (answeringDeclaration >= 0
						? world.scope(of: answeringDeclaration).sortedDeclaredPropertyForms.contains { declared in
							declared.property.label == label && !declared.property.propertyType.isConstant && !declared.property.propertyType.isSendable
						}
						: rootNonSendableWrapperLabels.contains(label))
					if capturesMockRootParameter || (readsNonSendableWrapper && !Self.isPassedNil(read.channel, of: label, answeredBy: answeringDeclaration, aboveCallOf: callee, by: caller, callerByVariant: callerByVariant, in: world)) {
						sendableFunctionCapturesWrapper = true
					}
				}
				answeringDeclarations[Int(callee)] = calleeAnsweringDeclarations
				stack.append(callee)
			}
		}
		self.sendableFunctionCapturesWrapper = sendableFunctionCapturesWrapper
	}

	/// Whether a `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`.
	let sendableFunctionCapturesWrapper: Bool

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

	/// Whether `property` is a wrapper that is not `Sendable`, read as itself or through its instance.
	private static func isNonSendableWrapper(_ property: Property) -> Bool {
		!property.asUnwrappedProperty.propertyType.isConstant && !property.asUnwrappedProperty.propertyType.isSendable
	}

	/// For each declaration, the types each receive of its tree that reads one of `labels` from above it declares, by
	/// label: its own receives' and aliases' fulfilling properties, and its children's where it reads the label from above
	/// too, folded to a fixed point over the edges, which may close cycles.
	private static func receiveTypesReadFromAbove(in world: some NodeRecordSources, labels: Set<String>) -> [[String: Set<TypeDescription>]] {
		let count = world.declarationCount
		var labelsReadFromAbove = [Set<String>]()
		var types = [[String: Set<TypeDescription>]](repeating: [:], count: count)
		for declaration in 0..<count {
			let readLabels = Set(world.reads(of: DeclarationID(declaration)).lazy.map(world.read).filter(\.channel.asksAboutLabel).map { world.text(ofLabel: $0.label) }).intersection(labels)
			labelsReadFromAbove.append(readLabels)
			switch world.kind(of: DeclarationID(declaration)) {
			case .alias, .hole:
				continue
			case .constant, .instantiator, .erasedInstantiator, .lazy, .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
				break
			}
			for dependency in world.scope(of: DeclarationID(declaration)).instantiable.dependencies {
				let received: Property
				switch dependency.source {
				case .received:
					received = dependency.property
				case let .aliased(fulfillingProperty, _, _):
					received = fulfillingProperty
				case .instantiated, .forwarded:
					continue
				}
				if readLabels.contains(received.label) {
					types[declaration][received.label, default: []].insert(received.typeDescription)
				}
			}
		}
		var changed = true
		while changed {
			changed = false
			for declaration in (0..<count).reversed() {
				for child in world.edges(from: DeclarationID(declaration)) {
					for (label, childTypes) in types[Int(child)] where labelsReadFromAbove[declaration].contains(label) && !childTypes.isSubset(of: types[declaration][label] ?? []) {
						types[declaration][label, default: []].formUnion(childTypes)
						changed = true
					}
				}
			}
		}
		return types
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
