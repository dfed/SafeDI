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

/// Stage D1's lane B: the wrappers a node builds its type in (the four instantiators and the two lazy wrappers), the
/// `@Sendable` builder functions of the `Sendable` ones and the locals their override reads are extracted into, and the
/// by-value reads of a lazy wrapper's instance.
extension MockLowering.Walk {
	/// The expression that reads the override at `expression` where the walk is: through the extractor of the enclosing
	/// `@Sendable` builder function, which reads it into a local before that function, or else the expression itself.
	func readingOverride(_ expression: String, localNameSuffix: String) -> String {
		sendableOverrideExtractor?.extract(expression, localNameSuffix: localNameSuffix) ?? expression
	}

	/// Starts a level of the walk whose nodes are `generators`: its allocator of names holds the builder functions the
	/// level declares, and inside a `@Sendable` builder function the extractor keeps its locals apart from those and from
	/// the builder functions the level's nodes declare in their own bodies, before any read there is named.
	mutating func enterLevel(of generators: [ScopeGenerator], boundAs bindingNames: [String?]) {
		// A node named apart from a sibling declares its function under its name.
		let functionNames = Set(zip(generators, bindingNames).compactMap { generator, bindingName in
			Self.builderFunctionName(of: generator).map { functionName in bindingName.map { MockLowering.builderFunctionName(boundAs: $0) } ?? functionName }
		})
		if let sendableOverrideExtractor {
			sendableOverrideExtractor.reserve(functionNames)
			for generator in generators where generator.mockLoweringBuiltProperty != nil {
				sendableOverrideExtractor.reserve(
					generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).compactMap { child in
						child.generator.mockLoweringBuiltProperty.map { ScopeGenerator.functionName(toBuildPropertyNamed: $0.label) }
					},
				)
			}
		}
		levelNames.append(GeneratedNameAllocator(reserving: functionNames))
	}

	/// Ends the level `enterLevel(of:)` started.
	mutating func leaveLevel() {
		levelNames.removeLast()
	}

	/// Starts the extraction of the `@Sendable` builder function named `functionName`, which a node of the current level
	/// declares outside every other `@Sendable` function: its locals are claimed from the level's names. Returns the
	/// extractor that was in effect, which `endExtraction(restoring:)` restores.
	mutating func startExtraction(inFunctionNamed functionName: String) -> ScopeGenerator.SendableOverrideExtractor? {
		let enclosingExtractor = sendableOverrideExtractor
		sendableOverrideExtractor = ScopeGenerator.SendableOverrideExtractor(functionName: functionName, names: levelNames[levelNames.count - 1])
		return enclosingExtractor
	}

	/// Ends the extraction `startExtraction(inFunctionNamed:)` started, whose locals the level's later functions keep
	/// apart from, and returns the lines that read them, at `indent`, before the function.
	mutating func endExtraction(restoring enclosingExtractor: ScopeGenerator.SendableOverrideExtractor?, indent: String) -> [String] {
		guard let extractor = sendableOverrideExtractor else { return [] }
		levelNames[levelNames.count - 1] = extractor.names
		sendableOverrideExtractor = enclosingExtractor
		return extractor.extractions.map { "\(indent)let \($0.localName) = \($0.expression)" }
	}

	/// The name of the builder function the node of `generator` declares, where it builds a property.
	private static func builderFunctionName(of generator: ScopeGenerator) -> String? {
		generator.mockLoweringBuiltProperty.map { ScopeGenerator.functionName(toBuildPropertyNamed: $0.label) }
	}
}

extension MockLowering {
	/// The value a node hands its construction for each argument of `initializer` a dependency in `dependencies`
	/// fulfills, in the initializer's order: the dependency's label, or the instance of the lazy wrapper in scope where a
	/// received dependency is read by value through it (`lazilyInstantiatedInstanceProperties`), or `nil` for a receive
	/// only if available that nothing provides where the node is built (`unavailableProperties`).
	static func argumentValues(
		of initializer: Initializer,
		given dependencies: [Dependency],
		lazilyInstantiatedInstanceProperties: Set<Property>,
		unavailableProperties: Set<Property>,
	) -> [(label: String, value: String)] {
		initializer.arguments.compactMap { argument in
			guard let dependency = dependencies.first(where: argument.isFulfilled(by:)) else { return nil }
			let value = if dependency.source == .received(onlyIfAvailable: true), unavailableProperties.contains(dependency.property) {
				"nil"
			} else if dependency.source.isReceived, lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
				"\(argument.innerLabel).\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else {
				argument.innerLabel
			}
			return (label: argument.label.spelledAsArgumentLabel, value: value)
		}
	}

	/// Whether `scope` holds the lazy wrapper whose instance `property` is, by value.
	static func scope(_ scope: Set<Property>, holdsWrapperOfInstance property: Property) -> Bool {
		[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].contains { wrapperName in
			scope.contains(Property(label: property.label, typeDescription: .simple(name: wrapperName, generics: [property.typeDescription])))
		}
	}

	/// The binding of a wrapper whose type is `typeDescription`, named `bindingName`, around the builder function named
	/// `functionName`, which takes `forwardedProperties` from the wrapper's argument; the lines after the first at `indent`.
	static func wrapperBindingLines(
		of typeDescription: TypeDescription,
		named bindingName: String,
		handing functionName: String,
		forwardedProperties: [Property],
		indent: String,
	) -> [String] {
		let unwrappedType = typeDescription.unwrapped
		let binding = unwrappedType.isConstructedByAnnotation ? "\(bindingName): \(unwrappedType.asSource)" : bindingName
		let wrapperType = unwrappedType.spelledForConstruction
		guard !forwardedProperties.isEmpty else {
			return ["\(indent)let \(binding) = \(wrapperType)(\(functionName))"]
		}
		let arguments = forwardedProperties.map {
			forwardedProperties.count > 1
				? "\($0.label.spelledAsArgumentLabel): $0.\($0.label)"
				: "\($0.label.spelledAsArgumentLabel): $0"
		}
		return [
			"\(indent)let \(binding) = \(wrapperType) {",
			"\(indent)\(ScopeGenerator.standardIndent)\(functionName)(\(arguments.joined(separator: ", ")))",
			"\(indent)}",
		]
	}
}

extension ScopeGenerator {
	/// The property this generator's node builds, where it is a node that builds one rather than an alias.
	nonisolated var mockLoweringBuiltProperty: Property? {
		if case let .property(_, property, _, _, _, _) = scopeData {
			property
		} else {
			nil
		}
	}
}
