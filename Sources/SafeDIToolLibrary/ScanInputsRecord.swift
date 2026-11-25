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
import SafeDICore

/// What one run of the `scan` subcommand read, recorded beside its manifest, so that a later run that would read the
/// same leaves the manifest and the scan cache as they are and parses nothing.
///
/// A build tool plugin cannot declare its planning step's inputs: SwiftPM and Xcode run the plugin, and so `scan`, every
/// time they plan a build, even when no file changed. `scan` parses every Swift file of the target and of every target it
/// depends on, so on a build that changes nothing, planning was most of SafeDI's time. A run whose arguments, tool,
/// input files and additional directories are what the record holds would write the same manifest and cache, so it
/// writes nothing.
///
/// What the record holds of each input is the modification times `scan` recorded before reading it, the ones `generate`
/// compares before reusing the scan cache, so the record is as fresh as that cache.
///
/// Memory: the record is read once per run and dropped when the run decides.
struct ScanInputsRecord: Codable {
	/// Everything other than the files' contents that decides what `scan` writes.
	struct Arguments: Codable, Equatable {
		/// The text of the input CSV, which lists every file `scan` parses, in order.
		let inputSourcesFileContent: String
		let projectRoot: String
		/// The project root with its symbolic links resolved, so that a root pointed at another directory scans again.
		let resolvedProjectRoot: String
		let outputDirectory: String
		let mockScopedFiles: [String]
		/// Sorted: `scan` treats the conditions as a set.
		let activeCompilationConditions: [String]
		/// The directory `scan` resolved relative paths against, `additionalDirectoriesToInclude` entries among them.
		let workingDirectory: String
		/// The running tool's path and modification times, so that another build of SafeDITool, whose scan may write
		/// another manifest from the same files, scans again.
		let toolPath: String
		let toolStamp: FileModificationStamp
	}

	let arguments: Arguments
	/// Every file `scan` read, with the times it recorded before reading it (`CachedScannedModuleInfo.scannedInputs`).
	let scannedInputs: [ScannedInput]
	/// Every `additionalDirectoriesToInclude` entry of every configuration in the module's files, as `scan` searched them,
	/// and the Swift files it found in them, as `ProjectFilePaths.projectFilePath(of:)` spells them, sorted: a file added
	/// to one of them can add an output or an input.
	let searchedDirectories: [String]
	let foundFiles: [String]
	/// The times of the manifest and the scan cache once `scan` wrote them, so that a manifest or cache changed or
	/// removed since is written again.
	let manifestStamp: FileModificationStamp
	let scanCacheStamp: FileModificationStamp

	/// Whether every input this record names is unchanged: each file `scan` read, the manifest and the scan cache report
	/// the times recorded, and the searched directories hold the files recorded.
	func inputsAreUnchanged(manifestFile: String, projectFilePaths: ProjectFilePaths) async -> Bool {
		guard FileModificationStamp(ofFileAtPath: manifestFile) == manifestStamp,
		      FileModificationStamp(ofFileAtPath: scannedModuleInfoURL(forManifestPath: manifestFile).path) == scanCacheStamp
		else {
			return false
		}
		let unchanged = await scannedInputs.concurrentlyMapped { scannedInput in
			FileModificationStamp(ofFileAtPath: scannedInput.path) == scannedInput.modificationStamp
		}
		guard !unchanged.contains(false) else {
			return false
		}
		if searchedDirectories.isEmpty {
			return true
		} else {
			let found = await (try? findSwiftFiles(inDirectories: searchedDirectories))?.map { projectFilePaths.projectFilePath(of: $0).path }
			return found?.sorted() == foundFiles
		}
	}

	/// The record `scan` wrote beside `manifestFile` when it holds `arguments`, or `nil`.
	static func read(besideManifestFile manifestFile: String, holding arguments: Arguments) -> ScanInputsRecord? {
		guard let data = try? Data(contentsOf: url(besideManifestFile: manifestFile)),
		      let record = try? JSONDecoder().decode(ScanInputsRecord.self, from: data),
		      record.arguments == arguments
		else {
			return nil
		}
		return record
	}

	/// The record's path: the manifest's name with the extension `safediScanInputs`, beside it.
	static func url(besideManifestFile manifestFile: String) -> URL {
		let manifestURL = manifestFile.asFileURL
		return manifestURL
			.deletingLastPathComponent()
			.appendingPathComponent("\(manifestURL.deletingPathExtension().lastPathComponent).safediScanInputs")
	}

	/// The running tool's path, or `nil` when the system does not say.
	static var toolPath: String? {
		Bundle.main.executablePath
	}
}
