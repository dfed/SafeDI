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

import ArgumentParser

/// The compilation conditions a build system reports by expanding build-setting references in a
/// build tool plugin command's arguments when the command runs.
///
/// Build tool plugins cannot read the conditions the compiler receives: SwiftPM reports only a
/// target's own `swiftSettings` defines, and Xcode reports nothing for a project target. Swift Build,
/// which runs plugin commands for Xcode and for SwiftPM's `swiftbuild` backend, expands
/// `${SWIFT_ACTIVE_COMPILATION_CONDITIONS}` and `${OTHER_SWIFT_FLAGS}` in a command's arguments to
/// the target's settings, and Xcode project builds expand them through the shell script that runs
/// the command. SwiftPM's native backend passes the references through unexpanded.
enum BuildSettingCompilationConditions {
	/// The option that carries `${SWIFT_ACTIVE_COMPILATION_CONDITIONS}`.
	static let activeCompilationConditionsOptionName = "build-setting-active-compilation-conditions"
	/// The option that carries `${OTHER_SWIFT_FLAGS}`.
	static let otherSwiftFlagsOptionName = "build-setting-other-swift-flags"

	/// The conditions the compiler receives, or `nil` when either setting is missing or was not expanded.
	///
	/// Each value arrives wrapped in square brackets so an empty setting still reads as a value.
	///
	/// - Parameters:
	///   - activeCompilationConditions: `[${SWIFT_ACTIVE_COMPILATION_CONDITIONS}]` as received.
	///   - otherSwiftFlags: `[${OTHER_SWIFT_FLAGS}]` as received; its `-D` flags are conditions too.
	static func conditions(
		activeCompilationConditions bracketedActiveCompilationConditions: String?,
		otherSwiftFlags bracketedOtherSwiftFlags: String?,
	) throws -> Set<String>? {
		guard let bracketedActiveCompilationConditions,
		      let bracketedOtherSwiftFlags
		else {
			return nil
		}
		let activeCompilationConditions = try unbracketed(bracketedActiveCompilationConditions, optionName: activeCompilationConditionsOptionName, settingName: "SWIFT_ACTIVE_COMPILATION_CONDITIONS")
		let otherSwiftFlags = try unbracketed(bracketedOtherSwiftFlags, optionName: otherSwiftFlagsOptionName, settingName: "OTHER_SWIFT_FLAGS")
		guard !isUnexpanded(activeCompilationConditions),
		      !isUnexpanded(otherSwiftFlags)
		else {
			return nil
		}
		return Set(arguments(in: activeCompilationConditions)).union(definedConditions(in: arguments(in: otherSwiftFlags)))
	}

	// MARK: Private

	/// Compiler flags whose next argument is passed to another tool, so a `-D` there defines nothing for Swift.
	private static let flagsForwardingNextArgument: Set<String> = ["-Xcc", "-Xclang-linker", "-Xfrontend", "-Xlinker", "-Xllvm"]

	private static func unbracketed(_ value: String, optionName: String, settingName: String) throws -> String {
		guard value.hasPrefix("["), value.hasSuffix("]"), value.count >= 2 else {
			throw ValidationError("--\(optionName) must be wrapped in square brackets, e.g. `--\(optionName)=[${\(settingName)}]`.")
		}
		return String(value.dropFirst().dropLast())
	}

	/// Whether a build-setting reference reached the tool literally. Neither setting can legitimately
	/// contain one once expanded, since expansion replaces every reference.
	private static func isUnexpanded(_ value: String) -> Bool {
		value.contains("${") || value.contains("$(")
	}

	/// The conditions `-D` flags define, as the Swift driver reads them.
	private static func definedConditions(in flags: [String]) -> Set<String> {
		var conditions = Set<String>()
		var index = flags.startIndex
		while index < flags.endIndex {
			let flag = flags[index]
			if flagsForwardingNextArgument.contains(flag) {
				index += 2
			} else if flag == "-D", index + 1 < flags.endIndex {
				conditions.insert(flags[index + 1])
				index += 2
			} else if flag.hasPrefix("-D"), flag.count > 2 {
				conditions.insert(String(flag.dropFirst(2)))
				index += 1
			} else {
				index += 1
			}
		}
		return conditions
	}

	/// Splits a build setting's value into arguments much as the shell does: whitespace separates
	/// arguments, quotes group them, and a backslash escapes the character after it, inside single
	/// quotes too, which no compiler flag needs to tell apart. Xcode keeps the
	/// quotes a project writes in `OTHER_SWIFT_FLAGS`, and Swift Build escapes the spaces inside
	/// each of a package's `unsafeFlags`.
	private static func arguments(in value: String) -> [String] {
		var arguments = [String]()
		var current = ""
		var isInArgument = false
		var quote: Character?
		var isEscaped = false
		for character in value {
			if isEscaped {
				current.append(character)
				isEscaped = false
			} else if character == "\\" {
				isEscaped = true
				isInArgument = true
			} else if let openQuote = quote {
				if character == openQuote {
					quote = nil
				} else {
					current.append(character)
				}
			} else if character == "\"" || character == "'" {
				quote = character
				isInArgument = true
			} else if character.isWhitespace {
				if isInArgument {
					arguments.append(current)
					current = ""
					isInArgument = false
				}
			} else {
				current.append(character)
				isInArgument = true
			}
		}
		if isInArgument {
			arguments.append(current)
		}
		return arguments
	}
}
