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

/// The builder surface: what a person writes against a seam's readable initializers and a `mock()`. A parameter of
/// either may name no type SafeDI generates – a scope enum, a scope's `_Values` struct, or a generated builder struct –
/// since a person's builder is to take only what its place forwards ("Builders a person writes" in
/// `.claude/rules/seam-and-mock-contract.md`), and every builder the fuzzer writes by hand must be such a builder.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerBuilderSurface {
	/// A parameter of a readable initializer or of a `mock()` that names a generated type, or a hand-written builder
	/// that takes a scope.
	struct Finding: Equatable, CustomStringConvertible {
		/// Where: `S1_Feature.init(…)` with the tier's access, `S1_Feature.mock(…)`, or the hand-written call.
		let declaration: String
		/// The parameter or builder as written.
		let parameter: String
		/// The generated type it names, or why a hand-written builder fails.
		let reason: String

		var description: String {
			"\(declaration) takes `\(parameter)`, which \(reason)"
		}
	}

	/// The generated type `parameter`'s type names, or `nil` for one that names none: a scope enum
	/// (`SafeDIScope_…`, `SafeDISendableScope_…`, `SafeDIMockScope_…`, `SafeDISendableMockScope_…`), a scope's
	/// `…_Values` struct, or a generated builder struct (`__safeDI_Builder…`).
	static func generatedTypeNamed(by parameter: String) -> String? {
		guard let colon = parameter.firstIndex(of: ":") else { return nil }
		let type = String(parameter[parameter.index(after: colon)...])
		for pattern in [#"SafeDI\w*Scope_\w*"#, #"\w+_Values\b"#, #"__safeDI_Builder\w*"#] {
			if let range = type.range(of: pattern, options: .regularExpression) {
				return String(type[range])
			}
		}
		return nil
	}

	/// Each parameter of a seam's readable initializer, every tier, in `generatedFiles` that names a generated type.
	/// Files the oracle adds (the hand-written seam and public mock callers) are not generated, and are not read.
	static func readableInitializerFindings(in generatedFiles: [String: String]) -> [Finding] {
		var findings = [Finding]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where isGenerated(fileName) {
			for initializer in GraphFuzzerOracle.seamInitializers(inGeneratedFile: contents) {
				for parameter in initializer.parameters {
					guard let generatedType = generatedTypeNamed(by: parameter) else { continue }
					findings.append(Finding(
						declaration: "\(fileName): \(initializer.access) \(initializer.seamTypeName).init(…)",
						parameter: parameter,
						reason: "names the generated type `\(generatedType)`",
					))
				}
			}
		}
		return findings
	}

	/// Each parameter of a generated `mock()` in `generatedFiles` that names a generated type.
	static func mockFindings(in generatedFiles: [String: String]) -> [Finding] {
		var findings = [Finding]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where isGenerated(fileName) {
			var extendedType: String?
			var mockedType: String?
			for line in contents.components(separatedBy: "\n") {
				if line.hasPrefix("extension "), line.hasSuffix(" {") {
					extendedType = String(line.dropFirst("extension ".count).dropLast(2))
				} else if mockedType == nil, line.hasSuffix("static func mock(") {
					mockedType = extendedType ?? "(unknown)"
				} else if let currentMockedType = mockedType {
					let trimmed = line.trimmingCharacters(in: .whitespaces)
					if trimmed.hasPrefix(")") {
						mockedType = nil
					} else if let generatedType = generatedTypeNamed(by: trimmed) {
						findings.append(Finding(
							declaration: "\(fileName): \(currentMockedType).mock(…)",
							parameter: trimmed.hasSuffix(",") ? String(trimmed.dropLast()) : trimmed,
							reason: "names the generated type `\(generatedType)`",
						))
					}
				}
			}
		}
		return findings
	}

	/// Each builder the fixture writes by hand – a public mock caller's (`GraphFuzzerPublicMockDraw.publicMockCallerMarker`)
	/// – that takes a scope: a closure that names a parameter, `{ _ in … }`, for a place that forwards nothing.
	static func handWrittenBuilderFindings(in fixture: GraphFuzzerFixture) -> [Finding] {
		var findings = [Finding]()
		for content in fixture.swiftFileContent {
			for line in content.split(separator: "\n") where line.hasPrefix(GraphFuzzerPublicMockDraw.publicMockCallerMarker) {
				let call = String(line.dropFirst(GraphFuzzerPublicMockDraw.publicMockCallerMarker.count))
				guard let range = call.range(of: #"\w+: \{ _ in "#, options: .regularExpression) else { continue }
				findings.append(Finding(
					declaration: "the hand-written call `\(call)`",
					parameter: String(call[range]).trimmingCharacters(in: .whitespaces),
					reason: "takes a scope its place does not forward",
				))
			}
		}
		return findings
	}

	/// Whether the tool generated `fileName`, rather than the oracle adding it as a hand-written caller.
	private static func isGenerated(_ fileName: String) -> Bool {
		!fileName.hasSuffix("+SafeDISeamCaller.swift") && !fileName.hasSuffix(GraphFuzzerOracle.publicMockCallerFileSuffix)
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph the tool accepts whose seams' readable initializers or generated mocks take a parameter
	/// that names a type SafeDI generates, or whose hand-written builders take a scope
	/// (`GraphFuzzerBuilderSurface`), or `nil`.
	var builderSurfaceFailure: GraphFuzzerFailure? {
		guard case let .accepted(generatedFiles, _) = firstOutcome else { return nil }
		let findings = GraphFuzzerBuilderSurface.readableInitializerFindings(in: generatedFiles)
			+ GraphFuzzerBuilderSurface.mockFindings(in: generatedFiles)
			+ GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: fixture)
		guard !findings.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .builderSurfaceNamesGeneratedType,
			details: "\(findings.map(\.description).joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)",
		)
	}
}

extension GraphFuzzerKnownIssue {
	/// `issues` with a shape of the builder surface added for `seeds`, each seed still listed once: an entry's seeds that
	/// also show the shape move to an entry of their own, with `reason` and `signature` added to the entry's, and the seeds
	/// no entry lists form an entry of the shape alone. The planned builder structs empty `seeds`, which then changes
	/// nothing.
	static func adding(_ signature: Signature, reason: String, seeds: [UInt64], to issues: [GraphFuzzerKnownIssue]) -> [GraphFuzzerKnownIssue] {
		let shapeSeeds = Set(seeds)
		var listedSeeds = Set<UInt64>()
		var result = [GraphFuzzerKnownIssue]()
		for issue in issues {
			let otherSeeds = issue.seeds.filter { !shapeSeeds.contains($0) }
			let sharedSeeds = issue.seeds.filter(shapeSeeds.contains)
			listedSeeds.formUnion(issue.seeds)
			if !otherSeeds.isEmpty {
				result.append(GraphFuzzerKnownIssue(reason: issue.reason, signatures: issue.signatures, seeds: otherSeeds))
			}
			if !sharedSeeds.isEmpty {
				result.append(GraphFuzzerKnownIssue(reason: "\(issue.reason); and \(reason)", signatures: issue.signatures + [signature], seeds: sharedSeeds))
			}
		}
		let seedsAlone = seeds.filter { !listedSeeds.contains($0) }
		if !seedsAlone.isEmpty {
			result.append(GraphFuzzerKnownIssue(reason: reason, signatures: [signature], seeds: seedsAlone))
		}
		return result
	}
}

// MARK: - The surface a call is judged against

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerBuilderSurface {
	/// A parameter of a readable initializer or a `mock()`, as the generated code spells it.
	struct Parameter: Equatable {
		let label: String
		let type: String
		let hasDefault: Bool

		init(_ text: String) {
			let trimmed = text.trimmingCharacters(in: .whitespaces)
			let colon = trimmed.firstIndex(of: ":") ?? trimmed.endIndex
			label = String(trimmed[..<colon])
			var type = colon == trimmed.endIndex ? "" : String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
			hasDefault = type.contains(" = ")
			if let defaultStart = type.range(of: " = ") {
				type = String(type[..<defaultStart.lowerBound])
			}
			self.type = type
		}

		var description: String {
			"\(label): \(type)"
		}
	}

	/// A readable initializer tier or a `mock()` tier, keyed by its module, its type and its access, which an edit that
	/// keeps the supply keeps.
	struct Callable: Equatable {
		let key: String
		let parameters: [Parameter]
	}

	/// The readable initializers and mocks of `generatedFiles`, each tier keyed apart, in key order.
	static func callables(in generatedFiles: [String: String]) -> [Callable] {
		var callables = [Callable]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where isGenerated(fileName) {
			let module = fileName.contains("/") ? String(fileName.prefix { $0 != "/" }) : ""
			for initializer in GraphFuzzerOracle.seamInitializers(inGeneratedFile: contents) {
				callables.append(Callable(key: "\(module) \(initializer.access) \(initializer.seamTypeName).init", parameters: initializer.parameters.map(Parameter.init)))
			}
			var extendedType: String?
			var mock: (key: String, parameters: [Parameter])?
			for line in contents.components(separatedBy: "\n") {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				if line.hasPrefix("extension "), line.hasSuffix(" {") {
					extendedType = String(line.dropFirst("extension ".count).dropLast(2))
				} else if mock == nil, trimmed.hasSuffix("static func mock(") {
					let access = ["public", "package"].first { trimmed.hasPrefix($0 + " ") || trimmed.contains(" \($0) ") } ?? "internal"
					mock = ("\(module) \(access) \(extendedType ?? "(unknown)").mock", [])
				} else if let current = mock {
					if trimmed.hasPrefix(")") {
						callables.append(Callable(key: current.key, parameters: current.parameters))
						mock = nil
					} else {
						mock = (current.key, current.parameters + [Parameter(trimmed.hasSuffix(",") ? String(trimmed.dropLast()) : trimmed)])
					}
				}
			}
		}
		return callables.sorted { $0.key < $1.key }
	}

	/// Whether `parameter` takes a hole's builder: on main, a closure handed a scope enum; once builders take no scope, a
	/// parameter whose label ends with `Builder` (or a `Builder_<Type>` a calling mock names apart) and whose type is a
	/// closure or a wrapper's `Builder`. The builder-struct work replaces this with what its generated code spells.
	static func isBuilder(_ parameter: Parameter) -> Bool {
		if generatedTypeNamed(by: parameter.description) != nil {
			return true
		}
		let labelNamesBuilder = parameter.label.hasSuffix("Builder") || parameter.label.contains("Builder_")
		return labelNamesBuilder && (parameter.type.contains(") -> ") || parameter.type.hasSuffix(".Builder"))
	}

	/// What a hand-written builder is for: the type that fills its places, the type it returns, and whether its places are
	/// built in `@Sendable` functions.
	struct BuilderFacts: Equatable {
		let fillingType: String
		let returnedType: String
		let isSendable: Bool
		/// The label the surface gives a builder that takes no scope, which then follows the contract; `nil` for a builder
		/// handed a scope, whose label the contract renames.
		var surfaceLabel: String?

		/// The label contract rule 8 gives the builder: `<fillingType>Builder` when the filling type is the returned type,
		/// else `<fillingType>_<ReturnedType>Builder`, the filling type's leading capitals lowered as SafeDI lowers them;
		/// a `@Sendable` builder's label says `Sendable` before `Builder`, as SafeDI's does today, since the rule does not
		/// say how the two families of one filling type are told apart.
		var contractLabel: String {
			if let surfaceLabel {
				return surfaceLabel
			}
			let stem = String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: fillingType).dropLast("Builder".count))
			let returnedName = Self.typeName(returnedType)
			return stem + (returnedName == fillingType ? "" : "_\(returnedName)") + (isSendable ? "Sendable" : "") + "Builder"
		}

		/// `type` without `any ` or `some `.
		static func typeName(_ type: String) -> String {
			for prefix in ["any ", "some "] where type.hasPrefix(prefix) {
				return String(type.dropFirst(prefix.count))
			}
			return type
		}
	}

	/// The facts of a builder parameter, read from its type: what it returns after its last `-> `, whether it is
	/// `@Sendable`, and, on main, the filling type its scope enum is named after (`SafeDI…Scope_<FillingType>` or
	/// `SafeDI…Scope_<FillingType>_<ReturnedType>`); once builders take no scope, the label is the surface's own, which then
	/// follows the contract, and a closure builds the returned type.
	static func builderFacts(of parameter: Parameter) -> BuilderFacts? {
		guard let arrow = parameter.type.range(of: ") -> ", options: .backwards) else { return nil }
		let returnedType = String(parameter.type[arrow.upperBound...])
		let isSendable = parameter.type.contains("@Sendable")
		let returnedName = BuilderFacts.typeName(returnedType)
		if let scopeRange = parameter.type.range(of: #"SafeDI\w*Scope_\w+"#, options: .regularExpression) {
			let scope = String(parameter.type[scopeRange])
			var core = scope.components(separatedBy: "Scope_").dropFirst().joined(separator: "Scope_")
			if core.hasSuffix("_" + returnedName) {
				core = String(core.dropLast(returnedName.count + 1))
			}
			return BuilderFacts(fillingType: core, returnedType: returnedType, isSendable: isSendable)
		}
		return BuilderFacts(fillingType: returnedName, returnedType: returnedType, isSendable: isSendable, surfaceLabel: parameter.label)
	}
}

// MARK: - The call a person writes

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerBuilderSurface {
	/// How a person writes a builder, as the Manual teaches: a closure that builds the value, `{ X() }`; the filling type's
	/// initializer, `X.init`; or a closure value stored with the parameter's own type, `() -> X`.
	enum BuilderForm: String, CaseIterable, Equatable {
		case closure
		case initializerReference
		case storedClosure
	}

	/// One argument of a call `C`: a value of exactly the type the drawn graph's surface takes, or a builder written in
	/// one of the Manual's forms.
	enum Argument: Equatable {
		case value(label: String, type: String)
		case builder(label: String, facts: BuilderFacts, form: BuilderForm)

		var label: String {
			switch self {
			case let .value(label, _), let .builder(label, _, _):
				label
			}
		}

		var description: String {
			switch self {
			case let .value(label, type):
				"\(label): <\(type)>"
			case let .builder(label, facts, form):
				switch form {
				case .closure:
					"\(label): { \(facts.fillingType)() }"
				case .initializerReference:
					"\(label): \(facts.fillingType).init"
				case .storedClosure:
					"\(label): <\(facts.isSendable ? "@Sendable " : "")() -> \(facts.returnedType)>"
				}
			}
		}
	}

	/// A call of one readable initializer tier or `mock()` tier.
	struct Call: Equatable {
		let key: String
		let arguments: [Argument]

		var description: String {
			"\(key)(\(arguments.map(\.description).joined(separator: ", ")))"
		}
	}

	/// The calls `C` a person writes against `callables`, the drawn graph's surface: for every callable, a required argument
	/// per parameter without a default, and one builder in the contract's label per builder parameter, in a form chosen by
	/// `seed` and the builder's position, so that the corpus writes every form. No `SafeDIOverrides`.
	static func calls(against callables: [Callable], seed: UInt64) -> [Call] {
		var builderIndex = Int(seed % UInt64(BuilderForm.allCases.count))
		return callables.map { callable in
			Call(key: callable.key, arguments: callable.parameters.compactMap { parameter -> Argument? in
				if isBuilder(parameter), let facts = builderFacts(of: parameter) {
					defer { builderIndex += 1 }
					return .builder(label: facts.contractLabel, facts: facts, form: BuilderForm.allCases[builderIndex % BuilderForm.allCases.count])
				}
				return parameter.hasDefault ? nil : .value(label: parameter.label, type: parameter.type)
			})
		}
	}

	/// Whether a parameter of type `parameterType` takes a builder for `facts` written in `form`: the one place that says
	/// which forms each parameter type accepts, by the type clause of contract rule 8. A place that forwards nothing takes
	/// `() -> B`, `Instantiator<T>.Builder`, `ErasedInstantiator<(), B>.Builder` or a `Sendable` twin, each of which takes
	/// every form; a `@Sendable` parameter takes a stored closure only when it is `@Sendable` too; a closure handed a scope
	/// takes none. The builder-struct work can back this with a compile of the call.
	static func accepts(parameterType: String, facts: BuilderFacts, form: BuilderForm) -> Bool {
		var type = parameterType
		for attribute in ["@escaping ", "@Sendable "] {
			type = type.replacingOccurrences(of: attribute, with: "")
		}
		guard generatedTypeNamed(by: "_: " + type) == nil else { return false }
		let isSendable = parameterType.contains("@Sendable") || type.hasPrefix("Sendable")
		if form == .storedClosure, isSendable != facts.isSendable {
			return false
		}
		let returnedName = BuilderFacts.typeName(facts.returnedType)
		if type.hasPrefix("() -> ") {
			return BuilderFacts.typeName(String(type.dropFirst("() -> ".count))) == returnedName
		}
		guard type.hasSuffix(".Builder"), let open = type.firstIndex(of: "<") else { return false }
		let wrapper = String(type[..<open])
		let arguments = GraphFuzzerOracle.topLevelParameters(String(type[type.index(after: open)..<type.index(type.endIndex, offsetBy: -".Builder".count - 1)]))
			.map { $0.trimmingCharacters(in: .whitespaces) }
		switch wrapper {
		case "Instantiator", "SendableInstantiator":
			return arguments.count == 1 && BuilderFacts.typeName(arguments[0]) == returnedName
		case "ErasedInstantiator", "SendableErasedInstantiator":
			let forwardsNothing = arguments.first.map { ["()", "Void"].contains($0) || $0.hasSuffix(".ForwardedProperties") } ?? false
			return arguments.count == 2 && forwardsNothing && BuilderFacts.typeName(arguments[1]) == returnedName
		default:
			return false
		}
	}

	/// Why `call` would not compile against `callables`, one line per problem, or nothing when every argument meets a
	/// parameter of its label, in order, that takes it, and every parameter it skips has a default. Each line names the
	/// callable and the argument, never a file, so the problems of two graphs compare.
	static func problems(of call: Call, against callables: [Callable]) -> [String] {
		guard let callable = callables.first(where: { $0.key == call.key }) else {
			return ["\(call.key) is gone"]
		}
		var problems = [String]()
		var remaining = callable.parameters[...]
		for argument in call.arguments {
			guard let index = remaining.firstIndex(where: { $0.label == argument.label }) else {
				problems.append("\(call.key) takes no `\(argument.label)` after the arguments before it")
				continue
			}
			for skipped in remaining[..<index] where !skipped.hasDefault {
				problems.append("\(call.key) requires `\(skipped.description)`, which the call does not pass")
			}
			let parameter = remaining[index]
			remaining = remaining[(index + 1)...]
			switch argument {
			case let .value(_, type) where type != parameter.type:
				problems.append("\(call.key) takes `\(parameter.description)` where the call passes a `\(type)`")
			case let .builder(_, facts, form) where !accepts(parameterType: parameter.type, facts: facts, form: form):
				problems.append("\(call.key) takes `\(parameter.description)`, which does not accept \(argument.description)")
			case .value, .builder:
				break
			}
		}
		for skipped in remaining where !skipped.hasDefault {
			problems.append("\(call.key) requires `\(skipped.description)`, which the call does not pass")
		}
		return problems
	}
}

// MARK: - Edited graphs

/// One edit of a drawn graph with a hole, made after every other draw so that the rest of the graph is drawn as before
/// (`GraphFuzzerGenerator.fixture(forSeed:features:builderSurfaceEdit:)`).
enum GraphFuzzerBuilderSurfaceEdit: String, CaseIterable, Comparable {
	/// Same supply: a second place of an existing builder, in another type of the seam's tree (`HoleSurfaceExtra`, a copy
	/// of the type that holds the hole, built as that type is).
	case secondPlaceInAnotherType
	/// Same supply: a plain place moved behind `LazilyInstantiated`, or a lazy place moved back.
	case placeBehindLazilyInstantiated
	/// Same supply: `Instantiator<Hole>`, whose `Hole` forwards nothing, moved to a plain place.
	case instantiatorPlaceMovedToPlainPlace
	/// Same supply: `Instantiator<Hole>` changed to `ErasedInstantiator<Hole.ForwardedProperties, Hole>` with
	/// `fulfilledByType: "Hole"`.
	case instantiatorChangedToErasedInstantiator
	/// Added supply: a place of a new builder whose filling type is an existing builder's, returning another type.
	case placeOfNewBuilderOfExistingFillingType
	/// Rejection: a place of an existing builder that forwards other values (`ErasedInstantiator<Int, …>`).
	case placeForwardingOtherValues
	/// The rejection's remedy: the same place forwarding what the existing places forward (`ErasedInstantiator<(), …>`).
	case placeForwardingOtherValuesRemedied

	/// The edits that keep every (filling type, returned type, family, forwarded values), against whose graphs the drawn
	/// graph's call must still compile.
	static let sameSupply: [GraphFuzzerBuilderSurfaceEdit] = [.secondPlaceInAnotherType, .placeBehindLazilyInstantiated, .instantiatorPlaceMovedToPlainPlace, .instantiatorChangedToErasedInstantiator]

	static func < (lhs: GraphFuzzerBuilderSurfaceEdit, rhs: GraphFuzzerBuilderSurfaceEdit) -> Bool {
		allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
	}
}

extension GraphFuzzerGenerator {
	/// The graph for `seed` and `features` with `edit` applied after every draw, or `nil` when the edit does not apply to
	/// the graph (it has no place the edit changes).
	static func fixture(forSeed seed: UInt64, features: Set<GraphFuzzerGeneratorFeature>, builderSurfaceEdit edit: GraphFuzzerBuilderSurfaceEdit) -> GraphFuzzerFixture? {
		guard !features.contains(.generateMockPublic) else {
			let draw = GraphFuzzerPublicMockDraw(seed: seed, builderSurfaceEdit: edit)
			return draw.appliesBuilderSurfaceEdit ? GraphFuzzerFixture(seed: seed, swiftFileContent: draw.swiftFileContent(storingEveryParameter: false, isKnownRight: false)) : nil
		}
		guard features.contains(.generateDependencyTree) else { return nil }
		var builder = Builder(seed: seed, features: features, storesEveryParameter: false)
		builder.builderSurfaceEdit = edit
		let swiftFileContent = builder.build()
		return builder.appliesBuilderSurfaceEdit ? GraphFuzzerFixture(seed: seed, swiftFileContent: swiftFileContent) : nil
	}

	/// `declarations`, a seam corpus graph's after every draw, with `edit` applied to `HoleSeam`'s hole, `holeService`, or
	/// `nil` when the edit does not apply to it.
	static func applying(_ edit: GraphFuzzerBuilderSurfaceEdit, to declarations: [TypeDeclaration], prefix: String, isSendableGraph: Bool) -> [TypeDeclaration]? {
		let serviceType = "any \(prefix)HoleService"
		guard let holderIndex = declarations.firstIndex(where: { declaration in
			declaration.module == .seamModule && declaration.properties.contains { $0.label == "holeService" && $0.type == serviceType }
		}) else { return nil }
		var declarations = declarations
		let holder = declarations[holderIndex]
		switch edit {
		case .secondPlaceInAnotherType:
			let seamName = "\(prefix)HoleSeam"
			guard let seamIndex = declarations.firstIndex(where: { $0.name == seamName }) else { return nil }
			let extraName = "\(prefix)HoleSurfaceExtra"
			var extra = TypeDeclaration(name: extraName, instantiableArguments: [], properties: [], declaresHelperTypes: false)
			extra.module = .seamModule
			if holder.name == seamName {
				// The seam holds the hole: the extra type, built by value at the seam's root as the hole is, holds a place of it.
				extra.properties = [PropertyDeclaration(attribute: "@Instantiated", label: "holeService", type: serviceType)]
				guard let holeIndex = declarations[seamIndex].properties.firstIndex(where: { $0.label == "holeService" }) else { return nil }
				declarations[seamIndex].properties.insert(PropertyDeclaration(attribute: "@Instantiated", label: "holeSurfaceExtra", type: extraName), at: holeIndex + 1)
			} else {
				// The owner holds the hole: the extra type is a copy of it, which the seam builds as it builds the owner, so its
				// places are built in the same family and see what the owner's do.
				extra.properties = holder.properties
				extra.access = holder.access
				extra.initializerAccess = holder.initializerAccess
				guard let ownerIndex = declarations[seamIndex].properties.firstIndex(where: { $0.type.contains(holder.name) }) else { return nil }
				let ownerProperty = declarations[seamIndex].properties[ownerIndex]
				declarations[seamIndex].properties.insert(PropertyDeclaration(
					attribute: ownerProperty.attribute,
					label: ownerProperty.label.replacingOccurrences(of: "holeOwner", with: "holeSurfaceExtra").replacingOccurrences(of: "holeSecondOwner", with: "holeSurfaceExtra"),
					type: ownerProperty.type.replacingOccurrences(of: holder.name, with: extraName),
				), at: ownerIndex + 1)
			}
			declarations.insert(extra, at: holderIndex + 1)
		case .placeBehindLazilyInstantiated:
			// A `LazilyInstantiated` is not `Sendable`, so a graph whose types all are holds none; and a
			// `SendableLazilyInstantiated` place is built in a `@Sendable` function, which is another family.
			guard !isSendableGraph else { return nil }
			if let lazyIndex = holder.properties.firstIndex(where: { $0.label == "holeServiceLazy" && $0.type == "LazilyInstantiated<\(serviceType)>" }) {
				declarations[holderIndex].properties[lazyIndex] = PropertyDeclaration(attribute: "@Instantiated", label: "holeServiceLazy", type: serviceType)
			} else if let holeIndex = holder.properties.firstIndex(where: { $0.label == "holeService" }) {
				declarations[holderIndex].properties[holeIndex] = PropertyDeclaration(attribute: "@Instantiated", label: "holeService", type: "LazilyInstantiated<\(serviceType)>")
			}
		case .placeForwardingOtherValues, .placeForwardingOtherValuesRemedied:
			let forwarded = edit == .placeForwardingOtherValues ? "Int" : "()"
			declarations[holderIndex].properties.append(PropertyDeclaration(
				attribute: "@Instantiated(fulfilledByType: \"\(prefix)HoleService\")",
				label: "holeServiceForwarding",
				type: "ErasedInstantiator<\(forwarded), \(serviceType)>",
			))
		case .instantiatorPlaceMovedToPlainPlace, .instantiatorChangedToErasedInstantiator, .placeOfNewBuilderOfExistingFillingType:
			// The seam corpus's holes are existentials, which no `Instantiator` wraps, and its colliding erasures already
			// draw a new builder of an existing filling type (`holeGadgetOther`, read as a pair from the graph without it).
			return nil
		}
		return declarations
	}
}

// MARK: - The checks of edited graphs

/// The tool's outcome for a graph with one builder surface edit (`GraphFuzzerGenerator.fixture(forSeed:features:builderSurfaceEdit:)`).
struct GraphFuzzerBuilderSurfaceRun {
	let edit: GraphFuzzerBuilderSurfaceEdit
	let fixture: GraphFuzzerFixture
	let outcome: GraphFuzzerToolOutcome
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerBuilderSurface {
	/// What one pair of a drawn graph and an edited graph shows: whether both were accepted, so the pair counts toward
	/// its edit kind's floor, and the problems the pair adds, empty when it passes.
	struct PairJudgment: Equatable {
		let isJudged: Bool
		let problems: [String]
	}

	/// Part (i), same supply: the calls `C` written against `drawn` must compile against `edited` as they compile against
	/// `drawn`, judged by `problems(of:against:)`: a problem `C` has against `edited` and not against `drawn` fails. On
	/// main every builder takes a scope, so `C` fails against both for the base check's reason, and nothing else shows.
	static func sameSupplyJudgment(drawn: GraphFuzzerToolOutcome, edited: GraphFuzzerToolOutcome, seed: UInt64) -> PairJudgment {
		guard case let .accepted(drawnFiles, _) = drawn, case let .accepted(editedFiles, _) = edited else {
			return PairJudgment(isJudged: false, problems: [])
		}
		let drawnCallables = callables(in: drawnFiles)
		let editedCallables = callables(in: editedFiles)
		var added = [String]()
		for call in calls(against: drawnCallables, seed: seed) {
			let drawnProblems = Set(problems(of: call, against: drawnCallables))
			added += problems(of: call, against: editedCallables).filter { !drawnProblems.contains($0) }.map { "\($0), in \(call.description)" }
		}
		return PairJudgment(isJudged: true, problems: added)
	}

	/// Parts (ii) and (iv), added supply: every builder parameter of `without`, the graph without the added places, keeps its
	/// label and type, in its order among the other builders, in `with`, so that a call with only the new builders' arguments
	/// added still compiles; `keys` limits the callables judged (a calling mock's, for part (iv)).
	static func addedSupplyJudgment(without: GraphFuzzerToolOutcome, with: GraphFuzzerToolOutcome, judging isJudgedKey: (String) -> Bool = { _ in true }) -> PairJudgment {
		guard case let .accepted(withoutFiles, _) = without, case let .accepted(withFiles, _) = with else {
			return PairJudgment(isJudged: false, problems: [])
		}
		let withCallables = callables(in: withFiles)
		var problems = [String]()
		for callable in callables(in: withoutFiles) where isJudgedKey(callable.key) {
			let builders = callable.parameters.filter(isBuilder)
			guard !builders.isEmpty else { continue }
			guard let withCallable = withCallables.first(where: { $0.key == callable.key }) else {
				problems.append("\(callable.key) is gone")
				continue
			}
			let withBuilders = withCallable.parameters.filter(isBuilder)
			for builder in builders where !withBuilders.contains(builder) {
				problems.append("\(callable.key) no longer takes `\(builder.description)`; its builders are now \(withBuilders.map { "`\($0.label)`" }.joined(separator: ", "))")
			}
			let keptInOrder = withBuilders.filter(builders.contains)
			if keptInOrder.count == builders.count, keptInOrder != builders {
				problems.append("\(callable.key) takes its builders in another order: \(keptInOrder.map { "`\($0.label)`" }.joined(separator: ", "))")
			}
		}
		return PairJudgment(isJudged: true, problems: problems)
	}

	/// Part (iii): a graph whose builder's places forward other values must be rejected by the module that builds the places,
	/// with an error there, and the same graph with the remedy applied must be accepted. `nil` when the graph has no pair.
	static func rejectionJudgment(unremedied: GraphFuzzerToolOutcome, remedied: GraphFuzzerToolOutcome, declaringModule: GraphFuzzerModule) -> PairJudgment {
		var problems = [String]()
		switch unremedied {
		case .accepted:
			problems.append("The tool accepts a builder whose places forward other values")
		case let .rejected(diagnostics):
			let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error: ") }
			if !errors.contains(where: { $0.contains("/\(declaringModule.name)/") }) {
				problems.append("The tool rejects a builder whose places forward other values only outside \(declaringModule.name), where they meet:\n\(errors.joined(separator: "\n"))")
			}
		}
		if case let .rejected(diagnostics) = remedied {
			problems.append("The tool rejects the remedied graph, whose places forward the same values:\n\(diagnostics)")
		}
		return PairJudgment(isJudged: true, problems: problems)
	}
}

// MARK: - The parts' failures

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The judged pairs of each part: each edit kind's, the second-place pairs of part (ii) (`holeGadgetOther`, a new
	/// builder of an existing filling type) and of part (iv) (a second call of a public mock, `t6Twin` or `t6Second`), each
	/// counted toward its kind's floor whether it passes or fails, as a compile of the call would count it.
	var builderSurfaceJudgments: [(kind: String, judgment: GraphFuzzerBuilderSurface.PairJudgment)] {
		var judgments = [(kind: String, judgment: GraphFuzzerBuilderSurface.PairJudgment)]()
		for run in builderSurfaceRuns {
			switch run.edit {
			case .secondPlaceInAnotherType, .placeBehindLazilyInstantiated, .instantiatorPlaceMovedToPlainPlace, .instantiatorChangedToErasedInstantiator:
				judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: firstOutcome, edited: run.outcome, seed: fixture.seed)))
			case .placeOfNewBuilderOfExistingFillingType:
				judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.addedSupplyJudgment(without: firstOutcome, with: run.outcome)))
			case .placeForwardingOtherValues:
				if let remedied = builderSurfaceRuns.first(where: { $0.edit == .placeForwardingOtherValuesRemedied }) {
					judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.rejectionJudgment(unremedied: run.outcome, remedied: remedied.outcome, declaringModule: .seamModule)))
				}
			case .placeForwardingOtherValuesRemedied:
				break
			}
		}
		if let withoutSecondHolePlaceOutcome {
			let isCallingMockPair = ["t6Twin", "t6Second"].contains(withoutSecondHolePlaceOutcome.place)
			if isCallingMockPair || withoutSecondHolePlaceOutcome.place == "holeGadgetOther" {
				let judgment = GraphFuzzerBuilderSurface.addedSupplyJudgment(without: withoutSecondHolePlaceOutcome.outcome, with: firstOutcome)
				judgments.append((isCallingMockPair ? Self.callingMockPairKind : Self.secondErasurePairKind, judgment))
			}
		}
		return judgments
	}

	/// The kind of a pair of part (ii) the seam corpus draws: `holeGadgetOther`, a second erasure of `HoleGadgetImpl`.
	static let secondErasurePairKind = "secondErasureOfFillingType"
	/// The kind of a pair of part (iv): a second call of a public mock of the hole's type.
	static let callingMockPairKind = "secondCallOfPublicMock"

	/// Part (i)'s failure, or `nil`.
	var sameSupplyFailure: GraphFuzzerFailure? {
		failure(of: .sameSupplyCallStopsCompiling, kinds: GraphFuzzerBuilderSurfaceEdit.sameSupply.map(\.rawValue))
	}

	/// Part (ii)'s failure, or `nil`.
	var addedSupplyFailure: GraphFuzzerFailure? {
		failure(of: .addedBuilderChangesExistingBuilder, kinds: [GraphFuzzerBuilderSurfaceEdit.placeOfNewBuilderOfExistingFillingType.rawValue, Self.secondErasurePairKind])
	}

	/// Part (iii)'s failure, or `nil`.
	var forwardedValuesFailure: GraphFuzzerFailure? {
		failure(of: .placesForwardingOtherValuesAccepted, kinds: [GraphFuzzerBuilderSurfaceEdit.placeForwardingOtherValues.rawValue])
	}

	/// Part (iv)'s failure, or `nil`.
	var callingMockFailure: GraphFuzzerFailure? {
		failure(of: .callingMockChangesBuilder, kinds: [Self.callingMockPairKind])
	}

	private func failure(of failureKind: GraphFuzzerFailure.Kind, kinds: [String]) -> GraphFuzzerFailure? {
		let problems = builderSurfaceJudgments.filter { kinds.contains($0.kind) }.flatMap { judged in judged.judgment.problems.map { "\(judged.kind): \($0)" } }
		guard !problems.isEmpty else { return nil }
		return GraphFuzzerFailure(seed: fixture.seed, kind: failureKind, details: "\(problems.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)")
	}
}

// MARK: - Floors

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerBuilderSurface {
	/// Every kind the long run counts toward a floor, in report order: each hole kind the base check judges (`base-…`),
	/// then each edit's and second place's pair kind.
	static let floorKinds: [String] = HoleKind.allCases.map(\.floorKind)
		+ GraphFuzzerBuilderSurfaceEdit.allCases.filter { $0 != .placeForwardingOtherValuesRemedied }.map(\.rawValue)
		+ [GraphFuzzerToolRuns.secondErasurePairKind, GraphFuzzerToolRuns.callingMockPairKind]

	/// The kinds of hole whose builders the base check judges in a graph.
	enum HoleKind: String, CaseIterable {
		/// A builder of a place that is not inside a `@Sendable` function.
		case plain
		/// A place beneath a `LazilyInstantiated` or `SendableLazilyInstantiated`.
		case lazy
		/// A place whose wrapper forwards values to the builder.
		case forwarding
		/// A builder of a place inside a `@Sendable` function.
		case sendable

		var floorKind: String {
			"base-\(rawValue)"
		}
	}

	/// The kinds of hole whose builders the readable initializers and mocks of an accepted graph take, read from the
	/// builder parameters themselves (so the count does not depend on whether they fail) and, for the place's wrapper, from
	/// the fixture.
	static func holeKinds(of fixture: GraphFuzzerFixture, generatedFiles: [String: String]) -> [HoleKind] {
		let builders = callables(in: generatedFiles).flatMap(\.parameters).filter(isBuilder)
		guard !builders.isEmpty else { return [] }
		let source = fixture.swiftFileContent.joined(separator: "\n")
		var kinds = [HoleKind]()
		if builders.contains(where: { !$0.type.contains("@Sendable") }) {
			kinds.append(.plain)
		}
		if source.range(of: #"LazilyInstantiated<(any )?S\d+_\w*Hole\w*>"#, options: .regularExpression) != nil {
			kinds.append(.lazy)
		}
		if source.range(of: #"ErasedInstantiator<(Int|\w+\.ForwardedProperties), (any )?S\d+_\w*Hole\w*>"#, options: .regularExpression) != nil {
			kinds.append(.forwarding)
		}
		if builders.contains(where: { $0.type.contains("@Sendable") }) {
			kinds.append(.sendable)
		}
		return kinds
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The kinds this graph counts toward the builder surface's floors: each hole kind the base check judges, and each
	/// judged pair's kind. Every judged graph counts, whether it passes or fails.
	var builderSurfaceFloorKinds: [String] {
		guard case let .accepted(generatedFiles, _) = firstOutcome else { return [] }
		return GraphFuzzerBuilderSurface.holeKinds(of: fixture, generatedFiles: generatedFiles).map(\.floorKind)
			+ builderSurfaceJudgments.filter(\.judgment.isJudged).map(\.kind)
	}
}
