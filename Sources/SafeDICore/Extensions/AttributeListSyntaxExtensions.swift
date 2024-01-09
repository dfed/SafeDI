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

extension AttributeListSyntax {

    public var instantiableMacro: AttributeSyntax? {
        guard let attribute = first(where: { element in
            switch element {
            case let .attribute(attribute):
                return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == InstantiableVisitor.macroName
            case .ifConfigDecl:
                return false
            }
        }) else {
            return nil
        }
        return AttributeSyntax(attribute)
    }

    public var instantiatedMacro: AttributeSyntax? {
        guard let attribute = first(where: { element in
            switch element {
            case let .attribute(attribute):
                return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == Dependency.Source.instantiated.rawValue
            case .ifConfigDecl:
                return false
            }
        }) else {
            return nil
        }
        return AttributeSyntax(attribute)
    }

    public var receivedMacro: AttributeSyntax? {
        guard let attribute = first(where: { element in
            switch element {
            case let .attribute(attribute):
                return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == Dependency.Source.received.rawValue
            case .ifConfigDecl:
                return false
            }
        }) else {
            return nil
        }
        return AttributeSyntax(attribute)
    }

    public var attributedNodes: [(attribute: String, node: AttributeListSyntax.Element)] {
        compactMap { element in
            switch element {
            case let .attribute(attribute):
                guard let identifierText = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                    return nil
                }
                return (attribute: identifierText, node: element)
            case .ifConfigDecl:
                return nil
            }
        }
    }

    public var dependencySources: [(source: Dependency.Source, node: AttributeListSyntax.Element)] {
        attributedNodes.compactMap {
            guard let source = Dependency.Source.init(rawValue: $0.attribute) else {
                return nil
            }
            return (source: source, node: $0.node)
        }
    }
}
