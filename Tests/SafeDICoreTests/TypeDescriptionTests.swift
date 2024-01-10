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

import Foundation
import SwiftParser
import SwiftSyntax
import XCTest

@testable import SafeDICore

final class TypeDescriptionTests: XCTestCase {

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    let simpleTestCase = TypeDescription.simple(
        name: "Foo",
        generics: [
            .simple(name: "Bar")
        ])
    let simpleTestCaseData = """
        {
            "caseDescription": "simple",
            "text": "Foo",
            "typeDescriptions": [{
                "caseDescription": "simple",
                "text": "Bar",
                "typeDescriptions": []
            }]
        }
        """.data(using: .utf8)!

    let nestedTestCase = TypeDescription.nested(
        name: "Bar",
        parentType: .simple(
            name: "Foo",
            generics: [.simple(name: "Int")]),
        generics: [.simple(name: "String")])
    let nestedTestCaseData = """
        {
            "typeDescriptions": [{
                "caseDescription": "simple",
                "text": "String",
                "typeDescriptions": []
            }],
            "caseDescription": "nested",
            "typeDescription": {
                "caseDescription": "simple",
                "text": "Foo",
                "typeDescriptions": [{
                    "caseDescription": "simple",
                    "text": "Int",
                    "typeDescriptions": []
            }]
            },
            "text": "Bar"
        }
        """.data(using: .utf8)!

    let optionalTestCase = TypeDescription.optional(.simple(name: "Foo"))
    let optionalTestCaseData = """
        {
            "caseDescription": "optional",
            "typeDescription": {
                "caseDescription": "simple",
                "text": "Foo",
                "typeDescriptions": []
            }
        }
        """.data(using: .utf8)!

    let implicitlyUnwrappedOptionalTestCase = TypeDescription.implicitlyUnwrappedOptional(.simple(name: "Foo"))
    let implicitlyUnwrappedOptionalTestCaseData = """
        {
            "caseDescription": "implicitlyUnwrappedOptional",
            "typeDescription": {
                "caseDescription":"simple",
                "text":"Foo",
                "typeDescriptions":[]
            }
        }
        """.data(using: .utf8)!

    let compositionTestCase = TypeDescription.composition(
        [
            .simple(name: "Foo"),
            .optional(.simple(name: "Bar")),
        ])
    let compositionTestCaseData = """
        {
            "caseDescription": "composition",
            "typeDescriptions": [
                {
                    "caseDescription": "simple",
                    "text": "Foo",
                    "typeDescriptions": []
                },
                {
                    "caseDescription": "optional",
                    "typeDescription": {
                        "caseDescription": "simple",
                        "text": "Bar",
                        "typeDescriptions": []
                    }
                }
            ]
        }
        """.data(using: .utf8)!

    let metatypeTestCase = TypeDescription.metatype(
        .simple(name: "Foo"),
        isType: false)
    let metatypeTestCaseData = """
        {
            "caseDescription": "metatype",
            "typeDescription": {
                "caseDescription": "simple",
                "text": "Foo",
                "typeDescriptions": []
            },
            "isType": false
        }
        """.data(using: .utf8)!

    let someTestCase = TypeDescription.some(
        .simple(name: "Foo"))
    let someTestCaseData = """
        {
            "caseDescription": "some",
            "typeDescription": {
                "caseDescription": "simple",
                "text": "Foo",
                "typeDescriptions": []
            },
        }
        """.data(using: .utf8)!

    let anyTestCase = TypeDescription.any(
        .simple(name: "Foo"))
    let anyTestCaseData = """
            {
                "caseDescription": "any",
                "typeDescription": {
                    "caseDescription": "simple",
                    "text": "Foo",
                    "typeDescriptions": []
                },
            }
            """.data(using: .utf8)!

    let attributedTestCase = TypeDescription.attributed(
        .simple(name: "Foo"),
        specifier: "inout",
        attributes: ["autoclosure"])
    let attributedTestCaseData = """
        {
            "caseDescription": "attributed",
            "typeDescription": {
                "caseDescription": "simple",
                "text": "Foo",
                "typeDescriptions": []
            },
            "specifier": "inout",
            "attributes": ["autoclosure"],
        }
        """.data(using: .utf8)!

    let arrayTestCase = TypeDescription.array(element: .simple(name: "Foo"))
    let arrayTestCaseData = """
        {
            "caseDescription": "array",
            "typeDescription": {
                "caseDescription": "simple",
                "text": "Foo",
                "typeDescriptions": []
            }
        }
        """.data(using: .utf8)!

    let dictionaryTestCase = TypeDescription.dictionary(
        key: .simple(name: "Foo"),
        value: .simple(name: "Bar"))
    let dictionaryTestCaseData = """
        {
            "caseDescription": "dictionary",
            "dictionaryKey": {
                "caseDescription": "simple",
                "text": "Foo",
                "typeDescriptions": []
            },
            "dictionaryValue": {
                "caseDescription": "simple",
                "text": "Bar",
                "typeDescriptions": []
            }
        }
        """.data(using: .utf8)!

    let tupleTestCase = TypeDescription.tuple(
        [
            .simple(name: "Foo"),
            .optional(.simple(name: "Bar"))
        ])
    let tupleTestCaseData = """
        {
            "caseDescription": "tuple",
            "typeDescriptions": [
                {
                    "caseDescription": "simple",
                    "text": "Foo",
                    "typeDescriptions": []
                },
                {
                    "caseDescription": "optional",
                    "typeDescription":
                    {
                        "caseDescription": "simple",
                        "text": "Bar",
                        "typeDescriptions": []
                    }
                }
            ]
        }
        """.data(using: .utf8)!

    let closureTestCase = TypeDescription.closure(
        arguments: [
            .simple(name: "Foo"),
            .optional(.simple(name: "Bar"))
        ],
        isAsync: true,
        doesThrow: true,
        returnType: .simple(name: "FooBar"))
    let closureTestCaseData = """
        {
            "caseDescription": "closure",
            "closureArguments": [
                {
                    "caseDescription": "simple",
                    "text": "Foo",
                    "typeDescriptions": []
                },
                {
                    "caseDescription": "optional",
                    "typeDescription":
                    {
                        "caseDescription": "simple",
                        "text": "Bar",
                        "typeDescriptions": []
                    }
                }
            ],
            "closureThrows": true,
            "closureIsAsync": true,
            "closureReturn": {
                "caseDescription": "simple",
                "text": "FooBar",
                "typeDescriptions": []
            }
        }
        """.data(using: .utf8)!

    let unknownTestCase = TypeDescription.unknown(text: "Foo")
    let unknownTestCaseData = """
        {
            "caseDescription": "unknown",
            "text": "Foo"
        }
        """.data(using: .utf8)!

    struct TypeDescriptionAndData {
        let typeDescription: TypeDescription
        let data: Data
    }

    lazy var allTypeDescriptionAndData = [
        TypeDescriptionAndData(
            typeDescription: simpleTestCase,
            data: simpleTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: nestedTestCase,
            data: nestedTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: optionalTestCase,
            data: optionalTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: implicitlyUnwrappedOptionalTestCase,
            data: implicitlyUnwrappedOptionalTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: compositionTestCase,
            data: compositionTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: metatypeTestCase,
            data: metatypeTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: someTestCase,
            data: someTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: anyTestCase,
            data: anyTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: attributedTestCase,
            data: attributedTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: arrayTestCase,
            data: arrayTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: dictionaryTestCase,
            data: dictionaryTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: tupleTestCase,
            data: tupleTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: closureTestCase,
            data: closureTestCaseData
        ),
        TypeDescriptionAndData(
            typeDescription: unknownTestCase,
            data: unknownTestCaseData
        ),
    ]

    func test_decodingPreviouslyPersistedTypeDescriptionData_succeeds() {
        for typeDescriptionAndData in allTypeDescriptionAndData {
            do {
                let decodedTypeDescription = try decoder.decode(TypeDescription.self, from: typeDescriptionAndData.data)
                XCTAssertEqual(
                    decodedTypeDescription,
                    typeDescriptionAndData.typeDescription
                )
            } catch {
                XCTFail("Encountered error decoding \(typeDescriptionAndData.typeDescription): \(error)")
            }
        }
    }

    func test_decodingGarbageTypeDescriptionData_throwsError() {
        let data = """
            {
                "caseDescription": "garbage"
            }
            """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(TypeDescription.self, from: data)) {
            XCTAssertEqual($0 as? TypeDescription.CodingError, TypeDescription.CodingError.unknownCase)
        }
    }

    func test_encodingAndDecodingRoundTrip_succeeds() {
        for typeDescription in allTypeDescriptionAndData.map(\.typeDescription) {
            do {
                let decodedTypeDescription = try decoder.decode(TypeDescription.self, from: try encoder.encode(typeDescription))
                XCTAssertEqual(
                    decodedTypeDescription,
                    typeDescription
                )
            } catch {
                XCTFail("Encountered error encoding and decoding decoding \(typeDescription): \(error)")
            }
        }
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingATypeIdentifierSyntax_findsTheType() throws {
        let content = """
            var int: Int = 1
            """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.typeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Int")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_findsTheType() throws {
        let content = """
            var int: Swift.Int = 1
            """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.nestedType)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Swift.Int")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_withRightHandGeneric_findsTheType() throws {
        let content = """
            var intArray: Swift.Array<Int> = [1]
            """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.nestedType)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Swift.Array<Int>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_withLeftHandGeneric_findsTheType() throws {
        let content = """
            var genericType: OuterGenericType<Int>.InnerType
            """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.nestedType)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "OuterGenericType<Int>.InnerType")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_withGenericOnBothSides_findsTheType() throws {
        let content = """
            var genericType: OuterGenericType<Int>.InnerGenericType<String>
            """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.nestedType)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "OuterGenericType<Int>.InnerGenericType<String>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingACompositionTypeSyntax_findsTheType() throws {
        let content = """
            protocol FooBar: Foo & Bar
            """

        let visitor = CompositionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.composedTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Foo & Bar")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAOptionalTypeSyntax_findsTheType() throws {
        let content = """
            protocol FooBar: Foo where Something == AnyObject? {}
            """

        let visitor = OptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        for optionalTypeIdentifier in visitor.optionalTypeIdentifiers {
            guard optionalTypeIdentifier.asSource != "Something" else { continue }
            XCTAssertFalse(optionalTypeIdentifier.isUnknown, "Type description is not of known type!")
            XCTAssertTrue(optionalTypeIdentifier.asSource.contains("AnyObject?"))
        }
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAImplicitlyUnwrappedOptionalTypeSyntax_findsTheType() throws {
        let content = """
            var int: Int!
            """

        let visitor = ImplicitlyUnwrappedOptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.implictlyUnwrappedOptionalTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Int!")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAType_findsTheType() throws {
        let content = """
            let metatype: Int.Type
            """

        let visitor = MetatypeTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.metatypeTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Int.Type")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAProtocol_findsTheType() throws {
        let content = """
            let metatype: Equatable.Protocol
            """

        let visitor = MetatypeTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.metatypeTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Equatable.Protocol")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASomeOrAnyTypeSyntax_withSome_findsTheType() throws {
        let content = """
            func makeSomething() -> some Equatable { "" }
            """

        let visitor = SomeOrAnyTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.someOrAnyTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "some Equatable")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASomeOrAnyTypeSyntax_withAny_findsTheType() throws {
        let content = """
            func makeSomething() -> any Equatable { "" }
            """

        let visitor = SomeOrAnyTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.someOrAnyTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "any Equatable")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnAttributedTypeSyntax_findsTheType() throws {
        let content = """
            func test(parameter: inout Int) {}
            """

        let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.attributedTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "inout Int")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnAttributedTypeSyntax_withAttributes_findsTheType() throws {
        let content = """
            @autoclosure () -> Void
            """

        let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.attributedTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "@autoclosure () -> Void")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnAttributedTypeSyntax_withSpecifierAndAttributes_findsTheType() throws {
        let content = """
            func test(parameter: inout @autoclosure () -> Void) {}
            """

        let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.attributedTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "inout @autoclosure () -> Void")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnArrayTypeSyntax_findsTheType() throws {
        let content = """
            var intArray: [Int] = [Int]()
            """

        let visitor = ArrayTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.arrayTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Array<Int>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnArray_notOfFormArrayTypeSyntax_findsTheType() throws {
        let content = """
            var intArray: Array<Int>
            """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.typeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Array<Int>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnArray_ofTwoDimensions_findsTheType() throws {
        let content = """
            var twoDimensionalIntArray: Array<Array<Int>>
            """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.typeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Array<Array<Int>>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingADictionaryTypeSyntax_findsTheType() throws {
        let content = """
            var dictionary: [Int: String] = [Int: String]()
            """

        let visitor = DictionaryTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.dictionaryTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Dictionary<Int, String>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingADictionary_notOfFormDictionaryTypeSyntax_findsTheType() throws {
        let content = """
            var dictionary: Dictionary<Int, String>
            """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.typeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Dictionary<Int, String>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingADictionary_OfTwoDimensions_findsTheType() throws {
        let content = """
            var twoDimensionalDictionary: Dictionary<Int, Dictionary<Int, String>>
            """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.typeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Dictionary<Int, Dictionary<Int, String>>")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingATupleTypeSyntax_findsTheType() throws {
        let content = """
            var tuple: (Int, String)
            """

        let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.tupleTypeIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "(Int, String)")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAClassRestrictionTypeSyntax_findsTheType() throws {
        let content = """
            protocol SomeObject: class {}
            """

        let visitor = ClassRestrictionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.classRestrictionIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "AnyObject")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAFunctionTypeSyntax_onAFunctionThatDoesNotThrow_findsTheType() throws {
        let content = """
            var test: (Int, Double) -> String
            """

        let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.functionIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "(Int, Double) -> String")
    }

    func test_typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAFunctionTypeSyntax_onAFunctionThatThrows_findsTheType() throws {
        let content = """
            var test: (Int, Double) throws -> String
            """

        let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.functionIdentifier)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "(Int, Double) throws -> String")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingASimpleType_findsTheType() throws {
        let content = """
            let type: Any.Type = String.self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "String")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingASimpleTypeWithGenerics_findsTheType() throws {
        let content = """
            let test: Any.Type = Array<Int>.self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Array<Int>")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingANestedTypeWithGenerics_findsTheType() throws {
        let content = """
            let test: Any.Type = Swift.Array<Int>.self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Swift.Array<Int>")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnAnyType_findsTheType() throws {
        let content = """
            let test: Any.Type = (any Collection).self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "any Collection")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingACompositionType_findsTheType() throws {
        let content = """
            let test: Any.Type = (Decodable & Encodable).self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Decodable & Encodable")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnOptionalType_findsTheType() throws {
        let content = """
            let test: Any.Type = Int?.self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Int?")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAMetatypeType_findsTheType() throws {
        let content = """
            let test: Any.Type = Int.Type.self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Int.Type")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAMetatypeProtocol_findsTheType() throws {
        let content = """
            let test: Any.Type = Int.Protocol.self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Int.Protocol")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnArrayType_findsTheType() throws {
        let content = """
            let test: Any.Type = [Int].self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Array<Int>")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingADictionaryType_findsTheType() throws {
        let content = """
            let test: Any.Type = [Int: String].self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "Dictionary<Int, String>")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingATupleType_findsTheType() throws {
        let content = """
            let test: Any.Type = (Int, String).self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "(Int, String)")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAClosureType_findsTheType() throws {
        let content = """
            let test: Any.Type = (() -> ()).self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "() -> ()")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAThrowingClosureType_findsTheType() throws {
        let content = """
            let test: Any.Type = (() throws -> ()).self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "() throws -> ()")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnAsyncClosureType_findsTheType() throws {
        let content = """
            let test: Any.Type = (() async -> ()).self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "() async -> ()")
    }

    func test_typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnAsyncThrowingClosureType_findsTheType() throws {
        let content = """
            let test: Any.Type = (() async throws -> ()).self
            """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try XCTUnwrap(visitor.typeDescription)
        XCTAssertFalse(typeDescription.isUnknown, "Type description is not of known type!")
        XCTAssertEqual(typeDescription.asSource, "() async throws -> ()")
    }

    func test_asSource_whenDescribingAnUnknownCase_returnsTheProvidedStringWithWhitespaceStripped() {
        let typeDescription = TypeSyntax(stringLiteral: " SomeTypeThatIsFormattedOddly    ").typeDescription
        XCTAssertEqual(typeDescription.asSource, "SomeTypeThatIsFormattedOddly")
    }

    // MARK: - Visitors

    private final class TypeIdentifierSyntaxVisitor: SyntaxVisitor {
        var typeIdentifier: TypeDescription?
        override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
            typeIdentifier = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class MemberTypeSyntaxVisitor: SyntaxVisitor {
        var nestedType: TypeDescription?
        override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
            nestedType = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class CompositionTypeSyntaxVisitor: SyntaxVisitor {
        var composedTypeIdentifier: TypeDescription?
        // Note: ideally we'd visit a node of type CompositionTypeElementListSyntax
        // but there's no easy way to get a TypeSyntax from an object of that type.
        override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
            composedTypeIdentifier = node.type.typeDescription
            return .skipChildren
        }
    }
    private final class OptionalTypeSyntaxVisitor: SyntaxVisitor {
        var optionalTypeIdentifiers = [TypeDescription]()
        override func visit(_ node: SameTypeRequirementSyntax) -> SyntaxVisitorContinueKind {
            optionalTypeIdentifiers += [
                node.leftType.typeDescription,
                node.rightType.typeDescription
            ]
            return .skipChildren
        }
    }
    private final class ImplicitlyUnwrappedOptionalTypeSyntaxVisitor: SyntaxVisitor {
        var implictlyUnwrappedOptionalTypeIdentifier: TypeDescription?
        override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) -> SyntaxVisitorContinueKind {
            implictlyUnwrappedOptionalTypeIdentifier = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class MetatypeTypeSyntaxVisitor: SyntaxVisitor {
        var metatypeTypeIdentifier: TypeDescription?
        override func visit(_ node: MetatypeTypeSyntax) -> SyntaxVisitorContinueKind {
            metatypeTypeIdentifier = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class SomeOrAnyTypeSyntaxVisitor: SyntaxVisitor {
        var someOrAnyTypeIdentifier: TypeDescription?
        override func visit(_ node: SomeOrAnyTypeSyntax) -> SyntaxVisitorContinueKind {
            someOrAnyTypeIdentifier = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class AttributedTypeSyntaxVisitor: SyntaxVisitor {
        var attributedTypeIdentifier: TypeDescription?
        override func visit(_ node: AttributedTypeSyntax) -> SyntaxVisitorContinueKind {
            attributedTypeIdentifier = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class ArrayTypeSyntaxVisitor: SyntaxVisitor {
        var arrayTypeIdentifier: TypeDescription?
        override func visit(_ node: ArrayTypeSyntax) -> SyntaxVisitorContinueKind {
            arrayTypeIdentifier = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class DictionaryTypeSyntaxVisitor: SyntaxVisitor {
        var dictionaryTypeIdentifier: TypeDescription?
        override func visit(_ node: DictionaryTypeSyntax) -> SyntaxVisitorContinueKind {
            dictionaryTypeIdentifier = TypeSyntax(node).typeDescription
            return .skipChildren
        }
    }
    private final class TupleTypeSyntaxVisitor: SyntaxVisitor {
        var tupleTypeIdentifier: TypeDescription?
        // Note: ideally we'd visit a node of type TupleTypeElementListSyntax
        // but there's no easy way to get a TypeSyntax from an object of that type.
        override func visit(_ node: TypeAnnotationSyntax) -> SyntaxVisitorContinueKind {
            tupleTypeIdentifier = node.type.typeDescription
            return .skipChildren
        }
    }
    private final class ClassRestrictionTypeSyntaxVisitor: SyntaxVisitor {
        var classRestrictionIdentifier: TypeDescription?
        // Note: ideally we'd visit a node of type ClassRestrictionTypeSyntax
        // but there's no way to get a TypeSyntax from an object of that type.
        override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
            classRestrictionIdentifier = node.type.typeDescription
            return .skipChildren
        }
    }
    private final class FunctionTypeSyntaxVisitor: SyntaxVisitor {
        var functionIdentifier: TypeDescription?
        // Note: ideally we'd visit a node of type FunctionTypeSyntax
        // but there's no way to get a TypeSyntax from an object of that type.
        override func visit(_ node: TypeAnnotationSyntax) -> SyntaxVisitorContinueKind {
            functionIdentifier = TypeSyntax(node.type)?.typeDescription
            return .skipChildren
        }
    }
    private final class MemberAccessExprSyntaxVisitor: SyntaxVisitor {
        var typeDescription: TypeDescription?
        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            typeDescription = ExprSyntax(node).typeDescription
            return .skipChildren
        }
    }
}
