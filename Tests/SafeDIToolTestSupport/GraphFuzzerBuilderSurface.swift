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
	/// Files the oracle adds (the hand-written seam and public mock callers) are not generated, and are not read. The
	/// initializer read is each tier's one that only generated code calls (`GraphFuzzerOracle.seamInitializers`), read as
	/// the plain initializer spells its parameters: the fuzzer's graphs set no `generatePlainDependencyTreeInitializers`,
	/// so today that tier stands in for the plain readable initializer, whose parameters it shares. The leak-fix slice, in
	/// which the two diverge, must read the plain initializer itself.
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

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerBuilderSurface {
	/// Each builder parameter of a readable initializer or a `mock()` in `generatedFiles` whose label is not the one contract
	/// rule 8 gives it, read from the surface alone: `<fillingType>Builder` when its filling type is its returned type, else
	/// `<fillingType>_<ReturnedType>Builder`, the filling type's leading capitals lowered, with `Sendable` before `Builder`
	/// for a builder of the `@Sendable` family. A builder handed a scope names its filling type in the scope's name; one that
	/// takes no scope names only its returned type, so its label must name the returned type where the filling type is
	/// expected to be it, or after `_` where the label names another filling type.
	static func labelFindings(in generatedFiles: [String: String]) -> [Finding] {
		var findings = [Finding]()
		for callable in callables(in: generatedFiles) {
			for parameter in callable.parameters where isBuilder(parameter) {
				guard let facts = builderFacts(of: parameter) else { continue }
				let label = parameter.label.hasPrefix("__safeDI_") ? String(parameter.label.dropFirst("__safeDI_".count)) : parameter.label
				guard let expected = expectedLabel(of: label, facts: facts), expected != label else { continue }
				findings.append(Finding(declaration: callable.key, parameter: parameter.description, reason: "contract rule 8 labels `\(expected)`"))
			}
		}
		return findings
	}

	/// The label contract rule 8 gives a builder of `facts` labeled `label`, or `nil` when the label could be the contract's
	/// for some filling type the surface does not name.
	static func expectedLabel(of label: String, facts: BuilderFacts) -> String? {
		let suffix = facts.isSendable ? "SendableBuilder" : "Builder"
		let returnedName = BuilderFacts.typeName(facts.returnedType)
		let returnedStem = String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: returnedName).dropLast("Builder".count))
		guard facts.surfaceLabel != nil else {
			let fillingStem = String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: facts.fillingType).dropLast("Builder".count))
			return fillingStem + (facts.fillingType == returnedName ? "" : "_\(returnedName)") + suffix
		}
		// A builder that takes no scope: its filling type is its returned type, or another type its label names before
		// `_<ReturnedType>`.
		guard label.hasSuffix(suffix) else { return returnedStem + suffix }
		let stem = label.dropLast(suffix.count)
		if stem == returnedStem {
			return nil
		}
		let fillingStem = stem.hasSuffix("_" + returnedName) ? stem.dropLast(returnedName.count + 1) : ""
		return fillingStem.isEmpty || fillingStem == returnedStem ? returnedStem + suffix : nil
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph the tool accepts some builder of whose readable initializers or generated mocks is labeled
	/// otherwise than contract rule 8 says (`GraphFuzzerBuilderSurface.labelFindings(in:)`), or `nil`.
	var builderLabelFailure: GraphFuzzerFailure? {
		guard case let .accepted(generatedFiles, _) = firstOutcome else { return nil }
		let findings = GraphFuzzerBuilderSurface.labelFindings(in: generatedFiles)
		guard !findings.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .builderLabelBreaksContract,
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
		return labelNamesBuilder && (isFunctionType(parameter.type) || parameter.type.hasSuffix(".Builder"))
	}

	/// Whether `type`, its attributes aside, is a function type, `(…) -> R`, rather than a type that only holds one, such as
	/// an erased instantiator whose forwarded tuple holds a closure.
	static func isFunctionType(_ type: String) -> Bool {
		var remainder = Substring(type)
		while remainder.hasPrefix("@") {
			guard let space = remainder.firstIndex(of: " ") else { return false }
			remainder = remainder[remainder.index(after: space)...]
		}
		guard remainder.hasPrefix("(") else { return false }
		var depth = 0
		for index in remainder.indices {
			switch remainder[index] {
			case "(", "<", "[":
				depth += 1
			case ")", ">", "]":
				depth -= 1
				if depth == 0 {
					let rest = remainder[remainder.index(after: index)...]
					return rest.hasPrefix(" -> ") || rest.hasPrefix(" throws") || rest.hasPrefix(" async")
				}
			default:
				break
			}
		}
		return false
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
		/// What the builder's places forward, which a builder that takes no scope takes: `F` of `(F) -> B` or of a wrapper's
		/// `.Builder`; `nil` for a builder whose places forward nothing, or one handed a scope, which carries what they forward.
		var forwardedType: String?

		/// Whether the builder's places forward nothing: no forwarded type, or `<Returned>.ForwardedProperties`, the type an
		/// `Instantiator<T>.Builder` names whether or not `T` forwards anything, which the surface cannot tell apart.
		var forwardsNothing: Bool {
			forwardedType.map { Self.forwardsNothing($0, returnedType: returnedType) } ?? true
		}

		/// Whether `forwardedType` is `<returnedType>.ForwardedProperties`.
		static func forwardsNothing(_ forwardedType: String, returnedType: String) -> Bool {
			forwardedType == "\(typeName(returnedType)).ForwardedProperties"
		}

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

	/// The facts of a builder parameter, read from its type: what it returns, whether it is `@Sendable`, and, on main, the
	/// filling type its scope enum is named after (`SafeDI…Scope_<FillingType>` or `SafeDI…Scope_<FillingType>_<ReturnedType>`);
	/// once builders take no scope, the label is the surface's own, which then follows the contract, the filling type is the
	/// returned type, and what the places forward is the closure's parameter or the wrapper's first generic argument.
	static func builderFacts(of parameter: Parameter) -> BuilderFacts? {
		let isSendable = isSendableBuilderType(parameter.type)
		if let wrapperBuilder = wrapperBuilder(of: parameter.type) {
			return BuilderFacts(fillingType: BuilderFacts.typeName(wrapperBuilder.returnedType), returnedType: wrapperBuilder.returnedType, isSendable: isSendable, surfaceLabel: parameter.label, forwardedType: wrapperBuilder.forwardedType)
		}
		guard let arrow = parameter.type.range(of: ") -> ", options: .backwards) else { return nil }
		let returnedType = String(parameter.type[arrow.upperBound...])
		let returnedName = BuilderFacts.typeName(returnedType)
		if let scopeRange = parameter.type.range(of: #"SafeDI\w*Scope_\w+"#, options: .regularExpression) {
			let scope = String(parameter.type[scopeRange])
			var core = scope.components(separatedBy: "Scope_").dropFirst().joined(separator: "Scope_")
			if core.hasSuffix("_" + returnedName) {
				core = String(core.dropLast(returnedName.count + 1))
			}
			return BuilderFacts(fillingType: core, returnedType: returnedType, isSendable: isSendable)
		}
		let parameters = parameter.type[..<arrow.lowerBound].split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? ""
		return BuilderFacts(fillingType: returnedName, returnedType: returnedType, isSendable: isSendable, surfaceLabel: parameter.label, forwardedType: parameters.isEmpty ? nil : parameters)
	}

	/// The returned type and forwarded type of a wrapper's nested `Builder` (`Instantiator<T>.Builder` and its `Sendable` and
	/// erased forms), or `nil` for another type. An `Instantiator<T>`'s places forward `T.ForwardedProperties`, and an erased
	/// instantiator's its first generic argument, nothing where that is `()` or `Void`.
	static func wrapperBuilder(of type: String) -> (wrapper: String, returnedType: String, forwardedType: String?)? {
		var type = type
		for attribute in ["@escaping ", "@Sendable "] {
			type = type.replacingOccurrences(of: attribute, with: "")
		}
		guard type.hasSuffix(".Builder"), let open = type.firstIndex(of: "<") else { return nil }
		let wrapper = String(type[..<open])
		let arguments = GraphFuzzerOracle.topLevelParameters(String(type[type.index(after: open)..<type.index(type.endIndex, offsetBy: -".Builder".count - 1)]))
			.map { $0.trimmingCharacters(in: .whitespaces) }
		switch wrapper {
		case "Instantiator", "SendableInstantiator":
			guard arguments.count == 1 else { return nil }
			return (wrapper, arguments[0], "\(BuilderFacts.typeName(arguments[0])).ForwardedProperties")
		case "ErasedInstantiator", "SendableErasedInstantiator":
			guard arguments.count == 2 else { return nil }
			return (wrapper, arguments[1], ["()", "Void"].contains(arguments[0]) ? nil : arguments[0])
		default:
			return nil
		}
	}
}

// MARK: - The call a person writes

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerBuilderSurface {
	/// How a person writes a builder, as the Manual teaches: a closure that builds the value, `{ X() }`; the filling type's
	/// initializer, `X.init`; a closure value stored with the parameter's own type, `() -> X`; or, for places that forward
	/// a value, a closure that takes it, `{ value in X(value) }`.
	enum BuilderForm: String, CaseIterable, Equatable {
		case closure
		case initializerReference
		case storedClosure
		case forwardingClosure

		/// The forms of a builder whose places forward nothing, which a call writes in turn.
		static let formsForwardingNothing: [BuilderForm] = [.closure, .initializerReference, .storedClosure]
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
					"\(label): <\(facts.isSendable ? "@Sendable " : "")(\(facts.forwardedType ?? "")) -> \(facts.returnedType)>"
				case .forwardingClosure:
					"\(label): { value in \(facts.fillingType)(value) }"
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
		let forms = BuilderForm.formsForwardingNothing
		var builderIndex = Int(seed % UInt64(forms.count))
		return callables.map { callable in
			Call(key: callable.key, arguments: callable.parameters.compactMap { parameter -> Argument? in
				if isBuilder(parameter), let facts = builderFacts(of: parameter) {
					guard facts.forwardsNothing else {
						return .builder(label: facts.contractLabel, facts: facts, form: .forwardingClosure)
					}
					defer { builderIndex += 1 }
					return .builder(label: facts.contractLabel, facts: facts, form: forms[builderIndex % forms.count])
				}
				return parameter.hasDefault ? nil : .value(label: parameter.label, type: parameter.type)
			})
		}
	}

	/// Whether a parameter of type `parameterType` takes a builder for `facts` written in `form`: the one place that says
	/// which forms each parameter type accepts, by the type clause of contract rule 8. A wrapper's `.Builder` whose
	/// forwarded type is `B.ForwardedProperties` – every `Instantiator<B>.Builder` – is read as forwarding nothing, since the
	/// surface does not say whether `B` forwards anything, and the corpora's `Instantiator` places forward nothing. A place
	/// that forwards nothing takes `() -> B`, `ErasedInstantiator<(), B>.Builder`, a `.Builder` read so, or a `Sendable`
	/// twin, each of which takes every form but a forwarding closure; a place that forwards `F` takes `(F) -> B` or
	/// `ErasedInstantiator<F, B>.Builder`, which takes a forwarding closure, or a stored closure of that type; a `@Sendable`
	/// parameter takes a stored closure only when it is `@Sendable` too; a closure handed a scope takes none. The
	/// builder-struct work can back this with a compile of the call.
	static func accepts(parameterType: String, facts: BuilderFacts, form: BuilderForm) -> Bool {
		guard generatedTypeNamed(by: "_: " + parameterType) == nil else { return false }
		let isSendable = isSendableBuilderType(parameterType)
		if form == .storedClosure, isSendable != facts.isSendable {
			return false
		}
		let returnedName = BuilderFacts.typeName(facts.returnedType)
		let takesForwardedValue = form == .forwardingClosure || (form == .storedClosure && !facts.forwardsNothing)
		if let wrapperBuilder = wrapperBuilder(of: parameterType) {
			guard BuilderFacts.typeName(wrapperBuilder.returnedType) == returnedName else { return false }
			let wrapperForwardsNothing = wrapperBuilder.forwardedType.map { BuilderFacts.forwardsNothing($0, returnedType: wrapperBuilder.returnedType) } ?? true
			return takesForwardedValue ? !wrapperForwardsNothing && wrapperBuilder.forwardedType == facts.forwardedType : wrapperForwardsNothing
		}
		var type = parameterType
		for attribute in ["@escaping ", "@Sendable "] {
			type = type.replacingOccurrences(of: attribute, with: "")
		}
		guard type.hasPrefix("("), let arrow = type.range(of: ") -> ", options: .backwards) else { return false }
		let forwardedType = String(type[type.index(after: type.startIndex)..<arrow.lowerBound])
		guard BuilderFacts.typeName(String(type[arrow.upperBound...])) == returnedName else { return false }
		return takesForwardedValue ? forwardedType == facts.forwardedType : forwardedType.isEmpty
	}

	/// Whether a builder parameter's type is of the `@Sendable` family: a `@Sendable` closure or a `Sendable` wrapper's
	/// `Builder`. The one test the base check's hole kinds and `accepts` share.
	static func isSendableBuilderType(_ type: String) -> Bool {
		type.contains("@Sendable") || type.replacingOccurrences(of: "@escaping ", with: "").hasPrefix("Sendable")
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
/// (`GraphFuzzerGenerator.fixture(forSeed:features:builderSurfaceEdit:)`). An inner seam of another module is
/// `HoleSurfaceInner`, a seam of the module beneath the seam's that the seam builds as it builds the type holding the hole,
/// so its places are of the seam's builder's family; the hole's protocol moves into that module with it.
enum GraphFuzzerBuilderSurfaceEdit: String, CaseIterable {
	/// Same supply: a second place of an existing builder, in another type of the seam's tree (`HoleSurfaceExtra`, a copy
	/// of the type that holds the hole, built as that type is).
	case secondPlaceInAnotherType
	/// Same supply: a second place of an existing builder in an inner seam of another module.
	case secondPlaceInInnerSeamOfAnotherModule
	/// Same supply: the place moved from the type holding it into an inner seam of another module, which that type builds.
	case holderMovedToInnerSeamOfAnotherModule
	/// Same supply: a plain place moved behind `LazilyInstantiated`, or a lazy place moved back.
	case placeBehindLazilyInstantiated
	/// Same supply: `Instantiator<Hole>`, whose `Hole` forwards nothing, moved to a plain place.
	case instantiatorPlaceMovedToPlainPlace
	/// Same supply: `Instantiator<Hole>` changed to `ErasedInstantiator<Hole.ForwardedProperties, Hole>` with
	/// `fulfilledByType: "Hole"`.
	case instantiatorChangedToErasedInstantiator
	/// The base of the `@Sendable` twins: `Instantiator<Hole>` changed to `SendableInstantiator<Hole>`, whose places are of
	/// the `@Sendable` family; judged only against the twins.
	case instantiatorMadeSendable
	/// The `@Sendable` twin of `instantiatorPlaceMovedToPlainPlace`: the place a plain `Hole` on `HoleSurfaceHost`, which
	/// `SendableInstantiator<HoleSurfaceHost>` builds in a `@Sendable` function.
	case sendableInstantiatorPlaceMovedToPlainPlace
	/// The `@Sendable` twin of `instantiatorChangedToErasedInstantiator`: `SendableErasedInstantiator<Hole.ForwardedProperties,
	/// Hole>`.
	case sendableInstantiatorChangedToSendableErasedInstantiator
	/// Added supply: a place of a new builder whose filling type is an existing builder's, returning another type.
	case placeOfNewBuilderOfExistingFillingType
	/// Added supply: a place of a new builder of the existing filling type in the inner seam of another module that
	/// `secondPlaceInInnerSeamOfAnotherModule` adds, against whose graph it is judged.
	case placeOfNewBuilderInInnerSeamOfAnotherModule
	/// Rejection: a place of an existing builder that forwards other values (`ErasedInstantiator<Int, …>`).
	case placeForwardingOtherValues
	/// The rejection's remedy: the same place forwarding what the existing places forward (`ErasedInstantiator<(), …>`).
	case placeForwardingOtherValuesRemedied
	/// Rejection across modules: the place forwarding other values in an inner seam of another module, whose builder the seam
	/// takes beside its own places' builder, so the places meet in the seam's module.
	case placeForwardingOtherValuesInInnerSeamOfAnotherModule
	/// That rejection's remedy.
	case placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied

	/// Whether each module of the edited graph lists every module it depends on. A module that declares a root whose only
	/// route to a fill passes beneath the seam's module must list the module the route reaches, the remedy the tool states
	/// ("A module that declares a root lists every module beneath it"), so the edit that leaves the inner seam the only
	/// holder of the place follows it, as an adopter would.
	var listsTransitiveDependencies: Bool {
		switch self {
		case .holderMovedToInnerSeamOfAnotherModule:
			true
		case .secondPlaceInAnotherType,
		     .secondPlaceInInnerSeamOfAnotherModule,
		     .placeBehindLazilyInstantiated,
		     .instantiatorPlaceMovedToPlainPlace,
		     .instantiatorChangedToErasedInstantiator,
		     .instantiatorMadeSendable,
		     .sendableInstantiatorPlaceMovedToPlainPlace,
		     .sendableInstantiatorChangedToSendableErasedInstantiator,
		     .placeOfNewBuilderOfExistingFillingType,
		     .placeOfNewBuilderInInnerSeamOfAnotherModule,
		     .placeForwardingOtherValues,
		     .placeForwardingOtherValuesRemedied,
		     .placeForwardingOtherValuesInInnerSeamOfAnotherModule,
		     .placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied:
			false
		}
	}
}

extension GraphFuzzerGenerator {
	/// What `applying(_:to:markerFreeFiles:context:)` needs of the graph beyond its declarations.
	struct BuilderSurfaceEditContext {
		let prefix: String
		/// Whether every wrapper of the graph is `Sendable`.
		let isSendableGraph: Bool
		/// Whether the graph's types that are not `@Instantiable` are `Sendable`.
		let helperTypesAreSendable: Bool
		/// Whether the seam's module has no package, beside which no seam of the module beneath it is drawn.
		let seamModuleOmitsPackageName: Bool
	}

	/// `declarations`, a seam corpus graph's after every draw, with `edit` applied to `HoleSeam`'s hole, `holeService`, or
	/// `nil` when the edit does not apply to it. An edit into an inner seam of another module moves `HoleService` into that
	/// module, from `HoleSeam`'s declarations or the file without a SafeDI marker that `markerFreeFiles` holds, so it applies
	/// only where the protocol is `public` and nothing a fill reads from the scope must be named there: `HoleImpl` receives
	/// nothing.
	static func applying(_ edit: GraphFuzzerBuilderSurfaceEdit, to declarations: [TypeDeclaration], markerFreeFiles: inout [(ownerName: String, fileName: String, declaration: String)], context: BuilderSurfaceEditContext) -> [TypeDeclaration]? {
		let prefix = context.prefix
		let serviceType = "any \(prefix)HoleService"
		guard let holderIndex = declarations.firstIndex(where: { declaration in
			declaration.module == .seamModule && declaration.properties.contains { $0.label == "holeService" && $0.type == serviceType }
		}) else { return nil }
		var declarations = declarations
		let holder = declarations[holderIndex]
		let seamName = "\(prefix)HoleSeam"
		/// The property the seam builds `name`, a new type, with: by value where the seam holds the hole, else as it builds the
		/// type holding it, so that the new type's places are built in the same family.
		func propertyBuilding(_ name: String, label: String) -> PropertyDeclaration? {
			guard holder.name != seamName else {
				return PropertyDeclaration(attribute: "@Instantiated", label: label, type: name)
			}
			guard let seamIndex = declarations.firstIndex(where: { $0.name == seamName }),
			      let ownerProperty = declarations[seamIndex].properties.first(where: { $0.type.contains(holder.name) })
			else { return nil }
			let wrapped = ownerProperty.type.replacingOccurrences(of: holder.name, with: name)
			return PropertyDeclaration(attribute: ownerProperty.attribute, label: wrapped == name ? label : label + "Builder", type: wrapped)
		}
		/// `declarations` with `HoleSurfaceInner`, a seam of the module beneath the seam's holding `properties`, which the seam
		/// builds as `propertyBuilding` says, and `HoleService` moved into its module; `nil` where the protocol cannot move.
		func addingInnerSeam(holding properties: [PropertyDeclaration], builtBy builder: (inout [TypeDeclaration], PropertyDeclaration) -> Bool) -> [TypeDeclaration]? {
			guard !context.seamModuleOmitsPackageName,
			      let implIndex = declarations.firstIndex(where: { $0.name == "\(prefix)HoleImpl" }),
			      !declarations[implIndex].properties.contains(where: { $0.attribute.hasPrefix("@Received") }),
			      let seamIndex = declarations.firstIndex(where: { $0.name == seamName })
			else { return nil }
			let serviceDeclaration = "public protocol \(prefix)HoleService\(context.helperTypesAreSendable ? ": Sendable" : "") {}"
			let innerName = "\(prefix)HoleSurfaceInner"
			var inner = TypeDeclaration(name: innerName, instantiableArguments: ["generateDependencyTree: true"], properties: properties, declaresHelperTypes: false)
			inner.module = .seamDependency
			let markerFreeFileIndex = markerFreeFiles.firstIndex { $0.ownerName == seamName && $0.declaration == serviceDeclaration }
			if let declarationIndex = declarations[seamIndex].additionalDeclarations.firstIndex(of: serviceDeclaration) {
				declarations[seamIndex].additionalDeclarations.remove(at: declarationIndex)
				inner.additionalDeclarations.append(serviceDeclaration)
			} else if markerFreeFileIndex == nil {
				return nil
			}
			guard let property = propertyBuilding(innerName, label: "holeSurfaceInner"), builder(&declarations, property) else { return nil }
			if let markerFreeFileIndex {
				// The protocol's file without a SafeDI marker moves with it, into its owner's module.
				markerFreeFiles[markerFreeFileIndex].ownerName = innerName
			}
			// The declarations of the callers' modules that name the protocol import its new module, which they do not list.
			for index in declarations.indices where ![.seamModule, .seamDependency].contains(declarations[index].module)
				&& (declarations[index].additionalConformances.contains("\(prefix)HoleService") || declarations[index].properties.contains { $0.type.contains("\(prefix)HoleService") })
			{
				declarations[index].imports.append(GraphFuzzerModule.seamDependency.name)
			}
			declarations.append(inner)
			return declarations
		}
		/// Inserts `property`, which builds the inner seam, on the seam beside the property that builds the holder.
		func insertingOnSeam(_ declarations: inout [TypeDeclaration], _ property: PropertyDeclaration) -> Bool {
			guard let seamIndex = declarations.firstIndex(where: { $0.name == seamName }) else { return false }
			declarations[seamIndex].properties.append(property)
			return true
		}
		let place = PropertyDeclaration(attribute: "@Instantiated", label: "holeService", type: serviceType)
		switch edit {
		case .secondPlaceInAnotherType:
			guard let seamIndex = declarations.firstIndex(where: { $0.name == seamName }) else { return nil }
			let extraName = "\(prefix)HoleSurfaceExtra"
			var extra = TypeDeclaration(name: extraName, instantiableArguments: [], properties: [], declaresHelperTypes: false)
			extra.module = .seamModule
			if holder.name == seamName {
				// The seam holds the hole: the extra type, built by value at the seam's root as the hole is, holds a place of it.
				extra.properties = [place]
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
		case .secondPlaceInInnerSeamOfAnotherModule:
			return addingInnerSeam(holding: [place], builtBy: insertingOnSeam)
		case .holderMovedToInnerSeamOfAnotherModule:
			// The type holding the place builds the inner seam by value where the place was, so the place stays in its family.
			return addingInnerSeam(holding: [place]) { declarations, _ in
				guard let index = declarations.firstIndex(where: { $0.name == holder.name }),
				      let holeIndex = declarations[index].properties.firstIndex(where: { $0.label == "holeService" && $0.type == serviceType })
				else { return false }
				declarations[index].properties[holeIndex] = PropertyDeclaration(attribute: "@Instantiated", label: "holeSurfaceInner", type: "\(prefix)HoleSurfaceInner")
				return true
			}
		case .placeOfNewBuilderInInnerSeamOfAnotherModule:
			// A second returned type of the protocol's builder: an erasure the inner seam's module declares.
			let erasedName = "\(prefix)HoleSurfaceAny"
			guard var edited = addingInnerSeam(holding: [
				place,
				PropertyDeclaration(attribute: "@Instantiated(fulfilledByType: \"\(prefix)HoleService\", erasedToConcreteExistential: true)", label: "holeSurfaceErased", type: erasedName),
			], builtBy: insertingOnSeam) else { return nil }
			edited[edited.count - 1].additionalDeclarations.append("public struct \(erasedName)\(context.helperTypesAreSendable ? ": Sendable" : "") {\n\tpublic init(_ value: \(serviceType)) {\n\t\tself.value = value\n\t}\n\n\tpublic let value: \(serviceType)\n}")
			return edited
		case .placeForwardingOtherValuesInInnerSeamOfAnotherModule, .placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied:
			let forwarded = edit == .placeForwardingOtherValuesInInnerSeamOfAnotherModule ? "Int" : "()"
			return addingInnerSeam(holding: [PropertyDeclaration(
				attribute: "@Instantiated(fulfilledByType: \"\(prefix)HoleService\")",
				label: "holeServiceForwarding",
				type: "\(context.isSendableGraph ? "SendableErasedInstantiator" : "ErasedInstantiator")<\(forwarded), \(serviceType)>",
			)], builtBy: insertingOnSeam)
		case .placeBehindLazilyInstantiated:
			// A `LazilyInstantiated` is not `Sendable`, so a graph whose types all are holds none; and a
			// `SendableLazilyInstantiated` place is built in a `@Sendable` function, which is another family.
			guard !context.isSendableGraph else { return nil }
			if let lazyIndex = holder.properties.firstIndex(where: { $0.label == "holeServiceLazy" && $0.type == "LazilyInstantiated<\(serviceType)>" }) {
				declarations[holderIndex].properties[lazyIndex] = place.relabeled("holeServiceLazy")
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
		case .instantiatorPlaceMovedToPlainPlace,
		     .instantiatorChangedToErasedInstantiator,
		     .instantiatorMadeSendable,
		     .sendableInstantiatorPlaceMovedToPlainPlace,
		     .sendableInstantiatorChangedToSendableErasedInstantiator,
		     .placeOfNewBuilderOfExistingFillingType:
			// The seam corpus's holes are existentials, which no `Instantiator` wraps, and its two erasures of `HoleGadgetImpl`
			// already draw a new builder of an existing filling type (`holeGadgetOther`, read as a pair from the graph without
			// it).
			return nil
		}
		return declarations
	}
}

extension GraphFuzzerGenerator.PropertyDeclaration {
	/// This property under `label`.
	func relabeled(_ label: String) -> Self {
		Self(attribute: attribute, label: label, type: type)
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
		guard case let .accepted(drawnFiles, _) = drawn else {
			return PairJudgment(isJudged: false, problems: [])
		}
		guard case let .accepted(editedFiles, _) = edited else {
			return PairJudgment(isJudged: false, problems: [rejectedEditProblem(edited)])
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

	/// The problem of an edit that keeps or adds to the supply which the tool rejects: the edit changes nothing a valid graph
	/// may not have, so a rejection is a failure (`sameSupplyEditRejected` for part (i), the part's own for part (ii)),
	/// though the pair, whose calls were never judged, counts toward no floor.
	static func rejectedEditProblem(_ outcome: GraphFuzzerToolOutcome) -> String {
		switch outcome {
		case .accepted:
			"The tool accepts the edited graph"
		case let .rejected(diagnostics):
			"The tool rejects the edited graph:\n\(diagnostics)"
		}
	}

	/// Parts (ii) and (iv), added supply: every builder parameter of `without`, the graph without the added places, keeps its
	/// label and type, in its order among the other builders, in `with`, so that a call with only the new builders' arguments
	/// added still compiles; `keys` limits the callables judged (a calling mock's, for part (iv)).
	static func addedSupplyJudgment(without: GraphFuzzerToolOutcome, with: GraphFuzzerToolOutcome, judging isJudgedKey: (String) -> Bool = { _ in true }) -> PairJudgment {
		guard case let .accepted(withoutFiles, _) = without else {
			return PairJudgment(isJudged: false, problems: ["The tool rejects the graph without the added places, which it accepts with them:\n\(without)"])
		}
		guard case let .accepted(withFiles, _) = with else {
			return PairJudgment(isJudged: false, problems: [rejectedEditProblem(with)])
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

	/// Part (iii): a graph whose builder's places forward other values must be rejected by the module where the places
	/// meet in one builder – the seam's, or the public mock's, which takes an inner seam's places too – with an error there.
	/// The remedy's rejection (`remedyJudgment(remedied:)`) and the remedy's builders (`remedyBuildersJudgment(drawn:remedied:)`)
	/// are judged apart.
	static func rejectionJudgment(unremedied: GraphFuzzerToolOutcome, meetingModule: GraphFuzzerModule) -> PairJudgment {
		switch unremedied {
		case .accepted:
			return PairJudgment(isJudged: true, problems: ["The tool accepts a builder whose places forward other values"])
		case let .rejected(diagnostics):
			let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error: ") }
			guard !errors.contains(where: { $0.contains("/\(meetingModule.name)/") }) else {
				return PairJudgment(isJudged: true, problems: [])
			}
			return PairJudgment(isJudged: true, problems: ["The tool rejects a builder whose places forward other values only outside \(meetingModule.name), where they meet:\n\(errors.joined(separator: "\n"))"])
		}
	}

	/// The remedy of part (iii), the added place forwarding what the drawn places forward, must be accepted with exactly the
	/// drawn graph's builders, callable by callable, since its places are places of the drawn graph's builder. Judged only
	/// where the tool accepts both graphs.
	static func remedyBuildersJudgment(drawn: GraphFuzzerToolOutcome, remedied: GraphFuzzerToolOutcome) -> PairJudgment {
		guard case let .accepted(drawnFiles, _) = drawn, case let .accepted(remediedFiles, _) = remedied else {
			return PairJudgment(isJudged: false, problems: [])
		}
		var problems = [String]()
		let remediedBuilders = Dictionary(grouping: callables(in: remediedFiles), by: \.key).mapValues { $0.flatMap(\.parameters).filter(isBuilder) }
		for callable in callables(in: drawnFiles) {
			let builders = callable.parameters.filter(isBuilder)
			let remedied = remediedBuilders[callable.key] ?? []
			if remedied != builders {
				problems.append("\(callable.key) takes builders \(remedied.map { "`\($0.description)`" }.joined(separator: ", ")) with the remedy and \(builders.map { "`\($0.description)`" }.joined(separator: ", ")) without it, so the remedied place is not a place of the drawn builder")
			}
		}
		return PairJudgment(isJudged: true, problems: problems)
	}

	/// The remedy of part (iii): the graph whose added place forwards what the drawn places forward must be accepted.
	static func remedyJudgment(remedied: GraphFuzzerToolOutcome) -> PairJudgment {
		switch remedied {
		case .accepted:
			PairJudgment(isJudged: true, problems: [])
		case let .rejected(diagnostics):
			PairJudgment(isJudged: false, problems: ["The tool rejects the remedied graph, whose places forward the same values:\n\(diagnostics)"])
		}
	}
}

// MARK: - The parts' failures

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The judged pairs of each part: each edit kind's, the reverse pairs of the same supply edits that change an
	/// `Instantiator` (the edited graph's calls judged against the drawn graph), the `@Sendable` twins (judged against
	/// `instantiatorMadeSendable`'s graph), the second-place pairs of part (ii) (`holeGadgetOther`, a new builder of an
	/// existing filling type) and of part (iv) (a second call of a public mock, `t6Twin` or `t6Second`), each counted toward
	/// its kind's floor whether it passes or fails, as a compile of the call would count it.
	var builderSurfaceJudgments: [(kind: String, judgment: GraphFuzzerBuilderSurface.PairJudgment)] {
		var judgments = [(kind: String, judgment: GraphFuzzerBuilderSurface.PairJudgment)]()
		func outcome(of edit: GraphFuzzerBuilderSurfaceEdit) -> GraphFuzzerToolOutcome? {
			builderSurfaceRuns.first { $0.edit == edit }?.outcome
		}
		for run in builderSurfaceRuns {
			switch run.edit {
			case .secondPlaceInAnotherType,
			     .secondPlaceInInnerSeamOfAnotherModule,
			     .holderMovedToInnerSeamOfAnotherModule,
			     .placeBehindLazilyInstantiated,
			     .instantiatorPlaceMovedToPlainPlace,
			     .instantiatorChangedToErasedInstantiator:
				judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: firstOutcome, edited: run.outcome, seed: fixture.seed)))
			case .instantiatorMadeSendable:
				// The twins' base, judged only as their drawn graph.
				break
			case .sendableInstantiatorPlaceMovedToPlainPlace,
			     .sendableInstantiatorChangedToSendableErasedInstantiator:
				if let base = outcome(of: .instantiatorMadeSendable) {
					let judgment = if case .rejected = base {
						GraphFuzzerBuilderSurface.PairJudgment(isJudged: false, problems: [GraphFuzzerBuilderSurface.rejectedEditProblem(base)])
					} else {
						GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: base, edited: run.outcome, seed: fixture.seed)
					}
					judgments.append((run.edit.rawValue, judgment))
				}
			case .placeOfNewBuilderOfExistingFillingType:
				judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.addedSupplyJudgment(without: firstOutcome, with: run.outcome)))
			case .placeOfNewBuilderInInnerSeamOfAnotherModule:
				if let without = outcome(of: .secondPlaceInInnerSeamOfAnotherModule) {
					judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.addedSupplyJudgment(without: without, with: run.outcome)))
				}
			case .placeForwardingOtherValues, .placeForwardingOtherValuesInInnerSeamOfAnotherModule:
				let remedy: GraphFuzzerBuilderSurfaceEdit = run.edit == .placeForwardingOtherValues ? .placeForwardingOtherValuesRemedied : .placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied
				if outcome(of: remedy) != nil {
					judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.rejectionJudgment(unremedied: run.outcome, meetingModule: .seamModule)))
				}
			case .placeForwardingOtherValuesRemedied, .placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied:
				judgments.append((run.edit.rawValue, GraphFuzzerBuilderSurface.remedyJudgment(remedied: run.outcome)))
				judgments.append((Self.remedyBuildersPairKind, GraphFuzzerBuilderSurface.remedyBuildersJudgment(drawn: firstOutcome, remedied: run.outcome)))
			}
		}
		// The reverse directions: a call written against the edited graph's surface, judged against the graph it was edited
		// from – the drawn graph, or for a `@Sendable` twin the graph whose `Instantiator` is made `SendableInstantiator`.
		let reverses: [(edit: GraphFuzzerBuilderSurfaceEdit, kind: String, base: GraphFuzzerToolOutcome?)] = [
			(.instantiatorPlaceMovedToPlainPlace, Self.plainPlaceMovedToInstantiatorPairKind, firstOutcome),
			(.instantiatorChangedToErasedInstantiator, Self.erasedInstantiatorChangedToInstantiatorPairKind, firstOutcome),
			(.sendableInstantiatorPlaceMovedToPlainPlace, Self.plainPlaceMovedToSendableInstantiatorPairKind, outcome(of: .instantiatorMadeSendable)),
			(.sendableInstantiatorChangedToSendableErasedInstantiator, Self.sendableErasedInstantiatorChangedToSendableInstantiatorPairKind, outcome(of: .instantiatorMadeSendable)),
		]
		for reverse in reverses {
			if let edited = outcome(of: reverse.edit), case .accepted = edited, let base = reverse.base, case .accepted = base {
				judgments.append((reverse.kind, GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: edited, edited: base, seed: fixture.seed)))
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
	/// The reverse of `instantiatorPlaceMovedToPlainPlace`: a plain place moved to `Instantiator<Hole>`.
	static let plainPlaceMovedToInstantiatorPairKind = "plainPlaceMovedToInstantiator"
	/// The reverse of `instantiatorChangedToErasedInstantiator`: an `ErasedInstantiator` changed to `Instantiator<Hole>`.
	static let erasedInstantiatorChangedToInstantiatorPairKind = "erasedInstantiatorChangedToInstantiator"
	/// The reverse of `sendableInstantiatorPlaceMovedToPlainPlace`: a plain place moved to `SendableInstantiator<Hole>`.
	static let plainPlaceMovedToSendableInstantiatorPairKind = "plainPlaceMovedToSendableInstantiator"
	/// The reverse of `sendableInstantiatorChangedToSendableErasedInstantiator`: a `SendableErasedInstantiator` changed to
	/// `SendableInstantiator<Hole>`.
	static let sendableErasedInstantiatorChangedToSendableInstantiatorPairKind = "sendableErasedInstantiatorChangedToSendableInstantiator"
	/// The kind of a pair of part (iii)'s remedy and the drawn graph, whose builders must be the same.
	static let remedyBuildersPairKind = "remedyKeepsDrawnBuilders"

	/// The pair kinds of part (i).
	static let sameSupplyPairKinds = [
		GraphFuzzerBuilderSurfaceEdit.secondPlaceInAnotherType.rawValue,
		GraphFuzzerBuilderSurfaceEdit.secondPlaceInInnerSeamOfAnotherModule.rawValue,
		GraphFuzzerBuilderSurfaceEdit.holderMovedToInnerSeamOfAnotherModule.rawValue,
		GraphFuzzerBuilderSurfaceEdit.placeBehindLazilyInstantiated.rawValue,
		GraphFuzzerBuilderSurfaceEdit.instantiatorPlaceMovedToPlainPlace.rawValue,
		GraphFuzzerBuilderSurfaceEdit.instantiatorChangedToErasedInstantiator.rawValue,
		GraphFuzzerBuilderSurfaceEdit.sendableInstantiatorPlaceMovedToPlainPlace.rawValue,
		GraphFuzzerBuilderSurfaceEdit.sendableInstantiatorChangedToSendableErasedInstantiator.rawValue,
		plainPlaceMovedToInstantiatorPairKind,
		erasedInstantiatorChangedToInstantiatorPairKind,
		plainPlaceMovedToSendableInstantiatorPairKind,
		sendableErasedInstantiatorChangedToSendableInstantiatorPairKind,
	]

	/// Part (i)'s failure, or `nil`: a judged pair's call that stops compiling.
	var sameSupplyFailure: GraphFuzzerFailure? {
		failure(of: .sameSupplyCallStopsCompiling, kinds: Self.sameSupplyPairKinds, judged: true)
	}

	/// The failure of a graph whose same-supply edit the tool rejects, or `nil`: its calls are never judged.
	var sameSupplyEditRejectedFailure: GraphFuzzerFailure? {
		failure(of: .sameSupplyEditRejected, kinds: Self.sameSupplyPairKinds, judged: false)
	}

	/// Part (ii)'s failure, or `nil`.
	var addedSupplyFailure: GraphFuzzerFailure? {
		failure(of: .addedBuilderChangesExistingBuilder, kinds: [
			GraphFuzzerBuilderSurfaceEdit.placeOfNewBuilderOfExistingFillingType.rawValue,
			GraphFuzzerBuilderSurfaceEdit.placeOfNewBuilderInInnerSeamOfAnotherModule.rawValue,
			Self.secondErasurePairKind,
		])
	}

	/// Part (iii)'s failure, or `nil`.
	var forwardedValuesFailure: GraphFuzzerFailure? {
		failure(of: .placesForwardingOtherValuesAccepted, kinds: [
			GraphFuzzerBuilderSurfaceEdit.placeForwardingOtherValues.rawValue,
			GraphFuzzerBuilderSurfaceEdit.placeForwardingOtherValuesInInnerSeamOfAnotherModule.rawValue,
		])
	}

	/// The failure of a graph whose part (iii) remedy the tool rejects, or `nil`. No known issue lists it.
	var forwardingRemedyFailure: GraphFuzzerFailure? {
		failure(of: .remedyOfPlacesForwardingOtherValuesRejected, kinds: [
			GraphFuzzerBuilderSurfaceEdit.placeForwardingOtherValuesRemedied.rawValue,
			GraphFuzzerBuilderSurfaceEdit.placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied.rawValue,
		])
	}

	/// The failure of a graph whose part (iii) remedy the tool accepts with other builders than the drawn graph's, or `nil`.
	var remedyBuildersFailure: GraphFuzzerFailure? {
		failure(of: .remedyAddsBuilder, kinds: [Self.remedyBuildersPairKind])
	}

	/// Part (iv)'s failure, or `nil`.
	var callingMockFailure: GraphFuzzerFailure? {
		failure(of: .callingMockChangesBuilder, kinds: [Self.callingMockPairKind])
	}

	/// The failure of `failureKind` from the problems of the pairs of `kinds`, only judged pairs' or only unjudged pairs'
	/// when `judged` says so.
	private func failure(of failureKind: GraphFuzzerFailure.Kind, kinds: [String], judged: Bool? = nil) -> GraphFuzzerFailure? {
		let problems = builderSurfaceJudgments.filter { pair in kinds.contains(pair.kind) && (judged.map { $0 == pair.judgment.isJudged } ?? true) }.flatMap { judged in judged.judgment.problems.map { "\(judged.kind): \($0)" } }
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
		+ GraphFuzzerBuilderSurfaceEdit.allCases.filter { $0 != .instantiatorMadeSendable }.map(\.rawValue)
		+ [
			GraphFuzzerToolRuns.plainPlaceMovedToInstantiatorPairKind,
			GraphFuzzerToolRuns.erasedInstantiatorChangedToInstantiatorPairKind,
			GraphFuzzerToolRuns.plainPlaceMovedToSendableInstantiatorPairKind,
			GraphFuzzerToolRuns.sendableErasedInstantiatorChangedToSendableInstantiatorPairKind,
			GraphFuzzerToolRuns.secondErasurePairKind,
			GraphFuzzerToolRuns.callingMockPairKind,
		]

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
		if builders.contains(where: { !isSendableBuilderType($0.type) }) {
			kinds.append(.plain)
		}
		if source.range(of: #"LazilyInstantiated<(any )?S\d+_\w*Hole\w*>"#, options: .regularExpression) != nil {
			kinds.append(.lazy)
		}
		if source.range(of: #"ErasedInstantiator<(Int|\w+\.ForwardedProperties), (any )?S\d+_\w*Hole\w*>"#, options: .regularExpression) != nil {
			kinds.append(.forwarding)
		}
		if builders.contains(where: { isSendableBuilderType($0.type) }) {
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

extension GraphFuzzerFailure {
	/// The kinds of failure of the builder surface a known issue may list (`GraphFuzzerKnownIssue.Signature.builderSurface`).
	/// The rejection of a remedy is not among them: no seed hides it.
	static let knownBuilderSurfaceKinds: Set<Kind> = [
		.builderSurfaceNamesGeneratedType,
		.builderLabelBreaksContract,
		.sameSupplyCallStopsCompiling,
		.sameSupplyEditRejected,
		.addedBuilderChangesExistingBuilder,
		.placesForwardingOtherValuesAccepted,
		.callingMockChangesBuilder,
	]
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerResult {
	/// Whether the graph fails no oracle but the builder surface's known kinds. Until the planned builder structs, every
	/// graph with a hole fails the builder surface, so what the smoke batches and the long run read from graphs that pass –
	/// the output features they show, the spellings they draw, the cross-process sample – reads these graphs too.
	var passesBesidesBuilderSurface: Bool {
		([failure] + laterFailures).compactMap(\.self).allSatisfy { GraphFuzzerFailure.knownBuilderSurfaceKinds.contains($0.kind) }
	}
}
