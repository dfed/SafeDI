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

import SafeDICore
import SwiftParser
import SwiftSyntax

/// What one run of the tool shows of the places of its seams' holes, read from the levels of every computation of a
/// seam's holes (`SeamPlaceLevels`), as plain text, so that the oracles that compare it with the scope enums the tool
/// generates (`GraphFuzzerScopeDeclarations`) need no type of `SafeDICore`.
///
/// Only the scopes outside every fill count: a fill's tree is built with the stack of the seam whose hole it fills, and
/// a place inside one is a case of the calling seam's enum of its own kind (`<call>_<builder>`), which the level before
/// the fill, whose next property is `nil`, does not name. A place an inner seam passes up has no levels in the outer
/// seam, so it produces no case here: the outer seam's case that wraps the inner seam's enum is left out of every
/// comparison with produced cases (`GraphFuzzerScopeDeclarations.ScopeCase.wrapsAnotherSeamsEnum`).
struct GraphFuzzerPlaceFacts: Equatable {
	init(
		producedCases: Set<ProducedCase> = [],
		levelFields: [LevelKey: [String]] = [:],
		declaredLabels: [Holder: Set<String>] = [:],
		chainRepeats: [String] = [],
		holdsPlaceInsideFill: Bool = false,
	) {
		self.producedCases = producedCases
		self.levelFields = levelFields
		self.declaredLabels = declaredLabels
		self.chainRepeats = chainRepeats
		self.holdsPlaceInsideFill = holdsPlaceInsideFill
	}

	/// The facts of `placeLevels`, every computation of a seam's holes a run made, in the order the run made them.
	init(placeLevels: [SeamPlaceLevels]) {
		self.init()
		for computation in placeLevels {
			let seamType = computation.seamType.asSource
			for place in computation.places {
				if place.levels.contains(where: \.isInFill) {
					holdsPlaceInsideFill = true
				}
				// The levels from the seam's root inward, up to the first scope of a fill.
				let outerLevels = Array(place.levels.reversed().prefix { !$0.isInFill })
				var declarationsOnPath = [String]()
				for (index, level) in outerLevels.enumerated() {
					guard let builtType = level.builtType else { continue }
					let holder = Holder(seamType: seamType, typeName: builtType.asSource, isSeamRoot: index == 0)
					declaredLabels[holder, default: []].formUnion(level.declarations.map(\.property.label))
					guard let nextProperty = level.nextProperty else { continue }
					producedCases.insert(ProducedCase(holder: holder, label: nextProperty.label))
					let key = LevelKey(holder: holder, nextProperty: nextProperty.asSource)
					if levelFields[key] == nil {
						levelFields[key] = level.fieldsOfType.map(\.asSource)
					}
					// The declaration the next property makes, keyed as the cycle check keys it: the property with a lazily
					// instantiated wrapper read as the instance it stands for, and the concrete type the next scope builds.
					guard index + 1 < outerLevels.count, let nextBuiltType = outerLevels[index + 1].builtType else { continue }
					let declaration = "`\(Self.cycleSpelling(of: nextProperty))` building `\(nextBuiltType.asSource)`"
					if declarationsOnPath.contains(declaration) {
						let repeatDescription = "The place `\(place.sitePath.map(\.label).joined(separator: "."))` of `\(seamType)` repeats the declaration \(declaration) on its path."
						if !chainRepeats.contains(repeatDescription) {
							chainRepeats.append(repeatDescription)
						}
					}
					declarationsOnPath.append(declaration)
				}
			}
		}
	}

	/// A type that binds a level on a place's path: the seam's root, or a type its tree builds.
	struct Holder: Hashable, Comparable {
		let seamType: String
		let typeName: String
		let isSeamRoot: Bool

		static func < (lhs: Holder, rhs: Holder) -> Bool {
			(lhs.seamType, lhs.typeName, lhs.isSeamRoot ? 0 : 1) < (rhs.seamType, rhs.typeName, rhs.isSeamRoot ? 0 : 1)
		}
	}

	/// A case some place's path produces: the holder's property that leads toward the place.
	struct ProducedCase: Hashable, Comparable {
		let holder: Holder
		let label: String

		static func < (lhs: ProducedCase, rhs: ProducedCase) -> Bool {
			(lhs.holder, lhs.label) < (rhs.holder, rhs.label)
		}
	}

	/// What a level is a level of: a holder, before one of its properties.
	struct LevelKey: Hashable, Comparable {
		let holder: Holder
		/// The property, as source: `label: Type`.
		let nextProperty: String

		static func < (lhs: LevelKey, rhs: LevelKey) -> Bool {
			(lhs.holder, lhs.nextProperty) < (rhs.holder, rhs.nextProperty)
		}
	}

	/// Each case some place's path produces.
	private(set) var producedCases: Set<ProducedCase>
	/// The fields of each level that its type binds, as source, from the first place whose path holds it: every build of a
	/// type binds the same (`placeLevelsDifferBetweenBuildsOfType` judges that), a builder function's cycle parameters aside
	/// (`SeamPlaceLevels.Level.fieldsOfType`).
	private(set) var levelFields: [LevelKey: [String]]
	/// The labels each holder declares, on any path: its forwarded properties and its children, and the seam root's
	/// parameters. A case of a holder's enum is named for one of them.
	private(set) var declaredLabels: [Holder: Set<String>]
	/// A description of each place whose path repeats a declaration, in the order the run computed them. The tree closes
	/// a cycle where its declaration is already being built above it, and a build that closes a cycle is the first
	/// build, so a scope value's chain never repeats a declaration (the design's second promise of section 2.4).
	private(set) var chainRepeats: [String]
	/// Whether some place of a seam's hole is inside a fill, which a call's case for the builder filled leads to, holding the
	/// inner seam's scope (the design's section 2.6), which the oracles that read the generated enums do not model yet.
	private(set) var holdsPlaceInsideFill: Bool

	/// These facts with the labels each seam that `sources` declare declares on its root: its parameters and its children,
	/// as its `@Received`, `@Forwarded` and `@Instantiated` properties name them. A seam whose every place an inner seam
	/// passes up has no levels of its own, so its root's labels come only from here, which its cases that wrap an inner
	/// seam's enum are named for.
	func addingSeamRootLabels(declaredIn sources: [String]) -> GraphFuzzerPlaceFacts {
		var facts = self
		for source in sources {
			let visitor = SeamRootLabelVisitor(viewMode: .sourceAccurate)
			visitor.walk(Parser.parse(source: source))
			for (seamType, labels) in visitor.labelsBySeamType {
				facts.declaredLabels[Holder(seamType: seamType, typeName: seamType, isSeamRoot: true), default: []].formUnion(labels)
			}
		}
		return facts
	}

	/// A description of each way the facts of a graph with a second path to a type that holds a place, `self`, differ from
	/// those of the graph without it, `withoutSecondPath`, beyond the one level the second path's property adds: its own,
	/// on `typeName`, labeled `label`. A second path to a shared type adds no level and changes no field of one, since a
	/// level is a fact of the type that binds it (the design's section 2.10).
	func secondPathLevelChanges(comparedWith withoutSecondPath: GraphFuzzerPlaceFacts, typeName: String, label: String) -> [String] {
		var changes = [String]()
		for (key, fields) in withoutSecondPath.levelFields.sorted(by: { $0.key < $1.key }) {
			if let fieldsWithPath = levelFields[key] {
				if fieldsWithPath != fields {
					changes.append("The level of `\(key.holder.typeName)` before `\(key.nextProperty)` holds \(Self.listDescription(of: fields)) without the second path and \(Self.listDescription(of: fieldsWithPath)) with it.")
				}
			} else {
				changes.append("The level of `\(key.holder.typeName)` before `\(key.nextProperty)` is gone with the second path.")
			}
		}
		let addedKeys = levelFields.keys.filter { withoutSecondPath.levelFields[$0] == nil }
		for key in addedKeys.sorted() where key.holder.typeName != typeName || String(key.nextProperty.prefix(while: { $0 != ":" })) != label {
			changes.append("The second path adds the level of `\(key.holder.typeName)` before `\(key.nextProperty)`.")
		}
		return changes
	}

	private static func listDescription(of fields: [String]) -> String {
		"[" + fields.joined(separator: ", ") + "]"
	}

	/// `property` as the cycle check keys it: a lazily instantiated wrapper as the instance it stands for, optional when
	/// the wrapper is.
	private static func cycleSpelling(of property: Property) -> String {
		func instanceType(of type: TypeDescription) -> TypeDescription? {
			switch type {
			case let .simple(name, generics):
				if let instance = generics.first, name == "LazilyInstantiated" || name == "SendableLazilyInstantiated" {
					instance
				} else {
					nil
				}
			case let .optional(wrapped), let .implicitlyUnwrappedOptional(wrapped):
				instanceType(of: wrapped).map { .optional($0) }
			case .any, .array, .attributed, .closure, .composition, .dictionary, .metatype, .nested, .some, .tuple, .unknown, .variadic, .void:
				nil
			}
		}
		return "\(property.label): \((instanceType(of: property.typeDescription) ?? property.typeDescription).asSource)"
	}
}

/// The labels of the properties SafeDI reads on each type a source declares with `generateDependencyTree: true`, by the
/// type's name.
private final class SeamRootLabelVisitor: SyntaxVisitor {
	private(set) var labelsBySeamType = [String: Set<String>]()

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		record(name: node.name.text, attributes: node.attributes, members: node.memberBlock)
		return .visitChildren
	}

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		record(name: node.name.text, attributes: node.attributes, members: node.memberBlock)
		return .visitChildren
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		record(name: node.name.text, attributes: node.attributes, members: node.memberBlock)
		return .visitChildren
	}

	private func record(name: String, attributes: AttributeListSyntax, members: MemberBlockSyntax) {
		guard attributes.trimmedDescription.contains("generateDependencyTree: true") else { return }
		var labels = Set<String>()
		for member in members.members {
			guard let variable = member.decl.as(VariableDeclSyntax.self),
			      variable.attributes.contains(where: { attribute in
			      	guard let attribute = attribute.as(AttributeSyntax.self) else { return false }
			      	return ["Instantiated", "Received", "Forwarded"].contains(attribute.attributeName.trimmedDescription)
			      })
			else { continue }
			for binding in variable.bindings {
				if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
					labels.insert(identifier.identifier.text)
				}
			}
		}
		labelsBySeamType[name, default: []].formUnion(labels)
	}
}

/// What `operation` returns, with the facts of the places of every seam's holes the tool computes while it runs, in the
/// order the tool first computes them (`GraphFuzzerPlaceFacts.init(placeLevels:)`).
func collectingPlaceFacts<Result>(during operation: () async throws -> Result) async rethrows -> (result: Result, facts: GraphFuzzerPlaceFacts) {
	let (stream, continuation) = AsyncStream.makeStream(of: SeamPlaceLevels.self)
	let enclosingObserver = SeamPlaceLevels.observer
	let result = try await SeamPlaceLevels.$observer.withValue({ placeLevels in
		continuation.yield(placeLevels)
		enclosingObserver?(placeLevels)
	}) {
		try await operation()
	}
	continuation.finish()
	var placeLevels = [SeamPlaceLevels]()
	for await computation in stream {
		placeLevels.append(computation)
	}
	return (result, GraphFuzzerPlaceFacts(placeLevels: placeLevels))
}
