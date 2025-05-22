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
import Testing

@testable import SafeDICore

struct TypeDescriptionTests {
    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAVoidTypeIdentifierSyntax_findsTheType() throws {
        let content = """
        var void: Void = ()
        """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Void")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingATypeIdentifierSyntax_findsTheType() throws {
        let content = """
        var int: Int = 1
        """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Int")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_findsTheType() throws {
        let content = """
        var int: Swift.Int = 1
        """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.nestedType)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Swift.Int")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_withRightHandGeneric_findsTheType() throws {
        let content = """
        var intArray: Swift.Array<Int> = [1]
        """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.nestedType)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Swift.Array<Int>")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_withLeftHandGeneric_findsTheType() throws {
        let content = """
        var genericType: OuterGenericType<Int>.InnerType
        """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.nestedType)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "OuterGenericType<Int>.InnerType")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAMemberTypeSyntax_withGenericOnBothSides_findsTheType() throws {
        let content = """
        var genericType: OuterGenericType<Int>.InnerGenericType<String>
        """

        let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.nestedType)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "OuterGenericType<Int>.InnerGenericType<String>")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingACompositionTypeSyntax_findsTheType() throws {
        let content = """
        protocol FooBar: Foo & Bar
        """

        let visitor = CompositionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.composedTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Foo & Bar")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAOptionalTypeSyntax_findsTheType() throws {
        let content = """
        var optionalAnyObject: AnyObject?
        """

        let visitor = OptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let optionalTypeIdentifier = try #require(visitor.optionalTypeIdentifier)
        #expect(!optionalTypeIdentifier.isUnknown, "Type description is not of known type!")
        #expect(optionalTypeIdentifier.asSource == "AnyObject?")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAOptionalClosureTypeSyntax_findsTheType() throws {
        let content = """
        var optionalClosure: (() -> Void)?
        """

        let visitor = OptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let optionalTypeIdentifier = try #require(visitor.optionalTypeIdentifier)
        #expect(!optionalTypeIdentifier.isUnknown, "Type description is not of known type!")
        #expect(optionalTypeIdentifier.asSource == "(() -> Void)?")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAImplicitlyUnwrappedOptionalTypeSyntax_findsTheType() throws {
        let content = """
        var int: Int!
        """

        let visitor = ImplicitlyUnwrappedOptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.implictlyUnwrappedOptionalTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Int!")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAType_findsTheType() throws {
        let content = """
        let metatype: Int.Type
        """

        let visitor = MetatypeTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.metatypeTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Int.Type")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAProtocol_findsTheType() throws {
        let content = """
        let metatype: Equatable.Protocol
        """

        let visitor = MetatypeTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.metatypeTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Equatable.Protocol")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASomeOrAnyTypeSyntax_withSome_findsTheType() throws {
        let content = """
        func makeSomething() -> some Equatable { "" }
        """

        let visitor = SomeOrAnyTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.someOrAnyTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "some Equatable")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASomeOrAnyTypeSyntax_withAny_findsTheType() throws {
        let content = """
        func makeSomething() -> any Equatable { "" }
        """

        let visitor = SomeOrAnyTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.someOrAnyTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "any Equatable")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnAttributedTypeSyntax_findsTheType() throws {
        let content = """
        func test(parameter: inout Int) {}
        """

        let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.attributedTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "inout Int")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnAttributedTypeSyntax_withAttributes_findsTheType() throws {
        let content = """
        @autoclosure () -> Void
        """

        let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.attributedTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "@autoclosure () -> Void")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnAttributedTypeSyntax_withSpecifierAndAttributes_findsTheType() throws {
        let content = """
        func test(parameter: inout @autoclosure () -> Void) {}
        """

        let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.attributedTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "inout @autoclosure () -> Void")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnAttributedTypeSyntax_withMultipleSpecifiers_findsTheType() throws {
        let content = """
        func test(parameter: sending @autoclosure () -> Void) {}
        """

        let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.attributedTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "sending @autoclosure () -> Void")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnArrayTypeSyntax_findsTheType() throws {
        let content = """
        var intArray: [Int] = [Int]()
        """

        let visitor = ArrayTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.arrayTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "[Int]")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnArray_notOfFormArrayTypeSyntax_findsTheType() throws {
        let content = """
        var intArray: Array<Int>
        """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Array<Int>")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAnArray_ofTwoDimensions_findsTheType() throws {
        let content = """
        var twoDimensionalIntArray: Array<Array<Int>>
        """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Array<Array<Int>>")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingADictionaryTypeSyntax_findsTheType() throws {
        let content = """
        var dictionary: [Int: String] = [Int: String]()
        """

        let visitor = DictionaryTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.dictionaryTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "[Int: String]")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingADictionary_notOfFormDictionaryTypeSyntax_findsTheType() throws {
        let content = """
        var dictionary: Dictionary<Int, String>
        """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Dictionary<Int, String>")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingADictionary_OfTwoDimensions_findsTheType() throws {
        let content = """
        var twoDimensionalDictionary: Dictionary<Int, Dictionary<Int, String>>
        """

        let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Dictionary<Int, Dictionary<Int, String>>")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAVoidTupleTypeSyntax_findsTheType() throws {
        let content = """
        var voidTuple: ()
        """

        let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.tupleTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "()")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASpelledOutVoidWrappedInTupleTypeSyntax_findsTheType() throws {
        let content = """
        var voidTuple: (Void)
        """

        let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.tupleTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Void")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAVoidWrappedInTupleTypeSyntax_findsTheType() throws {
        let content = """
        var voidTuple: (())
        """

        let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.tupleTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "()")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingATupleTypeSyntax_findsTheType() throws {
        let content = """
        var tuple: (Int, String)
        """

        let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.tupleTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "(Int, String)")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASigleElementTupleTypeSyntax_findsTheType() throws {
        let content = """
        var tupleWrappedString: (String)
        """

        let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.tupleTypeIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "String")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAClassRestrictionTypeSyntax_findsTheType() throws {
        let content = """
        protocol SomeObject: class {}
        """

        let visitor = ClassRestrictionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.classRestrictionIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "AnyObject")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAFunctionTypeSyntax_onAFunctionThatDoesNotThrow_findsTheType() throws {
        let content = """
        var test: (Int, Double) -> String
        """

        let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.functionIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "(Int, Double) -> String")
    }

    @Test
    func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingAFunctionTypeSyntax_onAFunctionThatThrows_findsTheType() throws {
        let content = """
        var test: (Int, Double) throws -> String
        """

        let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.functionIdentifier)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "(Int, Double) throws -> String")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAVoidType_findsTheType() throws {
        let content = """
        let type: Void.Type = Void.self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Void")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingASimpleType_findsTheType() throws {
        let content = """
        let type: Any.Type = String.self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "String")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingASimpleTypeWithGenerics_findsTheType() throws {
        let content = """
        let test: Any.Type = Array<Int>.self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))

        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Array<Int>")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingANestedTypeWithGenerics_findsTheType() throws {
        let content = """
        let test: Any.Type = Swift.Array<Int>.self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Swift.Array<Int>")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnAnyType_findsTheType() throws {
        let content = """
        let test: Any.Type = (any Collection).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "any Collection")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingACompositionType_findsTheType() throws {
        let content = """
        let test: Any.Type = (Decodable & Encodable).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Decodable & Encodable")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnOptionalType_findsTheType() throws {
        let content = """
        let test: Any.Type = Int?.self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Int?")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAMetatypeType_findsTheType() throws {
        let content = """
        let test: Any.Type = Int.Type.self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Int.Type")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAMetatypeProtocol_findsTheType() throws {
        let content = """
        let test: Any.Type = Int.Protocol.self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "Int.Protocol")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnArrayType_findsTheType() throws {
        let content = """
        let test: Any.Type = [Int].self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "[Int]")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingADictionaryType_findsTheType() throws {
        let content = """
        let test: Any.Type = [Int: String].self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "[Int: String]")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingATupleTypeWithoutLabels_findsTheType() throws {
        let content = """
        let test: Any.Type = (Int, String).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "(Int, String)")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingATupleTypeWithOneLabel_findsTheType() throws {
        let content = """
        let test: Any.Type = (int: Int, String).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "(int: Int, String)")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingATupleTypeWithLabels_findsTheType() throws {
        let content = """
        let test: Any.Type = (int: Int, string: String).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "(int: Int, string: String)")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAClosureType_findsTheType() throws {
        let content = """
        let test: Any.Type = (() -> ()).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "() -> ()")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAThrowingClosureType_findsTheType() throws {
        let content = """
        let test: Any.Type = (((() throws -> ()))).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "() throws -> ()")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnAsyncClosureType_findsTheType() throws {
        let content = """
        let test: Any.Type = (() async -> ()).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "() async -> ()")
    }

    @Test
    func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAnAsyncThrowingClosureType_findsTheType() throws {
        let content = """
        let test: Any.Type = (() async throws -> ()).self
        """
        let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: content))
        let typeDescription = try #require(visitor.typeDescription)
        #expect(!typeDescription.isUnknown, "Type description is not of known type!")
        #expect(typeDescription.asSource == "() async throws -> ()")
    }

    @Test
    func asSource_whenDescribingAnUnknownCase_returnsTheProvidedStringWithTrailingWhitespaceStripped() {
        let typeDescription = TypeSyntax(stringLiteral: "<[]>    ").typeDescription
        #expect(typeDescription.asSource == "<[]>")
    }

    @Test
    func equality_isTrueWhenComparingDifferentVoidSpellings() {
        #expect(TypeDescription.void(.identifier) == TypeDescription.void(.tuple))
    }

    @Test
    func equality_isTrueWhenComparingDifferentVoidSpellingsInHashedCollections() {
        #expect(Set([TypeDescription.void(.identifier)]) == Set([TypeDescription.void(.tuple)]))
    }

    @Test
    func equality_isTrueWhenComparingLexigraphicallyEquivalentCompositions() {
        #expect(
            TypeDescription.composition([
                .simple(name: "Foo"),
                .simple(name: "Bar"),
            ]) == TypeDescription.composition([
                .simple(name: "Foo"),
                .simple(name: "Bar"),
            ])
        )
    }

    @Test
    func equality_isTrueWhenComparingReversedCompositions() {
        #expect(
            TypeDescription.composition([
                .simple(name: "Foo"),
                .simple(name: "Bar"),
            ]) == TypeDescription.composition([
                .simple(name: "Bar"),
                .simple(name: "Foo"),
            ])
        )
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
        // but there’s no easy way to get a TypeSyntax from an object of that type.
        override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
            composedTypeIdentifier = node.type.typeDescription
            return .skipChildren
        }
    }

    private final class OptionalTypeSyntaxVisitor: SyntaxVisitor {
        var optionalTypeIdentifier: TypeDescription?
        override func visit(_ node: OptionalTypeSyntax) -> SyntaxVisitorContinueKind {
            optionalTypeIdentifier = TypeSyntax(node).typeDescription
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
        // but there’s no easy way to get a TypeSyntax from an object of that type.
        override func visit(_ node: TypeAnnotationSyntax) -> SyntaxVisitorContinueKind {
            tupleTypeIdentifier = node.type.typeDescription
            return .skipChildren
        }
    }

    private final class ClassRestrictionTypeSyntaxVisitor: SyntaxVisitor {
        var classRestrictionIdentifier: TypeDescription?
        // Note: ideally we'd visit a node of type ClassRestrictionTypeSyntax
        // but there’s no way to get a TypeSyntax from an object of that type.
        override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
            classRestrictionIdentifier = node.type.typeDescription
            return .skipChildren
        }
    }

    private final class FunctionTypeSyntaxVisitor: SyntaxVisitor {
        var functionIdentifier: TypeDescription?
        // Note: ideally we'd visit a node of type FunctionTypeSyntax
        // but there’s no way to get a TypeSyntax from an object of that type.
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

extension TypeDescription {
    var isUnknown: Bool {
        switch self {
        case .any,
             .array,
             .attributed,
             .closure,
             .composition,
             .dictionary,
             .implicitlyUnwrappedOptional,
             .metatype,
             .nested,
             .optional,
             .simple,
             .some,
             .tuple,
             .void:
            false
        case .unknown:
            true
        }
    }
}
