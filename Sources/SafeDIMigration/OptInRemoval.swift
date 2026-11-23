import SwiftParser
import SwiftSyntax

extension Migration {
	/// The 3.0 move (Dan, 2026-11-23): 3.0 deletes the opt-in, so this deletes the `apiVersion:` argument from every
	/// `#SafeDIConfiguration`, leaving `#SafeDIConfiguration()` where it was the only argument, and changes nothing else.
	public static func removeOptIn(sources: [SourceFile]) -> MigrationResult {
		var rewrittenFiles = [SourceFile]()
		var removedCount = 0
		for source in sources.sorted(by: { $0.path < $1.path }) {
			let remover = OptInRemover(viewMode: .sourceAccurate)
			let text = remover.rewrite(Parser.parse(source: source.text)).description
			removedCount += remover.removedCount
			if text != source.text {
				rewrittenFiles.append(SourceFile(path: source.path, text: text))
			}
		}
		return MigrationResult(
			rewrittenFiles: rewrittenFiles,
			editCounts: removedCount == 0 ? [:] : [.optInSettingRemoved: removedCount],
			findings: [],
		)
	}
}

private final class OptInRemover: SyntaxRewriter {
	private(set) var removedCount = 0

	override func visit(_ node: MacroExpansionDeclSyntax) -> DeclSyntax {
		super.visit(removingOptIn(node))
	}

	override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
		super.visit(removingOptIn(node))
	}

	private func removingOptIn<Node: FreestandingMacroExpansionSyntax>(_ node: Node) -> Node {
		guard node.macroName.text == "SafeDIConfiguration" else { return node }
		let kept = node.arguments.filter { $0.label?.text != MigrationOptions.optInArgumentLabel }
		guard kept.count < node.arguments.count else { return node }
		removedCount += node.arguments.count - kept.count
		var rewritten = node
		rewritten.arguments = MigrationRewriter.argumentList(Array(kept), replacing: node.arguments)
		return rewritten
	}
}
