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

import SwiftParser
import SwiftSyntax

/// The `carrier.member` check (rule 3 of the seam contract, as a carrier states it): each closure of a seam's carrier
/// captures only its carrier's carried set, so generated code stores or passes a carrier, never one of its closure members
/// apart from it. A member read and not called – bound with `let`, passed as an argument, or returned – would let what
/// holds it outlive the carrier's own lifetime rules, so every read of a closure member of a value whose type is a
/// carrier must be the callee of a call. A member that is itself a carrier (a level that binds nothing) is a carrier, and
/// may be stored.
///
/// The type of a value is read from the generated text alone: a parameter, or a `let` with a type annotation, whose type
/// spells a carrier, and a `let` bound to a call of a carrier's member that returns a carrier, or to a member that is one.
/// A carrier class is one any file of the graph declares (`final class __safeDI_…Carrier…<__safeDI_Built>`).
enum GraphFuzzerCarrierMembers {
	/// Each read of a closure member of a carrier in `generatedFiles` that is not the callee of a call, as
	/// `` `<file>` line <n>: `<base>.<member>` is read apart from its carrier: <statement> ``, in file name order and then
	/// in source order.
	static func membersReadApart(in generatedFiles: [String: String]) -> [String] {
		let members = carrierMembers(in: generatedFiles)
		guard !members.isEmpty else { return [] }
		var findings = [String]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where contents.contains("Carrier") {
			let tree = Parser.parse(source: contents)
			let visitor = Visitor(fileName: fileName, converter: SourceLocationConverter(fileName: fileName, tree: tree), members: members)
			visitor.walk(tree)
			findings += visitor.findings
		}
		return findings
	}

	/// How many reads of a carrier's closure members the check judges in `generatedFiles`.
	static func judgedReadCount(in generatedFiles: [String: String]) -> Int {
		let members = carrierMembers(in: generatedFiles)
		guard !members.isEmpty else { return 0 }
		var count = 0
		for (fileName, contents) in generatedFiles where contents.contains("Carrier") {
			let tree = Parser.parse(source: contents)
			let visitor = Visitor(fileName: fileName, converter: SourceLocationConverter(fileName: fileName, tree: tree), members: members)
			visitor.walk(tree)
			count += visitor.judgedReadCount
		}
		return count
	}

	/// A member of a carrier class: whether it is a closure, and the carrier it returns or is, if any.
	struct Member: Equatable {
		let isClosure: Bool
		let carrier: String?
	}

	/// The members of each carrier class the files declare, by class name and member label.
	static func carrierMembers(in generatedFiles: [String: String]) -> [String: [String: Member]] {
		var members = [String: [String: Member]]()
		for (_, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where contents.contains("Carrier") {
			let collector = CarrierCollector(viewMode: .sourceAccurate)
			collector.walk(Parser.parse(source: contents))
			members.merge(collector.members) { first, _ in first }
		}
		return members
	}

	/// The first carrier class `type` spells, read as its last dotted component: `__safeDI_ApiCarrier` in
	/// `Inner.__safeDI_ApiCarrier<any Api>`.
	static func firstCarrier(in type: String) -> String? {
		for token in type.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }) {
			if let last = token.split(separator: ".").last.map(String.init), GraphFuzzerScopeDeclarations.isCarrierName(last) {
				return last
			}
		}
		return nil
	}

	private final class CarrierCollector: SyntaxVisitor {
		private(set) var members = [String: [String: Member]]()

		override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
			let name = node.name.text
			guard GraphFuzzerScopeDeclarations.isCarrierName(name) else { return .visitChildren }
			var classMembers = [String: Member]()
			for member in node.memberBlock.members {
				guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
				for binding in variable.bindings {
					guard let type = binding.typeAnnotation?.type else { continue }
					let label = binding.pattern.trimmedDescription.replacingOccurrences(of: "`", with: "")
					if let functionType = type.as(FunctionTypeSyntax.self) ?? type.as(AttributedTypeSyntax.self)?.baseType.as(FunctionTypeSyntax.self) {
						classMembers[label] = Member(isClosure: true, carrier: firstCarrier(in: functionType.returnClause.type.trimmedDescription))
					} else {
						classMembers[label] = Member(isClosure: false, carrier: firstCarrier(in: type.trimmedDescription))
					}
				}
			}
			members[name] = classMembers
			return .skipChildren
		}
	}

	private final class Visitor: SyntaxVisitor {
		init(fileName: String, converter: SourceLocationConverter, members: [String: [String: Member]]) {
			self.fileName = fileName
			self.converter = converter
			self.members = members
			super.init(viewMode: .sourceAccurate)
		}

		private(set) var findings = [String]()
		private(set) var judgedReadCount = 0

		override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
			// A carrier's own declaration stores its members; it reads none.
			GraphFuzzerScopeDeclarations.isCarrierName(node.name.text) ? .skipChildren : .visitChildren
		}

		override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
			if let carrier = firstCarrier(in: node.type.trimmedDescription) {
				carrierByName[(node.secondName ?? node.firstName).text] = carrier
			}
			return .visitChildren
		}

		override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
			carrierByName[node.name.text] = nil
			return .visitChildren
		}

		override func visitPost(_ node: PatternBindingSyntax) {
			guard let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return }
			if let annotation = node.typeAnnotation {
				carrierByName[name] = firstCarrier(in: annotation.type.trimmedDescription)
			} else if let value = node.initializer?.value {
				carrierByName[name] = carrier(of: value)
			}
		}

		override func visitPost(_ node: MemberAccessExprSyntax) {
			guard let base = node.base?.as(DeclReferenceExprSyntax.self),
			      let carrier = carrierByName[base.baseName.text],
			      let member = members[carrier]?[node.declName.baseName.text.replacingOccurrences(of: "`", with: "")],
			      member.isClosure
			else { return }
			judgedReadCount += 1
			if let call = node.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id {
				return
			}
			let statement = node.ancestorOrSelf(mapping: { $0.is(CodeBlockItemSyntax.self) ? $0 : nil }) ?? Syntax(node)
			findings.append("`\(fileName)` line \(converter.location(for: node.positionAfterSkippingLeadingTrivia).line): `\(node.trimmedDescription)` is read apart from its carrier: \(statement.trimmedDescription)")
		}

		/// The carrier `expression` evaluates to: a call of a carrier's member that returns one, or a member that is one.
		private func carrier(of expression: ExprSyntax) -> String? {
			let memberAccess = expression.as(FunctionCallExprSyntax.self)?.calledExpression.as(MemberAccessExprSyntax.self) ?? expression.as(MemberAccessExprSyntax.self)
			guard let memberAccess,
			      let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
			      let baseCarrier = carrierByName[base.baseName.text],
			      let member = members[baseCarrier]?[memberAccess.declName.baseName.text]
			else { return nil }
			return member.isClosure == expression.is(FunctionCallExprSyntax.self) ? member.carrier : nil
		}

		private let fileName: String
		private let converter: SourceLocationConverter
		private let members: [String: [String: Member]]
		/// The carrier each name was last bound to, in source order: generated code names each binding apart.
		private var carrierByName = [String: String]()
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph whose generated code reads a closure member of a carrier apart from its carrier, in one
	/// module or under the module-info integration of a split of it, or `nil`.
	var carrierMemberReadApartFailure: GraphFuzzerFailure? {
		for (description, files) in judgedGeneratedFiles {
			let findings = GraphFuzzerCarrierMembers.membersReadApart(in: files)
			guard !findings.isEmpty else { continue }
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .carrierMemberReadApart,
				details: "\(findings.joined(separator: "\n"))\n\(description):\n\(files.keys.sorted().map { "// \($0)\n\(files[$0, default: ""])" }.joined(separator: "\n"))",
			)
		}
		return nil
	}
}
