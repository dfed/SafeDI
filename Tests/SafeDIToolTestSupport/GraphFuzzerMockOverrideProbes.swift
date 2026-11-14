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

// MARK: - The override oracle

/// A dependency a compared mock builds by value beside the mocked type, whose `SafeDIOverrides` field the base corpus's
/// override oracle may pass a sentinel: a root's own constant child, or a mirror's constant declaration – the mocked
/// type's own child or a dependency the mock promotes – built by a scope of the graph and not erased.
struct GraphFuzzerOverrideCandidate: Equatable {
	let label: String
	/// The concrete type whose scope builds the dependency.
	let builtTypeName: String
}

/// The form of the `SafeDIOverrides` field the override oracle passes its sentinel through.
enum GraphFuzzerOverrideFieldKind: String, CaseIterable, Comparable {
	/// A builder closure, `((…) -> T)?`, for a type with neither a subtree nor a default-valued input of its own.
	case builder
	/// A `T.SafeDIMockConfiguration`, whose unlabeled builder takes the sentinel.
	case configuration

	static func < (lhs: GraphFuzzerOverrideFieldKind, rhs: GraphFuzzerOverrideFieldKind) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// One override the oracle passes a compared mock: the mock's `SafeDIOverrides` field for `label`, given a builder that
/// builds the type as its own initializer (or `instantiate(…)`) does from the arguments the mock hands it, and records
/// what it built (`GraphFuzzerOverrideSentinel`). The pair's feature expression is the mock so called, with that record;
/// its known-right expression is the production build the mock's pair compares with, with the instance production puts
/// in scope under `label`. So the two agree only when the sentinel takes exactly that instance's place: every receiver
/// of the label holds the sentinel, nothing else holds it, and every other value is what production builds, as it is
/// for the mock called without the override.
struct GraphFuzzerOverrideProbe: Equatable {
	let mockedTypeName: String
	let label: String
	let builtTypeName: String
	let fieldKind: GraphFuzzerOverrideFieldKind
	let pair: DifferentialValueProbePair
}

/// The enum the value-oracle fixture declares beside its mirrors, which records the instance the override oracle's
/// builder built last. It is not `@Instantiable`, so the tool reads nothing of it, and its name sorts after every type
/// name of the graph, as a mirror's does.
enum GraphFuzzerOverrideSentinel {
	static func typeName(typeNamePrefix: String) -> String {
		"\(typeNamePrefix)ZOverrideSentinel"
	}

	/// The enum's file, which names itself (`GraphFuzzerFixture.fileNameMarker`), as it declares no `@Instantiable`
	/// type. `recording(_:)` wraps a builder in a `@Sendable` closure, which a builder field of either kind of
	/// graph takes, and which converts to one that is not `@Sendable`; `recorded(_:)` records a value a closure the
	/// oracle writes builds; `nonisolated(unsafe)` lets either write the record, which only the probe executable's one
	/// thread reads.
	static func source(typeNamePrefix: String) -> String {
		"""
		\(GraphFuzzerFixture.fileNameMarker)\(typeName(typeNamePrefix: typeNamePrefix)).swift
		enum \(typeName(typeNamePrefix: typeNamePrefix)) {
			nonisolated(unsafe) static var value: Any?

			static func recording<each Argument, Value>(_ build: @escaping @Sendable (repeat each Argument) -> Value) -> @Sendable (repeat each Argument) -> Value {
				{ (argument: repeat each Argument) -> Value in
					recorded(build(repeat each argument))
				}
			}

			static func recorded<Value>(_ value: Value) -> Value {
				\(typeName(typeNamePrefix: typeNamePrefix)).value = value
				return value
			}
		}

		"""
	}
}

extension GraphFuzzerValueOraclePlan {
	/// The override oracle's probes: for each compared pair – each root's, then each mirrored mock's – one override, of
	/// the candidates whose field the generated mock in `generatedFiles` has, chosen by the seed and the pair's position,
	/// so that a seed judges one field per mock and the corpus judges each of a mock's fields over its seeds.
	func overrideProbes(generatedFiles: [String: String]) -> [GraphFuzzerOverrideProbe] {
		var probes = [GraphFuzzerOverrideProbe]()
		var ordinal: UInt64 = 0
		for rootTypeName in rootTypeNames {
			if let probe = overrideProbe(
				mockedTypeName: rootTypeName,
				candidates: rootOverrideCandidates[rootTypeName] ?? [],
				mockFile: generatedFiles[rootTypeName + "+SafeDIMock.swift"],
				ordinal: ordinal,
				mockArguments: [],
				knownRightConstruction: "\(rootTypeName)()",
				knownRightValuePath: "",
			) {
				probes.append(probe)
			}
			ordinal += 1
		}
		for mirror in mirrors {
			let candidates = mirror.declarations.compactMap { declaration -> GraphFuzzerOverrideCandidate? in
				guard declaration.alias == nil,
				      let builtTypeName = declaration.builtTypeName,
				      !declaration.attribute.contains("erasedToConcreteExistential: true"),
				      GraphFuzzerMirrorTypes.kindOrder(of: declaration.property.type) == 0,
				      !declaration.property.isOptional
				else { return nil }
				return GraphFuzzerOverrideCandidate(label: declaration.property.label, builtTypeName: builtTypeName)
			}
			if let probe = overrideProbe(
				mockedTypeName: mirror.mockedTypeName,
				candidates: candidates,
				mockFile: generatedFiles[mirror.mockedTypeName + "+SafeDIMock.swift"],
				ordinal: ordinal,
				mockArguments: mirror.mockArguments,
				knownRightConstruction: mirror.knownRightConstruction,
				knownRightValuePath: ".\(GraphFuzzerMockMirror.valueLabel)",
			) {
				probes.append(probe)
			}
			ordinal += 1
		}
		return probes
	}

	/// The override probe of the mock of `mockedTypeName`, or `nil` when its mock has a field for none of `candidates`.
	/// - Parameters:
	///   - mockArguments: The samples the mock's pair hands its required parameters, which the probe hands them too.
	///   - knownRightConstruction: The production build the mock's pair compares with: the root, or the mirror, which a
	///     root of its own builds with the same samples when it forwards them.
	///   - knownRightValuePath: The path from that build to the mocked type's value: none for a root, the mirror's value
	///     for a mirror.
	private func overrideProbe(
		mockedTypeName: String,
		candidates: [GraphFuzzerOverrideCandidate],
		mockFile: String?,
		ordinal: UInt64,
		mockArguments: [String],
		knownRightConstruction: String,
		knownRightValuePath: String,
	) -> GraphFuzzerOverrideProbe? {
		guard let mockFile else { return nil }
		let fields = GraphFuzzerMockOverrides.overrideFields(mockFile)
		let matched = candidates.compactMap { candidate -> (candidate: GraphFuzzerOverrideCandidate, kind: GraphFuzzerOverrideFieldKind)? in
			// A root's generated `convenience init()` would make a reference to the type's initializer ambiguous.
			guard !rootTypeNames.contains(candidate.builtTypeName),
			      let field = fields.first(where: { $0.label == candidate.label })
			else { return nil }
			// A field of another type than the one built – an erased or fulfilled-by-type protocol – takes a builder that
			// the built type's initializer is not.
			if field.type == "\(candidate.builtTypeName).SafeDIMockConfiguration" {
				return (candidate, .configuration)
			} else if field.type.hasPrefix("("), field.type.hasSuffix(" -> \(candidate.builtTypeName))?") {
				return (candidate, .builder)
			} else {
				return nil
			}
		}
		guard !matched.isEmpty else { return nil }
		let (candidate, kind) = matched[Int((fixture.seed &+ ordinal) % UInt64(matched.count))]
		let sentinel = GraphFuzzerOverrideSentinel.typeName(typeNamePrefix: fixture.typeNamePrefix)
		let builder = if let instantiateParameters = instantiateParametersByExtensionTypeName[candidate.builtTypeName] {
			"{ \(sentinel).recorded(\(candidate.builtTypeName).instantiate(\(Self.builderArguments(ofInstantiateParameters: instantiateParameters).joined(separator: ", ")))) }"
		} else {
			"\(sentinel).recording(\(candidate.builtTypeName).init)"
		}
		let argument = switch kind {
		case .builder:
			builder
		case .configuration:
			".init(\(builder))"
		}
		return GraphFuzzerOverrideProbe(
			mockedTypeName: mockedTypeName,
			label: candidate.label,
			builtTypeName: candidate.builtTypeName,
			fieldKind: kind,
			pair: DifferentialValueProbePair(
				name: "\(mockedTypeName).mock(safeDIOverrides: .init(\(candidate.label): sentinel))",
				featureExpression: "{ \(sentinel).value = nil; let value = \(mockedTypeName).mock(\((mockArguments + ["safeDIOverrides: .init(\(candidate.label): \(argument))"]).joined(separator: ", "))); return (value, \(sentinel).value) }()",
				knownRightExpression: "{ let known = \(knownRightConstruction); return (known\(knownRightValuePath), known.\(candidate.label) as Any?) }()",
			),
		)
	}

	/// The arguments a builder closure passes an extension's `instantiate(…)`, one per parameter the builder takes, as
	/// `$0`, `$1`, …: each parameter but an unlabeled default-valued one, which has no configuration field and which a
	/// generated call leaves to its default.
	static func builderArguments(ofInstantiateParameters parameters: [String]) -> [String] {
		var arguments = [String]()
		for parameter in parameters.map({ $0.trimmingCharacters(in: .whitespaces) }) where !(parameter.hasPrefix("_ ") && parameter.contains(" = ")) {
			let argumentLabel = parameter.prefix { $0 != " " && $0 != ":" }
			arguments.append(argumentLabel == "_" ? "$\(arguments.count)" : "\(argumentLabel): $\(arguments.count)")
		}
		return arguments
	}
}
