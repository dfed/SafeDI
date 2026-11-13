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

import Testing

/// The isolation a fixture module's declarations default to: none, or the main actor, as `-default-isolation MainActor`
/// (SwiftPM's `defaultIsolation(MainActor.self)`, and a new Xcode 26 app target) sets it.
enum ModuleDefaultIsolation: CaseIterable, CustomTestStringConvertible, Sendable {
	case nonisolated
	case mainActor

	/// The settings the compile verifier compiles the fixture module with, which prepend `import SafeDI` to its files
	/// unless `prependsSafeDIImport` is `false`.
	func compilerSettings(prependsSafeDIImport: Bool = true) -> VerificationCompilerSettings {
		switch self {
		case .nonisolated:
			VerificationCompilerSettings(prependsSafeDIImport: prependsSafeDIImport)
		case .mainActor:
			VerificationCompilerSettings(defaultIsolation: "MainActor", prependsSafeDIImport: prependsSafeDIImport)
		}
	}

	var compilerSettings: VerificationCompilerSettings {
		compilerSettings()
	}

	var testDescription: String {
		switch self {
		case .nonisolated:
			"nonisolated by default"
		case .mainActor:
			"on the main actor by default"
		}
	}
}
