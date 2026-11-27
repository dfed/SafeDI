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

extension NodeRecords {
	/// The claim of `declaration` where it is a rename (`@Received(fulfilledByDependencyNamed:ofType:)`): of kind `rename`,
	/// discharging every refusal of stage 1. A rename is a leaf whose scope is the scope that declares it, so each refusal
	/// stage 1 finds of it is of that scope, which its own node holds; `nil` for any other node.
	static func renameClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.kind(of: declaration) == .alias else { return nil }
		// A rename of a builder that does not erase it can be a member of a loop of builders, which the tree rebinds where
		// the loop holds only builders (`ScopeGenerator.isLoopBuilder(amongSiblings:)`): a loop of builders, refused.
		let isLoopBuilder = rename(of: declaration, in: world).map { !$0.erasedToConcreteExistential && ScopeGenerator.isBuilder($0.property) } ?? false
		return NodeRecordClaim(kind: .rename, discharges: Set(NodeRecordRefusal.allCases), refusals: isLoopBuilder ? [.builderLoop] : [])
	}

	/// The rename `declaration` is, as its scope declares it, under its property (`TypeFactsGraph`).
	private static func rename(
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
	) -> (property: Property, fulfillingProperty: Property, erasedToConcreteExistential: Bool, declarationReference: AliasDeclarationReferences.Reference?)? {
		world.scope(of: declaration).propertiesToGenerate.lazy.compactMap { propertyToGenerate in
			if case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, _, declarationReference) = propertyToGenerate, property == world.property(of: declaration) {
				(property, fulfillingProperty, erasedToConcreteExistential, declarationReference)
			} else {
				nil
			}
		}.first
	}

	/// The record of `declaration`'s place in `variant`, a rename: its declaration, bound from its fulfilling property, or,
	/// only if available, to `nil` where `answers` finds no declaration it reads available, as the tree writes it.
	static func renameRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		answers: OnlyIfAvailableAnswers,
	) throws(NodeRecordRefusal) -> AliasPlaceRecord {
		guard let (property, fulfillingProperty, erasedToConcreteExistential, declarationReference) = rename(of: declaration, in: world) else { throw .renameOrHole }
		switch answers.renameBinding(of: variant) {
		case .boundToNil:
			// A rename only if available is still declared, so that the type declaring it reads it, `nil` included.
			let text = ScopeGenerator.referencingDeclaration(of: "let \(property.asSource) = nil", by: declarationReference)
			return AliasPlaceRecord(property: property, fulfillingProperty: nil, text: text, reads: [])
		case let .bound(fulfillingBindingIsOptional):
			return renameRecord(of: property, fulfilledBy: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, fulfillingBindingIsOptional: fulfillingBindingIsOptional, declarationReference: declarationReference)
		case nil:
			// A required rename is bound from its fulfilling property, which its scope requires.
			return renameRecord(of: property, fulfilledBy: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, fulfillingBindingIsOptional: false, declarationReference: declarationReference)
		}
	}

	private static func renameRecord(
		of property: Property,
		fulfilledBy fulfillingProperty: Property,
		erasedToConcreteExistential: Bool,
		fulfillingBindingIsOptional: Bool,
		declarationReference: AliasDeclarationReferences.Reference?,
	) -> AliasPlaceRecord {
		let text = ScopeGenerator.referencingDeclaration(
			of: ScopeGenerator.aliasDeclaration(
				of: property,
				fulfilledBy: fulfillingProperty.label,
				ofType: fulfillingProperty.typeDescription,
				erasedToConcreteExistential: erasedToConcreteExistential,
				fulfillingValueMayBeOptional: fulfillingBindingIsOptional,
			),
			by: declarationReference,
		)
		return AliasPlaceRecord(property: property, fulfillingProperty: fulfillingProperty, text: text)
	}
}
