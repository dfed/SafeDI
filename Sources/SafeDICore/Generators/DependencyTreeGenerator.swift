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

import Collections

public final class DependencyTreeGenerator {
    // MARK: Initialization

    public init(
        importStatements: [ImportStatement],
        typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
    ) {
        self.importStatements = importStatements
        self.typeDescriptionToFulfillingInstantiableMap = typeDescriptionToFulfillingInstantiableMap
    }

    // MARK: Public

    public func generateCodeTree() async throws -> String {
        let rootScopeGenerators = try rootScopeGenerators

        let dependencyTree = try await withThrowingTaskGroup(
            of: String.self,
            returning: String.self
        ) { taskGroup in
            for rootScopeGenerator in rootScopeGenerators {
                taskGroup.addTask { try await rootScopeGenerator.generateCode() }
            }
            var generatedRoots = [String]()
            for try await generatedRoot in taskGroup {
                generatedRoots.append(generatedRoot)
            }
            return generatedRoots.filter { !$0.isEmpty }.sorted().joined(separator: "\n\n")
        }

        let importsWhitespace = imports.isEmpty ? "" : "\n"
        return """
        // This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
        // Any modifications made to this file will be overwritten on subsequent builds.
        // Please refrain from editing this file directly.
        \(importsWhitespace)\(imports)\(importsWhitespace)
        \(dependencyTree.isEmpty ? "// No root @\(InstantiableVisitor.macroName)-decorated types found, or root types already had a `public init()` method." : dependencyTree)
        """
    }

    public func generateDOTTree() async throws -> String {
        let rootScopeGenerators = try rootScopeGenerators

        let dependencyTree = try await withThrowingTaskGroup(
            of: String.self,
            returning: String.self
        ) { taskGroup in
            for rootScopeGenerator in rootScopeGenerators {
                taskGroup.addTask { try await rootScopeGenerator.generateDOT() }
            }
            var generatedRoots = [String]()
            for try await generatedRoot in taskGroup {
                generatedRoots.append(generatedRoot)
            }
            return generatedRoots.filter { !$0.isEmpty }.sorted().joined(separator: "\n\n")
        }

        return """
        \(dependencyTree)
        """
    }

    // MARK: - DependencyTreeGeneratorError

    private enum DependencyTreeGeneratorError: Error, CustomStringConvertible {
        case noInstantiableFound(TypeDescription)
        case unfulfillableProperties([UnfulfillableProperty])
        case instantiableHasForwardedProperty(property: Property, instantiableWithForwardedProperty: Instantiable, parent: Instantiable)

        var description: String {
            switch self {
            case let .noInstantiableFound(typeDescription):
                "No `@\(InstantiableVisitor.macroName)`-decorated type or extension found to fulfill `@\(Dependency.Source.instantiatedRawValue)`-decorated property with type `\(typeDescription.asSource)`"
            case let .unfulfillableProperties(unfulfillableProperties):
                """
                \(unfulfillableProperties.map {
                    """
                    @\(Dependency.Source.receivedRawValue) property `\($0.property.asSource)` is not @\(Dependency.Source.instantiatedRawValue) or @\(Dependency.Source.forwardedRawValue) in chain: \(([$0.instantiable] + $0.parentStack)
                        .reversed()
                        .map(\.concreteInstantiable.asSource)
                        .joined(separator: " -> "))
                    """
                }.joined(separator: "\n"))
                """
            case let .instantiableHasForwardedProperty(property, instantiable, parent):
                "Property `\(property.asSource)` on \(parent.concreteInstantiable.asSource) has at least one @\(Dependency.Source.forwardedRawValue) property. Property should instead be of type `\(Dependency.instantiatorType)<\(instantiable.concreteInstantiable.asSource)>`."
            }
        }

        struct UnfulfillableProperty: Hashable, Comparable {
            static func < (lhs: DependencyTreeGenerator.DependencyTreeGeneratorError.UnfulfillableProperty, rhs: DependencyTreeGenerator.DependencyTreeGeneratorError.UnfulfillableProperty) -> Bool {
                lhs.property < rhs.property
            }

            let property: Property
            let instantiable: Instantiable
            let parentStack: [Instantiable]
        }
    }

    // MARK: Private

    private let importStatements: [ImportStatement]
    private let typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
    private var rootScopeGenerators: [ScopeGenerator] {
        get throws {
            if let _rootScopeGenerators {
                return _rootScopeGenerators
            } else {
                let rootScopeGenerators: [ScopeGenerator] = try {
                    try validateReachableTypeDescriptions()

                    let typeDescriptionToScopeMap = try createTypeDescriptionToScopeMapping()
                    try validateReceivedProperties(typeDescriptionToScopeMap: typeDescriptionToScopeMap)
                    return try rootInstantiables
                        .sorted()
                        .compactMap {
                            try typeDescriptionToScopeMap[$0]?.createScopeGenerator(
                                for: nil,
                                propertyStack: [],
                                erasedToConcreteExistential: false
                            )
                        }
                }()
                _rootScopeGenerators = rootScopeGenerators
                return rootScopeGenerators
            }
        }
    }

    private var _rootScopeGenerators: [ScopeGenerator]?

    private var imports: String {
        importStatements
            .reduce(into: [String: Set<ImportStatement>]()) { partialResult, importStatement in
                var importsForModuleName = partialResult[importStatement.moduleName, default: []]
                importsForModuleName.insert(importStatement)
                partialResult[importStatement.moduleName] = importsForModuleName
            }
            .flatMap {
                if let wholeModuleImport = $0.value.first(where: {
                    $0.kind.isEmpty
                        && $0.type.isEmpty
                }) {
                    [wholeModuleImport]
                } else {
                    Array($0.value)
                }
            }
            .map {
                """
                #if canImport(\($0.moduleName))
                \($0.asSource)
                #endif
                """
            }
            .sorted()
            .joined(separator: "\n")
    }

    /// A collection of `@Instantiable`-decorated types that do not explicitly receive dependencies.
    /// - Note: These are not necessarily roots in the build graph, since these types may be instantiated by another `@Instantiable`.
    private lazy var possibleRootInstantiables: Set<TypeDescription> = Set(
        typeDescriptionToFulfillingInstantiableMap
            .values
            .filter(\.dependencies.couldRepresentRoot)
            .map(\.concreteInstantiable)
    )

    /// A collection of `@Instantiable`-decorated types that are instantiated by at least one other
    /// `@Instantiable`-decorated type or do not explicitly receive dependencies.
    private lazy var reachableTypeDescriptions: Set<TypeDescription> = {
        var reachableTypeDescriptions = Set<TypeDescription>()

        func recordReachableTypeDescription(_ reachableTypeDescription: TypeDescription) {
            guard !reachableTypeDescriptions.contains(reachableTypeDescription) else {
                // We've visited this tree already. Ignore.
                return
            }
            reachableTypeDescriptions.insert(reachableTypeDescription)
            guard let instantiable = typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] else {
                // We can't find an instantiable for this type.
                // This is bad, but we'll handle this error in `validateReachableTypeDescriptions()`.
                return
            }
            let reachableChildTypeDescriptions = instantiable
                .dependencies
                .filter(\.isInstantiated)
                .map(\.asInstantiatedType)
            for reachableChildTypeDescription in reachableChildTypeDescriptions {
                recordReachableTypeDescription(reachableChildTypeDescription)
            }
        }

        for reachableTypeDescription in possibleRootInstantiables {
            recordReachableTypeDescription(reachableTypeDescription)
        }

        return reachableTypeDescriptions
    }()

    /// A collection of `@Instantiable`-decorated types that are at the roots of their respective dependency trees.
    private lazy var rootInstantiables: Set<TypeDescription> = possibleRootInstantiables
        // Remove all `@Instantiable`-decorated types that are instantiated by another
        // `@Instantiable`-decorated type.
        .subtracting(Set(
            reachableTypeDescriptions
                .compactMap { typeDescriptionToFulfillingInstantiableMap[$0] }
                .flatMap(\.dependencies)
                .filter(\.isInstantiated)
                .map(\.asInstantiatedType)
                .compactMap { typeDescriptionToFulfillingInstantiableMap[$0]?.concreteInstantiable }
        ))

    private func createTypeDescriptionToScopeMapping() throws -> [TypeDescription: Scope] {
        // Create the mapping.
        let typeDescriptionToScopeMap: [TypeDescription: Scope] = reachableTypeDescriptions
            .reduce(into: [TypeDescription: Scope]()) { partialResult, typeDescription in
                guard let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription] else {
                    // We can't find an instantiable for this type.
                    // This is bad, but we handle this error in `validateReachableTypeDescriptions()`.
                    return
                }
                guard partialResult[instantiable.concreteInstantiable] == nil else {
                    // We've already created a scope for this `instantiable`. Skip.
                    return
                }
                let scope = Scope(instantiable: instantiable)
                for instantiableType in instantiable.instantiableTypes {
                    partialResult[instantiableType] = scope
                }
            }

        // Populate the propertiesToGenerate on each scope.
        for scope in Set(typeDescriptionToScopeMap.values) {
            for dependency in scope.instantiable.dependencies {
                switch dependency.source {
                case let .instantiated(_, erasedToConcreteExistential):
                    let instantiatedType = dependency.asInstantiatedType
                    guard
                        let instantiable = typeDescriptionToFulfillingInstantiableMap[instantiatedType],
                        let instantiatedScope = typeDescriptionToScopeMap[instantiatedType]
                    else {
                        assertionFailure("Invalid state. Could not look up info for \(instantiatedType)")
                        continue
                    }
                    let type = dependency.property.propertyType
                    if type.isConstant {
                        guard instantiable.dependencies.filter(\.isForwarded).isEmpty else {
                            throw DependencyTreeGeneratorError
                                .instantiableHasForwardedProperty(
                                    property: dependency.property,
                                    instantiableWithForwardedProperty: instantiable,
                                    parent: scope.instantiable
                                )
                        }
                    }
                    scope.propertiesToGenerate.append(.instantiated(
                        dependency.property,
                        instantiatedScope,
                        erasedToConcreteExistential: erasedToConcreteExistential
                    ))
                case let .aliased(fulfillingProperty, erasedToConcreteExistential):
                    scope.propertiesToGenerate.append(.aliased(
                        dependency.property,
                        fulfilledBy: fulfillingProperty,
                        erasedToConcreteExistential: erasedToConcreteExistential
                    ))
                case .forwarded, .received:
                    continue
                }
            }
        }
        return typeDescriptionToScopeMap
    }

    private func validateReceivedProperties(typeDescriptionToScopeMap: [TypeDescription: Scope]) throws {
        var unfulfillableProperties = Set<DependencyTreeGeneratorError.UnfulfillableProperty>()
        func validateReceivedProperties(
            on scope: Scope,
            receivableProperties: Set<Property>,
            instantiables: OrderedSet<Instantiable>
        ) {
            let createdProperties = Set(
                scope
                    .instantiable
                    .dependencies
                    .filter {
                        switch $0.source {
                        case .instantiated, .forwarded:
                            // The source is being injected into the dependency tree.
                            true
                        case .aliased:
                            // This property is being re-injected into the dependency tree under a new alias.
                            true
                        case .received:
                            false
                        }
                    }
                    .map(\.property)
            )
            for receivedProperty in scope.receivedProperties {
                let parentContainsProperty = receivableProperties.contains(receivedProperty)
                let propertyIsCreatedAtThisScope = createdProperties.contains(receivedProperty)
                if !parentContainsProperty, !propertyIsCreatedAtThisScope {
                    if instantiables.elements.isEmpty {
                        // This property's scope is not a real root instantiable! Remove it from the list.
                        rootInstantiables.remove(scope.instantiable.concreteInstantiable)
                    } else {
                        // This property is in a dependency tree and is unfulfillable. Record the problem.
                        unfulfillableProperties.insert(.init(
                            property: receivedProperty,
                            instantiable: scope.instantiable,
                            parentStack: instantiables.elements
                        )
                        )
                    }
                }
            }

            for childPropertyToGenerate in scope.propertiesToGenerate {
                switch childPropertyToGenerate {
                case let .instantiated(childProperty, childScope, _):
                    guard !instantiables.contains(childScope.instantiable) else {
                        // We've previously visited this child scope.
                        // There is a cycle in our scope tree. Do not re-enter it.
                        continue
                    }
                    var instantiables = instantiables
                    instantiables.insert(scope.instantiable, at: 0)

                    validateReceivedProperties(
                        on: childScope,
                        receivableProperties: receivableProperties
                            .union(scope.properties)
                            .removing(childProperty),
                        instantiables: instantiables
                    )

                case .aliased:
                    break
                }
            }
        }

        for rootScope in rootInstantiables.compactMap({ typeDescriptionToScopeMap[$0] }) {
            validateReceivedProperties(
                on: rootScope,
                receivableProperties: Set(rootScope.properties),
                instantiables: []
            )
        }

        if !unfulfillableProperties.isEmpty {
            throw DependencyTreeGeneratorError.unfulfillableProperties(unfulfillableProperties.sorted())
        }
    }

    private func validateReachableTypeDescriptions() throws {
        for reachableTypeDescription in reachableTypeDescriptions {
            if typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] == nil {
                throw DependencyTreeGeneratorError.noInstantiableFound(reachableTypeDescription)
            }
        }
    }
}

// MARK: - Dependency

extension Dependency {
    fileprivate var isInstantiated: Bool {
        switch source {
        case .instantiated:
            true
        case .aliased, .forwarded, .received:
            false
        }
    }

    fileprivate var isForwarded: Bool {
        switch source {
        case .forwarded:
            true
        case .aliased, .instantiated, .received:
            false
        }
    }
}

// MARK: - Collection

extension Collection<Dependency> {
    fileprivate var couldRepresentRoot: Bool {
        first(where: {
            switch $0.source {
            case .instantiated, .aliased:
                false
            case .forwarded, .received:
                true
            }
        }) == nil
    }
}

// MARK: - Set

extension Set {
    fileprivate func removing(_ element: Element) -> Self {
        var setWithoutElement = self
        setWithoutElement.remove(element)
        return setWithoutElement
    }
}
