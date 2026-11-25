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

import SafeDIToolLibrary
import Testing

/// The check that a run decodes every stored block it reads: a run that throws after reading one runs again computing
/// everything, so a seam signature or public mock plan encoding that never decodes would change no generated file and
/// no error, and every run would pay for two.
enum StoredBlockDecodeChecks {
	/// What the runs of the current task generate, which an issue recorded here names so that it can be run again: the
	/// graph fuzzer sets it to a graph's seed, since one test of its runs thousands of graphs.
	@TaskLocal static var runDescription: String?

	/// Records an issue when a run first threw `discardedRunError` with the stored blocks it read
	/// (`Generate.Output.errorOfDiscardedRunThatReadStoredBlocks`) and then computed
	/// everything again without throwing, unless the test expects a block to fail and so observes it
	/// (`StoredBlockDecodeObservation.failureObserver`). Read from the run's output once it returns, never observed
	/// through a task-local value of this harness's own: one more `TaskLocal.withValue` around `generate()` in the
	/// harness made the release build of the tests abort on Linux with Swift 6.2 ("freed pointer was not the last
	/// allocation", in `swift_task_dealloc_specific`).
	static func expectNoDiscardedRun(throwing discardedRunError: (any Error)?, inRunOfModuleNamed moduleName: String?, sourceLocation: SourceLocation) {
		if let error = discardedRunError, StoredBlockDecodeObservation.failureObserver == nil {
			Issue.record("With the stored blocks it read, \(run(ofModuleNamed: moduleName)) threw, and computing everything again did not: \(error)", sourceLocation: sourceLocation)
		}
	}

	/// The run of the module named `moduleName`, with what the current task's runs generate (`runDescription`).
	private static func run(ofModuleNamed moduleName: String?) -> String {
		"the run of \(moduleName.map { "module \($0)" } ?? "a module without a name")\(runDescription.map { " (\($0))" } ?? "")"
	}

	/// Records an issue for each stored block of `file`, as a run wrote it, that does not decode, or that decodes to
	/// values the tool writes as other bytes: real seam signatures and public mock plans, of as many seams and mocks as
	/// the module declares, read back through the layout that wrote them.
	static func expectStoredBlocksReadBackAsWritten(in file: ModuleInfoFile, writtenByRunOfModuleNamed moduleName: String?, sourceLocation: SourceLocation) {
		let run = run(ofModuleNamed: moduleName)
		do {
			for encoding in try file.storedBlockEncodings where encoding.held != encoding.ofDecodedValues {
				Issue.record("The stored \(encoding.block) that \(run) wrote decode to values the tool writes as other bytes: \(encoding.held.count) bytes held, \(encoding.ofDecodedValues.count) written of what they decode to", sourceLocation: sourceLocation)
			}
		} catch {
			Issue.record("A stored block that \(run) wrote does not decode: \(error)", sourceLocation: sourceLocation)
		}
	}
}
