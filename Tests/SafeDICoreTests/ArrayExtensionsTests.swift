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

import XCTest

@testable import SafeDICore

final class ArrayExtensionsTests: XCTestCase {

    func test_variantUnlabeledParameterList_withSingleVariant() throws {
        let dependencies = [Dependency(property: Property(label: "int", type: "Int"), source: .variant)]
        XCTAssertEqual(
            dependencies.variantUnlabeledParameterList.description,
            "Int"
        )
    }

    func test_variantUnlabeledParameterList_withMultipleVariants() throws {
        let dependencies = [
            Dependency(property: Property(label: "int", type: "Int"), source: .variant),
            Dependency(property: Property(label: "string", type: "String"), source: .variant),
            Dependency(property: Property(label: "double", type: "Double"), source: .variant),
            Dependency(property: Property(label: "invariant", type: "Invariant"), source: .providedInvariant)
        ]
        XCTAssertEqual(
            dependencies.variantUnlabeledParameterList.description,
            "Int, String, Double"
        )
    }

    func test_variantParameterList_withSingleVariant() throws {
        let dependencies = [Dependency(property: Property(label: "int", type: "Int"), source: .variant)]
        XCTAssertEqual(
            dependencies.variantParameterList.description,
            "int: Int"
        )
    }

    func test_variantParameterList_withMultipleVariants() throws {
        let dependencies = [
            Dependency(property: Property(label: "int", type: "Int"), source: .variant),
            Dependency(property: Property(label: "string", type: "String"), source: .variant),
            Dependency(property: Property(label: "double", type: "Double"), source: .variant),
            Dependency(property: Property(label: "invariant", type: "Invariant"), source: .providedInvariant)
        ]
        XCTAssertEqual(
            dependencies.variantParameterList.description,
            "int: Int, string: String, double: Double"
        )
    }

    func test_variantUnlabeledExpressionList_withSingleVariant() throws {
        let dependencies = [Dependency(property: Property(label: "int", type: "Int"), source: .variant)]
        XCTAssertEqual(
            dependencies.variantUnlabeledExpressionList,
            "int"
        )
    }

    func test_variantUnlabeledExpressionList_withMultipleVariants() throws {
        let dependencies = [
            Dependency(property: Property(label: "int", type: "Int"), source: .variant),
            Dependency(property: Property(label: "string", type: "String"), source: .variant),
            Dependency(property: Property(label: "double", type: "Double"), source: .variant),
            Dependency(property: Property(label: "invariant", type: "Invariant"), source: .providedInvariant)
        ]
        XCTAssertEqual(
            dependencies.variantUnlabeledExpressionList,
            "int, string, double"
        )
    }


    func test_variantLabeledExpressionList_withSingleVariant() throws {
        let dependencies = [Dependency(property: Property(label: "int", type: "Int"), source: .variant)]
        XCTAssertEqual(
            dependencies.variantLabeledExpressionList,
            "int: int"
        )
    }

    func test_variantLabeledExpressionList_withMultipleVariants() throws {
        let dependencies = [
            Dependency(property: Property(label: "int", type: "Int"), source: .variant),
            Dependency(property: Property(label: "string", type: "String"), source: .variant),
            Dependency(property: Property(label: "double", type: "Double"), source: .variant),
            Dependency(property: Property(label: "invariant", type: "Invariant"), source: .providedInvariant)
        ]
        XCTAssertEqual(
            dependencies.variantLabeledExpressionList,
            "int: int, string: string, double: double"
        )
    }

    func test_invariantParameterList_withSingleInvariant() throws {
        let dependencies = [Dependency(property: Property(label: "int", type: "Int"), source: .providedInvariant)]
        XCTAssertEqual(
            dependencies.invariantParameterList.description,
            "int: Int"
        )
    }

    func test_invariantParameterList_withMultipleInvariants() throws {
        let dependencies = [
            Dependency(property: Property(label: "int", type: "Int"), source: .singletonInvariant),
            Dependency(property: Property(label: "string", type: "String"), source: .constructedInvariant),
            Dependency(property: Property(label: "double", type: "Double"), source: .providedInvariant),
            Dependency(property: Property(label: "variant", type: "Variant"), source: .variant)
        ]
        XCTAssertEqual(
            dependencies.invariantParameterList.description,
            "int: Int, string: String, double: Double"
        )
    }

    func test_invariantAssignmentExpressionList_withSingleInvariant() throws {
        let dependencies = [Dependency(property: Property(label: "int", type: "Int"), source: .providedInvariant)]
        XCTAssertEqual(
            dependencies.invariantAssignmentExpressionList,
            "self.int = int"
        )
    }

    func test_invariantAssignmentExpressionList_withMultipleInvariants() throws {
        let dependencies = [
            Dependency(property: Property(label: "int", type: "Int"), source: .singletonInvariant),
            Dependency(property: Property(label: "string", type: "String"), source: .constructedInvariant),
            Dependency(property: Property(label: "double", type: "Double"), source: .providedInvariant),
            Dependency(property: Property(label: "variant", type: "Variant"), source: .variant)
        ]
        XCTAssertEqual(
            dependencies.invariantAssignmentExpressionList,
            """
            self.int = int
            self.string = string
            self.double = double
            """
        )
    }
}
