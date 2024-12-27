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
/// e.g. `@Instantiated let myService: MyService`
public struct Dependency: Codable, Hashable, Sendable {
    // MARK: Initialization

    public init(
        property: Property,
        source: Dependency.Source
    ) {
        self.property = property
        self.source = source
        switch source {
        case .received, .forwarded:
            asInstantiatedType = property.typeDescription.asInstantiatedType
        case let .instantiated(fulfillingTypeDescription, _):
            asInstantiatedType = (fulfillingTypeDescription ?? property.typeDescription).asInstantiatedType
        case let .aliased(fulfillingProperty, _):
            asInstantiatedType = fulfillingProperty.typeDescription.asInstantiatedType
        }
    }

    // MARK: Public

    /// A representation of the dependency as it is declared on its `@Instantiable` type.
    public let property: Property
    /// The source of the dependency within the dependency tree.
    public let source: Source
    /// The receiver’s type description as an `@Instantiable`-decorated type.
    public let asInstantiatedType: TypeDescription

    public enum Source: Codable, Hashable, Sendable {
        case instantiated(fulfillingTypeDescription: TypeDescription?, erasedToConcreteExistential: Bool)
        case received
        case aliased(fulfillingProperty: Property, erasedToConcreteExistential: Bool)
        case forwarded

        public init?(node: AttributeListSyntax.Element) {
            if let instantiatedMacro = node.instantiatedMacro {
                self = .instantiated(
                    fulfillingTypeDescription: instantiatedMacro.fulfillingTypeDescription,
                    erasedToConcreteExistential: instantiatedMacro.erasedToConcreteExistentialType
                )
            } else if let receivedMacro = node.receivedMacro {
                if let fulfillingPropertyName = receivedMacro.fulfillingPropertyName,
                   let fulfillingTypeDescription = receivedMacro.fulfillingTypeDescription
                {
                    self = .aliased(
                        fulfillingProperty: Property(
                            label: fulfillingPropertyName,
                            typeDescription: fulfillingTypeDescription
                        ),
                        erasedToConcreteExistential: receivedMacro.erasedToConcreteExistentialType
                    )
                } else {
                    self = .received
                }
            } else if node.forwardedMacro != nil {
                self = .forwarded
            } else {
                return nil
            }
        }

        public var fulfillingProperty: Property? {
            switch self {
            case let .aliased(fulfillingProperty, _):
                fulfillingProperty
            case .instantiated, .received, .forwarded:
                nil
            }
        }

        public static let instantiatedRawValue = "Instantiated"
        public static let receivedRawValue = "Received"
        public static let forwardedRawValue = "Forwarded"
    }

    // MARK: Internal

    static let instantiatorType = "Instantiator"
    static let erasedInstantiatorType = "ErasedInstantiator"
    static let sendableInstantiatorType = "SendableInstantiator"
    static let sendableErasedInstantiatorType = "SendableErasedInstantiator"
}
