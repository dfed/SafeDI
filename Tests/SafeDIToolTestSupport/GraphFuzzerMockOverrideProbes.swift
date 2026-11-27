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
	/// The type of the dependency's property, without `any` or the types it is nested in.
	let propertyTypeName: String
	let kind: GraphFuzzerOverrideCandidateKind
	/// The dependency's property as declared.
	let property: GraphFuzzerMirrorProperty
	/// For an erased dependency, the type of its property as declared, which the mock's builder field returns.
	var erasedPropertyType: String?
	/// Whether an erased dependency is `erasedToConcreteExistential: true`, so that production holds an erasing type
	/// that stores the instance (`value`), rather than the instance as the protocol it fulfills.
	var isErasedToConcreteExistential = false

	/// A candidate for `property`, which the scope of `builtTypeName` builds and `attribute` declares, or `nil` for one
	/// the oracle does not judge.
	init?(property: GraphFuzzerMirrorProperty, attribute: String, builtTypeName: String) {
		guard !property.isOptional, var kind = GraphFuzzerOverrideCandidateKind(propertyType: property.type) else { return nil }
		if attribute.contains("fulfilledByType: ") {
			switch kind {
			case .constant:
				kind = .erased
			case .sendableInstantiator:
				break
			case .lazilyInstantiated, .erased:
				// An erased lazily instantiated dependency's field is not judged.
				return nil
			}
			erasedPropertyType = GraphFuzzerMirrorTypes.instantiatedType(of: property.type)
			isErasedToConcreteExistential = attribute.contains("erasedToConcreteExistential: true")
		}
		self.property = property
		label = property.label
		self.builtTypeName = builtTypeName
		propertyTypeName = GraphFuzzerMockMirrorModel.unqualifiedName(of: GraphFuzzerMirrorTypes.instantiatedType(of: property.type))
		self.kind = kind
	}
}

/// The kind of dependency whose `SafeDIOverrides` field the override oracle passes its sentinel through, which decides
/// where production holds the instance the sentinel takes the place of.
enum GraphFuzzerOverrideCandidateKind: String, CaseIterable, Comparable {
	/// A constant, which production holds under the label.
	case constant
	/// A `LazilyInstantiated` or `SendableLazilyInstantiated`, whose instance production creates on its first read: the
	/// sentinel is built when the mock's wrapper is first read, so each side reads its record after the rest of the probe.
	case lazilyInstantiated
	/// A constant whose property is of another type than the one built (`fulfilledByType:`): an erasing type
	/// (`erasedToConcreteExistential: true`) or a protocol the built type fulfills. Its builder field returns the
	/// property's type, and its configuration's builder the built type, which the mock then erases.
	case erased
	/// A `SendableInstantiator` or `SendableErasedInstantiator` of a type that forwards nothing, which the mocked type
	/// stores, whose builder field or configuration's builder the instantiator's `@Sendable` builder function calls once
	/// per instance: each side records what one more call of the instantiator the mocked type holds builds.
	case sendableInstantiator

	/// The kind of a non-optional dependency of `type`, or `nil` for a kind the oracle does not judge.
	init?(propertyType type: String) {
		switch GraphFuzzerMirrorTypes.kindOrder(of: type) {
		case 0:
			self = .constant
		case 3, 4:
			self = .sendableInstantiator
		case 5, 6:
			self = .lazilyInstantiated
		default:
			return nil
		}
	}

	static func < (lhs: GraphFuzzerOverrideCandidateKind, rhs: GraphFuzzerOverrideCandidateKind) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
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
/// builds the type as its own initializer (or `instantiate(…)`, or the hand-written mock the tool builds the property with
/// when that mock returns another of the type's types) does from the arguments the mock hands it, and records what it built (`GraphFuzzerOverrideSentinel`). The pair's feature expression is the mock so called, with that record;
/// its known-right expression is the production build the mock's pair compares with, with the instance production puts
/// in scope under `label`. So the two agree only when the sentinel takes exactly that instance's place: every receiver
/// of the label holds the sentinel, nothing else holds it, and every other value is what production builds, as it is
/// for the mock called without the override.
struct GraphFuzzerOverrideProbe: Equatable {
	let mockedTypeName: String
	let label: String
	let builtTypeName: String
	let candidateKind: GraphFuzzerOverrideCandidateKind
	let fieldKind: GraphFuzzerOverrideFieldKind
	let pair: DifferentialValueProbePair
}

/// The enum the value-oracle fixture declares beside its mirrors, which records the instance the override oracle's
/// builder built first: a node a cycle builds again beneath an instantiator reads the override of the nearest node of
/// its type around it (`mock-generation.md`), so the builder builds again each time the describer calls such an
/// instantiator, which for a lazily instantiated dependency it does before the record is read (base corpus seed 209). It is not `@Instantiable`, so the tool reads nothing of it, and its name sorts after every type
/// name of the graph, as a mirror's does.
enum GraphFuzzerOverrideSentinel {
	static func typeName(typeNamePrefix: String) -> String {
		"\(typeNamePrefix)ZOverrideSentinel"
	}

	/// The enum's file, which names itself (`GraphFuzzerFixture.fileNameMarker`), as it declares no `@Instantiable`
	/// type. `recording(_:)` wraps a builder in a `@Sendable` closure, which a builder field of either kind of
	/// graph takes, and which converts to one that is not `@Sendable`, and `recording(_:erasedBy:)` one whose value an
	/// erased dependency's field erases; `recorded(_:)` records a value a closure the
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

			static func recording<each Argument, Value, Erased>(_ build: @escaping @Sendable (repeat each Argument) -> Value, erasedBy erase: @escaping @Sendable (Value) -> Erased) -> @Sendable (repeat each Argument) -> Erased {
				{ (argument: repeat each Argument) -> Erased in
					recorded(erase(build(repeat each argument)))
				}
			}

			static func recorded<Value>(_ value: Value) -> Value {
				if \(typeName(typeNamePrefix: typeNamePrefix)).value == nil {
					\(typeName(typeNamePrefix: typeNamePrefix)).value = value
				}
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
				guard declaration.alias == nil, let builtTypeName = declaration.builtTypeName else { return nil }
				return GraphFuzzerOverrideCandidate(property: declaration.property, attribute: declaration.attribute, builtTypeName: builtTypeName)
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
			// The sentinel's `@Sendable` builder cannot send the values it is handed on to an actor's initializer.
			guard !rootTypeNames.contains(candidate.builtTypeName),
			      !actorTypeNames.contains(candidate.builtTypeName),
			      let field = fields.first(where: { $0.label == candidate.label })
			else { return nil }
			// A lazily instantiated dependency's instance is created where the mocked type's value reads it, so only one the
			// mocked type holds, as the wrapper or its instance, is created on both sides (base corpus seed 691).
			guard candidate.kind != .lazilyInstantiated || dependenciesByTypeName[mockedTypeName]?.contains(where: { $0.property.label == candidate.label }) == true else { return nil }
			// The probe calls the instantiator the mocked type stores, without a sample of forwarded values, on the main
			// actor.
			guard candidate.kind != .sendableInstantiator
				|| (!actorTypeNames.contains(mockedTypeName)
					&& dependenciesByTypeName[mockedTypeName]?.contains { $0.property == candidate.property } == true
					&& dependenciesByTypeName[candidate.builtTypeName]?.contains { $0.source == .forwarded } == false)
			else { return nil }
			// The builder field of a dependency of another type than the one built – an erased or fulfilled-by-type
			// protocol – returns the property's type.
			if field.type == "\(candidate.builtTypeName).SafeDIMockConfiguration" {
				return (candidate, .configuration)
			} else if field.type.hasPrefix("("), field.type.hasSuffix(" -> \(candidate.erasedPropertyType ?? candidate.builtTypeName))?") {
				return (candidate, .builder)
			} else {
				return nil
			}
		}
		guard !matched.isEmpty else { return nil }
		let (candidate, kind) = matched[Int((fixture.seed &+ ordinal) % UInt64(matched.count))]
		let sentinel = GraphFuzzerOverrideSentinel.typeName(typeNamePrefix: fixture.typeNamePrefix)
		// A builder field of an erased dependency returns the property's type: the erasing type around the built
		// instance, or the instance as the protocol it fulfills.
		let erasure: ((String) -> String)? = if kind == .builder, let erasedPropertyType = candidate.erasedPropertyType {
			candidate.isErasedToConcreteExistential ? { "\(erasedPropertyType)(\($0))" } : { "\($0) as \(erasedPropertyType)" }
		} else {
			nil
		}
		let builder = if let instantiateParameters = instantiateParametersByExtensionTypeName[candidate.builtTypeName] {
			"{ \(sentinel).recorded(\((erasure ?? { $0 })("\(candidate.builtTypeName).instantiate(\(Self.builderArguments(ofInstantiateParameters: instantiateParameters).joined(separator: ", ")))"))) }"
		} else if kind == .configuration,
		          let handWrittenMock = handWrittenMocksReturningAdditionalTypes[candidate.builtTypeName],
		          handWrittenMock.returnTypeName == candidate.propertyTypeName
		{
			// The tool builds the property with the hand-written mock, which returns the property's type, so the
			// configuration's builder takes the mock's parameters, which the initializer need not take. The builder returns
			// the configured type, which the mock built and returns as the property's type.
			"{ \(sentinel).recorded(\(candidate.builtTypeName).\(handWrittenMock.name)(\(Self.builderArguments(ofInstantiateParameters: handWrittenMock.parameters).joined(separator: ", "))) as! \(candidate.builtTypeName)) }"
		} else if let erasure {
			"\(sentinel).recording(\(candidate.builtTypeName).init, erasedBy: { \(erasure("$0")) })"
		} else {
			"\(sentinel).recording(\(candidate.builtTypeName).init)"
		}
		let argument = switch kind {
		case .builder:
			builder
		case .configuration:
			".init(\(builder))"
		}
		// A configuration of an erased dependency builds the instance the erasing type production holds stores.
		let erasedInstancePath = kind == .configuration && candidate.isErasedToConcreteExistential ? ".value" : ""
		// What each side records: the sentinel the mock built, and the instance production holds under the label.
		let (featureRecord, knownRightRecord) = switch candidate.kind {
		case .constant:
			("\(sentinel).value", "known.\(candidate.label) as Any?")
		case .lazilyInstantiated:
			// The instance is created on the wrapper's first read, which the describer makes after the rest of the
			// probe's value, so each record is read after it too, through a wrapper of its own.
			("LazilyInstantiated<Any?> { \(sentinel).value }", "LazilyInstantiated<Any?> { known.\(candidate.label).instance as Any? }")
		case .erased:
			// A configuration's builder builds the instance the erasing type production holds stores.
			("\(sentinel).value", "known.\(candidate.label)\(erasedInstancePath) as Any?")
		case .sendableInstantiator:
			// What one more call builds, on each side.
			("{ \(sentinel).value = nil; _ = value.\(candidate.label).instantiate(); return \(sentinel).value }()", "known.\(candidate.label).instantiate()\(erasedInstancePath) as Any?")
		}
		return GraphFuzzerOverrideProbe(
			mockedTypeName: mockedTypeName,
			label: candidate.label,
			builtTypeName: candidate.builtTypeName,
			candidateKind: candidate.kind,
			fieldKind: kind,
			pair: DifferentialValueProbePair(
				name: "\(mockedTypeName).mock(safeDIOverrides: .init(\(candidate.label): sentinel))",
				featureExpression: "{ \(sentinel).value = nil; let value = \(mockedTypeName).mock(\((mockArguments + ["safeDIOverrides: .init(\(candidate.label): \(argument))"]).joined(separator: ", "))); return (value, \(featureRecord)) }()",
				knownRightExpression: "{ let known = \(knownRightConstruction); return (known\(knownRightValuePath), \(knownRightRecord)) }()",
			),
		)
	}

	/// The arguments a builder closure passes an extension's `instantiate(…)`, one per parameter the builder takes, as
	/// `$0`, `$1`, …: each parameter but those a generated call leaves to their default, which have no configuration
	/// field: an unlabeled default-valued one, and a throwing `@autoclosure` whose default throws
	/// (`Initializer.Argument.isLeftToItsDefault`), which the extension draw spells `= try <function>()`.
	static func builderArguments(ofInstantiateParameters parameters: [String]) -> [String] {
		var arguments = [String]()
		for parameter in parameters.map({ $0.trimmingCharacters(in: .whitespaces) }) where !isLeftToItsDefault(parameter) {
			let argumentLabel = parameter.prefix { $0 != " " && $0 != ":" }
			arguments.append(argumentLabel == "_" ? "$\(arguments.count)" : "\(argumentLabel): $\(arguments.count)")
		}
		return arguments
	}

	/// Whether a generated call leaves the parameter declared as `parameter` to its default: an unlabeled default-valued
	/// one, or a throwing `@autoclosure` whose default begins with a plain `try`, neither `try?` nor `try!`.
	private static func isLeftToItsDefault(_ parameter: String) -> Bool {
		guard let defaultSeparator = parameter.range(of: " = ") else { return false }
		let declaration = parameter[..<defaultSeparator.lowerBound]
		let defaultValue = parameter[defaultSeparator.upperBound...]
		return parameter.hasPrefix("_ ")
			|| (declaration.contains("@autoclosure") && declaration.contains(" throws ") && defaultValue.hasPrefix("try "))
	}
}
