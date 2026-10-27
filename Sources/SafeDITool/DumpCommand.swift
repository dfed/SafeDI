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
import Foundation

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct Dump: ParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Print a `.safedi` module info file or the cache `scan` writes for `generate` as JSON, or explain why SafeDITool cannot read it.",
	)

	@Argument(help: "The path to a `.safedi` file that `generate --module-info-output` wrote, or to the scan cache that `scan` writes beside its manifest, named after the manifest with the extension `safediScanCache`.") var file: String

	func run() throws {
		try print(json())
	}

	/// The file's contents as pretty-printed JSON with sorted keys.
	func json() throws -> String {
		let data = try Data(contentsOf: file.asFileURL)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let json = if BinaryFile.data(data, beginsAs: .moduleInfo) {
			try encoder.encode(ModuleInfo(moduleInfoData: data))
		} else {
			try encoder.encode(CachedScannedModuleInfo(scanCacheData: data))
		}
		return String(decoding: json, as: UTF8.self)
	}
}
