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
	/// Each refusal `refusalsOfBuiltByInitializer(_:in:)` can find of a rename, all of its declaring scope's, which that
	/// scope's own node holds. A refusal added there later is not discharged for a rename until it is named here.
	private static let renameDischarges: Set<NodeRecordRefusal> = [
		.construction,
		.erased,
		.sendable,
		.lazy,
		.renameOrHole,
		.cycle,
		.unavailableOrInlineSeam,
		.fill,
		.uncoveredDependency,
		.onlyIfAvailable,
		.noInitializer,
	]

	/// The claim of `declaration` where it is a rename (`@Received(fulfilledByDependencyNamed:ofType:)`): of kind `rename`,
	/// discharging each refusal `refusalsOfBuiltByInitializer(_:in:)` finds of it. A rename is a leaf whose scope is the
	/// scope that declares it, so each such refusal is of that scope, which its own node holds; `nil` for any other node.
	static func renameClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.kind(of: declaration) == .alias else { return nil }
		// A rename of a builder that does not erase it can be a member of a loop of builders, which the tree rebinds where
		// the loop holds only builders (`ScopeGenerator.isLoopBuilder(amongSiblings:)`): a loop of builders, refused.
		let isLoopBuilder = rename(of: declaration, in: world).map { !$0.erasedToConcreteExistential && ScopeGenerator.isBuilder($0.property) } ?? false
		return NodeRecordClaim(kind: .rename, discharges: renameDischarges, refusals: isLoopBuilder ? [.builderLoop] : [])
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

	/// The record of `declaration`'s place in `variant`, a rename: its declaration, bound from its fulfilling property, the
	/// instance of the wrapper of its label where `readsWrappersInstance` (`DeclarationsAnsweringReads`), or, only if
	/// available, to `nil` where `answers` finds no declaration it reads available, as the tree writes it. In a mock root's
	/// world, an erased rename only if available maps over its fulfilling value wherever it is bound, as the mock's walk
	/// binds it (`MockLowering.AliasBinding`), rather than only where the declaration it reads is optional, as a production
	/// tree binds it: a fact of the world, which no production world answers. A rename reads no override, so a mock root's
	/// world decorates its record with nothing.
	static func renameRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		answers: OnlyIfAvailableAnswers,
		readsWrappersInstance: Bool,
		wrapperName: String? = nil,
	) throws(NodeRecordRefusal) -> AliasPlaceRecord {
		guard let (declaredProperty, renamedProperty, erasedToConcreteExistential, declarationReference) = rename(of: declaration, in: world) else { throw .renameOrHole }
		// A rename of a mock root's level whose label another value of the level binds is bound under the name the root gives
		// it apart, which the root's construction reads and each receive of it beneath binds again under its label
		// (`mockNamesReadApart(in:)`), as the walk binds it (`MockLowering.rootLevelBindingNames(of:besideNamesTaken:)`).
		// A rename beneath the root's level of a label the root names apart is refused (`refusalOfNamingApart(_:in:)`), so
		// every rename with a name apart is of the root's level.
		let property = world.mockRootNames.nameApart(of: declaredProperty).map { Property(label: $0, typeDescription: declaredProperty.typeDescription) } ?? declaredProperty
		// A rename of a wrapper a mock binds around an instance it takes reads the wrapper by name, as the walk reads it
		// (`mockNamesReadApart(in:)`).
		let fulfillingProperty = wrapperName.map { Property(label: $0, typeDescription: renamedProperty.typeDescription) } ?? renamedProperty
		switch answers.renameBinding(of: variant) {
		case .boundToNil:
			// A rename only if available is still declared, so that the type declaring it reads it, `nil` included.
			let text = ScopeGenerator.referencingDeclaration(of: "let \(property.asSource) = nil", by: declarationReference)
			return AliasPlaceRecord(property: property, fulfillingProperty: nil, text: text, reads: [])
		case let .bound(fulfillingBindingIsOptional):
			return renameRecord(of: property, fulfilledBy: fulfillingProperty, readsWrappersInstance: readsWrappersInstance, erasedToConcreteExistential: erasedToConcreteExistential, fulfillingBindingIsOptional: fulfillingBindingIsOptional || world.isMockWorld, declarationReference: declarationReference)
		case nil:
			// A required rename is bound from its fulfilling property, which its scope requires.
			return renameRecord(of: property, fulfilledBy: fulfillingProperty, readsWrappersInstance: readsWrappersInstance, erasedToConcreteExistential: erasedToConcreteExistential, fulfillingBindingIsOptional: false, declarationReference: declarationReference)
		}
	}

	private static func renameRecord(
		of property: Property,
		fulfilledBy fulfillingProperty: Property,
		readsWrappersInstance: Bool,
		erasedToConcreteExistential: Bool,
		fulfillingBindingIsOptional: Bool,
		declarationReference: AliasDeclarationReferences.Reference?,
	) -> AliasPlaceRecord {
		let text = ScopeGenerator.referencingDeclaration(
			of: ScopeGenerator.aliasDeclaration(
				of: property,
				fulfilledBy: readsWrappersInstance ? "\(fulfillingProperty.label).\(Dependency.lazilyInstantiatedInstancePropertyName)" : fulfillingProperty.label,
				ofType: fulfillingProperty.typeDescription,
				erasedToConcreteExistential: erasedToConcreteExistential,
				fulfillingValueMayBeOptional: fulfillingBindingIsOptional,
			),
			by: declarationReference,
		)
		return AliasPlaceRecord(property: property, fulfillingProperty: fulfillingProperty, text: text)
	}
}
