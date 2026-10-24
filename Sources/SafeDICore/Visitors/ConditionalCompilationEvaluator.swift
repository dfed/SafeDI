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

/// How a visitor treats `#if` blocks while scanning for SafeDI declarations.
public enum ConditionalCompilationHandling: Equatable, Sendable {
	/// Scan every clause of every `#if` block without evaluating conditions.
	///
	/// The `@Instantiable` macro runs inside the compiler, which has already selected the
	/// active clause, so the macro sees only active code and need not evaluate anything.
	case scanAllClauses
	/// Scan only the clauses the evaluator determines could be active.
	case evaluate(ConditionalCompilationEvaluator)
}

/// Decides which clauses of an `#if` block SafeDITool scans for declarations.
///
/// Only the compiler can evaluate platform conditions such as `os(iOS)` or `canImport(UIKit)`,
/// so every clause guarded by one is scanned. Bare conditions such as `DEBUG` are evaluated against
/// ``activeCompilationConditions``, which is taken to be complete: a bare condition that is not in
/// the set is inactive. Each such evaluation that decides what SafeDI scans is reported as a
/// ``ConditionalCompilationDecision`` so the generated code can assert it at compile time.
public struct ConditionalCompilationEvaluator: Equatable, Sendable {
	// MARK: Initialization

	/// - Parameters:
	///   - activeCompilationConditions: Every bare condition that is active, matching the compiler's `-D` flags.
	///   - mockConditionalCompilation: The condition the module's generated mock code is wrapped in.
	///     Declarations that only feed mock generation are scanned as if this condition were active,
	///     because the generated code that references them is guarded by the same condition.
	///     Pass `nil` when the module generates mocks without conditional compilation.
	public init(
		activeCompilationConditions: Set<String>,
		mockConditionalCompilation: String? = "DEBUG",
	) {
		self.activeCompilationConditions = activeCompilationConditions
		self.mockConditionalCompilation = mockConditionalCompilation
	}

	// MARK: Public

	public let activeCompilationConditions: Set<String>
	public let mockConditionalCompilation: String?

	// MARK: Internal

	/// The clauses of `node` to scan, given what SafeDI would learn from its declarations.
	func scannableClauses(in node: IfConfigDeclSyntax, guarding content: SafeDIContent) -> ScannableClauses {
		switch content {
		case .none:
			// Nothing SafeDI scans for is inside, so the selection affects nothing SafeDI generates.
			ScannableClauses(
				clauses: activeClauses(in: node, activeCompilationConditions: activeCompilationConditions).clauses,
				decisions: [],
			)
		case .mockOnly:
			if let mockConditionalCompilation {
				mockOnlyScannableClauses(in: node, mockConditionalCompilation: mockConditionalCompilation)
			} else {
				activeClauses(in: node, activeCompilationConditions: activeCompilationConditions)
			}
		case .production:
			activeClauses(in: node, activeCompilationConditions: activeCompilationConditions)
		}
	}

	func evaluate(_ condition: ExprSyntax) -> Evaluation {
		if let booleanLiteral = BooleanLiteralExprSyntax(condition) {
			.known(booleanLiteral.literal.tokenKind == .keyword(.true))
		} else if let identifier = DeclReferenceExprSyntax(condition), !identifier.baseName.text.hasPrefix("$") {
			.known(activeCompilationConditions.contains(identifier.baseName.text))
		} else if let prefixOperator = PrefixOperatorExprSyntax(condition) {
			// `!` is the only prefix operator the compiler accepts in a build configuration.
			evaluate(prefixOperator.expression).negated
		} else if let sequence = SequenceExprSyntax(condition) {
			evaluateSequence(sequence)
		} else if let tuple = TupleExprSyntax(condition), tuple.elements.count == 1, let element = tuple.elements.first {
			evaluate(element.expression)
		} else {
			// `os(…)`, `arch(…)`, `canImport(…)`, `targetEnvironment(…)`, `swift(…)`, `compiler(…)`,
			// feature flags such as `$Macros`, and the like depend on the compiler and destination,
			// which no build integration reports.
			.compilerDetermined
		}
	}

	// MARK: Private

	/// The generated mock code that references mock-only declarations is wrapped in the mock
	/// condition, so the condition is active wherever that code compiles. A decision that rests on
	/// it cannot be asserted outside that code, so only decisions about other conditions are reported.
	private func mockOnlyScannableClauses(in node: IfConfigDeclSyntax, mockConditionalCompilation: String) -> ScannableClauses {
		activeClauses(
			in: node,
			activeCompilationConditions: activeCompilationConditions.union([mockConditionalCompilation]),
			ignoringDecisionsMentioning: mockConditionalCompilation,
		)
	}

	/// - Parameter ignoredCondition: A condition whose evaluation is settled by where the generated
	///   code is compiled, so decisions that mention it are not reported.
	private func activeClauses(
		in node: IfConfigDeclSyntax,
		activeCompilationConditions: Set<String>,
		ignoringDecisionsMentioning ignoredCondition: String? = nil,
	) -> ScannableClauses {
		let evaluator = ConditionalCompilationEvaluator(
			activeCompilationConditions: activeCompilationConditions,
			mockConditionalCompilation: mockConditionalCompilation,
		)
		var selectedClauses = [IfConfigClauseSyntax]()
		var decisions = [ConditionalCompilationDecision]()
		var isSettled = false
		for clause in node.clauses where !isSettled {
			if let condition = clause.condition {
				switch evaluator.evaluate(condition) {
				case let .known(isActive):
					let mentionedConditions = mentionedCompilationConditions(in: condition)
					// A condition without compilation conditions, such as `#if false`, cannot be decided wrongly.
					if !mentionedConditions.isEmpty, !mentionedConditions.contains(ignoredCondition ?? "") {
						decisions.append(ConditionalCompilationDecision(
							condition: condition.trimmedDescription,
							isActive: isActive,
						))
					}
					if isActive {
						selectedClauses.append(clause)
						isSettled = true
					}
				case .compilerDetermined:
					// The compiler may pick this clause or a later one, so scan both.
					selectedClauses.append(clause)
				}
			} else {
				// `#else` is active whenever no earlier clause was.
				selectedClauses.append(clause)
			}
		}
		return ScannableClauses(
			clauses: selectedClauses,
			decisions: decisions,
		)
	}

	/// The bare compilation conditions `condition` refers to, which are the inputs its evaluation rests on.
	private func mentionedCompilationConditions(in condition: ExprSyntax) -> Set<String> {
		if let identifier = DeclReferenceExprSyntax(condition), !identifier.baseName.text.hasPrefix("$") {
			[identifier.baseName.text]
		} else if let prefixOperator = PrefixOperatorExprSyntax(condition) {
			mentionedCompilationConditions(in: prefixOperator.expression)
		} else if let sequence = SequenceExprSyntax(condition) {
			sequence.elements
				.filter { BinaryOperatorExprSyntax($0) == nil }
				.reduce(into: Set<String>()) { $0.formUnion(mentionedCompilationConditions(in: $1)) }
		} else if let tuple = TupleExprSyntax(condition), tuple.elements.count == 1, let element = tuple.elements.first {
			mentionedCompilationConditions(in: element.expression)
		} else {
			// Literals, platform conditions, and feature flags.
			[]
		}
	}

	/// Evaluates an unfolded `a && b || c` sequence. `&&` binds tighter than `||`, so the
	/// sequence is split into disjuncts at each `||` and each disjunct's operands are conjoined.
	private func evaluateSequence(_ sequence: SequenceExprSyntax) -> Evaluation {
		var disjuncts: [[ExprSyntax]] = [[]]
		for element in sequence.elements {
			if let binaryOperator = BinaryOperatorExprSyntax(element) {
				if binaryOperator.operator.text == "||" {
					disjuncts.append([])
				}
			} else {
				disjuncts[disjuncts.count - 1].append(element)
			}
		}
		return disjuncts
			.map { operands in
				operands.map(evaluate).reduce(.known(true)) { $0.and($1) }
			}
			.reduce(.known(false)) { $0.or($1) }
	}
}

/// The result of evaluating one build configuration condition.
enum Evaluation: Equatable {
	case known(Bool)
	/// The result depends on the compiler or destination platform.
	case compilerDetermined

	var negated: Self {
		switch self {
		case let .known(value):
			.known(!value)
		case .compilerDetermined:
			self
		}
	}

	func and(_ other: Self) -> Self {
		switch (self, other) {
		case (.known(false), _), (_, .known(false)):
			.known(false)
		case let (.known(true), other):
			other
		case let (selfEvaluation, .known(true)):
			selfEvaluation
		case (.compilerDetermined, .compilerDetermined):
			.compilerDetermined
		}
	}

	func or(_ other: Self) -> Self {
		switch (self, other) {
		case (.known(true), _), (_, .known(true)):
			.known(true)
		case let (.known(false), other):
			other
		case let (selfEvaluation, .known(false)):
			selfEvaluation
		case (.compilerDetermined, .compilerDetermined):
			.compilerDetermined
		}
	}
}

struct ScannableClauses {
	let clauses: [IfConfigClauseSyntax]
	/// The evaluations of bare conditions that the selection rests on, in source order.
	let decisions: [ConditionalCompilationDecision]
}
