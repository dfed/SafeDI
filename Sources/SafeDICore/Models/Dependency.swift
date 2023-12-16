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

    // MARK: Public

    public let property: Property
    public let source: Source
    public let fulfillingTypeDescription: TypeDescription?

    public var asInstantiatedType: TypeDescription {
        (fulfillingTypeDescription ?? property.typeDescription).asInstantiatedType
    }

    public enum Source: String, CustomStringConvertible, Codable, Hashable {
        case instantiated = "Instantiated"
        case received = "Received"
        case forwarded = "Forwarded"

        public var description: String {
            rawValue
        }
    }

    // MARK: Internal

    /// The label by which this property is referenced inside the `init` method.
    var propertyLabelInInit: String {
        property.label
    }

    static let instantiatorType = "Instantiator"
    static let forwardingInstantiatorType = "ForwardingInstantiator"
}
