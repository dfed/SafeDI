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

enum DependencyTreeGeneratorError: Error, CustomStringConvertible {

    case noInstantiableFound(TypeDescription)
    case noRootInstantiableFound
    case unsatisfiableSingletons([Property], roots: [TypeDescription])
    case unfulfillableProperties([UnfulfillableProperty])

    var description: String {
        switch self {
        case let .noInstantiableFound(typeDescription):
            "No `@\(InstantiableVisitor.macroName)`-decorated type found to fulfill `@\(Dependency.Source.instantiated.rawValue)`, `@\(Dependency.Source.lazyInstantiated.rawValue)`, or `@\(Dependency.Source.singleton.rawValue)`-decorated property with type '\(typeDescription.asSource)'"
        case .noRootInstantiableFound:
            "All `@\(InstantiableVisitor.macroName)`-decorated types were found on a @\(Dependency.Source.instantiated.rawValue)`, `@\(Dependency.Source.lazyInstantiated.rawValue)`, or `@\(Dependency.Source.singleton.rawValue)`-decorated property. There must be at least one `@\(InstantiableVisitor.macroName)`-decorated types that is not instantiated by another `@\(InstantiableVisitor.macroName)`-decorated type"
        case let .unsatisfiableSingletons(properties, roots):
            "All `@\(Dependency.Source.singleton.rawValue)`-decorated properties must be in the same dependency tree to ensure they are singletons. Found multiple root `@\(InstantiableVisitor.macroName)`-decorated types: \(roots.map(\.asSource).joined(separator: ", ")). The following `@\(Dependency.Source.singleton.rawValue)`-decorated properties were found across multiple roots: \(properties.map(\.asSource).joined(separator: ", "))."
        case let .unfulfillableProperties(unfulfillableProperties):
            """
            The following inherited properties were never instantiated:
            \(unfulfillableProperties.map {
                """
                \($0.property.asSource) on \($0.instantiable.concreteInstantiableType.asSource) is not instantiated in any parent in chain: \($0.parentStack.map {
                    $0.concreteInstantiableType.asSource
                }.joined(separator: " <- "))
                """
            }.joined(separator: "\n"))
            """
        }
    }

    struct UnfulfillableProperty {
        let property: Property
        let instantiable: Instantiable
        let parentStack: [Instantiable]
    }
}
