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

/// What the declarations above each variant answer its tree's reads with, of the two answers a record or a refusal
/// reads, made from what each call hands its callee (`TypeFactsWorld.sources(ofCall:of:)`) with no walk of a place:
///
/// - The by-value properties each variant's body reads as the instance of a `LazilyInstantiated` or a
///   `SendableLazilyInstantiated` declared above it: what the tree hands each place as its
///   `lazilyInstantiatedInstanceProperties` (`Scope.createScopeGenerator`).
/// - Whether a `@Sendable` function reads a wrapper that is not `Sendable`, declared outside it, which the tree reports
///   as an error (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`): such a world keeps its tree
///   (`NodeRecordRefusal.sendableFunctionCapturesWrapper`).
///
/// The nearest node above that declares a label answers a read of it, and a `value` read is of a wrapper's instance
/// where that node's scope declares the instance (`ConstructionScope.declaredLazilyInstantiatedInstanceProperties`).
/// Each variant is resolved once, from the first call a walk from the root meets, and every other call into it answers
/// alike: the calls share the variant's key, and a `value` read keys by the forms its declaration provides, which tell a
/// wrapper's declaration from a value's, and one wrapper kind from another. A node built beneath a wrapper on one path
/// and a value on another therefore has two variants, which `NodeRecords` refuses
/// (`NodeRecordRefusal.nodeHasSeveralVariants`). The stages that admit a receive only if available or a rename, whose
/// reads are of other channels, read their answers here too.
///
/// An edge that opens a `@Sendable` function (`TypeFactsEdge.opens`) builds its child inside that function, so every
/// read of the child's tree that a declaration above the child answers is made from outside the function: a capture
/// where that declaration is an `Instantiator`, an `ErasedInstantiator` or a `LazilyInstantiated`, read as itself or as
/// its instance. A read a declaration inside the function answers is none of the call's sources. A read of any channel
/// counts, so a stage that admits a receive passed `nil`, which captures nothing, keeps the tree of more worlds than the
/// tree reports until it reads that answer here.
///
/// Memory: a set per variant, each empty unless the variant's tree reads a wrapper's instance, for as long as
/// `NodeRecords.init` makes the records; none in a world that declares no lazily instantiated property and opens no
/// `@Sendable` function. The declaration that answers each read, one ID per key of every variant, lives only while the
/// sets are made.
struct DeclarationsAnsweringReads: Sendable {
	init(world: some NodeRecordSources) {
		let declarations = 0..<Int32(world.declarationCount)
		guard declarations.contains(where: { declaration in
			!world.scope(of: declaration).declaredLazilyInstantiatedInstanceProperties.isEmpty
				|| world.edgeFacts(from: declaration).contains { Self.opensSendableFunction($0) }
		}) else {
			self.lazilyInstantiatedInstancePropertiesByVariant = []
			self.sendableFunctionCapturesWrapper = false
			return
		}
		var lazilyInstantiatedInstancePropertiesByVariant = [Set<Property>](repeating: [], count: world.variantCount)
		var sendableFunctionCapturesWrapper = false
		// For each variant reached, the declaration that answers each of its reads, -1 where none does. Nothing is above
		// the root, so nothing answers what its tree reads.
		var answeringDeclarations = [[DeclarationID]?](repeating: nil, count: world.variantCount)
		answeringDeclarations[0] = [DeclarationID](repeating: -1, count: world.reads(of: world.declaration(of: 0)).count)
		// A stack, since a tree can be as deep as the module has types.
		var stack: [VariantID] = [0]
		while let caller = stack.popLast() {
			let callerAnsweringDeclarations = answeringDeclarations[Int(caller)] ?? []
			let edgeFacts = world.edgeFacts(from: world.declaration(of: caller))
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() where answeringDeclarations[Int(callee)] == nil {
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
					guard answeringDeclaration >= 0, read.channel.asksAboutLabel else { continue }
					let scope = world.scope(of: answeringDeclaration)
					let instanceProperties = read.channel == .value ? scope.declaredLazilyInstantiatedInstanceProperties : []
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
	}

	/// The by-value properties `variant`'s body reads as a wrapper's instance, of the labels its tree reads from above.
	func lazilyInstantiatedInstanceProperties(readBy variant: VariantID) -> Set<Property> {
		lazilyInstantiatedInstancePropertiesByVariant.isEmpty ? [] : lazilyInstantiatedInstancePropertiesByVariant[Int(variant)]
	}

	/// Whether a `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`.
	let sendableFunctionCapturesWrapper: Bool

	/// By variant; empty in a world that declares no lazily instantiated property and opens no `@Sendable` function.
	private let lazilyInstantiatedInstancePropertiesByVariant: [Set<Property>]

	private static func opensSendableFunction(_ edge: TypeFactsEdge) -> Bool {
		switch edge.opens {
		case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
			true
		case .none, .instantiatorBuilder:
			false
		}
	}
}
