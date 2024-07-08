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

extension ImportDeclSyntax {
    // MARK: Public

    public var asImportStatement: ImportStatement {
        ImportStatement(
            attribute: attribute,
            kind: kind,
            moduleName: path.first?.name.text ?? "",
            type: path
                .map(\.name.text)
                .dropFirst()
                .joined(separator: ".")
        )
    }

    // MARK: Private

    /// Finds the type of an import
    ///
    /// - Parameter syntaxNode: The Swift Syntax import declaration node
    ///
    /// - Returns: A string representing the kind of the import
    ///            e.g `import class UIKit.UIViewController` returns class
    ///            while `import UIKit` and `import UIKit.UIViewController` return an empty String
    private var kind: String {
        importKindSpecifier?.text ?? ""
    }

    private var attribute: String {
        // This AttributeList is of the form ["@", "attribute"]
        // Grab the whole thing.
        attributes.trimmedDescription
    }
}
