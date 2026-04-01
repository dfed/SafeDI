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

/// Generates mock extensions for `@Instantiable` types.
public struct MockGenerator: Sendable {
	// MARK: Initialization

	public init(
		typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
		mockConditionalCompilation: String?,
	) {
		self.typeDescriptionToFulfillingInstantiableMap = typeDescriptionToFulfillingInstantiableMap
		self.mockConditionalCompilation = mockConditionalCompilation

		// Build a map of erased type → concrete type from all erasedToConcreteExistential relationships.
		var erasureMap = [TypeDescription: TypeDescription]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			for dependency in instantiable.dependencies {
				if case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential) = dependency.source,
				   erasedToConcreteExistential,
				   let concreteType = fulfillingTypeDescription?.asInstantiatedType
				{
					erasureMap[dependency.property.typeDescription] = concreteType
				}
			}
		}
		erasedToConcreteTypeMap = erasureMap
	}

	// MARK: Public

	public struct GeneratedMock: Sendable {
		public let typeDescription: TypeDescription
		public let sourceFilePath: String?
		public let code: String
	}

	/// Generates mock code for the given `@Instantiable` type.
	public func generateMock(for instantiable: Instantiable) -> String {
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "

		// Collect all types in the dependency subtree.
		var treeInfo = TreeInfo()
		collectTreeInfo(
			for: instantiable,
			path: [],
			treeInfo: &treeInfo,
			visited: [],
		)

		// Collect direct dependencies as well (for received/forwarded at the top level).
		for dependency in instantiable.dependencies {
			let depType = dependency.property.typeDescription.asInstantiatedType
			let depTypeName = depType.asSource
			let sanitizedDepTypeName = sanitizeForIdentifier(depTypeName)
			switch dependency.source {
			case .received, .aliased:
				// Check if this type has an erased→concrete relationship.
				if let concreteType = erasedToConcreteTypeMap[dependency.property.typeDescription] {
					// Only add the erased type entry — the concrete type is an
					// implementation detail used in the default construction.
					if treeInfo.typeEntries[depTypeName] == nil {
						treeInfo.typeEntries[depTypeName] = TypeEntry(
							entryKey: depTypeName,
							typeDescription: depType,
							sourceType: dependency.property.typeDescription,
							hasKnownMock: true,
							erasedToConcreteExistential: true,
							wrappedConcreteType: concreteType,
							enumName: sanitizedDepTypeName,
							paramLabel: lowercaseFirst(sanitizedDepTypeName),
							isInstantiator: false,
							builtTypeForwardedProperties: [],
						)
					}
				} else if treeInfo.typeEntries[depTypeName] == nil {
					treeInfo.typeEntries[depTypeName] = TypeEntry(
						entryKey: depTypeName,
						typeDescription: depType,
						sourceType: dependency.property.typeDescription,
						hasKnownMock: typeDescriptionToFulfillingInstantiableMap[depType] != nil,
						erasedToConcreteExistential: false,
						wrappedConcreteType: nil,
						enumName: sanitizedDepTypeName,
						paramLabel: lowercaseFirst(sanitizedDepTypeName),
						isInstantiator: false,
						builtTypeForwardedProperties: [],
					)
				}
				treeInfo.typeEntries[depTypeName]?.pathCases.append(
					PathCase(name: "parent"),
				)
			case .forwarded:
				let key = dependency.property.label
				if treeInfo.forwardedEntries[key] == nil {
					treeInfo.forwardedEntries[key] = ForwardedEntry(
						label: dependency.property.label,
						typeDescription: dependency.property.typeDescription,
					)
				}
			case .instantiated:
				// Handled by collectTreeInfo
				break
			}
		}

		// Bubble up received deps from children that aren't already in the tree.
		// If a child receives a type that no one in this subtree instantiates,
		// it must become a parameter of the mock so the caller can provide it.
		bubbleUpUnresolvedReceivedDeps(&treeInfo)

		// Disambiguate entries with duplicate enumName values.
		disambiguateEnumNames(&treeInfo)

		// If there are no dependencies at all, generate a simple mock.
		if treeInfo.typeEntries.isEmpty, treeInfo.forwardedEntries.isEmpty {
			if instantiable.declarationType.isExtension {
				return generateSimpleExtensionMock(
					typeName: typeName,
					mockAttributesPrefix: mockAttributesPrefix,
				)
			} else {
				return generateSimpleMock(
					typeName: typeName,
					mockAttributesPrefix: mockAttributesPrefix,
				)
			}
		}

		// Build the mock code.
		let indent = "    "

		// Generate SafeDIMockPath enum.
		var enumLines = [String]()
		enumLines.append("\(indent)public enum SafeDIMockPath {")
		for (_, entry) in treeInfo.typeEntries.sorted(by: { $0.key < $1.key }) {
			let uniqueCases = entry.pathCases.map(\.name).uniqued()
			let casesStr = uniqueCases.map { "case \($0)" }.joined(separator: "; ")
			enumLines.append("\(indent)\(indent)public enum \(entry.enumName) { \(casesStr) }")
		}
		enumLines.append("\(indent)}")

		// Generate mock method signature.
		var params = [String]()
		for (_, entry) in treeInfo.forwardedEntries.sorted(by: { $0.key < $1.key }) {
			params.append("\(indent)\(indent)\(entry.label): \(entry.typeDescription.asSource)")
		}
		for (_, entry) in treeInfo.typeEntries.sorted(by: { $0.key < $1.key }) {
			let sourceTypeName = entry.sourceType.asSource
			if entry.hasKnownMock {
				params.append("\(indent)\(indent)\(entry.paramLabel): ((SafeDIMockPath.\(entry.enumName)) -> \(sourceTypeName))? = nil")
			} else {
				params.append("\(indent)\(indent)\(entry.paramLabel): @escaping (SafeDIMockPath.\(entry.enumName)) -> \(sourceTypeName)")
			}
		}
		let paramsStr = params.joined(separator: ",\n")

		// Generate mock method body.
		let bodyLines = generateMockBody(
			instantiable: instantiable,
			treeInfo: treeInfo,
			indent: indent,
		)

		var lines = [String]()
		lines.append("extension \(typeName) {")
		lines.append(contentsOf: enumLines)
		lines.append("")
		lines.append("\(indent)\(mockAttributesPrefix)public static func mock(")
		lines.append(paramsStr)
		lines.append("\(indent)) -> \(typeName) {")
		lines.append(contentsOf: bodyLines)
		lines.append("\(indent)}")
		lines.append("}")

		let code = lines.joined(separator: "\n")
		return wrapInConditionalCompilation(code)
	}

	// MARK: Private

	private let typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
	private let mockConditionalCompilation: String?

	private func wrapInConditionalCompilation(_ code: String) -> String {
		if let mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(code)\n#endif"
		} else {
			code
		}
	}

	/// Maps erased wrapper types to their concrete fulfilling types (from erasedToConcreteExistential relationships).
	private let erasedToConcreteTypeMap: [TypeDescription: TypeDescription]

	// MARK: Tree Analysis

	private struct PathCase: Equatable {
		let name: String
	}

	private struct TypeEntry {
		/// The key used to store this entry in `TreeInfo.typeEntries`.
		let entryKey: String
		let typeDescription: TypeDescription
		let sourceType: TypeDescription
		/// Whether this type is in the type map and will have a generated mock().
		let hasKnownMock: Bool
		/// When true, the sourceType is a type-erased wrapper around a concrete type.
		let erasedToConcreteExistential: Bool
		/// For erased types, the concrete type that this wraps.
		let wrappedConcreteType: TypeDescription?
		/// The enum name for this entry in SafeDIMockPath. May be mutated during disambiguation.
		var enumName: String
		/// The parameter label for this entry in mock().
		var paramLabel: String
		/// Whether this entry represents an Instantiator/ErasedInstantiator property.
		let isInstantiator: Bool
		/// Forwarded properties of the built type (for Instantiator closure parameters).
		let builtTypeForwardedProperties: [ForwardedEntry]
		var pathCases = [PathCase]()
	}

	private struct ForwardedEntry {
		let label: String
		let typeDescription: TypeDescription
	}

	private struct TreeInfo {
		var typeEntries = [String: TypeEntry]() // keyed by enumName
		var forwardedEntries = [String: ForwardedEntry]() // keyed by label
	}

	private func collectTreeInfo(
		for instantiable: Instantiable,
		path: [String],
		treeInfo: inout TreeInfo,
		visited: Set<TypeDescription>,
	) {
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				let depType = (fulfillingTypeDescription ?? dependency.property.typeDescription).asInstantiatedType
				let caseName = path.isEmpty ? "root" : path.joined(separator: "_")
				let isInstantiator = !dependency.property.propertyType.isConstant

				// Determine enum name and param label.
				var enumName: String
				var paramLabel: String
				if isInstantiator {
					// Instantiator types use property label (capitalized) as enum name.
					let label = dependency.property.label
					enumName = String(label.prefix(1).uppercased()) + label.dropFirst()
					paramLabel = label
				} else if erasedToConcreteExistential {
					// Erased types: use the concrete type name for the concrete entry.
					enumName = sanitizeForIdentifier(depType.asSource)
					paramLabel = lowercaseFirst(sanitizeForIdentifier(depType.asSource))
				} else {
					enumName = sanitizeForIdentifier(depType.asSource)
					paramLabel = lowercaseFirst(sanitizeForIdentifier(depType.asSource))
				}

				// Collect forwarded properties of the built type (for Instantiator closures).
				var forwardedProps = [ForwardedEntry]()
				if isInstantiator, let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[depType] {
					forwardedProps = builtInstantiable.dependencies
						.filter { $0.source == .forwarded }
						.map { ForwardedEntry(label: $0.property.label, typeDescription: $0.property.typeDescription) }
				}

				// Key by type name for constant deps, property label for Instantiator deps.
				// This ensures different types don't overwrite each other.
				let entryKey = isInstantiator ? dependency.property.label : depType.asSource
				if treeInfo.typeEntries[entryKey] == nil {
					treeInfo.typeEntries[entryKey] = TypeEntry(
						entryKey: entryKey,
						typeDescription: depType,
						sourceType: isInstantiator ? dependency.property.typeDescription : (erasedToConcreteExistential ? depType : dependency.property.typeDescription),
						hasKnownMock: typeDescriptionToFulfillingInstantiableMap[depType] != nil,
						erasedToConcreteExistential: false,
						wrappedConcreteType: nil,
						enumName: enumName,
						paramLabel: paramLabel,
						isInstantiator: isInstantiator,
						builtTypeForwardedProperties: forwardedProps,
					)
				}
				treeInfo.typeEntries[entryKey]?.pathCases.append(
					PathCase(name: caseName),
				)

				// For erasedToConcreteExistential, also add an entry for the erased wrapper.
				if erasedToConcreteExistential {
					let erasedType = dependency.property.typeDescription
					let erasedKey = erasedType.asSource
					if treeInfo.typeEntries[erasedKey] == nil {
						treeInfo.typeEntries[erasedKey] = TypeEntry(
							entryKey: erasedKey,
							typeDescription: erasedType,
							sourceType: erasedType,
							hasKnownMock: true,
							erasedToConcreteExistential: true,
							wrappedConcreteType: depType,
							enumName: sanitizeForIdentifier(erasedType.asSource),
							paramLabel: lowercaseFirst(sanitizeForIdentifier(erasedType.asSource)),
							isInstantiator: false,
							builtTypeForwardedProperties: [],
						)
					}
					treeInfo.typeEntries[erasedKey]?.pathCases.append(
						PathCase(name: caseName),
					)
				}

				// Recurse into built type's tree (Instantiator is NOT a boundary).
				guard !visited.contains(depType) else { continue }
				if let childInstantiable = typeDescriptionToFulfillingInstantiableMap[depType] {
					var newVisited = visited
					newVisited.insert(depType)
					collectTreeInfo(
						for: childInstantiable,
						path: path + [dependency.property.label],
						treeInfo: &treeInfo,
						visited: newVisited,
					)
				}
			case .received, .aliased:
				// Received deps at non-root level don't get their own parameter
				// (they're threaded from parent scope). Only top-level received deps
				// are added as parameters (done in generateMock).
				break
			case .forwarded:
				break
			}
		}
	}

	// MARK: Code Generation

	private func generateSimpleMock(
		typeName: String,
		mockAttributesPrefix: String,
	) -> String {
		let code = """
		extension \(typeName) {
		    \(mockAttributesPrefix)public static func mock() -> \(typeName) {
		        \(typeName)()
		    }
		}
		"""
		return wrapInConditionalCompilation(code)
	}

	private func generateSimpleExtensionMock(
		typeName: String,
		mockAttributesPrefix: String,
	) -> String {
		let code = """
		extension \(typeName) {
		    \(mockAttributesPrefix)public static func mock() -> \(typeName) {
		        \(typeName).instantiate()
		    }
		}
		"""
		return wrapInConditionalCompilation(code)
	}

	private func generateMockBody(
		instantiable: Instantiable,
		treeInfo: TreeInfo,
		indent: String,
	) -> [String] {
		var lines = [String]()
		let bodyIndent = "\(indent)\(indent)"
		var constructedVariables = [String: String]() // typeDescription.asSource -> local var name

		// Phase 1: Register forwarded properties (they're just parameters, no closures).
		for (_, entry) in treeInfo.forwardedEntries.sorted(by: { $0.key < $1.key }) {
			constructedVariables[entry.typeDescription.asSource] = entry.label
		}

		// Compute which Instantiator entries should be constructed inside another
		// Instantiator's closure (because they depend on that Instantiator's forwarded props).
		let nestedEntriesByParent = computeNestedEntriesByParent(treeInfo: treeInfo)
		let allNestedEntryKeys = Set(nestedEntriesByParent.values.flatMap(\.self))

		// Phase 2: Topologically sort all type entries and construct in order.
		let sortedEntries = topologicallySortedEntries(treeInfo: treeInfo)
		for entry in sortedEntries {
			// Skip entries that are nested inside another Instantiator's closure.
			if allNestedEntryKeys.contains(entry.entryKey) { continue }

			let concreteTypeName = entry.typeDescription.asSource
			let sourceTypeName = entry.sourceType.asSource
			guard constructedVariables[concreteTypeName] == nil, constructedVariables[sourceTypeName] == nil else { continue }

			// Pick the first path case for this type's closure call.
			guard let pathCase = entry.pathCases.first?.name else { continue }
			let dotPathCase = pathCase.contains(".") ? pathCase : ".\(pathCase)"

			if entry.isInstantiator {
				// Instantiator entries: wrap inline tree in Instantiator { forwarded in ... }
				let instantiatorDefault = buildInstantiatorDefault(
					for: entry,
					nestedEntriesByParent: nestedEntriesByParent,
					treeInfo: treeInfo,
					constructedVariables: constructedVariables,
					indent: bodyIndent,
				)
				lines.append("\(bodyIndent)let \(entry.paramLabel) = \(entry.paramLabel)?(\(dotPathCase))")
				lines.append("\(bodyIndent)    ?? \(instantiatorDefault)")
				constructedVariables[sourceTypeName] = entry.paramLabel
			} else if entry.hasKnownMock {
				let defaultExpr: String
				if entry.erasedToConcreteExistential, let wrappedConcreteType = entry.wrappedConcreteType {
					let concreteExpr = if let existingVar = constructedVariables[wrappedConcreteType.asSource] {
						existingVar
					} else {
						buildInlineConstruction(for: wrappedConcreteType, constructedVariables: constructedVariables)
					}
					defaultExpr = "\(sourceTypeName)(\(concreteExpr))"
				} else {
					defaultExpr = buildInlineConstruction(
						for: entry.typeDescription,
						constructedVariables: constructedVariables,
					)
				}
				lines.append("\(bodyIndent)let \(entry.paramLabel) = \(entry.paramLabel)?(\(dotPathCase)) ?? \(defaultExpr)")
				constructedVariables[concreteTypeName] = entry.paramLabel
			} else {
				lines.append("\(bodyIndent)let \(entry.paramLabel) = \(entry.paramLabel)(\(dotPathCase))")
				constructedVariables[concreteTypeName] = entry.paramLabel
			}
		}

		// Phase 3: Construct the final return value.
		if let initializer = instantiable.initializer {
			let argList = initializer.arguments.compactMap { arg -> String? in
				let constructedVariableName = constructedVariables[arg.typeDescription.asInstantiatedType.asSource]
					?? constructedVariables[arg.typeDescription.asSource]
				if let constructedVariableName {
					return "\(arg.label): \(constructedVariableName)"
				} else {
					// Arg has a default value or is not a tracked dependency.
					return nil
				}
			}.joined(separator: ", ")
			let typeName = instantiable.concreteInstantiable.asSource
			if instantiable.declarationType.isExtension {
				lines.append("\(bodyIndent)return \(typeName).instantiate(\(argList))")
			} else {
				lines.append("\(bodyIndent)return \(typeName)(\(argList))")
			}
		}

		return lines
	}

	/// Builds the default value for an Instantiator entry: `Instantiator { forwarded in ... }`.
	private func buildInstantiatorDefault(
		for entry: TypeEntry,
		nestedEntriesByParent: [String: [String]],
		treeInfo: TreeInfo,
		constructedVariables: [String: String],
		indent: String,
	) -> String {
		let builtType = entry.typeDescription
		let propertyType = entry.sourceType
		let forwardedProps = entry.builtTypeForwardedProperties
		let isSendable = propertyType.asSource.hasPrefix("Sendable")

		// Build the closure parameter list from forwarded properties.
		let closureParams: String
		if forwardedProps.isEmpty {
			closureParams = ""
		} else if forwardedProps.count == 1 {
			closureParams = " \(forwardedProps[0].label) in"
		} else {
			// Multiple forwarded properties: tuple destructuring.
			let labels = forwardedProps.map(\.label).joined(separator: ", ")
			closureParams = " (\(labels)) in"
		}

		// Build the type's initializer call inside the closure.
		let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[builtType]
		let initializer = builtInstantiable?.initializer

		// Build constructor args: forwarded from closure params, received from parent scope.
		var closureConstructedVariables = constructedVariables
		for fwd in forwardedProps {
			closureConstructedVariables[fwd.typeDescription.asSource] = fwd.label
		}

		let closureIndent = "\(indent)    "
		var closureBodyLines = [String]()

		// Construct nested entries inside this closure (both Instantiator and
		// constant entries that depend on this closure's forwarded types).
		if let nestedKeys = nestedEntriesByParent[entry.entryKey] {
			let nestedEntries = nestedKeys.compactMap { treeInfo.typeEntries[$0] }
			let nestedTypeNames = Set(nestedEntries.map(\.typeDescription.asSource))
			let sortedNestedEntries = nestedEntries.sorted { entryA, _ in
				guard let instantiableA = typeDescriptionToFulfillingInstantiableMap[entryA.typeDescription] else {
					return true
				}
				return !instantiableA.dependencies.contains { dependency in
					let dependencyTypeName = dependency.property.typeDescription.asInstantiatedType.asSource
					return nestedTypeNames.contains(dependencyTypeName)
				}
			}
			for nestedEntry in sortedNestedEntries {
				let pathCase = nestedEntry.pathCases.first?.name ?? "root"
				let dotPathCase = pathCase.contains(".") ? pathCase : ".\(pathCase)"
				if nestedEntry.isInstantiator {
					let nestedDefault = buildInstantiatorDefault(
						for: nestedEntry,
						nestedEntriesByParent: nestedEntriesByParent,
						treeInfo: treeInfo,
						constructedVariables: closureConstructedVariables,
						indent: closureIndent,
					)
					closureBodyLines.append("\(closureIndent)let \(nestedEntry.paramLabel) = \(nestedEntry.paramLabel)?(\(dotPathCase))")
					closureBodyLines.append("\(closureIndent)    ?? \(nestedDefault)")
					closureConstructedVariables[nestedEntry.sourceType.asSource] = nestedEntry.paramLabel
				} else {
					// Constant entry nested inside the closure.
					let defaultExpression = buildInlineConstruction(
						for: nestedEntry.typeDescription,
						constructedVariables: closureConstructedVariables,
					)
					if nestedEntry.hasKnownMock {
						closureBodyLines.append("\(closureIndent)let \(nestedEntry.paramLabel) = \(nestedEntry.paramLabel)?(\(dotPathCase)) ?? \(defaultExpression)")
					} else {
						closureBodyLines.append("\(closureIndent)let \(nestedEntry.paramLabel) = \(nestedEntry.paramLabel)(\(dotPathCase))")
					}
					closureConstructedVariables[nestedEntry.typeDescription.asSource] = nestedEntry.paramLabel
				}
			}
		}

		// Build lookup including aliased deps and fulfilling types.
		var argumentLabelToConstructedVariableName = [String: String]()
		if let builtInstantiable {
			for dependency in builtInstantiable.dependencies {
				let declaredType = dependency.property.typeDescription.asInstantiatedType.asSource
				if let constructedVariableName = closureConstructedVariables[declaredType] ?? closureConstructedVariables[dependency.property.typeDescription.asSource] {
					argumentLabelToConstructedVariableName[dependency.property.label] = constructedVariableName
					continue
				}
				if case let .aliased(fulfillingProperty, _, _) = dependency.source {
					let fulfillingType = fulfillingProperty.typeDescription.asInstantiatedType.asSource
					if let constructedVariableName = closureConstructedVariables[fulfillingType] ?? closureConstructedVariables[fulfillingProperty.typeDescription.asSource] {
						argumentLabelToConstructedVariableName[dependency.property.label] = constructedVariableName
						continue
					}
				}
				// Check if the concrete fulfilling type is in scope.
				if let fulfillingInstantiable = typeDescriptionToFulfillingInstantiableMap[dependency.property.typeDescription.asInstantiatedType] {
					let concreteTypeName = fulfillingInstantiable.concreteInstantiable.asSource
					if let constructedVariableName = closureConstructedVariables[concreteTypeName] {
						argumentLabelToConstructedVariableName[dependency.property.label] = constructedVariableName
					}
				}
			}
		}

		let dependencyByLabel = Dictionary(
			(builtInstantiable?.dependencies ?? []).map { ($0.property.label, $0) },
			uniquingKeysWith: { first, _ in first },
		)
		let args = (initializer?.arguments ?? []).compactMap { [self] arg -> String? in
			if let constructedVariableName = argumentLabelToConstructedVariableName[arg.innerLabel] {
				return "\(arg.label): \(constructedVariableName)"
			} else if let constructedVariableName = closureConstructedVariables[arg.typeDescription.asInstantiatedType.asSource]
				?? closureConstructedVariables[arg.typeDescription.asSource]
			{
				return "\(arg.label): \(constructedVariableName)"
			} else if arg.typeDescription.isOptional {
				// Optional arg not in scope — pass nil.
				return "\(arg.label): nil"
			} else if let dependency = dependencyByLabel[arg.innerLabel] {
				let cycleGuard: Set<TypeDescription> = [builtType]
				if dependency.property.propertyType.isConstant {
					return "\(arg.label): \(buildInlineConstruction(for: arg.typeDescription.asInstantiatedType, constructedVariables: closureConstructedVariables, visitedTypes: cycleGuard))"
				} else {
					return "\(arg.label): \(buildInlineInstantiatorExpression(for: dependency, constructedVariables: closureConstructedVariables, visitedTypes: cycleGuard))"
				}
			} else {
				// Arg has a default value.
				return nil
			}
		}.joined(separator: ", ")

		let typeName = (builtInstantiable?.concreteInstantiable ?? builtType).asSource
		let construction = if builtInstantiable?.declarationType.isExtension == true {
			"\(typeName).instantiate(\(args))"
		} else {
			"\(typeName)(\(args))"
		}

		closureBodyLines.append("\(closureIndent)\(construction)")

		let closureBody = closureBodyLines.joined(separator: "\n")
		let sendablePrefix = isSendable ? " @Sendable" : ""
		return "\(propertyType.asSource) {\(sendablePrefix)\(closureParams)\n\(closureBody)\n\(indent)}"
	}

	/// Determines which entries should be constructed inside an Instantiator's
	/// closure because they depend (directly, via alias, or via fulfilling type)
	/// on that Instantiator's forwarded props which are not available at root scope.
	/// Returns: parentEntryKey → [nestedEntryKeys]
	private func computeNestedEntriesByParent(treeInfo: TreeInfo) -> [String: [String]] {
		var result = [String: [String]]()

		let instantiatorEntries = treeInfo.typeEntries.filter(\.value.isInstantiator)

		// Types available at root scope: non-Instantiator entries + root-level forwarded entries.
		var rootAvailableTypes = Set<String>()
		for (_, entry) in treeInfo.typeEntries where !entry.isInstantiator {
			rootAvailableTypes.insert(entry.typeDescription.asSource)
		}
		for (_, forwardedEntry) in treeInfo.forwardedEntries {
			rootAvailableTypes.insert(forwardedEntry.typeDescription.asSource)
		}

		for (parentKey, parentEntry) in instantiatorEntries where !parentEntry.builtTypeForwardedProperties.isEmpty {
			let forwardedTypeNames = Set(parentEntry.builtTypeForwardedProperties.map(\.typeDescription.asSource))

			// Check ALL entries (not just Instantiators) — constant entries that
			// receive a forwarded type also need to be nested inside the closure.
			for (childKey, childEntry) in treeInfo.typeEntries where childKey != parentKey {
				guard let childInstantiable = typeDescriptionToFulfillingInstantiableMap[childEntry.typeDescription] else {
					continue
				}
				let needsNesting = childInstantiable.dependencies.contains { dependency in
					guard dependency.source != .forwarded else { return false }
					// Collect all type names this dep resolves to:
					// declared type, aliased fulfilling type, AND the concrete type
					// that fulfills this dep's type in the DI graph.
					var relevantTypeNames = [
						dependency.property.typeDescription.asInstantiatedType.asSource,
					]
					if case let .aliased(fulfillingProperty, _, _) = dependency.source {
						relevantTypeNames.append(fulfillingProperty.typeDescription.asInstantiatedType.asSource)
					}
					// Also check the concrete fulfilling type (e.g., UserVendor fulfilled by UserManager).
					if let fulfillingInstantiable = typeDescriptionToFulfillingInstantiableMap[dependency.property.typeDescription.asInstantiatedType] {
						relevantTypeNames.append(fulfillingInstantiable.concreteInstantiable.asSource)
					}
					// Needs nesting if any relevant type matches a forwarded type
					// and is not available at root scope.
					return relevantTypeNames.contains { name in
						forwardedTypeNames.contains(name)
							&& !rootAvailableTypes.contains(name)
					}
				}
				if needsNesting {
					result[parentKey, default: []].append(childKey)
				}
			}
		}

		return result
	}

	/// Checks if a dependency is unresolved — i.e., its type (or fulfilling type for aliases)
	/// is in the tree but not yet resolved.
	private func isDependencyUnresolved(
		_ dep: Dependency,
		allTypeNames: Set<String>,
		resolved: Set<String>,
	) -> Bool {
		guard dep.source != .forwarded else { return false }
		// Check the declared property type.
		let declaredTypeName = dep.property.typeDescription.asInstantiatedType.asSource
		if allTypeNames.contains(declaredTypeName), !resolved.contains(declaredTypeName) {
			return true
		}
		// For aliased deps, also check the fulfilling property type.
		if case let .aliased(fulfillingProperty, _, _) = dep.source {
			let fulfillingTypeName = fulfillingProperty.typeDescription.asInstantiatedType.asSource
			if allTypeNames.contains(fulfillingTypeName), !resolved.contains(fulfillingTypeName) {
				return true
			}
		}
		return false
	}

	/// Sorts type entries in dependency order: types with no unresolved deps first.
	private func topologicallySortedEntries(treeInfo: TreeInfo) -> [TypeEntry] {
		let entries = treeInfo.typeEntries.values.sorted(by: { $0.enumName < $1.enumName })
		let allTypeNames = Set(entries.map(\.typeDescription.asSource))
		var result = [TypeEntry]()
		var resolved = Set<String>()
		// Also consider forwarded types as resolved.
		for (_, fwd) in treeInfo.forwardedEntries {
			resolved.insert(fwd.typeDescription.asSource)
		}

		// Iteratively add entries whose dependencies are all resolved.
		var remaining = entries
		while !remaining.isEmpty {
			let previousCount = remaining.count
			remaining = remaining.filter { entry in
				let typeName = entry.typeDescription.asSource
				// Erased types depend on their wrapped concrete type.
				if entry.erasedToConcreteExistential, let wrappedConcreteType = entry.wrappedConcreteType {
					let wrappedName = wrappedConcreteType.asSource
					if allTypeNames.contains(wrappedName), !resolved.contains(wrappedName) {
						return true // Keep waiting for concrete type.
					}
					result.append(entry)
					resolved.insert(typeName)
					return false
				}
				// Instantiator entries depend on all types they capture from parent scope.
				if entry.isInstantiator {
					if let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[entry.typeDescription] {
						let hasUnresolvedDeps = builtInstantiable.dependencies.contains {
							isDependencyUnresolved($0, allTypeNames: allTypeNames, resolved: resolved)
						}
						if hasUnresolvedDeps { return true }
					}
					result.append(entry)
					resolved.insert(typeName)
					return false
				}
				guard let instantiable = typeDescriptionToFulfillingInstantiableMap[entry.typeDescription] else {
					// Unknown type — has no dependencies we track.
					result.append(entry)
					resolved.insert(typeName)
					return false
				}
				let hasUnresolvedDeps = instantiable.dependencies.contains {
					isDependencyUnresolved($0, allTypeNames: allTypeNames, resolved: resolved)
				}
				if !hasUnresolvedDeps {
					result.append(entry)
					resolved.insert(typeName)
					return false
				}
				return true
			}
			if remaining.count == previousCount {
				// No progress — break cycle by adding remaining in order.
				result.append(contentsOf: remaining)
				break
			}
		}
		return result
	}

	private func buildInlineConstruction(
		for typeDescription: TypeDescription,
		constructedVariables: [String: String],
		visitedTypes: Set<TypeDescription> = [],
	) -> String {
		let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription]
		let typeName = (instantiable?.concreteInstantiable ?? typeDescription).asSource

		// Break cycles: if we've already visited this type, emit a no-arg call.
		guard !visitedTypes.contains(typeDescription) else {
			return "\(typeName)()"
		}

		// Build a map from init arg label → constructed var name, checking both
		// the declared type AND the fulfilling type for aliased dependencies.
		guard let instantiable, let initializer = instantiable.initializer else {
			return "\(typeName)()"
		}

		// Build lookup: for each dependency, map the init arg label to the constructed var.
		var argumentLabelToConstructedVariableName = [String: String]()
		for dependency in instantiable.dependencies {
			// Check the declared property type.
			let declaredType = dependency.property.typeDescription.asInstantiatedType.asSource
			if let constructedVariableName = constructedVariables[declaredType] ?? constructedVariables[dependency.property.typeDescription.asSource] {
				argumentLabelToConstructedVariableName[dependency.property.label] = constructedVariableName
				continue
			}
			// For aliased deps, check the fulfilling property type.
			if case let .aliased(fulfillingProperty, _, _) = dependency.source {
				let fulfillingType = fulfillingProperty.typeDescription.asInstantiatedType.asSource
				if let constructedVariableName = constructedVariables[fulfillingType] ?? constructedVariables[fulfillingProperty.typeDescription.asSource] {
					argumentLabelToConstructedVariableName[dependency.property.label] = constructedVariableName
					continue
				}
			}
			// Check if the concrete type that fulfills this dep (from the DI graph)
			// is available in scope. E.g., UserVendor fulfilled by UserManager.
			if let fulfillingInstantiable = typeDescriptionToFulfillingInstantiableMap[dependency.property.typeDescription.asInstantiatedType] {
				let concreteTypeName = fulfillingInstantiable.concreteInstantiable.asSource
				if let constructedVariableName = constructedVariables[concreteTypeName] {
					argumentLabelToConstructedVariableName[dependency.property.label] = constructedVariableName
				}
			}
		}

		// Build inline using initializer — always call init, never .mock(),
		// so that parent-scope dependencies are threaded to the child.
		let dependencyByLabel = Dictionary(
			instantiable.dependencies.map { ($0.property.label, $0) },
			uniquingKeysWith: { first, _ in first },
		)
		let args = initializer.arguments.compactMap { [self] arg -> String? in
			if let constructedVariableName = argumentLabelToConstructedVariableName[arg.innerLabel] {
				return "\(arg.label): \(constructedVariableName)"
			} else if let constructedVariableName = constructedVariables[arg.typeDescription.asInstantiatedType.asSource]
				?? constructedVariables[arg.typeDescription.asSource]
			{
				return "\(arg.label): \(constructedVariableName)"
			} else if arg.typeDescription.isOptional {
				// Optional arg not in scope — pass nil.
				return "\(arg.label): nil"
			} else if let dependency = dependencyByLabel[arg.innerLabel] {
				var childVisitedTypes = visitedTypes
				childVisitedTypes.insert(typeDescription)
				if dependency.property.propertyType.isConstant {
					// Required constant dep not in scope — construct recursively.
					return "\(arg.label): \(buildInlineConstruction(for: arg.typeDescription.asInstantiatedType, constructedVariables: constructedVariables, visitedTypes: childVisitedTypes))"
				} else {
					// Instantiator dep not in scope — build closure wrapper.
					return "\(arg.label): \(buildInlineInstantiatorExpression(for: dependency, constructedVariables: constructedVariables, visitedTypes: childVisitedTypes))"
				}
			} else {
				// Arg has a default value.
				return nil
			}
		}.joined(separator: ", ")

		if instantiable.declarationType.isExtension {
			return "\(typeName).instantiate(\(args))"
		}
		return "\(typeName)(\(args))"
	}

	/// Builds an inline Instantiator expression for a dependency that is an
	/// Instantiator/ErasedInstantiator property not found in constructedVariables.
	/// Produces e.g. `Instantiator<T> { forwarded in T(forwarded: forwarded, received: var) }`.
	private func buildInlineInstantiatorExpression(
		for dependency: Dependency,
		constructedVariables: [String: String],
		visitedTypes: Set<TypeDescription> = [],
	) -> String {
		let propertyType = dependency.property.typeDescription
		let builtType = dependency.property.typeDescription.asInstantiatedType
		let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[builtType]
		let isSendable = propertyType.asSource.hasPrefix("Sendable")

		// Get forwarded properties of the built type.
		let forwardedProperties = builtInstantiable?.dependencies
			.filter { $0.source == .forwarded }
			.map { ForwardedEntry(label: $0.property.label, typeDescription: $0.property.typeDescription) }
			?? []

		// Build closure params from forwarded properties.
		let closureParams: String
		if forwardedProperties.isEmpty {
			closureParams = ""
		} else if forwardedProperties.count == 1 {
			closureParams = " \(forwardedProperties[0].label) in"
		} else {
			let labels = forwardedProperties.map(\.label).joined(separator: ", ")
			closureParams = " (\(labels)) in"
		}

		// Build constructor args inside the closure.
		var closureConstructedVariables = constructedVariables
		for forwardedProperty in forwardedProperties {
			closureConstructedVariables[forwardedProperty.typeDescription.asSource] = forwardedProperty.label
		}
		let inlineConstruction = buildInlineConstruction(
			for: builtType,
			constructedVariables: closureConstructedVariables,
			visitedTypes: visitedTypes,
		)

		let sendablePrefix = isSendable ? " @Sendable" : ""
		return "\(propertyType.asSource) {\(sendablePrefix)\(closureParams) \(inlineConstruction) }"
	}

	/// Scans all types in the tree and adds entries for received deps
	/// that aren't already accounted for. This ensures that if a child
	/// receives a type not instantiated in this subtree, it bubbles up
	/// as a parameter of the mock method.
	private func bubbleUpUnresolvedReceivedDeps(_ treeInfo: inout TreeInfo) {
		// Keep iterating until no new entries are added, to handle transitive cases.
		var didAddEntry = true
		while didAddEntry {
			didAddEntry = false
			// Collect all type names available in the tree — both the entry keys
			// (type names for constant entries, labels for Instantiator entries)
			// and the actual typeDescription names (the built types).
			var typesInTree = Set(treeInfo.typeEntries.keys)
			for (_, entry) in treeInfo.typeEntries {
				typesInTree.insert(entry.typeDescription.asSource)
				typesInTree.insert(entry.sourceType.asSource)
			}
			// Collect all types available as forwarded properties (root-level + inside Instantiator closures).
			var availableForwardedTypes = Set<String>()
			for (_, forwardedEntry) in treeInfo.forwardedEntries {
				availableForwardedTypes.insert(forwardedEntry.typeDescription.asSource)
			}
			for (_, entry) in treeInfo.typeEntries where entry.isInstantiator {
				for forwardedProperty in entry.builtTypeForwardedProperties {
					availableForwardedTypes.insert(forwardedProperty.typeDescription.asSource)
				}
			}

			for entry in treeInfo.typeEntries.values {
				guard let instantiable = typeDescriptionToFulfillingInstantiableMap[entry.typeDescription] else {
					continue
				}
				for dependency in instantiable.dependencies {
					switch dependency.source {
					case .received(onlyIfAvailable: false),
					     .aliased(fulfillingProperty: _, erasedToConcreteExistential: _, onlyIfAvailable: false):
						break // Process below.
					case .instantiated, .forwarded,
					     .received(onlyIfAvailable: true),
					     .aliased(fulfillingProperty: _, erasedToConcreteExistential: _, onlyIfAvailable: true):
						continue
					}
					let dependencyType = dependency.property.typeDescription.asInstantiatedType
					let dependencyTypeName = dependencyType.asSource
					// Skip if already in the tree or available as a forwarded type.
					guard !typesInTree.contains(dependencyTypeName),
					      !availableForwardedTypes.contains(dependency.property.typeDescription.asSource)
					else { continue }
					// For aliased deps, skip if the fulfilling type is already resolvable.
					if case let .aliased(fulfillingProperty, _, _) = dependency.source {
						let fulfillingTypeName = fulfillingProperty.typeDescription.asInstantiatedType.asSource
						if typesInTree.contains(fulfillingTypeName)
							|| availableForwardedTypes.contains(fulfillingProperty.typeDescription.asSource)
						{
							continue
						}
					}
					// Skip if the concrete type that fulfills this dep (from the DI graph)
					// is available as a forwarded type — it will be resolved inside
					// the Instantiator closure via nesting, preserving alias identity.
					if let fulfillingInstantiable = typeDescriptionToFulfillingInstantiableMap[dependencyType] {
						let concreteTypeName = fulfillingInstantiable.concreteInstantiable.asSource
						if availableForwardedTypes.contains(concreteTypeName) {
							continue
						}
					}
					let sanitizedDependencyTypeName = sanitizeForIdentifier(dependencyTypeName)
					treeInfo.typeEntries[dependencyTypeName] = TypeEntry(
						entryKey: dependencyTypeName,
						typeDescription: dependencyType,
						sourceType: dependency.property.typeDescription,
						hasKnownMock: typeDescriptionToFulfillingInstantiableMap[dependencyType] != nil,
						erasedToConcreteExistential: false,
						wrappedConcreteType: nil,
						enumName: sanitizedDependencyTypeName,
						paramLabel: lowercaseFirst(sanitizedDependencyTypeName),
						isInstantiator: false,
						builtTypeForwardedProperties: [],
					)
					treeInfo.typeEntries[dependencyTypeName]?.pathCases.append(
						PathCase(name: "parent"),
					)
					didAddEntry = true
				}
			}
		}
	}

	private func lowercaseFirst(_ string: String) -> String {
		guard let first = string.first else { return string }
		return String(first.lowercased()) + string.dropFirst()
	}

	/// Converts a type name to a valid Swift identifier by replacing special characters.
	/// e.g. `Container<Bool>` → `Container__Bool`
	/// Detects duplicate `enumName` values and appends a sanitized type suffix to disambiguate.
	private func disambiguateEnumNames(_ treeInfo: inout TreeInfo) {
		// Group entries by enumName.
		var enumNameToKeys = [String: [String]]()
		for (key, entry) in treeInfo.typeEntries {
			enumNameToKeys[entry.enumName, default: []].append(key)
		}
		// For each group with duplicates, append the sanitized sourceType to disambiguate.
		for (_, keys) in enumNameToKeys where keys.count > 1 {
			for key in keys {
				guard var entry = treeInfo.typeEntries[key] else { continue }
				let suffix = sanitizeForIdentifier(entry.sourceType.asSource)
				entry.enumName = "\(entry.enumName)_\(suffix)"
				entry.paramLabel = "\(entry.paramLabel)_\(lowercaseFirst(suffix))"
				treeInfo.typeEntries[key] = entry
			}
		}
	}

	private func sanitizeForIdentifier(_ typeName: String) -> String {
		typeName
			.replacingOccurrences(of: "<", with: "__")
			.replacingOccurrences(of: ">", with: "")
			.replacingOccurrences(of: "->", with: "_to_")
			.replacingOccurrences(of: ", ", with: "_")
			.replacingOccurrences(of: ",", with: "_")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "[", with: "Array_")
			.replacingOccurrences(of: "]", with: "")
			.replacingOccurrences(of: ":", with: "_")
			.replacingOccurrences(of: "(", with: "")
			.replacingOccurrences(of: ")", with: "")
			.replacingOccurrences(of: "&", with: "_and_")
			.replacingOccurrences(of: "?", with: "_Optional")
			.replacingOccurrences(of: " ", with: "")
	}
}

// MARK: - Array Extension

extension Array where Element: Hashable {
	fileprivate func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
