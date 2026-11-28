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
@testable import SafeDICore

struct ValuePathReleaseTests {
	@Test(arguments: [10_000, 100_000])
	func deinit_releasesEveryMemberWithoutNesting_whenOverridePathOutgrowsHalfMegabyteStack(depth: Int) async {
		// A mock's override of a node reads a member of its parent's, so the layout's path to a node's override is as deep as
		// the mock's tree. Built here directly, since generating a mock that deep is slow in a debug build.
		await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
			let thread = Thread {
				var path = ValuePath.rootDeclaration("safeDIOverrides")
				for index in 0..<depth {
					path = index.isMultiple(of: 2) ? .member("feature\(index)", of: path) : .optionalMember("feature\(index)", of: path)
				}
				// Replacing the path releases all of it on this thread.
				path = .rootDeclaration("safeDIOverrides")
				_ = path
				finished.resume()
			}
			thread.stackSize = 512 * 1_024
			thread.start()
		}
	}
}
