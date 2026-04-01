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
	/// Returns `nil` if the type cannot be mocked (e.g. has Instantiator dependencies).
	public func generateMock(for instantiable: Instantiable) -> String? {
		// Skip types with Instantiator/ErasedInstantiator dependencies — these require
		// closure-wrapping logic that is not yet implemented in the mock generator.
		let hasUnsupportedDeps = instantiable.dependencies.contains { dep in
			let propertyType = dep.property.propertyType
			return !propertyType.isConstant
		}
		if hasUnsupportedDeps {
			return nil
		}

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
							isForwarded: false,
							hasKnownMock: true,
							erasedToConcreteExistential: true,
							wrappedConcreteType: concreteType,
						)
					}
				} else if treeInfo.typeEntries[depTypeName] == nil {
					treeInfo.typeEntries[depTypeName] = TypeEntry(
						typeDescription: depType,
						sourceType: dependency.property.typeDescription,
						isForwarded: false,
						hasKnownMock: typeDescriptionToFulfillingInstantiableMap[depType] != nil,
						erasedToConcreteExistential: false,
						wrappedConcreteType: nil,
					)
				}
				treeInfo.typeEntries[depTypeName]!.pathCases.append(
					PathCase(name: "parent", constructionPath: []),
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
			let nestedEnumName = entry.displayTypeName
			let uniqueCases = entry.pathCases.map(\.name).uniqued()
			let casesStr = uniqueCases.map { "case \($0)" }.joined(separator: "; ")
			enumLines.append("\(indent)\(indent)public enum \(nestedEnumName) { \(casesStr) }")
		}
		enumLines.append("\(indent)}")

		// Generate mock method signature.
		var params = [String]()
		for (_, entry) in treeInfo.forwardedEntries.sorted(by: { $0.key < $1.key }) {
			params.append("\(indent)\(indent)\(entry.label): \(entry.typeDescription.asSource)")
		}
		for (_, entry) in treeInfo.typeEntries.sorted(by: { $0.key < $1.key }) {
			let paramLabel = parameterLabel(for: entry.displayType)
			let sourceTypeName = entry.sourceType.asSource
			let enumTypeName = entry.displayTypeName
			if entry.hasKnownMock {
				params.append("\(indent)\(indent)\(paramLabel): ((SafeDIMockPath.\(enumTypeName)) -> \(sourceTypeName))? = nil")
			} else {
				params.append("\(indent)\(indent)\(paramLabel): @escaping (SafeDIMockPath.\(enumTypeName)) -> \(sourceTypeName)")
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
		let constructionPath: [String] // property labels from root to this instantiation
	}

	private struct TypeEntry {
		let typeDescription: TypeDescription
		let sourceType: TypeDescription
		let isForwarded: Bool
		/// Whether this type is in the type map and will have a generated mock().
		let hasKnownMock: Bool
		/// When true, the sourceType is a type-erased wrapper around a concrete type.
		/// The default construction should be `SourceType(ConcreteType.mock())`.
		let erasedToConcreteExistential: Bool
		/// For erased types, the concrete type that this wraps.
		let wrappedConcreteType: TypeDescription?
		var pathCases = [PathCase]()

		/// The type to use for parameter labels and enum names.
		/// For erasedToConcreteExistential, this is the sourceType (the erased wrapper).
		/// Otherwise, it's the typeDescription (the concrete type).
		var displayType: TypeDescription {
			erasedToConcreteExistential ? sourceType : typeDescription
		}

		var displayTypeName: String {
			displayType.asSource
		}
	}

	private struct ForwardedEntry {
		let label: String
		let typeDescription: TypeDescription
	}

	private struct TreeInfo {
		var typeEntries = [String: TypeEntry]() // keyed by type name
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
				let depTypeName = depType.asSource
				let caseName = path.isEmpty ? "root" : path.joined(separator: "_")

				if treeInfo.typeEntries[depTypeName] == nil {
					treeInfo.typeEntries[depTypeName] = TypeEntry(
						typeDescription: depType,
						sourceType: erasedToConcreteExistential ? depType : dependency.property.typeDescription,
						isForwarded: false,
						hasKnownMock: typeDescriptionToFulfillingInstantiableMap[depType] != nil,
						erasedToConcreteExistential: false,
						wrappedConcreteType: nil,
					)
				}

				// For erasedToConcreteExistential, also add an entry for the erased wrapper type.
				if erasedToConcreteExistential {
					let erasedType = dependency.property.typeDescription
					let erasedTypeName = erasedType.asSource
					if treeInfo.typeEntries[erasedTypeName] == nil {
						treeInfo.typeEntries[erasedTypeName] = TypeEntry(
							typeDescription: erasedType,
							sourceType: erasedType,
							isForwarded: false,
							hasKnownMock: true, // Will default to wrapping the concrete mock
							erasedToConcreteExistential: true,
							wrappedConcreteType: depType,
						)
					}
					treeInfo.typeEntries[erasedTypeName]!.pathCases.append(
						PathCase(name: caseName, constructionPath: path + [dependency.property.label]),
					)
				}
				treeInfo.typeEntries[depTypeName]!.pathCases.append(
					PathCase(name: caseName, constructionPath: path + [dependency.property.label]),
				)

				// Recurse into instantiated dependency's tree.
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
		// Types with no dependencies (in the constructed set) go first.
		let sortedEntries = topologicallySortedEntries(treeInfo: treeInfo)
		for entry in sortedEntries {
			let varName = parameterLabel(for: entry.displayType)
			let concreteTypeName = entry.typeDescription.asSource
			let sourceTypeName = entry.sourceType.asSource
			guard constructedVars[concreteTypeName] == nil, constructedVars[sourceTypeName] == nil else { continue }

			// Pick the first path case for this type's closure call.
			let pathCase = entry.pathCases.first!.name
			let dotPathCase = pathCase.contains(".") ? pathCase : ".\(pathCase)"
			if entry.hasKnownMock {
				let defaultExpr: String
				if entry.erasedToConcreteExistential, let wrappedConcreteType = entry.wrappedConcreteType {
					// The erased type wraps the concrete type.
					// If the concrete type is already constructed (e.g., as a separate param at this level),
					// reference the variable. Otherwise, build the concrete type inline.
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
				lines.append("\(bodyIndent)let \(varName) = \(varName)?(\(dotPathCase)) ?? \(defaultExpr)")
			} else {
				lines.append("\(bodyIndent)let \(varName) = \(varName)(\(dotPathCase))")
			}
			constructedVars[concreteTypeName] = varName
		}

		// Phase 3: Construct the final return value.
		if let initializer = instantiable.initializer {
			let argList = initializer.arguments.compactMap { arg -> String? in
				let varName = constructedVars[arg.typeDescription.asInstantiatedType.asSource]
					?? constructedVars[arg.typeDescription.asSource]
				if let varName {
					return "\(arg.label): \(varName)"
				} else if arg.hasDefaultValue {
					return nil
				} else {
					return "\(arg.label): \(arg.innerLabel)"
				}
			}.joined(separator: ", ")
			let construction = if instantiable.declarationType.isExtension {
				"\(instantiable.concreteInstantiable.asSource).instantiate(\(argList))"
			} else {
				"\(instantiable.concreteInstantiable.asSource)(\(argList))"
			}
			lines.append("\(bodyIndent)return \(construction)")
		}

		return lines
	}

	/// Sorts type entries in dependency order: types with no unresolved deps first.
	private func topologicallySortedEntries(treeInfo: TreeInfo) -> [TypeEntry] {
		let entries = treeInfo.typeEntries.values.sorted(by: { $0.typeDescription.asSource < $1.typeDescription.asSource })
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
				guard let instantiable = typeDescriptionToFulfillingInstantiableMap[entry.typeDescription] else {
					// Unknown type — has no dependencies we track.
					result.append(entry)
					resolved.insert(typeName)
					return false
				}
				// Check if all received/aliased deps of this type are resolved.
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
		let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription]!

		// Check if this type has received deps that are already constructed.
		let hasReceivedDepsInScope = instantiable.dependencies.contains { dep in
			switch dep.source {
			case .received, .aliased:
				constructedVars[dep.property.typeDescription.asInstantiatedType.asSource] != nil
					|| constructedVars[dep.property.typeDescription.asSource] != nil
			case .instantiated, .forwarded:
				false
			}
		}

		if !hasReceivedDepsInScope {
			// No received deps in scope — safe to use mock().
			if instantiable.declarationType.isExtension {
				return "\(instantiable.concreteInstantiable.asSource).instantiate()"
			}
			return "\(instantiable.concreteInstantiable.asSource).mock()"
		}

		// Build inline using initializer.
		let initializer = instantiable.initializer!

		let typeName = instantiable.concreteInstantiable.asSource
		let args = initializer.arguments.compactMap { arg -> String? in
			let varName = constructedVars[arg.typeDescription.asInstantiatedType.asSource]
				?? constructedVars[arg.typeDescription.asSource]
			if let varName {
				return "\(arg.label): \(varName)"
			} else if arg.hasDefaultValue {
				return nil
			} else {
				return "\(arg.label): \(arg.innerLabel)"
			}
		}.joined(separator: ", ")

		if instantiable.declarationType.isExtension {
			return "\(typeName).instantiate(\(args))"
		}
		return "\(typeName)(\(args))"
	}

	private func parameterLabel(for typeDescription: TypeDescription) -> String {
		let typeName = typeDescription.asSource
		guard let first = typeName.first else { return typeName }
		return String(first.lowercased()) + typeName.dropFirst()
	}
}

// MARK: - Array Extension

extension Array where Element: Hashable {
	fileprivate func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
