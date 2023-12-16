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

public struct Instantiable: Codable, Hashable {

    // MARK: Initialization

    public init(
        instantiableType: TypeDescription,
        initializer: Initializer?,
        additionalInstantiableTypes: [TypeDescription]?,
        dependencies: [Dependency],
        declarationType: DeclarationType)
    {
        self.instantiableTypes = [instantiableType] + (additionalInstantiableTypes ?? [])
        self.initializer = initializer
        self.dependencies = dependencies
        self.declarationType = declarationType
    }

    // MARK: Public

    /// The types that can be fulfilled with this Instantiable.
    public let instantiableTypes: [TypeDescription]
    /// The concrete type that fulfills `instantiableTypes`.
    public var concreteInstantiableType: TypeDescription {
        instantiableTypes[0]
    }
    /// A memberwise initializer for the concrete instantiable type.
    /// If `nil`, the Instanitable type is incorrectly configured.
    public let initializer: Initializer?
    /// The ordered dependencies of this Instantiable.
    public let dependencies: [Dependency]
    /// The declaration type of the Instantiable's concrete type.
    public let declarationType: DeclarationType

    /// The type of declaration where this Instantiable was defined.
    public enum DeclarationType: Codable, Hashable {
        case classType
        case actorType
        case structType
        case extensionType
    }

    // MARK: Internal

    var instantiatedDependencies: [Dependency] {
        dependencies
            .filter { $0.source == .instantiated }
    }
}
