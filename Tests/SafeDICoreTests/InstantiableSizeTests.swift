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
import Testing

/// `generate` keeps an `Instantiable` in each `Scope` of every tree and copies it into many values, so its size is
/// paid many times over: shrinking it from 864 to 416 bytes, by boxing the fields few declarations set, lowered
/// `generate`’s peak memory by up to 14%. A field added to `Instantiable` itself rather than to its box fails here.
struct InstantiableSizeTests {
	@Test
	func instantiable_fitsInBoxedSize_whenFieldsFewDeclarationsSetAreBoxed() {
		#expect(
			MemoryLayout<Instantiable>.size <= Self.maximumSize,
			"`Instantiable` takes \(MemoryLayout<Instantiable>.size) bytes, over \(Self.maximumSize): add a field that few declarations set to its box of rarely set fields instead",
		)
	}

	/// The size on 64-bit platforms once the rarely set fields are boxed.
	private static let maximumSize = 416
}
