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

/// The line-shift oracle: a graph whose every declaration moves down and to the right, in the same order, must give the
/// same verdict, the same diagnostics but for their positions, generated code identical byte for byte in every module,
/// the moved one's own included, and `.safedi` files identical byte for byte. A position-only edit of one module then
/// changes no input of another module's build and recompiles no generated code anywhere.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerLineShift {
	/// The line the shift writes beneath a file's leading comments, which name its module and its file. It spells none
	/// of the words `executeSafeDIToolTest` names a file by.
	static let insertedComment = "// The line-shift oracle moved every line below down and to the right."

	/// `content` with every line after its leading comments moved down and to the right, in the same order: a comment
	/// and a blank line beneath the leading comments, each blank line doubled, so that each declaration moves further
	/// than the one before it, and each other line indented by a tab. The graph's fixtures hold no multi-line string
	/// literal, whose value the shift would change.
	static func shifted(_ content: String) -> String {
		let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
		let leadingCommentCount = lines.prefix { $0.hasPrefix("//") }.count
		var shiftedLines = lines.prefix(leadingCommentCount).map(String.init)
		shiftedLines.append(insertedComment)
		shiftedLines.append("")
		for line in lines.dropFirst(leadingCommentCount) {
			if line.isEmpty {
				shiftedLines.append("")
				shiftedLines.append("")
			} else {
				shiftedLines.append("\t" + line)
			}
		}
		return shiftedLines.joined(separator: "\n")
	}

	/// `text` with the line and column after each Swift file's path, and the end of a fix-it's range after them,
	/// reduced to `<position>`, as are the line and column fields a warning's reflected location spells: a diagnostic about
	/// a moved declaration is reported where it now is.
	static func reducingPositions(in text: String) -> String {
		text
			.replacingOccurrences(of: #"(\.swift):[0-9]+(:[0-9]+)?(-[0-9]+:[0-9]+)?"#, with: "$1:<position>", options: .regularExpression)
			.replacingOccurrences(of: #"\b(line|column|startLine|startColumn|endLine|endColumn): [0-9]+"#, with: "$1: <position>", options: .regularExpression)
	}

	/// A `.safedi` file's bytes as text that compares as the bytes do, one character per byte, with each occurrence of
	/// `fixtureRoot`, the directory a run writes its fixtures under, replaced by `<fixture-root>`: two runs' roots differ
	/// only in a UUID, so every length the file stores agrees. The header's checksum (bytes 22 to 30, `BinaryFile`) is
	/// left out: it covers the body's bytes, the root among them, so it differs between two runs whose bodies are the same
	/// once the root is replaced, and says nothing the body does not.
	static func moduleInfoText(_ data: Data, fixtureRoot: String) -> String {
		var bytes = data
		let checksumRange = (bytes.startIndex + 22)..<(bytes.startIndex + 30)
		if bytes.count >= 30 {
			bytes.replaceSubrange(checksumRange, with: Data(count: checksumRange.count))
		}
		return (String(data: bytes, encoding: .isoLatin1) ?? "").replacingOccurrences(of: fixtureRoot, with: "<fixture-root>")
	}

	/// Each module's `.safedi` text (`moduleInfoText(_:fixtureRoot:)`), by module name, of every module a run of the
	/// module-info integration wrote one for. The harness writes each at `<fixture root>/ModuleInfo/<module>.safedi`.
	static func moduleInfoTexts(of outputs: [String: ModuleTestOutput]) -> [String: String] {
		var texts = [String: String]()
		for (moduleName, output) in outputs {
			guard let path = output.moduleInfoOutputPath, let data = FileManager.default.contents(atPath: path) else { continue }
			let fixtureRoot = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().path
			texts[moduleName] = moduleInfoText(data, fixtureRoot: fixtureRoot)
		}
		return texts
	}

	/// Every aspect in which `shiftedRun`, the run of the graph with its lines shifted, differs from `run`, the run of the
	/// graph as drawn, or `nil` when the two agree.
	static func difference(between run: GraphFuzzerToolRun, and shiftedRun: GraphFuzzerToolRun) -> String? {
		var differences = [String]()
		switch (run.outcome, shiftedRun.outcome) {
		case let (.rejected(diagnostics), .rejected(shiftedDiagnostics)):
			if run.rejectingModuleName != shiftedRun.rejectingModuleName {
				differences.append("the module that rejects it (\(run.rejectingModuleName ?? "its one module") against \(shiftedRun.rejectingModuleName ?? "its one module"))")
			}
			if reducingPositions(in: diagnostics) != reducingPositions(in: shiftedDiagnostics) {
				differences.append("its diagnostics (\(firstDifferingLine(of: reducingPositions(in: diagnostics), and: reducingPositions(in: shiftedDiagnostics))))")
			}
		case let (.accepted(generatedFiles, warnings), .accepted(shiftedGeneratedFiles, shiftedWarnings)):
			differences += codeDifferences(between: generatedFiles, and: shiftedGeneratedFiles)
			if warnings.map(reducingPositions(in:)).sorted() != shiftedWarnings.map(reducingPositions(in:)).sorted() {
				differences.append("its warnings")
			}
		case (.accepted, .rejected), (.rejected, .accepted):
			differences.append("its verdict")
		}
		differences += moduleInfoDifferences(between: run.moduleInfoTexts, and: shiftedRun.moduleInfoTexts)
		return differences.isEmpty ? nil : differences.joined(separator: "; ")
	}

	/// Every aspect in which `shiftedOutcome`, a partitioned graph's run of the module-info integration with its lines
	/// shifted, differs from `outcome`, the run of the graph as drawn, or `nil` when the two agree.
	static func difference(between outcome: GraphFuzzerMultiModuleOutcome, and shiftedOutcome: GraphFuzzerMultiModuleOutcome) -> String? {
		var differences = [String]()
		if outcome.verdicts.map(\.moduleName) != shiftedOutcome.verdicts.map(\.moduleName) {
			differences.append("the modules it generates before a rejection (\(outcome.verdicts.map(\.moduleName)) against \(shiftedOutcome.verdicts.map(\.moduleName)))")
		}
		for (verdict, shiftedVerdict) in zip(outcome.verdicts, shiftedOutcome.verdicts) where verdict.moduleName == shiftedVerdict.moduleName {
			switch (verdict.kind, shiftedVerdict.kind) {
			case (.skipped, .skipped):
				break
			case let (.rejected(diagnostics), .rejected(shiftedDiagnostics)):
				if reducingPositions(in: diagnostics) != reducingPositions(in: shiftedDiagnostics) {
					differences.append("the diagnostics of \(verdict.moduleName) (\(firstDifferingLine(of: reducingPositions(in: diagnostics), and: reducingPositions(in: shiftedDiagnostics))))")
				}
			case let (.accepted(module), .accepted(shiftedModule)):
				differences += codeDifferences(between: module.units, and: shiftedModule.units).map { "\($0) in \(verdict.moduleName)" }
				if module.importsByFileName != shiftedModule.importsByFileName {
					differences.append("the imports of \(verdict.moduleName)")
				}
				if module.warnings.map(reducingPositions(in:)).sorted() != shiftedModule.warnings.map(reducingPositions(in:)).sorted() {
					differences.append("the warnings of \(verdict.moduleName)")
				}
			case (.skipped, _), (.accepted, _), (.rejected, _):
				differences.append("the verdict of \(verdict.moduleName)")
			}
		}
		differences += moduleInfoDifferences(between: outcome.moduleInfoTexts, and: shiftedOutcome.moduleInfoTexts)
		return differences.isEmpty ? nil : differences.joined(separator: "; ")
	}

	/// A difference for the names of the files one side alone generates, and one for each file both generate whose code
	/// differs, naming its first line that differs.
	private static func codeDifferences(between files: [String: String], and shiftedFiles: [String: String]) -> [String] {
		var differences = [String]()
		if Set(files.keys) != Set(shiftedFiles.keys) {
			differences.append("the names of its generated files (\(files.keys.sorted()) against \(shiftedFiles.keys.sorted()))")
		}
		for name in files.keys.sorted() {
			guard let code = files[name], let shiftedCode = shiftedFiles[name], code != shiftedCode else { continue }
			differences.append("the code of `\(name)` (\(firstDifferingLine(of: code, and: shiftedCode)))")
		}
		return differences
	}

	/// A difference for each module whose `.safedi` one side alone wrote, or whose bytes differ.
	private static func moduleInfoDifferences(between texts: [String: String], and shiftedTexts: [String: String]) -> [String] {
		var differences = [String]()
		for moduleName in Set(texts.keys).union(shiftedTexts.keys).sorted() {
			switch (texts[moduleName], shiftedTexts[moduleName]) {
			case let (text?, shiftedText?):
				guard text != shiftedText else { continue }
				// The header's length and checksum follow the body, so the first difference shown is the body's
				// (`BinaryFile`: the body starts at byte 30).
				let bodyOffset = 30
				let offset = bodyOffset + zip(text.unicodeScalars.dropFirst(bodyOffset), shiftedText.unicodeScalars.dropFirst(bodyOffset)).prefix { $0 == $1 }.count
				differences.append("the `.safedi` of \(moduleName) (\(text.unicodeScalars.count) bytes against \(shiftedText.unicodeScalars.count), the body from byte \(offset): `\(excerpt(of: text, at: offset))` against `\(excerpt(of: shiftedText, at: offset))`)")
			case (nil, _?), (_?, nil):
				differences.append("whether \(moduleName) writes a `.safedi`")
			case (nil, nil):
				break
			}
		}
		return differences
	}

	/// The first line of `code` that differs from `shiftedCode`'s, with its number and the shifted run's line.
	private static func firstDifferingLine(of code: String, and shiftedCode: String) -> String {
		let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
		let shiftedLines = shiftedCode.split(separator: "\n", omittingEmptySubsequences: false)
		let index = zip(lines, shiftedLines).prefix { $0 == $1 }.count
		let line = index < lines.count ? String(lines[index]) : "(end of file)"
		let shiftedLine = index < shiftedLines.count ? String(shiftedLines[index]) : "(end of file)"
		return "line \(index + 1): `\(line)` against `\(shiftedLine)`"
	}

	/// Up to 48 bytes of a `.safedi` text from `offset`, each byte outside printable ASCII escaped as `\xNN`.
	private static func excerpt(of text: String, at offset: Int) -> String {
		text.unicodeScalars.dropFirst(offset).prefix(48).map { scalar in
			(0x20..<0x7F).contains(scalar.value) && scalar != "`" ? String(scalar) : String(format: "\\x%02X", scalar.value)
		}.joined()
	}
}

/// One run of the tool over a graph, as `GraphFuzzerOracle.toolRun(of:)` makes it.
struct GraphFuzzerToolRun {
	let outcome: GraphFuzzerToolOutcome
	/// The module whose `generate` rejected a graph split across modules: `nil` where the tool accepts the graph, or where
	/// the graph is in one module, which is then the module that rejects it.
	let rejectingModuleName: String?
	/// Each module's `.safedi` as `GraphFuzzerLineShift.moduleInfoText(_:)` reads it, by module name, for a graph split
	/// across modules run as Bazel runs the tool: every module it wrote one for, a module before a rejection included.
	/// None for a graph in one module, or run as the SwiftPM plugin runs the tool.
	var moduleInfoTexts: [String: String] = [:]
}

extension ModuleFixture {
	/// The fixture with each of its files' content transformed by `transform`, and nothing else changed.
	func withEachFile(transformedBy transform: (String) -> String) -> ModuleFixture {
		ModuleFixture(
			name: name,
			packageName: packageName,
			swiftFileContent: swiftFileContent.map(transform),
			swiftFileContentByFilePath: swiftFileContentByFilePath.mapValues(transform),
			dependencies: dependencies,
			isCheckoutPackage: isCheckoutPackage,
			activeCompilationConditions: activeCompilationConditions,
			buildSettingArguments: buildSettingArguments,
			verificationCompilationConditions: verificationCompilationConditions,
			mockConditionalCompilation: mockConditionalCompilation,
			deletesSwiftFilesAfterRunning: deletesSwiftFilesAfterRunning,
			omitsModuleName: omitsModuleName,
			omitsPackageName: omitsPackageName,
			isReleaseConfiguration: isReleaseConfiguration,
			runsSafeDI: runsSafeDI,
			compilerSettings: compilerSettings,
		)
	}
}
