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

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// A wrapper around `SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion` that uses
/// Swift Testing's `Issue.record` instead of `XCTFail` for failure reporting.
func assertMacroExpansion(
	_ originalSource: String,
	expandedSource expectedExpandedSource: String,
	diagnostics: [DiagnosticSpec] = [],
	macros: [String: Macro.Type],
	applyFixIts: [String]? = nil,
	fixedSource expectedFixedSource: String? = nil,
	fileID: StaticString = #fileID,
	filePath: StaticString = #filePath,
	line: UInt = #line,
	column: UInt = #column
) {
	let specs = macros.mapValues { MacroSpec(type: $0) }
	SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
		originalSource,
		expandedSource: expectedExpandedSource,
		diagnostics: diagnostics,
		macroSpecs: specs,
		applyFixIts: applyFixIts,
		fixedSource: expectedFixedSource,
		failureHandler: { spec in
			Issue.record(
				Comment(rawValue: spec.message),
				sourceLocation: SourceLocation(
					fileID: String(describing: spec.location.fileID),
					filePath: String(describing: spec.location.filePath),
					line: Int(spec.location.line),
					column: Int(spec.location.column)
				)
			)
		},
		fileID: fileID,
		filePath: filePath,
		line: line,
		column: column
	)
}
