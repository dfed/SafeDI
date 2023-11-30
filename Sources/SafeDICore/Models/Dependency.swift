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

import SwiftSyntax

/// A representation of a dependency.
/// e.g. `@Singleton let mySingleton: MySingleton`
public struct Dependency: Codable, Hashable {
    public let property: Property
    public let source: Source

    public var isVariant: Bool {
        switch source {
        case .instantiated, .lazyInstantiated, .inherited, .singleton:
            return false
        case .forwarded:
            return true
        }
    }

    public var isInvariant: Bool {
        switch source {
        case .instantiated, .lazyInstantiated, .inherited, .singleton:
            return true
        case .forwarded:
            return false
        }
    }

    public enum Source: String, CustomStringConvertible, Codable, Hashable {
        case instantiated = "Instantiated"
        case lazyInstantiated = "LazyInstantiated"
        case inherited = "Inherited"
        case singleton = "Singleton"
        case forwarded = "Forwarded"

        public var description: String {
            rawValue
        }
    }

    // MARK: Internal

    /// A version of the dependency as it looks in an initializer argument.
    var asInitializerArgument: Property {
        Property(
            label: initializerArgumentLabel,
            typeDescription: initializerArgumentTypeDescription)
    }

    /// The label by which this property is referenced in an initializer.
    var initializerArgumentLabel: String {
        switch source {
        case .instantiated, .inherited, .singleton, .forwarded:
            return property.label
        case .lazyInstantiated:
            return "\(property.label)\(Self.builderType)"
        }
    }

    /// The type description by which this property is referenced in an initializer.
    var initializerArgumentTypeDescription: TypeDescription {
        switch source {
        case .instantiated, .inherited, .singleton, .forwarded:
            return property.typeDescription
        case .lazyInstantiated:
            // TODO: fully qualify this type with `SafeDI.` member prefix
            return .simple(
                name: Self.builderType,
                generics: [
                    .tuple([]),
                    property.typeDescription
                ]
            )
        }
    }

    static let builderType = "Builder"
}
