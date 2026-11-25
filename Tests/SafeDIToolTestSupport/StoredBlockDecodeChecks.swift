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
	/// An observer that hands a stored block whose decoding threw to `enclosingObserver`, the test that expects it, or
	/// records an issue when no test does.
	static func recordingFailures(handingOn enclosingObserver: (@Sendable (StoredBlockDecodeObservation.Block) -> Void)?) -> @Sendable (StoredBlockDecodeObservation.Block) -> Void {
		{ block in
			if let enclosingObserver {
				enclosingObserver(block)
			} else {
				Issue.record("A stored block threw while the run decoded it, so the run computed everything again: \(block)")
			}
		}
	}

	/// Records an issue for each stored block of `file`, as a run wrote it, that does not decode, or that decodes to
	/// values the tool writes as other bytes: real seam signatures and public mock plans, of as many seams and mocks as
	/// the module declares, read back through the layout that wrote them.
	static func expectStoredBlocksReadBackAsWritten(in file: ModuleInfoFile, sourceLocation: SourceLocation) {
		do {
			for encoding in try file.storedBlockEncodings where encoding.held != encoding.ofDecodedValues {
				Issue.record("The stored \(encoding.block) of the module decode to values the tool writes as other bytes: \(encoding.held.count) bytes held, \(encoding.ofDecodedValues.count) written of what they decode to", sourceLocation: sourceLocation)
			}
		} catch {
			Issue.record("A stored block of the module does not decode: \(error)", sourceLocation: sourceLocation)
		}
	}
}
