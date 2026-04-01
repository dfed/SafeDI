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
		let typeDescription: TypeDescription
		let sourceType: TypeDescription
		/// Whether this type is in the type map and will have a generated mock().
		let hasKnownMock: Bool
		/// When true, the sourceType is a type-erased wrapper around a concrete type.
		let erasedToConcreteExistential: Bool
		/// For erased types, the concrete type that this wraps.
		let wrappedConcreteType: TypeDescription?
		/// The enum name for this entry in SafeDIMockPath.
		let enumName: String
		/// The parameter label for this entry in mock().
		let paramLabel: String
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
				let enumName: String
				let paramLabel: String
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

				let entryKey = enumName
				if treeInfo.typeEntries[entryKey] == nil {
					treeInfo.typeEntries[entryKey] = TypeEntry(
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
		var constructedVars = [String: String]() // typeDescription.asSource -> local var name

		// Phase 1: Register forwarded properties (they're just parameters, no closures).
		for (_, entry) in treeInfo.forwardedEntries.sorted(by: { $0.key < $1.key }) {
			constructedVars[entry.typeDescription.asSource] = entry.label
		}

		// Phase 2: Topologically sort all type entries and construct in order.
		let sortedEntries = topologicallySortedEntries(treeInfo: treeInfo)
		for entry in sortedEntries {
			let concreteTypeName = entry.typeDescription.asSource
			let sourceTypeName = entry.sourceType.asSource
			guard constructedVars[concreteTypeName] == nil, constructedVars[sourceTypeName] == nil else { continue }

			// Pick the first path case for this type's closure call.
			guard let pathCase = entry.pathCases.first?.name else { continue }
			let dotPathCase = pathCase.contains(".") ? pathCase : ".\(pathCase)"

			if entry.isInstantiator {
				// Instantiator entries: wrap inline tree in Instantiator { forwarded in ... }
				let instantiatorDefault = buildInstantiatorDefault(
					for: entry,
					constructedVars: constructedVars,
					indent: bodyIndent,
				)
				lines.append("\(bodyIndent)let \(entry.paramLabel) = \(entry.paramLabel)?(\(dotPathCase))")
				lines.append("\(bodyIndent)    ?? \(instantiatorDefault)")
				constructedVars[sourceTypeName] = entry.paramLabel
			} else if entry.hasKnownMock {
				let defaultExpr: String
				if entry.erasedToConcreteExistential, let wrappedConcreteType = entry.wrappedConcreteType {
					let concreteExpr = if let existingVar = constructedVars[wrappedConcreteType.asSource] {
						existingVar
					} else {
						buildInlineConstruction(for: wrappedConcreteType, constructedVars: constructedVars)
					}
					defaultExpr = "\(sourceTypeName)(\(concreteExpr))"
				} else {
					defaultExpr = buildInlineConstruction(
						for: entry.typeDescription,
						constructedVars: constructedVars,
					)
				}
				lines.append("\(bodyIndent)let \(entry.paramLabel) = \(entry.paramLabel)?(\(dotPathCase)) ?? \(defaultExpr)")
				constructedVars[concreteTypeName] = entry.paramLabel
			} else {
				lines.append("\(bodyIndent)let \(entry.paramLabel) = \(entry.paramLabel)(\(dotPathCase))")
				constructedVars[concreteTypeName] = entry.paramLabel
			}
		}

		// Phase 3: Construct the final return value.
		if let initializer = instantiable.initializer {
			let argList = initializer.arguments.compactMap { arg -> String? in
				let varName = constructedVars[arg.typeDescription.asInstantiatedType.asSource]
					?? constructedVars[arg.typeDescription.asSource]
				if let varName {
					return "\(arg.label): \(varName)"
				} else {
					// Arg has a default value or is not a tracked dependency.
					return nil
				}
			}.joined(separator: ", ")
			let typeName = instantiable.concreteInstantiable.asSource
			lines.append("\(bodyIndent)return \(typeName)(\(argList))")
		}

		return lines
	}

	/// Builds the default value for an Instantiator entry: `Instantiator { forwarded in ... }`.
	private func buildInstantiatorDefault(
		for entry: TypeEntry,
		constructedVars: [String: String],
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
		var closureConstructedVars = constructedVars
		for fwd in forwardedProps {
			closureConstructedVars[fwd.typeDescription.asSource] = fwd.label
		}

		let args = (initializer?.arguments ?? []).compactMap { arg -> String? in
			let varName = closureConstructedVars[arg.typeDescription.asInstantiatedType.asSource]
				?? closureConstructedVars[arg.typeDescription.asSource]
			if let varName {
				return "\(arg.label): \(varName)"
			} else {
				// Arg has a default value or is not a tracked dependency.
				return nil
			}
		}.joined(separator: ", ")

		let typeName = (builtInstantiable?.concreteInstantiable ?? builtType).asSource
		let construction = if builtInstantiable?.declarationType.isExtension == true {
			"\(typeName).instantiate(\(args))"
		} else {
			"\(typeName)(\(args))"
		}

		let sendablePrefix = isSendable ? "@Sendable " : ""
		return "\(propertyType.asSource) {\(sendablePrefix)\(closureParams)\n\(indent)    \(construction)\n\(indent)}"
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
						let hasUnresolvedDeps = builtInstantiable.dependencies.contains { dep in
							guard dep.source != .forwarded else { return false }
							let depTypeName = dep.property.typeDescription.asInstantiatedType.asSource
							return allTypeNames.contains(depTypeName) && !resolved.contains(depTypeName)
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
				let hasUnresolvedDeps = instantiable.dependencies.contains { dep in
					let depTypeName = dep.property.typeDescription.asInstantiatedType.asSource
					return allTypeNames.contains(depTypeName) && !resolved.contains(depTypeName)
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
		constructedVars: [String: String],
	) -> String {
		let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription]
		let typeName = (instantiable?.concreteInstantiable ?? typeDescription).asSource

		// Check if any of this type's deps are already constructed in the parent scope.
		// If so, we must build inline to thread the parent's values through.
		let hasDepsInScope = instantiable?.dependencies.contains { dep in
			guard dep.source != .forwarded else { return false }
			return constructedVars[dep.property.typeDescription.asInstantiatedType.asSource] != nil
				|| constructedVars[dep.property.typeDescription.asSource] != nil
		} ?? false

		if !hasDepsInScope {
			// No deps in scope — safe to use mock().
			if instantiable?.declarationType.isExtension == true {
				return "\(typeName).instantiate()"
			}
			return "\(typeName).mock()"
		}

		// Build inline using initializer.
		let args = instantiable?.initializer?.arguments.compactMap { arg -> String? in
			let varName = constructedVars[arg.typeDescription.asInstantiatedType.asSource]
				?? constructedVars[arg.typeDescription.asSource]
			if let varName {
				return "\(arg.label): \(varName)"
			} else {
				// Arg has a default value or is not a tracked dependency.
				return nil
			}
		}.joined(separator: ", ") ?? ""

		if instantiable?.declarationType.isExtension == true {
			return "\(typeName).instantiate(\(args))"
		}
		return "\(typeName)(\(args))"
	}

	private func lowercaseFirst(_ string: String) -> String {
		guard let first = string.first else { return string }
		return String(first.lowercased()) + string.dropFirst()
	}

	/// Converts a type name to a valid Swift identifier by replacing special characters.
	/// e.g. `Container<Bool>` → `Container__Bool`
	private func sanitizeForIdentifier(_ typeName: String) -> String {
		typeName
			.replacingOccurrences(of: "<", with: "__")
			.replacingOccurrences(of: ">", with: "")
			.replacingOccurrences(of: ", ", with: "_")
			.replacingOccurrences(of: ",", with: "_")
			.replacingOccurrences(of: ".", with: "_")
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
