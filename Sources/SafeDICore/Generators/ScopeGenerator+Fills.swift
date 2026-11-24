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

import Foundation
import SwiftParser
import SwiftSyntax

extension ScopeGenerator {
	/// The body of `fill`, whose function is `code` indented by `leadingMemberWhitespace`, as the dispatcher case that calls
	/// it holds it: the function's body under the names the case binds. `nil` for a fill whose scope parameter is named
	/// apart, because its place carries a field or its tree reads a value labeled `scope`, which the dispatcher's own
	/// parameter would hide: it keeps its function.
	static func inlinedFill(of fill: ScopeGenerator, code: String, leadingMemberWhitespace: String) -> FillDispatcher.InlinedFill? {
		// A fill is its function's declaration, its body, and the line closing it.
		let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let valuesType = fill.fillHole?.valuesType(qualifiedBy: nil)
		let carriesPayload = valuesType != nil
		// A seam's carrier hands the fill the payload's fields as arguments, the first named `scope_<label>`
		// (`SeamHoles.argumentName(of:inPayloadNamed:)`), where a builder struct hands it the payload named `scope`.
		let argumentFields: [SeamSignature.Hole.Field]? = if case let .nested(_, enumType, _)? = valuesType, ReservedName.seamCarrier(ofEnum: enumType) != nil {
			fill.fillHole.map { $0.enumPlace?.values ?? $0.fields } ?? []
		} else {
			nil
		}
		let scopePrefix = argumentFields.map { fields in (fill.fillCarrierUse?.parameterNames(of: fields, inPayloadNamed: "scope") ?? fields.map { SeamHoles.argumentName(of: $0, inPayloadNamed: "scope") }).first.map { "(_ \($0): " } ?? "(" } ?? "(_ scope: "
		guard lines.count > 2,
		      !carriesPayload || lines[0].contains(scopePrefix),
		      lines[lines.count - 1] == leadingMemberWhitespace + "}"
		else { return nil }
		let body = lines[1..<(lines.count - 1)].map { Self.standardIndent + $0 }
		// The fill binds the fields its tree reads first, each from the scope; nothing after them reads the scope.
		let readsScope = carriesPayload && lines[1].hasPrefix(leadingMemberWhitespace + Self.standardIndent + "let ") && (lines[1].contains(" = scope.") || (argumentFields != nil && lines[1].contains(" = scope_")))
		let builtProperty = fill.propertiesToGenerate.first?.property
		let forwardedValueName = fill.fillHole?.forwardedType == nil ? nil : builtProperty.map(Self.forwardedValueParameterName(forBuilding:))
		let readsForwardedValue = forwardedValueName.map { name in
			body.contains { line in
				line.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).contains(Substring(name))
			}
		} ?? false
		return FillDispatcher.InlinedFill(
			carriesPayload: carriesPayload,
			readsScope: readsScope,
			forwardedValueName: forwardedValueName,
			readsForwardedValue: readsForwardedValue,
			body: body,
		)
	}

	/// Whether this fill's body declares a function: the builder function of the property it fills, which a wrapper, a
	/// constant with children of its own, and a call of a seam or a public mock declare. A constant built in one expression
	/// declares none.
	nonisolated func fillDeclaresFunction(fillPlaceBindings: FillPlaceBindings) -> Bool {
		guard let filled = propertiesToGenerate.first, let property = filled.property else { return false }
		return !property.propertyType.isConstant
			|| !filled.propertiesToGenerate.isEmpty
			|| filled.seamCall != nil
			|| filled.publicMockCall != nil
			// The builder function of a type that binds a place of an internal mock's fill (`FillPlace`).
			|| fillPlaceBindings.bindingsByGenerator[ObjectIdentifier(filled)] != nil
	}

	/// The name of the parameter that holds the value an instantiator forwards, in a fill of a hole's `property`: named
	/// apart from the function that builds the property, which it would hide, or be hidden by.
	private static func forwardedValueParameterName(forBuilding property: Property) -> String {
		let name = ReservedName.forwardedValueParameterName
		return functionName(toBuild: property) == name ? "\(name)_" : name
	}

	/// The function a seam's caller generates to fill the builder for `hole`: it binds the fields of the payload its case
	/// carries that the tree of its one child, the hole's property, reads, builds the property as inline builds it at the
	/// site, and returns it, or, for a wrapper, what the wrapper's builder function builds, handing that function the value
	/// an instantiator forwards. A case that carries no payload – a place held in a `Sendable` wrapper – hands the fill none.
	func generateFillCode(
		of hole: SeamSignature.Hole,
		functionName: String,
		isSendable: Bool,
		takesPayloadFields: Bool,
		codeGeneration: CodeGeneration,
		propertiesGeneratedLater: Set<Property>,
		enclosingFunctionNames: [BuiltDeclaration: String],
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> String {
		guard let child = propertiesToGenerate.first, let property = child.property else { return "" }
		// A field is bound where the tree reads it, or where a site inside the fill – one of the seam whose tree the fill
		// is generated in – carries this binding in its own struct, unless the fill reads it from the caller's scope: one bound
		// from a deferred parameter (see `fillStructBoundLabels`).
		func isRead(_ field: SeamSignature.Hole.Field) -> Bool {
			fillStructBoundLabels.contains(field.property.label)
				&& (child.reads(field.property) || child.fieldsCarriedBySites.contains(field.property))
		}
		// The parameter is named apart from what the tree reads by name, which it would hide.
		let labelsReadInFill = Set(fillFields.map(\.property.label)
			+ child.receivedProperties.map(\.label)
			+ child.fieldsCarriedBySites.map(\.label))
		var scopeParameterName = "scope"
		while labelsReadInFill.contains(scopeParameterName) {
			scopeParameterName += "_"
		}
		let indent = Self.standardIndent
		let childCode = try await generateProperties(
			codeGeneration: codeGeneration,
			propertiesGeneratedLater: propertiesGeneratedLater,
			enclosingFunctionNames: enclosingFunctionNames,
			leadingMemberWhitespace: indent,
			fillPlaceBindings: fillPlaceBindings,
		)
		// A caller's own value the fill reads from its mock root's binding is bound under its label from the name the root binds
		// it under, where that is not the label.
		var body = fillCallerReads.mockRootRebindings(rootBindingNames: fillPlaceBindings.rootBindingNames).map { "\(indent)let \($0.label) = \($0.rootBindingName)" }
		// A fill is hosted as its text until fills are planned (`.claude/rules/emission-decisions.md`).
		body += GeneratedCode.lines(childCode).spelled().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		guard !fillReturnsWrapperBuilder else {
			// A level function's member hands the fill of an instantiator's place each field it reads, and the fill returns the
			// builder the wrapper keeps, spelled as the wrapper's own `Builder`: a function type a value it forwards could not
			// escape from. No payload struct is in scope, so the builder captures none. Each struct of the fill's own level is
			// handed as the function the inner seam's member returns for the place, the erased wrapper's `Builder` over the
			// struct, `@Sendable` in a `@Sendable` enum, whose case carries no payload: the property's builder function calls it
			// with what it was forwarded (`innerScopesCalledWithForwardedValue`).
			let innerScopeLabels = Set(fillCallerReads.innerScopeParameters.map(\.property.label))
			let parameters = fillMemberParameterFields.map { field in
				let type = if innerScopeLabels.contains(field.property.label) {
					TypeDescription.attributed(
						DependencyTreeGenerator.erasedBuilderType(
							forwarding: hole.forwardedType?.strippingEscaping ?? .void(.tuple),
							returning: field.property.typeDescription,
							isSendable: hole.enumPlace?.isBuiltBySendableBuilder ?? false,
						),
						specifiers: [],
						attributes: ["escaping"],
					)
				} else {
					field.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)
				}
				return "\(field.property.label.spelledAsArgumentLabel): \(type.asSource)"
			}
			let builderType = TypeDescription.nested(name: Dependency.wrapperBuilderTypeName, parentType: hole.property.typeDescription.unwrapped, generics: [])
			return (["\(Self.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(parameters.joined(separator: ", "))) -> \(builderType.asSource) {"]
				+ body
				+ ["}"]).joined(separator: "\n")
		}
		// A wrapper's scope returns what its builder function builds, and a constant's has bound it.
		if property.propertyType.isConstant {
			body.append(indent + "return \(property.label)")
		}
		guard !takesPayloadFields else {
			// An override closure of the call calls the fill with the values the call passes the called mock, and a level
			// function's member with its payload's, each by itself: no other module can make the payload.
			let parameters = fillMemberParameterFields(takingPayloadFields: true).map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			return (["\(Self.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(parameters.joined(separator: ", "))) -> \(hole.builtType.asSource) {"]
				+ body
				+ ["}"]).joined(separator: "\n")
		}
		// A fill of a place nested by type binds what its case's payload holds, and takes what a type further out binds.
		let nestedByTypeValues = hole.enumPlace?.values
		let valuesType = hole.valuesType(qualifiedBy: hole.scopeSeamType)
		// A deferred parameter's field the fill binds from the struct is bound as its memo (`bindingItsMemo`).
		let memoBoundLabels = Set(fillFields.filter(\.bindsMemo).map(\.property.label))
		// A seam's carrier hands the fill the case's values as arguments, each named as the payload's name joined with its label.
		let takesValuesAsArguments = if case let .nested(_, enumType, _)? = valuesType {
			ReservedName.seamCarrier(ofEnum: enumType) != nil
		} else {
			false
		}
		let caseValues = nestedByTypeValues ?? hole.fields
		let bindings: [String] = valuesType == nil ? [] : caseValues.enumerated().filter { isRead($0.element) }.map { index, field -> String in
			let bindsMemo = memoBoundLabels.contains(field.property.label)
			let read = if let fillCarrierUse, takesValuesAsArguments {
				// The struct of the run the values end holds the field, unless it is one taken after it.
				fillCarrierUse.read(ofFieldAt: index, of: caseValues, inPayloadNamed: scopeParameterName, bindingMemo: bindsMemo)
			} else if takesValuesAsArguments {
				SeamHoles.argumentRead(of: field, inPayloadNamed: scopeParameterName, bindingMemo: bindsMemo)
			} else {
				"\(scopeParameterName).\(field.memberName(bindingMemo: bindsMemo))"
			}
			return "\(indent)let \(field.property.label) = \(read)"
		}
		// A fill of an instantiator's place returns the wrapper's builder (`fillReturnsWrapperBuilder`), so no fill here takes
		// a forwarded value.
		var parameters: [String] = if let fillCarrierUse, takesValuesAsArguments {
			zip(fillCarrierUse.parameterNames(of: caseValues, inPayloadNamed: scopeParameterName), fillCarrierUse.parameterTypes(of: caseValues, qualifiedBy: hole.scopeSeamType, typesDeclaredEscaping: typesDeclaredEscaping)).map { "_ \($0): \($1.asSource)" }
		} else if takesValuesAsArguments {
			caseValues.map { "_ \(SeamHoles.argumentName(of: $0, inPayloadNamed: scopeParameterName)): \(($0.memoType ?? $0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource)" }
		} else {
			valuesType.map { ["_ \(scopeParameterName): \($0.asSource)"] } ?? []
		}
		parameters += fillParameterFields.map { "\($0.property.label.spelledAsArgumentLabel): \($0.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
		return (["\(Self.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(parameters.joined(separator: ", "))) -> \(hole.builtType.asSource) {"]
			+ bindings
			+ body
			+ ["}"]).joined(separator: "\n")
	}
}
