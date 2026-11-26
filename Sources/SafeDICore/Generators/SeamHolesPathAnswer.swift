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

/// What a seam's tree reads of `SeamHoles` at each path, handed to `observer` with the node and edge of the seam's graph
/// the path ends on, so a test can check that every path of one node and edge reads the same answer: the check before the
/// per-path maps are answered by node and edge (per-type facts, track C, piece 9). Each answer is a projection that leaves
/// out what names the path itself (its length, its properties), so two paths agree exactly when what the tree emits from
/// the answer is the same.
public struct SeamHolesPathAnswer: Sendable, Hashable {
	/// The seam whose tree reads the answer.
	public let seamType: String
	/// The declaration the edge leaves: the property and concrete type of the scope that builds the edge's property, or
	/// the seam's root.
	public let node: String
	/// The property the path ends on, with the concrete type it is built for.
	public let edge: String
	/// Which read of `SeamHoles` this is.
	public let column: String
	/// The projected answer.
	public let answer: String
	/// The path, spelled, which only the report reads.
	public let path: String
	/// Whether a `Sendable` wrapper is on the path above the edge: the family a binding of the edge can depend on.
	public let isInsideSendableWrapper: Bool

	/// Called with each answer of a seam's tree built for emission, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (SeamHolesPathAnswer) -> Void)?
	/// The seam whose emitted tree is being built, set only while `observer` is.
	@TaskLocal static var seamBeingBuilt: TypeDescription?

	/// Whether answers are being recorded.
	static var isRecording: Bool {
		observer != nil && seamBeingBuilt != nil
	}

	/// Builds `operation` recording the answers of the tree of `seamType`, when an observer is set.
	static func building<Result>(treeOf seamType: TypeDescription, _ operation: () throws -> Result) rethrows -> Result {
		guard observer != nil else { return try operation() }
		return try $seamBeingBuilt.withValue(seamType) { try operation() }
	}

	/// The node of a scope built at a path whose last property is `edgeProperty`, beneath `parent`.
	static func node(parentProperty: Property?, parentConcreteType: TypeDescription?) -> String {
		guard let parentProperty, let parentConcreteType else { return "<seam root>" }
		return "\(parentProperty.asSource) built as \(parentConcreteType.asSource)"
	}

	static func edge(property: Property, concreteType: TypeDescription?) -> String {
		"\(property.asSource)" + (concreteType.map { " built as \($0.asSource)" } ?? "")
	}

	static func record(node: String, edge: String, column: String, answer: String, path: [Property], isInsideSendableWrapper: Bool) {
		guard let observer, let seamBeingBuilt else { return }
		observer(SeamHolesPathAnswer(
			seamType: seamBeingBuilt.asSource,
			node: node,
			edge: edge,
			column: column,
			answer: answer,
			path: path.map(\.asSource).joined(separator: " / "),
			isInsideSendableWrapper: isInsideSendableWrapper,
		))
	}

	// MARK: Projections

	static func projection(of bindings: [SeamHoles.ValuesBinding]) -> String {
		bindings.map { binding in
			"\(binding.line(readingInstancesOf: [])) | inside function: \(binding.isCalledInsideFunction) | bound: \(binding.boundType.asSource) | let child: \(binding.isLetChild) | carrier: \(projection(of: binding.carrierUse))"
		}.joined(separator: "\n")
	}

	static func projection(of use: SeamCarrierValues.Use?) -> String {
		guard let use else { return "none" }
		return "\(use.level) struct end \(use.structEnd.map(String.init) ?? "none") extras \(use.extras) ends \(use.ends)"
	}

	static func projection(of carrierSite: SeamHoles.CarrierSite?) -> String {
		guard let carrierSite else { return "none" }
		return "\(projection(of: carrierSite.use)) formations:\n\(projection(of: carrierSite.formations))"
	}

	static func projection(of hole: SeamSignature.Hole?) -> String {
		guard let hole else { return "none" }
		var text = "\(hole.internalName) builder \(hole.builderLabel) wrapper \(hole.wrapperFunctionName ?? "none") sendable \(hole.isSendable)"
		if let enumPlace = hole.enumPlace {
			text += " enum \(enumPlace.rootEnumTypeName ?? "").\(enumPlace.enumTypeName) case \(enumPlace.caseName) values \(enumPlace.values.map(\.property.asSource)) route "
			text += enumPlace.route.map { step in
				"\(step.caseName)[values \(step.values?.bindingName ?? "-"), member \(step.member?.bindingName ?? "-"), inner \(step.innerScope?.name ?? "-")]"
			}.joined(separator: " > ")
		}
		return text
	}

	/// What the site's own code and its place record read of the hole (`ScopeGenerator.buildSiteCode`, `HoleSiteReads`,
	/// `fieldsCarried(by:)`): the route only from its last step, and the fields the steps after the innermost fill carry.
	static func projection(ofSiteAsRead hole: SeamSignature.Hole?) -> String {
		guard let hole else { return "none" }
		var text = "\(hole.internalName) builder \(hole.builderLabel) wrapper \(hole.wrapperFunctionName ?? "none") sendable \(hole.isSendable) built \(hole.builtType.asSource)"
		if let enumPlace = hole.enumPlace {
			let members = enumPlace.route.compactMap(\.member)
			let builtType = members.lazy.compactMap(\.levelType.genericArgumentsOfThisAndEnclosingTypes.last).first?.asSource ?? "-"
			text += " enum \(enumPlace.rootEnumTypeName ?? "").\(enumPlace.enumTypeName) case \(enumPlace.caseName) member values \(enumPlace.memberValuesTypeName ?? "-") values \(enumPlace.values.map(\.property.asSource)) sendable builder \(enumPlace.isBuiltBySendableBuilder) level built \(builtType)"
			if let lastStep = enumPlace.route.last {
				text += " last step [member \(lastStep.member.map { "\($0.bindingName): \($0.levelType.asSource)" } ?? "-"), inner \(lastStep.innerScope?.name ?? "-")]"
			}
			let carried = if let lastFillStep = enumPlace.route.lastIndex(where: \.leadsIntoFill) {
				enumPlace.route[(lastFillStep + 1)...].flatMap { $0.values?.fields ?? [] } + enumPlace.values
			} else {
				hole.fields
			}
			text += " carried \(carried.map(\.property.asSource))"
		} else {
			text += " fields \(hole.fields.map(\.property.asSource))"
		}
		return text
	}

	static func projection(ofCallAt path: [Property], innerKey: SeamSignature.ScopeEnum.Key, in seamHoles: SeamHoles) -> String {
		var text = "route case: "
		if let routeCase = seamHoles.routeCase(at: path, innerKey: innerKey) {
			text += "\(routeCase.memberCall ?? "none") on \(routeCase.passedUpStruct.map { "\($0.name): \($0.type.asSource)" } ?? "none")"
		} else {
			text += "none"
		}
		let innerScopes = seamHoles.innerScopes(at: path, innerKey: innerKey)
		text += " | inner scopes: " + innerScopes.map { "\($0.name): \($0.enumType.asSource) builder \($0.builderLabel)" }.joined(separator: ", ")
		text += " | carries struct: \(seamHoles.carriesStruct(at: path, innerKey: innerKey))"
		text += " | carried structs: " + innerScopes.map { seamHoles.carriedStruct(at: path, innerKey: innerKey, innerScopeName: $0.name) ?? "none" }.joined(separator: ", ")
		return text
	}
}
