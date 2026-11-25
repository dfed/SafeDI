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

/// The default actor isolation the build compiles a module with, as a build system reports it.
///
/// SafeDI never generates from it: a module states its default isolation in `#SafeDIConfiguration`, which reads the
/// same under every build system. Where the build reports one, `generate` warns when the two disagree.
enum BuildDefaultIsolation: Equatable {
	case mainActor
	case nonisolated

	/// The isolation a `-default-isolation` value or a `SWIFT_DEFAULT_ACTOR_ISOLATION` setting names, or `nil` for any
	/// other value, which reports nothing: the compiler accepts only these two.
	init?(_ value: String) {
		switch value {
		case "MainActor":
			self = .mainActor
		case "nonisolated":
			self = .nonisolated
		default:
			return nil
		}
	}

	/// The option that carries the default isolation a build system sets apart from `OTHER_SWIFT_FLAGS`.
	static let optionName = "build-default-isolation"

	/// The default isolation the build reports.
	///
	/// - Parameters:
	///   - option: The value of `--build-default-isolation`: the isolation the build system sets before
	///     `OTHER_SWIFT_FLAGS`, as Bazel reads it from `copts` and Tuist from `SWIFT_DEFAULT_ACTOR_ISOLATION`.
	///   - expandedBuildSettings: The build settings, when they arrived expanded. A `-default-isolation` flag in their
	///     `OTHER_SWIFT_FLAGS` reaches the compiler after the option's setting, so it wins.
	static func reported(
		option: String?,
		expandedBuildSettings: BuildSettingCompilationConditions.Expanded?,
	) -> BuildDefaultIsolation? {
		expandedBuildSettings?.defaultIsolation ?? option.flatMap(BuildDefaultIsolation.init)
	}

	/// A warning when the module's configuration declares another default isolation than this one, the build's. The
	/// generated code follows the configuration either way.
	func mismatchWarning(declaredBy configuration: SafeDIConfiguration?) -> SourceDiagnostic? {
		switch self {
		case .mainActor:
			guard let configuration else {
				return SourceDiagnostic(
					severity: .warning,
					location: nil,
					message: "This module is compiled with `-default-isolation MainActor`, but it declares no `#\(SafeDIConfigurationVisitor.macroName)`, so SafeDI generates code for a nonisolated module. Add `#\(SafeDIConfigurationVisitor.macroName)(defaultIsolation: MainActor.self)` to a file named `\(SafeDIConfiguration.conventionalFileName)` in this module.",
				)
			}
			switch configuration.defaultIsolation {
			case .mainActor:
				return nil
			case nil:
				return SourceDiagnostic(
					severity: .warning,
					location: configuration.declarationLocation,
					message: "This module is compiled with `-default-isolation MainActor`, but `#\(SafeDIConfigurationVisitor.macroName)` doesn’t declare `defaultIsolation: MainActor.self`, so SafeDI generates code for a nonisolated module.",
				)
			}
		case .nonisolated:
			switch configuration?.defaultIsolation {
			case .mainActor:
				return SourceDiagnostic(
					severity: .warning,
					location: configuration?.declarationLocation,
					message: "This module is compiled with `-default-isolation nonisolated`, but `#\(SafeDIConfigurationVisitor.macroName)` declares `defaultIsolation: MainActor.self`, so SafeDI generates code for a main-actor module.",
				)
			case nil:
				return nil
			}
		}
	}
}
