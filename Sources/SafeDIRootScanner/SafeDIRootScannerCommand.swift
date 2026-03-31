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

@main
struct SafeDIRootScannerCommand {
	static func main() throws {
		try run(arguments: Array(CommandLine.arguments.dropFirst()))
	}

	static func run(arguments: [String]) throws {
		let arguments = try Arguments(arguments: arguments)
		let scanner = RootScanner()
		let inputFilePaths = try RootScanner.inputFilePaths(from: arguments.inputSourcesFile)
		let result = try scanner.scan(
			inputFilePaths: inputFilePaths,
			relativeTo: arguments.projectRoot,
			outputDirectory: arguments.outputDirectory,
		)
		try result.writeManifest(to: arguments.manifestFile)
		try result.writeOutputFiles(to: arguments.outputFilesFile)
	}
}

struct Arguments {
	enum ParseError: Error, Equatable, CustomStringConvertible {
		case missingValue(flag: String)
		case unexpectedArgument(String)
		case missingRequiredFlags(Set<String>)

		var description: String {
			switch self {
			case let .missingValue(flag):
				"Missing value for '\(flag)'."
			case let .unexpectedArgument(argument):
				"Unexpected argument '\(argument)'."
			case let .missingRequiredFlags(flags):
				"Missing required arguments: \(flags.sorted().joined(separator: ", "))."
			}
		}
	}

	let inputSourcesFile: URL
	let projectRoot: URL
	let outputDirectory: URL
	let manifestFile: URL
	let outputFilesFile: URL

	init(arguments: [String]) throws {
		var remainingRequiredFlags: Set = [
			"--input-sources-file",
			"--project-root",
			"--output-directory",
			"--manifest-file",
			"--output-files-file",
		]
		var values = [String: String]()
		var iterator = arguments.makeIterator()

		while let argument = iterator.next() {
			guard argument.hasPrefix("--") else {
				throw ParseError.unexpectedArgument(argument)
			}
			guard let value = iterator.next() else {
				throw ParseError.missingValue(flag: argument)
			}
			values[argument] = value
			remainingRequiredFlags.remove(argument)
		}

		guard remainingRequiredFlags.isEmpty else {
			throw ParseError.missingRequiredFlags(remainingRequiredFlags)
		}

		inputSourcesFile = URL(fileURLWithPath: values["--input-sources-file"]!)
		projectRoot = URL(fileURLWithPath: values["--project-root"]!)
		outputDirectory = URL(fileURLWithPath: values["--output-directory"]!)
		manifestFile = URL(fileURLWithPath: values["--manifest-file"]!)
		outputFilesFile = URL(fileURLWithPath: values["--output-files-file"]!)
	}
}
