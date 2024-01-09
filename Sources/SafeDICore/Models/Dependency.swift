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
public struct Dependency: Codable, Hashable {

    // MARK: Initialization

    public init(
        property: Property,
        source: Dependency.Source,
        fulfillingPropertyName: String? = nil,
        fulfillingTypeDescription: TypeDescription? = nil
    ) {
        self.property = property
        self.source = source
        self.fulfillingPropertyName = fulfillingPropertyName
        self.fulfillingTypeDescription = fulfillingTypeDescription

        if let fulfillingPropertyName, let fulfillingTypeDescription {
            fulfillingProperty = Property(
                label: fulfillingPropertyName,
                typeDescription: fulfillingTypeDescription)
        } else {
            fulfillingProperty = nil
        }
        asInstantiatedType = (fulfillingTypeDescription ?? property.typeDescription).asInstantiatedType
    }

    // MARK: Public

    /// A representation of the dependency as it is declared on its `@Instantiable` type.
    public let property: Property
    /// The source of the dependency within the dependency tree.
    public let source: Source
    /// The name of the property that will be used to fulfill this property.
    public let fulfillingPropertyName: String?
    /// The type description of the type that will be used to fulfill this property.
    /// This type must be the same as or a parent type of `property.typeDescription`.
    public let fulfillingTypeDescription: TypeDescription?
    /// The property that will be used to fulfill this property.
    public let fulfillingProperty: Property?
    /// The receiver's type description as an `@Instantiable`-decorated type.
    public let asInstantiatedType: TypeDescription

    public enum Source: String, CustomStringConvertible, Codable, Hashable {
        case instantiated = "Instantiated"
        case received = "Received"
        case forwarded = "Forwarded"

        public var description: String {
            rawValue
        }
    }

    // MARK: Internal

    static let instantiatorType = "Instantiator"
    static let forwardingInstantiatorType = "ForwardingInstantiator"
}
