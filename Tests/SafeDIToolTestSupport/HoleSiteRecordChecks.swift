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

import SafeDICore
import SwiftParser
import SwiftSyntax
import Testing

extension HoleSiteRecordObservation {
	/// An observer that records an issue for each way the site's record disagrees with its text, then hands the site to
	/// `enclosingObserver`.
	static func checkingRecords(handingOn enclosingObserver: TaskLocalFunction<@Sendable (HoleSiteRecordObservation) -> Void>?) -> TaskLocalFunction<@Sendable (HoleSiteRecordObservation) -> Void> {
		TaskLocalFunction { site in
			for mismatch in site.recordMismatches {
				Issue.record(Comment(rawValue: mismatch))
			}
			enclosingObserver?(site)
		}
	}

	/// Each way the record disagrees with the text: a name the text reads that the record lists neither as a read nor as a
	/// binding, a read the text does not make, and a binding the text does not declare. A name the text reads that starts
	/// with a capital letter, or that it calls directly, is a type, which no record lists.
	var recordMismatches: [String] {
		Self.recordMismatches(text: text, readNames: readNames, boundNames: boundNames, place: "a hole’s site")
	}

	/// Each way the record of `place`, written as `text`, disagrees with it, as `recordMismatches` says of a hole's site.
	static func recordMismatches(text: String, readNames: [String]?, boundNames: [String], place: String) -> [String] {
		let syntax = Parser.parse(source: text)
		let visitor = NameVisitor(viewMode: .sourceAccurate)
		visitor.walk(syntax)
		let bound = Set(boundNames.map(Self.withoutBackticks))
		var mismatches = [String]()
		for name in Self.withoutBackticks(visitor.declaredNames).symmetricDifference(bound).sorted() {
			mismatches.append("The record of \(place) lists `\(name)` as bound where its text \(bound.contains(name) ? "does not declare it" : "declares it unlisted"):\n\(text)")
		}
		guard let readNames else { return mismatches }
		let reads = Set(readNames.map(Self.withoutBackticks))
		let referenced = Self.withoutBackticks(visitor.referencedNames)
		for name in reads.subtracting(referenced).sorted() {
			mismatches.append("The record of \(place) lists a read of `\(name)` its text does not make:\n\(text)")
		}
		let typeNames = Self.withoutBackticks(visitor.calledNames)
		// A closure's anonymous parameter (`$0`, a wrapper's forwarded value) is no read.
		for name in referenced.subtracting(reads).subtracting(bound).subtracting(typeNames).sorted() where name.first?.isUppercase == false && name.first != "$" {
			mismatches.append("The text of \(place) reads `\(name)`, which its record does not list:\n\(text)")
		}
		return mismatches
	}

	private static func withoutBackticks(_ name: String) -> String {
		name.filter { $0 != "`" }
	}

	private static func withoutBackticks(_ names: Set<String>) -> Set<String> {
		Set(names.map(withoutBackticks))
	}

	/// The names a site's text declares, refers to as values, and calls directly.
	private final class NameVisitor: SyntaxVisitor {
		var declaredNames = Set<String>()
		var referencedNames = Set<String>()
		var calledNames = Set<String>()

		override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
			declaredNames.insert(node.identifier.text)
			return .visitChildren
		}

		/// An attribute, such as the `@inline(never)` a seam’s tree declares its local functions with, reads no value.
		override func visit(_: AttributeSyntax) -> SyntaxVisitorContinueKind {
			.skipChildren
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			declaredNames.insert(node.name.text)
			return .visitChildren
		}

		override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
			if let memberAccess = node.parent?.as(MemberAccessExprSyntax.self), memberAccess.declName.id == node.id {
				return .visitChildren
			}
			referencedNames.insert(node.baseName.text)
			return .visitChildren
		}

		override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
			var callee = node.calledExpression
			if let specialization = callee.as(GenericSpecializationExprSyntax.self) {
				callee = specialization.expression
			}
			if let reference = callee.as(DeclReferenceExprSyntax.self) {
				calledNames.insert(reference.baseName.text)
			}
			return .visitChildren
		}
	}
}
