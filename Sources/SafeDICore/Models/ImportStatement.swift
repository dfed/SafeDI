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

public struct ImportStatement: Codable, Hashable, Sendable {
    // MARK: Initialization

    public init(
        attribute: String = "",
        kind: String = "",
        moduleName: String,
        type: String = ""
    ) {
        self.attribute = attribute
        self.kind = kind
        self.moduleName = moduleName
        self.type = type
    }

    // MARK: Public

    /// Attributes on the import (i.e. `@testable`)
    public let attribute: String
    /// The kind of import, if specified (i.e. `class`, `struct`, etc).
    public let kind: String
    /// The name of the module.
    public let moduleName: String
    /// The type imported from the module.
    public let type: String

    /// A canonical representation of this import that can be used in source code.
    public var asSource: String {
        """
        \(attributeStatement)import \(kind.isEmpty ? "" : kind + " ")\(moduleName)\(type.isEmpty ? "" : "." + type)
        """
    }

    // MARK: Private

    private var attributeToGenerate: String {
        if Self.attributesToFilterOut.contains(attribute) {
            ""
        } else {
            attribute
        }
    }

    private var attributeStatement: String {
        let attributeToGenerate = attributeToGenerate
        return if attributeToGenerate.isEmpty {
            ""
        } else {
            attributeToGenerate + " "
        }
    }

    private static let attributesToFilterOut = Set([
        // We don't use concurrency in generated code, so including this attribute leads to a warning:
        //     '@preconcurrency' attribute on module 'ImportedModule' is unused
        "@preconcurrency",
    ])
}
