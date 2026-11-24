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
	/// The lines that make the member calls of builder structs at the top of this scope's builder function, indented for its
	/// body (`memberCallsInsideFunction`).
	nonisolated var memberCallLines: [String] {
		memberCallsInsideFunction.map { "\(Self.standardIndent)\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))" }
	}

	/// The lines that bind the payloads of the cases on the routes to the places beneath this scope, which its parent emits
	/// before its builder function, where the parent binds their labels: each field read as the parent's receivers read it.
	nonisolated var valuesBindingLines: String {
		valuesBindings.map { "\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))\n" }.joined()
	}

	/// The payloads `valuesBindingLines` binds, each as an argument of the initializer of the class a boxed loop's box is
	/// (`boxedLoops`), labeled with its binding's name.
	/// A run struct of a carrier level's values (`SeamCarrierValues`) is bound before the box, where the members' arguments
	/// read it, and is not boxed: no builder function of the loop reads it, so unboxing it would bind a value nothing reads.
	nonisolated var valuesBindingArguments: [String] {
		valuesBindings.filter { $0.formsRunAfter == nil }.map { binding in
			"\(binding.bindingName): \(binding.expression(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))"
		}
	}

	/// The lines that bind the run structs the box's arguments read, before the box.
	nonisolated var runStructBindingLinesBeforeBox: String {
		valuesBindings.filter { $0.formsRunAfter != nil }.map { "\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))\n" }.joined()
	}

	/// The lines at the top of a boxed loop member's builder function that unbox its own payloads under their names, so
	/// everything beneath reads them as it reads a payload bound before the function.
	nonisolated func loopLevelsUnboxingLines(from loopLevelsName: String) -> [String] {
		valuesBindings.filter { $0.formsRunAfter == nil }.map { "\(Self.standardIndent)let \($0.bindingName) = \(loopLevelsName).\($0.bindingName)" }
	}

	/// The binding of a boxed loop's box, `name`, an instance of `typeName` made of `arguments`, the payloads of the loop's
	/// members in the order the body generates them (see `boxedLoops`).
	static func loopLevelsBinding(named name: String, ofType typeName: String, arguments: [String]) -> String {
		var lines = ["let \(name) = \(typeName)("]
		lines.append(arguments.map { "\(standardIndent)\($0)" }.joined(separator: ",\n"))
		lines.append(")")
		return lines.joined(separator: "\n") + "\n"
	}

	/// The private class a boxed loop's box is (`boxedLoops`), which the seam whose tree it is declares beside its
	/// initializers: a local type cannot be declared in a generic context, which a seam's initializer can be, and a type
	/// nested in the seam reaches the generic parameters of an enclosing generic type. Each binding is a stored property of
	/// its own, so that a member's function reads its own in constant time; a tuple held behind a generic parameter was
	/// copied whole on each read, and a walk of the loop grew with its square.
	struct LoopLevelsType {
		/// The class that holds `bindings`, the payloads of a loop's members, in the order the body generates them.
		init(holding bindings: [SeamHoles.ValuesBinding]) {
			// Named after what it holds, so that two loops that hold the same bindings share one declaration, and no other loop
			// of the seam's tree, nor any tier, can declare another class of the name.
			var hash = SeamSignatureHash()
			for binding in bindings {
				hash.combine(binding.bindingName)
				hash.combine(binding.boundType.asSource)
			}
			name = "\(ReservedName.loopLevelsTypeName)_\(hash.hexadecimal)"
			let memberIndent = ScopeGenerator.standardIndent + ScopeGenerator.standardIndent
			var lines = [
				"\(ScopeGenerator.standardIndent)/// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.",
				"\(ScopeGenerator.standardIndent)nonisolated private final class \(name) {",
				"\(memberIndent)init(",
			]
			lines.append(bindings.map { "\(memberIndent)\(ScopeGenerator.standardIndent)\($0.bindingName): \($0.boundType.asSource)" }.joined(separator: ",\n"))
			lines.append("\(memberIndent)) {")
			lines += bindings.map { "\(memberIndent)\(ScopeGenerator.standardIndent)self.\($0.bindingName) = \($0.bindingName)" }
			lines += ["\(memberIndent)}", ""]
			lines += bindings.map { "\(memberIndent)let \($0.bindingName): \($0.boundType.asSource)" }
			lines.append("\(ScopeGenerator.standardIndent)}")
			declaration = lines.joined(separator: "\n")
		}

		let name: String
		/// The class's declaration, indented as a member of the seam's extension.
		let declaration: String
	}

	/// The code a seam's tree generates at a site of `property`, a hole: the member of its case called on the builder struct
	/// in scope there, handed the values in scope there. A constant is bound with its declared type, as inline binds an
	/// existential. An instantiator is built around what its member returns, the builder the wrapper keeps, with no function
	/// of the seam's own. Any other wrapper is built around a function that makes the call, as inline builds a wrapper around
	/// its builder function, which is `@Sendable` for a `Sendable` wrapper.
	/// - Parameters:
	///   - functionName: The name of that function where it differs from `functionName(toBuild:)`.
	///   - lazilyInstantiatedInstanceProperties: The by-value properties whose labels the site's owner holds only as a
	///     `LazilyInstantiated` property, whose instance the payload reads, as the owner's receivers do
	///     (`SeamHoles.valuesArguments(of:readingInstancesOf:)`).
	///   - lazilyInstantiatedBindingNames: In a public mock, the names the wrappers it binds apart from their instances' labels
	///     have where the site is built, which the payload reads a field of such a wrapper by
	///     (`SeamHoles.valuesArguments(of:readingInstancesOf:bindingNamesPassedByName:lazilyInstantiatedBindingNames:)`).
	// Kept out of `generatePropertyCode`'s async frame, as the functions that write a property's scope are.
	@inline(never)
	static func buildSiteCode(of property: Property, at site: SeamSignature.Hole, functionName: String?, readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property> = [], lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:], carrierUse: SeamCarrierValues.Use? = nil) -> String {
		// A place nested by type is handed what its owner binds before it; the cases that lead to it carry what each type on
		// the way binds, which the tree bound before building the next. A place in a `@Sendable` enum held in a `Sendable`
		// wrapper carries nothing.
		let fields = site.enumPlace?.values ?? site.fields
		let arguments = SeamHoles.valuesArguments(of: fields, readingInstancesOf: lazilyInstantiatedInstanceProperties, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)
		// The expression that builds the value: the place's member, called on the struct the last case on its route returned,
		// or on the builder itself. An instantiator's member returns the builder its wrapper keeps. Every place of a seam's or
		// a public mock's tree has its enum's case, whose member takes a struct (`SeamBuilderFamilies`). The `""` is never
		// returned: a hole is built before its place's case is known, so `enumPlace` is optional, and it is assigned to every
		// place before any code is generated; no type holds that order. 2.3.1's emitter rewrite replaces this code and drops
		// the fallback.
		guard let enumPlace = site.enumPlace, let memberValuesTypeName = enumPlace.memberValuesTypeName else { return "" }
		let valuesType = TypeDescription.nested(name: memberValuesTypeName, parentType: enumPlace.enumType(qualifiedBy: nil), generics: [])
		// Inside a fill whose call's case leads on, the fill is handed the struct of its own level.
		let lastStep = enumPlace.route.last
		let parentName = (lastStep?.member == nil ? nil : lastStep?.innerScope?.name) ?? lastStep?.member?.bindingName ?? site.internalName
		let buildExpression = if ReservedName.seamCarrier(ofEnum: enumPlace.enumType(qualifiedBy: nil)) != nil {
			// A seam's carrier takes the place's values as its member's arguments.
			"\(parentName).\(enumPlace.caseName)(\(SeamHoles.carrierArguments(of: fields, use: carrierUse, readingInstancesOf: lazilyInstantiatedInstanceProperties, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)))"
		} else {
			"\(parentName).\(enumPlace.caseName)(\(valuesType.asSource)(\(arguments)))"
		}
		let propertyType = property.propertyType
		guard !propertyType.isConstant else {
			return "let \(property.asSource) = \(buildExpression)"
		}
		let unwrappedType = property.typeDescription.unwrapped
		// A type constructed by annotation spells its generic arguments only in the declaration's annotation.
		let declaration = property.typeDescription.asSource == unwrappedType.spelledForConstruction ? "let \(property.label)" : "let \(property.asSource)"
		guard !propertyType.isAnyInstantiator else {
			// An instantiator's member returns the builder the wrapper keeps, which takes the forwarded value itself.
			return "\(declaration) = \(unwrappedType.spelledForConstruction)(\(buildExpression))"
		}
		let functionName = functionName ?? site.wrapperFunctionName ?? Self.functionName(toBuild: property)
		return """
		\(localFunctionPrefix(isSendable: propertyType.isSendable))func \(functionName)() -> \(site.builtType.asSource) {
		\(standardIndent)\(buildExpression)
		}
		\(declaration) = \(unwrappedType.spelledForConstruction)(\(functionName))
		"""
	}
}
