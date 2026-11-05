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

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension InstantiableMacro {
	/// Reports each `@Received(fulfilledByDependencyNamed:ofType:)` declaration among `members` that is fulfilled by
	/// another rename of the same declaration, or by its own label with its own type (or that type made optional, only
	/// if available).
	///
	/// A rename of another rename holds only in an evaluation of the `#if` blocks among `members` that selects both
	/// declarations. The compiler has selected the clauses before the macro runs, but the macro reads every clause, so
	/// it reports a rename only of another rename that is in its clause, in a clause enclosing it, or in a clause it
	/// encloses: every evaluation that selects the inner one selects the outer one. Renames in two clauses of one block
	/// are exclusive, and whether two blocks are both active is for the compiler to decide, so the macro accepts those:
	/// SafeDITool, which evaluates the blocks, reports the rename where its evaluation selects both.
	static func diagnoseRenamesOfRenamesAndOfThemselves(
		among members: MemberBlockItemListSyntax,
		context: some MacroExpansionContext,
	) {
		let dependencies = DeclaredDependency.all(among: members)
		for renamed in dependencies.renames(labeled: nil, inOneEvaluationWith: []) {
			if renamed.rename.sourceLabel == renamed.dependency.label {
				diagnoseRenameOfItself(renamed.dependency, rename: renamed.rename, context: context)
			} else if dependencies.renames(labeled: renamed.rename.sourceLabel, inOneEvaluationWith: [renamed.dependency.clausePath]).contains(where: { $0.index != renamed.index }) {
				diagnoseRenameOfRename(renamed, among: dependencies, context: context)
			}
		}
	}

	/// Reports `dependency`, whose `rename` is fulfilled by its own label, when it also keeps its type – or makes it
	/// optional only if available, without wrapping it. A rename that keeps its label and changes its type is a
	/// retyping, which stays.
	private static func diagnoseRenameOfItself(
		_ dependency: DeclaredDependency,
		rename: DeclaredDependency.Rename,
		context: some MacroExpansionContext,
	) {
		let spelling: FixableInstantiableError.RenameOfItselfSpelling
		if rename.isOnlyIfAvailable,
		   !rename.isErased,
		   dependency.type.isOptional,
		   rename.ofType == dependency.type || rename.ofType == dependency.type.unwrapped
		{
			spelling = .onlyIfAvailableOptional
		} else if rename.ofType == dependency.type {
			spelling = rename.isErased ? .sameTypeWrapped : .sameType
		} else {
			return
		}
		let error = FixableInstantiableError.renameOfItself(label: dependency.label.spelledWithoutBackticks, spelling: spelling)
		switch spelling {
		case .sameType:
			context.diagnose(Diagnostic(
				node: dependency.variable,
				error: error,
				changes: [.replace(oldNode: Syntax(rename.attribute), newNode: Syntax(rename.attribute.receivingWithoutRenaming(onlyIfAvailable: false)))],
			))
		case .onlyIfAvailableOptional:
			context.diagnose(Diagnostic(
				node: dependency.variable,
				error: error,
				changes: [.replace(oldNode: Syntax(rename.attribute), newNode: Syntax(rename.attribute.receivingWithoutRenaming(onlyIfAvailable: true)))],
			))
		case .sameTypeWrapped:
			// Dropping the arguments would drop the wrapper too.
			context.diagnose(Diagnostic(node: dependency.variable, message: error.diagnostic))
		}
	}

	/// Reports `renamed`, one of `dependencies`, which is fulfilled by another rename of the same declaration.
	/// It follows the renames to the property they start from, the label of no rename that holds in one evaluation
	/// with each rename followed, and offers a fix-it that renames that property instead, with the type the last
	/// rename followed reads it as – unless a rename on the way wraps its value, which renaming the start directly
	/// would skip; or receives it only if available while the reported declaration is not optional, which it must be
	/// to receive the start only if available too; or the start is not found. Each rename is followed at most once.
	private static func diagnoseRenameOfRename(
		_ renamed: DeclaredDependency.Renamed,
		among dependencies: [DeclaredDependency],
		context: some MacroExpansionContext,
	) {
		let dependency = renamed.dependency
		let rename = renamed.rename
		var followedIndices: Set = [renamed.index]
		var followedClausePaths = [dependency.clausePath]
		var readType = rename.ofType
		var ofTypeExpression = rename.ofTypeExpression
		var sourceLabel = rename.sourceLabel
		var sourceExpression = rename.sourceExpression
		var wrappingLabel: String?
		var onlyIfAvailableLabel: String?
		var hasUnnamedStart = false
		while true {
			let nextRenames = dependencies.renames(labeled: sourceLabel, inOneEvaluationWith: followedClausePaths)
			guard let nextRenamed = nextRenames.first else { break }
			let next = nextRenamed.dependency
			let nextRename = nextRenamed.rename
			guard nextRenames.count == 1, nextRename.sourceLabel != next.label else {
				// Two renames of the label hold here, or the rename keeps its label: it reads a declaration of its label
				// that the declaration itself hides from every other rename.
				hasUnnamedStart = true
				break
			}
			guard followedIndices.insert(nextRenamed.index).inserted else {
				context.diagnose(Diagnostic(
					node: dependency.variable,
					message: FixableInstantiableError.renameOfRename(
						label: dependency.label.spelledWithoutBackticks,
						sourceLabel: rename.sourceLabel.spelledWithoutBackticks,
						remedy: .renamesFulfillOneAnother,
					).diagnostic,
				))
				return
			}
			if nextRename.isErased, wrappingLabel == nil {
				wrappingLabel = next.label.spelledWithoutBackticks
			}
			if nextRename.isOnlyIfAvailable, onlyIfAvailableLabel == nil {
				onlyIfAvailableLabel = next.label.spelledWithoutBackticks
			}
			if readType == next.type {
				readType = nextRename.ofType
				ofTypeExpression = nextRename.ofTypeExpression
			} else if let instanceType = next.type.instanceTypeOfLazilyInstantiatedWrapper,
			          readType == instanceType,
			          let sourceInstanceType = nextRename.ofType.instanceTypeOfLazilyInstantiatedWrapper
			{
				// The rename reads the instance of a wrapper the next rename renames, so it reads the instance of the
				// wrapper that one is fulfilled by.
				readType = sourceInstanceType
				ofTypeExpression = ExprSyntax("\(raw: sourceInstanceType.asTypeLiteralSource)")
			} else {
				hasUnnamedStart = true
			}
			sourceLabel = nextRename.sourceLabel
			sourceExpression = nextRename.sourceExpression
			followedClausePaths.append(next.clausePath)
		}
		let start = sourceLabel.spelledWithoutBackticks
		let remedy: FixableInstantiableError.RenameOfRenameRemedy = if hasUnnamedStart {
			.renameUnnamedStart
		} else if let wrappingLabel {
			.renameStartAndWrap(start: start, wrappingLabel: wrappingLabel)
		} else if let onlyIfAvailableLabel, !dependency.type.isOptional {
			.renameStartOnlyIfAvailable(start: start, onlyIfAvailableLabel: onlyIfAvailableLabel)
		} else {
			.renameStart(start)
		}
		let error = FixableInstantiableError.renameOfRename(
			label: dependency.label.spelledWithoutBackticks,
			sourceLabel: rename.sourceLabel.spelledWithoutBackticks,
			remedy: remedy,
		)
		switch remedy {
		case .renameStart:
			context.diagnose(Diagnostic(
				node: dependency.variable,
				error: error,
				changes: [.replace(
					oldNode: Syntax(rename.attribute),
					newNode: Syntax(rename.attribute(
						renaming: sourceExpression,
						ofType: ofTypeExpression,
						onlyIfAvailable: onlyIfAvailableLabel != nil,
					)),
				)],
			))
		case .renameStartAndWrap, .renameStartOnlyIfAvailable, .renamesFulfillOneAnother, .renameUnnamedStart:
			context.diagnose(Diagnostic(node: dependency.variable, message: error.diagnostic))
		}
	}
}

/// A dependency a declaration's member declares, as the macro reads it to compare its renames.
private struct DeclaredDependency {
	/// The property's label, in `spelledAsIdentifier` spelling.
	let label: String
	let type: TypeDescription
	let variable: VariableDeclSyntax
	/// The clauses of the `#if` blocks that enclose the declaration, outermost first.
	let clausePath: [SyntaxIdentifier]
	/// What the declaration renames, when it is a `@Received(fulfilledByDependencyNamed:ofType:)` declaration.
	let rename: Rename?

	/// What a `@Received(fulfilledByDependencyNamed:ofType:)` declaration renames.
	struct Rename {
		let attribute: AttributeSyntax
		/// The attribute's arguments, which hold `fulfilledByDependencyNamed:` and `ofType:` first.
		let arguments: LabeledExprListSyntax
		/// The label `fulfilledByDependencyNamed:` names, in `spelledAsIdentifier` spelling.
		let sourceLabel: String
		let sourceExpression: ExprSyntax
		let ofType: TypeDescription
		let ofTypeExpression: ExprSyntax
		let isErased: Bool
		let isOnlyIfAvailable: Bool
	}

	/// A dependency that is a rename, at `index` among the declaration's dependencies.
	struct Renamed {
		let index: Int
		let dependency: DeclaredDependency
		let rename: Rename
	}

	/// The dependencies the members declare, in source order, with those of every clause of each `#if` block among
	/// them, as `InstantiableVisitor` reads them.
	static func all(among members: MemberBlockItemListSyntax) -> [DeclaredDependency] {
		var dependencies = [DeclaredDependency]()
		func collect(among members: MemberBlockItemListSyntax, clausePath: [SyntaxIdentifier]) {
			for member in members {
				if let ifConfigDeclaration = IfConfigDeclSyntax(member.decl) {
					for clause in ifConfigDeclaration.clauses {
						if let clauseMembers = clause.elements?.as(MemberBlockItemListSyntax.self) {
							collect(among: clauseMembers, clausePath: clausePath + [clause.id])
						}
					}
				} else if let variable = VariableDeclSyntax(member.decl),
				          variable.modifiers.staticModifier == nil,
				          let (source, attribute) = variable.attributes.dependencySources.first
				{
					let rename: Rename? = if case let .aliased(fulfillingProperty, isErased, isOnlyIfAvailable) = source,
					                         let sourceExpression = attribute.fulfilledByDependencyNamed,
					                         let ofTypeExpression = attribute.ofType,
					                         let arguments = attribute.arguments.flatMap(LabeledExprListSyntax.init)
					{
						Rename(
							attribute: attribute,
							arguments: arguments,
							sourceLabel: fulfillingProperty.label,
							sourceExpression: sourceExpression,
							ofType: fulfillingProperty.typeDescription,
							ofTypeExpression: ofTypeExpression,
							isErased: isErased,
							isOnlyIfAvailable: isOnlyIfAvailable,
						)
					} else {
						nil
					}
					for binding in variable.bindings {
						if let identifier = IdentifierPatternSyntax(binding.pattern)?.identifier,
						   let type = binding.typeAnnotation?.type
						{
							dependencies.append(DeclaredDependency(
								label: identifier.text.spelledAsIdentifier,
								type: type.typeDescription,
								variable: variable,
								clausePath: clausePath,
								rename: rename,
							))
						}
					}
				}
			}
		}
		collect(among: members, clausePath: [])
		return dependencies
	}
}

extension [DeclaredDependency] {
	/// The renames among these dependencies, in source order, labeled `label` (any label when it is `nil`), that hold in
	/// one evaluation with a declaration in each of `clausePaths`: each path is the rename's own, encloses it, or is
	/// enclosed by it.
	fileprivate func renames(labeled label: String?, inOneEvaluationWith clausePaths: [[SyntaxIdentifier]]) -> [DeclaredDependency.Renamed] {
		enumerated().compactMap { index, dependency in
			if let rename = dependency.rename,
			   label.map({ $0 == dependency.label }) ?? true,
			   clausePaths.allSatisfy({ dependency.clausePath.starts(with: $0) || $0.starts(with: dependency.clausePath) })
			{
				DeclaredDependency.Renamed(index: index, dependency: dependency, rename: rename)
			} else {
				nil
			}
		}
	}
}

extension DeclaredDependency.Rename {
	/// This rename's attribute fulfilled by `sourceExpression` read as `ofTypeExpression`, and, when `onlyIfAvailable`
	/// is set, only if available. Every other argument is kept.
	fileprivate func attribute(
		renaming sourceExpression: ExprSyntax,
		ofType ofTypeExpression: ExprSyntax,
		onlyIfAvailable: Bool,
	) -> AttributeSyntax {
		var arguments = Array(arguments)
		arguments[0].expression = sourceExpression.with(\.leadingTrivia, arguments[0].expression.leadingTrivia).with(\.trailingTrivia, arguments[0].expression.trailingTrivia)
		arguments[1].expression = ofTypeExpression.with(\.leadingTrivia, arguments[1].expression.leadingTrivia).with(\.trailingTrivia, arguments[1].expression.trailingTrivia)
		if onlyIfAvailable {
			if let onlyIfAvailableIndex = arguments.firstIndex(where: { $0.label?.text == "onlyIfAvailable" }) {
				arguments[onlyIfAvailableIndex].expression = ExprSyntax(BooleanLiteralExprSyntax(booleanLiteral: true))
			} else {
				arguments[arguments.count - 1].trailingComma = .commaToken(trailingTrivia: .space)
				arguments.append(LabeledExprSyntax(
					label: .identifier("onlyIfAvailable"),
					colon: .colonToken(trailingTrivia: .space),
					expression: BooleanLiteralExprSyntax(booleanLiteral: true),
				))
			}
		}
		var renamed = attribute
		renamed.arguments = .argumentList(LabeledExprListSyntax(arguments))
		return renamed
	}
}

extension AttributeSyntax {
	/// This `@Received(fulfilledByDependencyNamed:ofType:)` attribute as `@Received`, or as
	/// `@Received(onlyIfAvailable: true)` when `onlyIfAvailable` is set.
	fileprivate func receivingWithoutRenaming(onlyIfAvailable: Bool) -> AttributeSyntax {
		var received = self
		if onlyIfAvailable {
			received.arguments = .argumentList([LabeledExprSyntax(
				label: .identifier("onlyIfAvailable"),
				colon: .colonToken(trailingTrivia: .space),
				expression: BooleanLiteralExprSyntax(booleanLiteral: true),
			)])
		} else {
			received.attributeName = attributeName.with(\.trailingTrivia, rightParen?.trailingTrivia ?? attributeName.trailingTrivia)
			received.leftParen = nil
			received.arguments = nil
			received.rightParen = nil
		}
		return received
	}
}

extension TypeDescription {
	/// The type of the instance a `LazilyInstantiated` or `SendableLazilyInstantiated` creates, when this is one.
	fileprivate var instanceTypeOfLazilyInstantiatedWrapper: TypeDescription? {
		if case let .simple(name, generics) = self,
		   name == Dependency.lazilyInstantiatedType || name == Dependency.sendableLazilyInstantiatedType,
		   generics.count == 1
		{
			generics[0]
		} else {
			nil
		}
	}
}
