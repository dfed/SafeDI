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

import ChildAModule
import ChildBModule
import ChildCModule
import Foundation
import SafeDI
import SharedModule

@Instantiable(isRoot: true) @MainActor
public final class Root: Instantiable {
	public init(childA: ChildA, childB: ChildB, childC: ChildC, shared: SharedThing, userDefaults: UserDefaults) {
		self.childA = childA
		self.childB = childB
		self.childC = childC
		self.shared = shared
		self.userDefaults = userDefaults
	}

	static let shared = Root()

	@Instantiated let childA: ChildA

	@Instantiated let childB: ChildB

	@Instantiated let childC: ChildC

	@Instantiated let shared: SharedThing

	@Instantiated let userDefaults: UserDefaults
}
