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
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// Acceptance cells of the mock cycle kind: mocks of cycles of instantiators, with an override at every place of the
/// configuration tree, each recording the configuration path it was read from. `Walks.swift` walks each mock's
/// instantiators and lazy wrappers from seeded choices, three and four laps of its cycle deep, and returns each step
/// and the override it read, the place the step entered: the comparator prints those for each walk and compares the
/// mock laid out from node records with the mock's walk (`MockKindsAcceptance`), which reads what 2.4.0 reads on these
/// graphs. The rule: a step to a property already on the path returns to that place with its configuration; any other
/// step enters a new place, configured as the nearest place of its type on the path, else the parent's field, else an
/// empty configuration. The last cells are the value harness's graphs whose overrides differed from 2.4.0 on the mock
/// writer. Written by `cycle_cells.py` beside the value harness, which reads each graph's configuration tree.
struct SafeDIToolMockKindsCycleValueTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests
