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
	private static func parsedType(_ source: String) -> TypeDescription {
		var parser = Parser(source)
		return TypeSyntax.parse(from: &parser).typeDescription
	}

	@Test(arguments: [
		("Store", "ModA.Store"),
		("Box<Store>", "Box<ModA.Store>"),
		("Outer.Box<Store>", "Outer.Box<ModA.Store>"),
		("Store & Other", "ModA.Store & Other"),
		("Store?", "ModA.Store?"),
		("Store!", "ModA.Store!"),
		("some Store", "some ModA.Store"),
		("any Store", "any ModA.Store"),
		("Store.Type", "ModA.Store.Type"),
		("sending Store", "sending ModA.Store"),
		("[Store]", "[ModA.Store]"),
		("[Store: Int]", "[ModA.Store: Int]"),
		("[Int: Store]", "[Int: ModA.Store]"),
		("(Store, label: Store)", "(ModA.Store, label: ModA.Store)"),
		("(Store) -> Void", "(ModA.Store) -> Void"),
		("() throws(Store) -> Void", "() throws(ModA.Store) -> Void"),
		("() -> Store", "() -> ModA.Store"),
		("(Store...) -> Void", "(ModA.Store...) -> Void"),
	])
	func replacingTypes_replacesTheType_whereverTheReceiverNamesIt(source: String, expected: String) {
		#expect(Self.parsedType(source).replacingTypes([.simple(name: "Store"): .nested(name: "Store", parentType: .simple(name: "ModA"))])?.asSource == expected)
	}

	@Test(arguments: ["Int", "Store.Config", "Box<Int>", "Outer.Box<Int>", "Int & Other", "Int?", "Int!", "some Int", "any Int", "Int.Type", "sending Int", "[Int]", "[Int: Int]", "(Int, label: Int)", "(Int) throws -> Int", "(Int...) -> Void", "Void"])
	func replacingTypes_returnsNil_whenTheReceiverNamesNoType(source: String) {
		#expect(Self.parsedType(source).replacingTypes([.simple(name: "Store"): .nested(name: "Store", parentType: .simple(name: "ModA"))]) == nil)
	}

	@Test(arguments: [("Store", "ModA.Store"), ("Feature.Store", "ModA.Feature.Store"), ("Box<Int>", "ModA.Box<Int>")])
	func qualified_spellsTheModuleBeforeTheOutermostName_whenTheReceiverIsANamedType(source: String, expected: String) {
		#expect(Self.parsedType(source).qualified(byModuleNamed: "ModA")?.asSource == expected)
	}

	@Test(arguments: ["any Store", "Store?", "[Store]", "Store & Other", "() -> Void", "(Int, Int)", "Void"])
	func qualified_returnsNil_whenTheReceiverIsNotANamedType(source: String) {
		#expect(Self.parsedType(source).qualified(byModuleNamed: "ModA") == nil)
	}

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
		func test(parameter: @autoclosure () -> Void) {}
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
	func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingATupleTypeSyntaxWithLabelsEscapedEitherWay_spellsLabelsAsDeclarationsDo() throws {
		let content = """
		var tuple: (default: Int, `string`: String)
		"""

		let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.tupleTypeIdentifier)
		#expect(typeDescription.asSource == "(`default`: Int, string: String)")
	}

	@Test
	func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASingleElementTupleTypeSyntax_findsTheType() throws {
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
	func typeDescription_whenCalledOnATypeSyntaxNodeRepresentingASuppressedTypeSyntax_returnsUnknown() throws {
		let content = """
		var test: ~Copyable
		"""

		let visitor = SuppressedTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))
		let typeDescription = try #require(visitor.suppressedTypeIdentifier)
		#expect(typeDescription.isUnknown)
		#expect(typeDescription.asSource == "~Copyable")
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
	func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingATupleTypeWithLabelsEscapedEitherWay_spellsLabelsAsDeclarationsDo() throws {
		let content = """
		let test: Any.Type = (default: Int, `string`: String).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))
		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asSource == "(`default`: Int, string: String)")
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
	func typeDescription_whenCalledOnAExprSyntaxNodeRepresentingAClosureTypeWithArguments_findsTheType() throws {
		let content = """
		let test: Any.Type = ((Int, String) -> Bool).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))
		let typeDescription = try #require(visitor.typeDescription)
		#expect(!typeDescription.isUnknown, "Type description is not of known type!")
		#expect(typeDescription.asSource == "(Int, String) -> Bool")
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
		#expect(TypeDescription.composition([
			.simple(name: "Foo"),
			.simple(name: "Bar"),
		]) == TypeDescription.composition([
			.simple(name: "Foo"),
			.simple(name: "Bar"),
		]))
	}

	@Test
	func equality_isTrueWhenComparingReversedCompositions() {
		#expect(TypeDescription.composition([
			.simple(name: "Foo"),
			.simple(name: "Bar"),
		]) == TypeDescription.composition([
			.simple(name: "Bar"),
			.simple(name: "Foo"),
		]))
	}

	@Test
	func asFunctionParameter_doesNotChangeOrderingOfEscapingWhenEscapingIsLast() {
		#expect(TypeDescription.attributed(
			.closure(
				arguments: [.void(.tuple)],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.identifier),
			),
			specifiers: [],
			attributes: ["autoclosure", "escaping"],
		).asFunctionParameter == TypeDescription.attributed(
			.closure(
				arguments: [.void(.tuple)],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.identifier),
			),
			specifiers: [],
			attributes: ["autoclosure", "escaping"],
		))
	}

	@Test
	func asFunctionParameter_doesNotChangeOrderingOfEscapingWhenEscapingIsFirst() {
		#expect(TypeDescription.attributed(
			.closure(
				arguments: [.void(.tuple)],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.identifier),
			),
			specifiers: [],
			attributes: ["escaping", "autoclosure"],
		).asFunctionParameter == TypeDescription.attributed(
			.closure(
				arguments: [.void(.tuple)],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.identifier),
			),
			specifiers: [],
			attributes: ["escaping", "autoclosure"],
		))
	}

	@Test
	func strippingEscaping_removesEscapingButPreservesSpecifiers() {
		let type = TypeDescription.attributed(
			.closure(
				arguments: [],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.tuple),
			),
			specifiers: ["borrowing"],
			attributes: ["escaping"],
		)
		let stripped = type.strippingEscaping
		#expect(stripped == .attributed(
			.closure(
				arguments: [],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.tuple),
			),
			specifiers: ["borrowing"],
			attributes: [],
		))
	}

	@Test
	func asFunctionParameter_addsEscapingWhenNoAttributesFound() {
		#expect(TypeDescription.attributed(
			.closure(
				arguments: [.void(.tuple)],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.identifier),
			),
			specifiers: [],
			attributes: [],
		).asFunctionParameter == TypeDescription.attributed(
			.closure(
				arguments: [.void(.tuple)],
				isAsync: false,
				doesThrow: false,
				returnType: .void(.identifier),
			),
			specifiers: [],
			attributes: ["escaping"],
		))
	}

	// MARK: - simplified Tests

	@Test
	func simplified_stripsOptional() {
		let type = TypeDescription.optional(.simple(name: "Service"))
		#expect(type.simplified == .simple(name: "Service"))
	}

	@Test
	func simplified_stripsImplicitlyUnwrappedOptional() {
		let type = TypeDescription.implicitlyUnwrappedOptional(.simple(name: "Service"))
		#expect(type.simplified == .simple(name: "Service"))
	}

	@Test
	func simplified_stripsSome() {
		let type = TypeDescription.some(.simple(name: "Equatable"))
		#expect(type.simplified == .simple(name: "Equatable"))
	}

	@Test
	func simplified_stripsAny() {
		let type = TypeDescription.any(.simple(name: "Collection"))
		#expect(type.simplified == .simple(name: "Collection"))
	}

	@Test
	func simplified_stripsMetatype() {
		let type = TypeDescription.metatype(.simple(name: "Int"), isType: true)
		#expect(type.simplified == .simple(name: "Int"))
	}

	@Test
	func simplified_stripsAttributes() {
		let type = TypeDescription.attributed(.simple(name: "Int"), specifiers: ["inout"], attributes: [])
		#expect(type.simplified == .simple(name: "Int"))
	}

	@Test
	func simplified_stripsNestedWrappers() {
		let type = TypeDescription.optional(.attributed(.some(.simple(name: "Service")), specifiers: [], attributes: ["Sendable"]))
		#expect(type.simplified == .simple(name: "Service"))
	}

	@Test
	func simplified_preservesSimpleType() {
		let type = TypeDescription.simple(name: "String")
		#expect(type.simplified == .simple(name: "String"))
	}

	@Test
	func simplified_preservesClosure() {
		let type = TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: .void(.identifier))
		#expect(type.simplified == type)
	}

	@Test
	func simplified_preservesArray() {
		let type = TypeDescription.array(element: .simple(name: "Int"))
		#expect(type.simplified == type)
	}

	// MARK: - asIdentifier Tests

	@Test
	func asIdentifier_forNestedTypeWithoutGenerics_producesValidIdentifier() throws {
		let content = """
		var int: Swift.Int = 1
		"""

		let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.nestedType)
		#expect(typeDescription.asIdentifier == "Swift_Int")
	}

	@Test
	func asIdentifier_forFunctionType_producesValidIdentifier() throws {
		let content = """
		var test: (Int, Double) -> String
		"""

		let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.functionIdentifier)
		#expect(typeDescription.asIdentifier == "Int_Double_to_String")
	}

	@Test
	func asIdentifier_forThrowingFunctionType_producesValidIdentifier() throws {
		let content = """
		var test: (Int, Double) throws -> String
		"""

		let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.functionIdentifier)
		#expect(typeDescription.asIdentifier == "Int_Double_throws_to_String")
	}

	@Test
	func asIdentifier_forExprClosureType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (() -> ()).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Void_to_Void")
	}

	@Test
	func asIdentifier_forExprThrowingClosureType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (() throws -> ()).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Void_throws_to_Void")
	}

	@Test
	func asIdentifier_forExprAsyncClosureType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (() async -> ()).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Void_async_to_Void")
	}

	@Test
	func asIdentifier_forExprAsyncThrowingClosureType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (() async throws -> ()).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Void_async_throws_to_Void")
	}

	@Test
	func asIdentifier_forNestedGenericType_producesValidIdentifier() throws {
		let content = """
		var test: OuterGenericType<Int>.InnerGenericType<String>
		"""

		let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.nestedType)
		#expect(typeDescription.asIdentifier == "OuterGenericType__Int_InnerGenericType__String")
	}

	@Test
	func asIdentifier_forImplicitlyUnwrappedOptional_producesValidIdentifier() throws {
		let content = """
		var type: Int! = 1
		"""

		let visitor = ImplicitlyUnwrappedOptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.implictlyUnwrappedOptionalTypeIdentifier)
		#expect(typeDescription.asIdentifier == "Int_Optional")
	}

	@Test
	func asIdentifier_forSomeType_producesValidIdentifier() throws {
		let content = """
		var type: some Equatable = 1
		"""

		let visitor = SomeOrAnyTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.someOrAnyTypeIdentifier)
		#expect(typeDescription.asIdentifier == "some_Equatable")
	}

	@Test
	func asIdentifier_forMetatypeType_producesValidIdentifier() throws {
		let content = """
		var type: Int.Type = Int.self
		"""

		let visitor = MetatypeTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let metatypeTypeIdentifier = try #require(visitor.metatypeTypeIdentifier)
		#expect(metatypeTypeIdentifier.asIdentifier == "Int_Type")
	}

	@Test
	func asIdentifier_forInoutAttribute_producesValidIdentifier() throws {
		let content = """
		func test(parameter: inout Int) {}
		"""

		let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeIdentifier = try #require(visitor.attributedTypeIdentifier)
		#expect(typeIdentifier.asIdentifier == "inout_Int")
	}

	@Test
	func asIdentifier_forAutoclosureAttribute_producesValidIdentifier() throws {
		let content = """
		func test(parameter: @autoclosure () -> Void) {}
		"""

		let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeIdentifier = try #require(visitor.attributedTypeIdentifier)
		#expect(typeIdentifier.asIdentifier == "autoclosure_Void_to_Void")
	}

	@Test
	func asIdentifier_forInoutAutoclosureAttribute_producesValidIdentifier() throws {
		let content = """
		func test(parameter: inout @autoclosure () -> Void) {}
		"""

		let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeIdentifier = try #require(visitor.attributedTypeIdentifier)
		#expect(typeIdentifier.asIdentifier == "inout_autoclosure_Void_to_Void")
	}

	@Test
	func asIdentifier_forSendingAutoclosureAttribute_producesValidIdentifier() throws {
		let content = """
		func test(parameter: sending @autoclosure () -> Void) {}
		"""

		let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeIdentifier = try #require(visitor.attributedTypeIdentifier)
		#expect(typeIdentifier.asIdentifier == "sending_autoclosure_Void_to_Void")
	}

	@Test
	func asIdentifier_forArrayTypeSyntax_producesValidIdentifier() throws {
		let content = """
		var array: [Int] = []
		"""

		let visitor = ArrayTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let arrayTypeIdentifier = try #require(visitor.arrayTypeIdentifier)
		#expect(arrayTypeIdentifier.asIdentifier == "Array_Int")
	}

	@Test
	func asIdentifier_forGenericArray_producesValidIdentifier() throws {
		let content = """
		var array: Array<Int> = []
		"""

		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let arrayTypeIdentifier = try #require(visitor.typeIdentifier)
		#expect(arrayTypeIdentifier.asIdentifier == "Array__Int")
	}

	@Test
	func asIdentifier_forTwoDimensionalArray_producesValidIdentifier() throws {
		let content = """
		var array: Array<Array<Int>> = []
		"""

		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let arrayTypeIdentifier = try #require(visitor.typeIdentifier)
		#expect(arrayTypeIdentifier.asIdentifier == "Array__Array__Int")
	}

	@Test
	func asIdentifier_forDictionaryTypeSyntax_producesValidIdentifier() throws {
		let content = """
		var dict: [Int: String] = [:]
		"""

		let visitor = DictionaryTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let dictionaryTypeIdentifier = try #require(visitor.dictionaryTypeIdentifier)
		#expect(dictionaryTypeIdentifier.asIdentifier == "Dictionary_Int_String")
	}

	@Test
	func asIdentifier_forGenericDictionary_producesValidIdentifier() throws {
		let content = """
		var dict: Dictionary<Int, String> = [:]
		"""

		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let dictionaryTypeIdentifier = try #require(visitor.typeIdentifier)
		#expect(dictionaryTypeIdentifier.asIdentifier == "Dictionary__Int__String")
	}

	@Test
	func asIdentifier_forTwoDimensionalDictionary_producesValidIdentifier() throws {
		let content = """
		var dict: Dictionary<Int, Dictionary<Int, String>> = [:]
		"""

		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let dictionaryTypeIdentifier = try #require(visitor.typeIdentifier)
		#expect(dictionaryTypeIdentifier.asIdentifier == "Dictionary__Int__Dictionary__Int__String")
	}

	@Test
	func asIdentifier_forVoidTuple_producesValidIdentifier() throws {
		let content = """
		var void: () = ()
		"""

		let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let tupleTypeIdentifier = try #require(visitor.tupleTypeIdentifier)
		#expect(tupleTypeIdentifier.asIdentifier == "Void")
	}

	@Test
	func asIdentifier_forSpelledOutVoidInTuple_producesValidIdentifier() throws {
		let content = """
		var void: (Void) = ()
		"""

		let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let tupleTypeIdentifier = try #require(visitor.tupleTypeIdentifier)
		#expect(tupleTypeIdentifier.asIdentifier == "Void")
	}

	@Test
	func asIdentifier_forVoidWrappedInTuple_producesValidIdentifier() throws {
		let content = """
		var void: (()) = ()
		"""

		let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let tupleTypeIdentifier = try #require(visitor.tupleTypeIdentifier)
		#expect(tupleTypeIdentifier.asIdentifier == "Void")
	}

	@Test
	func asIdentifier_forTupleType_producesValidIdentifier() throws {
		let content = """
		var tuple: (Int, String) = (1, "")
		"""

		let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let tupleTypeIdentifier = try #require(visitor.tupleTypeIdentifier)
		#expect(tupleTypeIdentifier.asIdentifier == "Int_and_String")
	}

	@Test
	func asIdentifier_forSingleElementTuple_producesValidIdentifier() throws {
		let content = """
		var element: (String) = ""
		"""

		let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let tupleTypeIdentifier = try #require(visitor.tupleTypeIdentifier)
		#expect(tupleTypeIdentifier.asIdentifier == "String")
	}

	@Test
	func asIdentifier_forClassRestriction_producesValidIdentifier() throws {
		let content = """
		protocol SomeObject: class {}
		"""

		let visitor = ClassRestrictionTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let classRestrictionTypeIdentifier = try #require(visitor.classRestrictionIdentifier)
		#expect(classRestrictionTypeIdentifier.asIdentifier == "AnyObject")
	}

	@Test
	func asIdentifier_forExprVoidType_producesValidIdentifier() throws {
		let content = """
		let type: Void.Type = Void.self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Void")
	}

	@Test
	func asIdentifier_forExprSimpleType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = String.self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "String")
	}

	@Test
	func asIdentifier_forExprGenericType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = Array<Int>.self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Array__Int")
	}

	@Test
	func asIdentifier_forExprNestedGenericType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = Swift.Array<Int>.self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Swift_Array__Int")
	}

	@Test
	func asIdentifier_forExprAnyType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (any Collection).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "any_Collection")
	}

	@Test
	func asIdentifier_forExprCompositionType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (Decodable & Encodable).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Decodable_and_Encodable")
	}

	@Test
	func asIdentifier_forExprOptionalType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = Int?.self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Int_Optional")
	}

	@Test
	func asIdentifier_forExprMetatypeType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = Int.Type.self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Int_Type")
	}

	@Test
	func asIdentifier_forExprMetatypeProtocol_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = Int.Protocol.self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Int_Protocol")
	}

	@Test
	func asIdentifier_forExprArrayType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = [Int].self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Array_Int")
	}

	@Test
	func asIdentifier_forExprDictionaryType_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = [Int: String].self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Dictionary_Int_String")
	}

	@Test
	func asIdentifier_forExprTupleWithoutLabels_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (Int, String).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Int_and_String")
	}

	@Test
	func asIdentifier_forExprTupleWithOneLabel_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (int: Int, String).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Int_and_String")
	}

	@Test
	func asIdentifier_forExprTupleWithLabels_producesValidIdentifier() throws {
		let content = """
		let type: Any.Type = (int: Int, string: String).self
		"""
		let visitor = MemberAccessExprSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: content))

		let typeDescription = try #require(visitor.typeDescription)
		#expect(typeDescription.asIdentifier == "Int_and_String")
	}

	@Test
	func asIdentifier_forUnknownType_producesValidIdentifier() {
		let typeDescription = TypeSyntax(stringLiteral: "<[]>    ").typeDescription
		#expect(typeDescription.asIdentifier == "")
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

	private final class SuppressedTypeSyntaxVisitor: SyntaxVisitor {
		var suppressedTypeIdentifier: TypeDescription?
		override func visit(_ node: SuppressedTypeSyntax) -> SyntaxVisitorContinueKind {
			suppressedTypeIdentifier = TypeSyntax(node).typeDescription
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

	// MARK: - containsSelf

	@Test
	func containsSelf_whenTypeIsBareSelf_returnsTrue() throws {
		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Self"))
		let typeDescription = try #require(visitor.typeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsSimpleNonSelf_returnsFalse() throws {
		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Int"))
		let typeDescription = try #require(visitor.typeIdentifier)
		#expect(!typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenSelfIsNestedInGenerics_returnsTrue() throws {
		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Optional<Self>"))
		let typeDescription = try #require(visitor.typeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenNestedTypeHasSelfParent_returnsTrue() throws {
		let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Self.Element"))
		let typeDescription = try #require(visitor.nestedType)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenNestedTypeHasSelfInGenerics_returnsTrue() throws {
		let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Tree.Node<Self>"))
		let typeDescription = try #require(visitor.nestedType)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsOptionalSelf_returnsTrue() throws {
		let visitor = OptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Self?"))
		let typeDescription = try #require(visitor.optionalTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsImplicitlyUnwrappedOptionalSelf_returnsTrue() throws {
		let visitor = ImplicitlyUnwrappedOptionalTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Self!"))
		let typeDescription = try #require(visitor.implictlyUnwrappedOptionalTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsSomeSelf_returnsTrue() throws {
		let visitor = SomeOrAnyTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: some Self"))
		let typeDescription = try #require(visitor.someOrAnyTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsAnySelf_returnsTrue() throws {
		let visitor = SomeOrAnyTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: any Self"))
		let typeDescription = try #require(visitor.someOrAnyTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsArrayOfSelf_returnsTrue() throws {
		let visitor = ArrayTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: [Self]"))
		let typeDescription = try #require(visitor.arrayTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsDictionaryWithSelfKey_returnsTrue() throws {
		let visitor = DictionaryTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: [Self: Int]"))
		let typeDescription = try #require(visitor.dictionaryTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsDictionaryWithSelfValue_returnsTrue() throws {
		let visitor = DictionaryTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: [Int: Self]"))
		let typeDescription = try #require(visitor.dictionaryTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsTupleContainingSelf_returnsTrue() throws {
		let visitor = TupleTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: (Int, Self)"))
		let typeDescription = try #require(visitor.tupleTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsCompositionContainingSelf_returnsTrue() throws {
		let visitor = CompositionTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "protocol P: Hashable & Self {}"))
		let typeDescription = try #require(visitor.composedTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenClosureReturnsSelf_returnsTrue() throws {
		let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: (Int) -> Self"))
		let typeDescription = try #require(visitor.functionIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenClosureArgumentIsSelf_returnsTrue() throws {
		let visitor = FunctionTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: (Self) -> Void"))
		let typeDescription = try #require(visitor.functionIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsSelfMetatype_returnsTrue() throws {
		let visitor = MetatypeTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Self.Type"))
		let typeDescription = try #require(visitor.metatypeTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsAttributedSelf_returnsTrue() throws {
		let visitor = AttributedTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: @escaping (Int) -> Self"))
		let typeDescription = try #require(visitor.attributedTypeIdentifier)
		#expect(typeDescription.containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsUnknown_returnsFalse() {
		// `.unknown` is created for type syntax the parser can't categorize.
		// The stored `text` is incidental — `containsSelf` never inspects it.
		#expect(!TypeDescription.unknown(text: "Self").containsSelf)
	}

	@Test
	func containsSelf_whenTypeIsVoid_returnsFalse() throws {
		let visitor = TypeIdentifierSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Void"))
		let typeDescription = try #require(visitor.typeIdentifier)
		#expect(!typeDescription.containsSelf)
	}

	// MARK: - namesType

	@Test
	func namesType_namesEveryPathTheTypesPathStartsWith_whenTypeIsNestedTwoLevels() throws {
		let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: Child.Config.Options"))
		let typeDescription = try #require(visitor.nestedType)
		var namedPaths = [[String]]()
		_ = typeDescription.namesType(where: {
			namedPaths.append($0)
			return false
		})
		#expect(namedPaths == [["Child"], ["Child", "Config"], ["Child", "Config", "Options"]])
	}

	@Test
	func namesType_namesNoPathThroughParent_whenParentIsNotNamedType() throws {
		let visitor = MemberTypeSyntaxVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: "var x: [Config].Element"))
		let typeDescription = try #require(visitor.nestedType)
		var namedPaths = [[String]]()
		_ = typeDescription.namesType(where: {
			namedPaths.append($0)
			return false
		})
		#expect(namedPaths == [["Config"]])
	}

	// MARK: - nestingOutermostNames

	@Test(arguments: [
		("Theme", "Child.Theme"),
		("Box<Theme>", "Child.Box<Child.Theme>"),
		("Inner.Palette", "Child.Inner.Palette"),
		("Swift.Result<Theme, Failure>", "Swift.Result<Child.Theme, Failure>"),
		("Theme?", "Child.Theme?"),
		("Theme!", "Child.Theme!"),
		("some Delegate", "some Child.Delegate"),
		("any Delegate", "any Child.Delegate"),
		("Delegate & Sendable", "Child.Delegate & Sendable"),
		("Theme.Type", "Child.Theme.Type"),
		("@escaping (Theme) async throws -> Inner.Palette", "@escaping (Child.Theme) async throws -> Child.Inner.Palette"),
		("[Theme]", "[Child.Theme]"),
		("[Failure: Theme]", "[Failure: Child.Theme]"),
		("(Theme, label: Theme)", "(Child.Theme, label: Child.Theme)"),
		("Void", "Void"),
		("~Copyable", "~Copyable"),
	])
	func nestingOutermostNames_nestsOnlyTheOutermostNamesItIsGivenAnEnclosingTypeFor_whereverTheyAreInTheType(source: String, expected: String) {
		let typeDescription = TypeSyntax(stringLiteral: source).typeDescription

		let nested = typeDescription.nestingOutermostNames { name in
			["Theme", "Box", "Inner", "Delegate"].contains(name) ? .simple(name: "Child") : nil
		}

		#expect(nested.asSource == expected)
	}

	@Test(arguments: [
		"Theme",
		"Box<Theme>",
		"Inner.Palette",
		"Swift.Result<Theme, Failure>",
		"Theme?",
		"Theme!",
		"some Delegate",
		"any Delegate",
		"Delegate & Sendable",
		"Theme.Type",
		"@escaping (Theme) async throws -> Inner.Palette",
		"[Theme]",
		"[Failure: Theme]",
		"(Theme, label: Theme)",
		"Void",
		"~Copyable",
	])
	func nestingOutermostNamesIfAny_returnsNil_whenItIsGivenNoEnclosingTypeForAnyName(source: String) {
		let typeDescription = TypeSyntax(stringLiteral: source).typeDescription

		let nested = typeDescription.nestingOutermostNamesIfAny { _ in nil }

		#expect(nested == nil)
	}

	@Test(arguments: [
		("(Failure, label: Theme)", "(Failure, label: Child.Theme)"),
		("[Theme: Failure]", "[Child.Theme: Failure]"),
		("(Failure) -> Theme", "(Failure) -> Child.Theme"),
		("Swift.Result<Failure, Theme>", "Swift.Result<Failure, Child.Theme>"),
		("Sendable & Delegate", "Sendable & Child.Delegate"),
	])
	func nestingOutermostNamesIfAny_keepsEveryOtherPart_whenItNestsOneNameAfterOthersItKeeps(source: String, expected: String) throws {
		let typeDescription = TypeSyntax(stringLiteral: source).typeDescription

		let nested = try #require(typeDescription.nestingOutermostNamesIfAny { name in
			["Theme", "Delegate"].contains(name) ? .simple(name: "Child") : nil
		})

		#expect(nested.asSource == expected)
	}

	// MARK: - qualifyingInstantiatedType

	@Test(arguments: [
		("Service", "Feature.Service"),
		("Instantiator<Service>?", "Instantiator<Feature.Service>?"),
		("LazilyInstantiated<any Service>", "LazilyInstantiated<any Feature.Service>"),
		("Other", "Other"),
		("Instantiator<Other>", "Instantiator<Other>"),
		("Inner.Service", "Feature.Inner.Service"),
		("any Other", "any Other"),
		("[Other]", nil),
		("Missing", nil),
	] as [(String, String?)])
	func qualifyingInstantiatedType_qualifiesAsItDoesWhenSearchingEveryName_whenGivenOnlyTheNamesOfNestedInstantiableTypes(source: String, expected: String?) {
		let typeDescription = TypeSyntax(stringLiteral: source).typeDescription
		let parentType = TypeDescription.nested(name: "Root", parentType: .simple(name: "Feature"))
		let instantiableTypes: Set<TypeDescription> = [
			.nested(name: "Service", parentType: .simple(name: "Feature")),
			.nested(name: "Service", parentType: .nested(name: "Inner", parentType: .simple(name: "Feature"))),
			.simple(name: "Other"),
		]

		let qualified = typeDescription.qualifyingInstantiatedType(
			within: parentType,
			amongInstantiableTypes: instantiableTypes,
			searchingTypesEnclosingIt: true,
			namesOfNestedInstantiableTypes: ["Service"],
		)

		#expect(qualified?.asSource == expected)
		// Every name the arguments spell, so that every option of each is searched.
		let qualifiedSearchingEveryName = typeDescription.qualifyingInstantiatedType(
			within: parentType,
			amongInstantiableTypes: instantiableTypes,
			searchingTypesEnclosingIt: true,
			namesOfNestedInstantiableTypes: ["Inner", "Missing", "Other", "Service"],
		)
		#expect(qualified?.asSource == qualifiedSearchingEveryName?.asSource)
	}

	// MARK: - replacingInstantiatedType

	@Test
	func replacingInstantiatedType_replacesOnlyBuiltType_whenErasedInstantiatorForwardsTypeOfSameName() {
		let typeDescription = TypeSyntax(stringLiteral: "ErasedInstantiator<Service, Service>").typeDescription

		let replaced = typeDescription.replacingInstantiatedType { _ in
			.nested(name: "Service", parentType: .simple(name: "Feature"))
		}

		#expect(replaced?.asSource == "ErasedInstantiator<Service, Feature.Service>")
	}

	@Test
	func replacingInstantiatedType_replacesTypeThatAsInstantiatedTypeReturns_whenTypeWrapsInstantiatedType() throws {
		for source in [
			"Service",
			"Service?",
			"Service!",
			"any Service",
			"some Service",
			"Instantiator<Service>?",
			"SendableInstantiator<Service>",
			"SendableErasedInstantiator<(), Service>",
			"ErasedInstantiator<(), any Service>",
			"LazilyInstantiated<Service>",
			"LazilyInstantiated<any Service>?",
			"SendableLazilyInstantiated<Service>",
			"SendableLazilyInstantiated<any Service>",
		] {
			let typeDescription = TypeSyntax(stringLiteral: source).typeDescription
			let replacementType = TypeDescription.nested(name: "Service", parentType: .simple(name: "Feature"))

			let replaced = try #require(typeDescription.replacingInstantiatedType { instantiatedType in
				#expect(instantiatedType == typeDescription.asInstantiatedType)
				return replacementType
			})

			#expect(replaced.asInstantiatedType == replacementType)
		}
	}

	@Test
	func replacingInstantiatedType_keepsExistentialSpelling_whenLazilyInstantiatedBuildsExistential() {
		let typeDescription = TypeSyntax(stringLiteral: "LazilyInstantiated<any Service>").typeDescription

		let replaced = typeDescription.replacingInstantiatedType { _ in
			.nested(name: "Service", parentType: .simple(name: "Feature"))
		}

		#expect(replaced?.asSource == "LazilyInstantiated<any Feature.Service>")
	}

	@Test
	func replacingInstantiatedType_returnsNil_whenReplacementKeepsInstantiatedType() {
		let typeDescription = TypeSyntax(stringLiteral: "Instantiator<Service>?").typeDescription

		#expect(typeDescription.replacingInstantiatedType { _ in nil } == nil)
	}

	// MARK: - Equatable and Hashable

	@Test(arguments: [
		"() throws(Failure) -> Void",
		"(Int) async throws(Space.Failure) -> Void",
		"(Int...) -> Void",
		"((any Service)...) -> Void",
		"@convention(c) () -> Void",
		"@convention(c, cType: \"void (*)(void)\") () -> Void",
		"@isolated(any) () -> Void",
		"@Space.Act () -> Void",
		"@Space.Act @Sendable () -> Void",
		"nonisolated(nonsending) () async -> Void",
		"InlineArray<3, Int>",
	])
	func asSource_spellsWhatTheDeclarationSpells_whenTypeIsNotOneOfTheUsualClosures(source: String) {
		let typeDescription = TypeSyntax(stringLiteral: source).typeDescription
		#expect(typeDescription.asSource == source.replacingOccurrences(of: "c, cType: ", with: "c,cType:"))
		#expect(!typeDescription.isUnknown)
		#expect(TypeSyntax(stringLiteral: typeDescription.asSource).typeDescription == typeDescription)
	}

	@Test(arguments: [
		"() throws(any Error) -> Void",
		"() throws(Error) -> Void",
		"() throws(any Swift.Error) -> Void",
		"() throws(Swift.Error) -> Void",
	])
	func equals_returnsTrue_whenClosureNamesAnyErrorAsItsThrownType(spelling: String) {
		let typeDescription = TypeSyntax(stringLiteral: spelling).typeDescription
		let bareThrows = TypeSyntax(stringLiteral: "() throws -> Void").typeDescription
		#expect(typeDescription == bareThrows)
		#expect(Set([typeDescription]).contains(bareThrows))
		#expect(typeDescription.asSource == spelling)
	}

	@Test(arguments: [
		("() throws -> Void", "() throws(Failure) -> Void"),
		("() throws(Other) -> Void", "() throws(Failure) -> Void"),
		("(Int) -> Void", "(Int...) -> Void"),
		("@convention(c) () -> Void", "@convention(thin) () -> Void"),
		("@Space.Act () -> Void", "@Space.Other () -> Void"),
		("() async -> Void", "nonisolated(nonsending) () async -> Void"),
		("InlineArray<3, Int>", "InlineArray<4, Int>"),
	])
	func equals_returnsFalse_whenTypesDifferInWhatOnlyASpecifierAttributeOrEffectSpells(lhs: String, rhs: String) {
		#expect(TypeSyntax(stringLiteral: lhs).typeDescription != TypeSyntax(stringLiteral: rhs).typeDescription)
	}

	@Test
	func exprTypeDescription_readsThrownTypeAndVariadicArgument_whenClosureIsWrittenAsTypeLiteral() {
		let literal: ExprSyntax = "((Int...) throws(Failure) -> Void).self"
		#expect(literal.typeDescription == TypeSyntax(stringLiteral: "(Int...) throws(Failure) -> Void").typeDescription)
	}

	@Test
	func asIdentifier_isOneIdentifier_whenTypeHasAttributeArgumentThrownTypeAndVariadicArgument() {
		#expect(TypeSyntax(stringLiteral: "@convention(c) () -> Void").typeDescription.asIdentifier == "conventionc_Void_to_Void")
		#expect(TypeSyntax(stringLiteral: "@Space.Act () -> Void").typeDescription.asIdentifier == "SpaceAct_Void_to_Void")
		#expect(TypeSyntax(stringLiteral: "(Int...) throws(Failure) -> Void").typeDescription.asIdentifier == "Int_Variadic_throws_Failure_to_Void")
	}

	@Test
	func namesType_findsThrownTypeAndVariadicArgument() {
		func namesConfig(_ source: String) -> Bool {
			TypeSyntax(stringLiteral: source).typeDescription.namesType(where: { $0 == ["Config"] })
		}
		#expect(namesConfig("() throws(Config) -> Void"))
		#expect(namesConfig("(Config...) -> Void"))
		#expect(!namesConfig("() throws(Other) -> Void"))
	}

	@Test
	func nestingOutermostNames_nestsThrownTypeAndVariadicArgument() {
		let nested = TypeSyntax(stringLiteral: "(Config...) throws(Config) -> Void").typeDescription.nestingOutermostNames(in: { $0 == "Config" ? .simple(name: "Child") : nil })
		#expect(nested.asSource == "(Child.Config...) throws(Child.Config) -> Void")
	}

	@Test(arguments: [
		("Optional<Int>", "Int?"),
		("Swift.Optional<Int>", "Int?"),
		("Array<Int>", "[Int]"),
		("Dictionary<String, Int>", "[String: Int]"),
		("Array<Optional<Int>>", "[Int?]"),
		("Swift.Int", "Int"),
		("Swift.Void", "()"),
		("Feature.Config", "Config"),
		("(Feature.Config) -> Swift.Int", "(Config) -> Int"),
		("() throws(Feature.Failure) -> Void", "() throws(Failure) -> Void"),
		("(Array<Int>...) -> Void", "([Int]...) -> Void"),
		("@Sendable @MainActor () -> Void", "@MainActor @Sendable () -> Void"),
		("(first: Optional<Int>, second: Swift.String)", "(first: Int?, second: String)"),
		("(any Feature.Config)?", "(any Config)?"),
		("some Feature.Config", "some Config"),
		("Feature.Config.Type", "Config.Type"),
		("Feature.Config & Swift.Sendable", "Config & Sendable"),
		("Feature.Config!", "Config!"),
		("Feature.Config.Nested<Array<Int>>", "Config.Nested<[Int]>"),
	])
	func withoutSpellingDifferences_returnsSameType_whenSpellingsNameOneType(lhs: String, rhs: String) {
		let moduleNames = ["Swift", "Feature"]
		#expect(TypeSyntax(stringLiteral: lhs).typeDescription.withoutSpellingDifferences(qualifiedByModulesNamed: moduleNames, declaredTypeNames: DeclaredTypeNames())
			== TypeSyntax(stringLiteral: rhs).typeDescription.withoutSpellingDifferences(qualifiedByModulesNamed: moduleNames, declaredTypeNames: DeclaredTypeNames()))
	}

	@Test(arguments: [
		("Other.Config", "Config"),
		("Optional<Int, Int>", "Int?"),
		("Array<Int>", "Int"),
		("(first: Int, second: String)", "(second: String, first: Int)"),
		("@MainActor () -> Void", "() -> Void"),
		("Optional<Int>", "Int"),
	])
	func withoutSpellingDifferences_returnsDifferentTypes_whenSpellingsNameDifferentTypes(lhs: String, rhs: String) {
		let moduleNames = ["Swift", "Feature"]
		#expect(TypeSyntax(stringLiteral: lhs).typeDescription.withoutSpellingDifferences(qualifiedByModulesNamed: moduleNames, declaredTypeNames: DeclaredTypeNames())
			!= TypeSyntax(stringLiteral: rhs).typeDescription.withoutSpellingDifferences(qualifiedByModulesNamed: moduleNames, declaredTypeNames: DeclaredTypeNames()))
	}

	@Test
	func withoutAny_stripsAnyFromThrownTypeAndVariadicArgument() {
		let type = TypeSyntax(stringLiteral: "((any Service)...) throws(any Other) -> Void").typeDescription
		#expect(type.withoutAny.asSource == "(Service...) throws(Other) -> Void")
	}

	@Test
	func equals_returnsTrueAndHashesAlike_whenTypesDifferOnlyInAnyAtAnyDepth() {
		for (anySpelling, plainSpelling) in [
			("any Service", "Service"),
			("(any Service)?", "Service?"),
			("(any Service)!", "Service!"),
			("[any Service]", "[Service]"),
			("[String: any Service]", "[String: Service]"),
			("(any Service, label: any Other)", "(Service, label: Other)"),
			("(any Service) async throws -> any Other", "(Service) async throws -> Other"),
			("@Sendable (any Service) -> Void", "@Sendable (Service) -> Void"),
			("any Service & Other", "Service & Other"),
			("(any Service & Other)?", "(Service & Other)?"),
			("any Service.Type", "Service.Type"),
			("(any Service).Type", "Service.Protocol"),
			("Instantiator<any Service>", "Instantiator<Service>"),
			("Feature<any Service>.Nested<any Other>", "Feature<Service>.Nested<Other>"),
			("(any Service, ~Copyable)", "(Service, ~Copyable)"),
			("((any Service)...) -> Void", "(Service...) -> Void"),
			("() throws(any Service) -> Void", "() throws(Service) -> Void"),
		] {
			let anyType = TypeSyntax(stringLiteral: anySpelling).typeDescription
			let plainType = TypeSyntax(stringLiteral: plainSpelling).typeDescription

			#expect(anyType == plainType, "\(anySpelling) != \(plainSpelling)")
			#expect(Set([anyType]).contains(plainType), "\(anySpelling) does not hash as \(plainSpelling)")
		}
	}

	@Test
	func equals_returnsFalse_whenTypesDifferInMoreThanAny() {
		for (lhsSpelling, rhsSpelling) in [
			("some Service", "Service"),
			("some Service", "any Service"),
			("(any Service).Type", "Service.Type"),
			("any Service.Type", "Service.Protocol"),
			("any Service", "Other"),
			("(any Service)?", "any Service"),
			("(any Service, ~Copyable)", "(Service, ~Escapable)"),
		] {
			let lhs = TypeSyntax(stringLiteral: lhsSpelling).typeDescription
			let rhs = TypeSyntax(stringLiteral: rhsSpelling).typeDescription

			#expect(lhs != rhs, "\(lhsSpelling) == \(rhsSpelling)")
		}
	}

	@Test
	func lessThan_ordersBySpellingWithoutAny_whenTypesAreSpelledWithAny() {
		for (lesserSpelling, greaterSpelling) in [
			("any Proto", "Result"),
			("[any Proto]", "[Result]"),
			("(any Proto)?", "Result?"),
			("(any Proto)!", "Result!"),
			("[String: any Proto]", "[String: Result]"),
			("(any Proto, Int)", "(Result, Int)"),
			("(any Proto) -> Void", "(Result) -> Void"),
			("@Sendable (any Proto) -> Void", "@Sendable (Result) -> Void"),
			("any Proto & Other", "Result & Other"),
			("(any Proto).Type", "Result.Type"),
			("some Box<any Proto>", "some Box<Result>"),
			("Feature<any Proto>.Inner", "Feature<Result>.Inner"),
			("any Proto", "Void"),
			("any Proto", "~Copyable"),
			("Result", "any Service"),
		] {
			let lesser = TypeSyntax(stringLiteral: lesserSpelling).typeDescription
			let greater = TypeSyntax(stringLiteral: greaterSpelling).typeDescription

			#expect(lesser < greater, "\(lesserSpelling) is not less than \(greaterSpelling)")
			#expect(!(greater < lesser), "\(greaterSpelling) is less than \(lesserSpelling)")
		}
	}

	@Test
	func lessThan_ordersBySpelling_whenTypesDifferOnlyInAny() {
		let plainType = TypeSyntax(stringLiteral: "Service").typeDescription
		let anyType = TypeSyntax(stringLiteral: "any Service").typeDescription

		#expect(plainType < anyType)
		#expect(!(anyType < plainType))
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
		     .variadic,
		     .void:
			false
		case .unknown:
			true
		}
	}
}
