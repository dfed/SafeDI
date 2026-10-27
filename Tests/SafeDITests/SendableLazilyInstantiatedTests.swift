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

import Synchronization
import Testing
@testable import SafeDI

struct SendableLazilyInstantiatedTests {
	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func init_doesNotInstantiate() {
		let instantiationCount = Mutex(0)
		_ = SendableLazilyInstantiated {
			instantiationCount.withLock { $0 += 1 }
			return BuiltProduct()
		}
		#expect(instantiationCount.withLock { $0 } == 0)
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func instance_returnsSameObjectEachTime() {
		let systemUnderTest = SendableLazilyInstantiated { BuiltProduct() }
		let firstBuiltProduct = systemUnderTest.instance
		let secondBuiltProduct = systemUnderTest.instance
		#expect(firstBuiltProduct === secondBuiltProduct)
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func instance_instantiatesOnce_whenFirstReadFromManyTasksAtOnce() async {
		let instantiationCount = Mutex(0)
		let systemUnderTest = SendableLazilyInstantiated {
			instantiationCount.withLock { $0 += 1 }
			return BuiltProduct()
		}
		let builtProducts = await withTaskGroup(of: ObjectIdentifier.self) { taskGroup in
			for _ in 0..<1_000 {
				taskGroup.addTask { ObjectIdentifier(systemUnderTest.instance) }
			}
			var builtProducts = Set<ObjectIdentifier>()
			for await builtProduct in taskGroup {
				builtProducts.insert(builtProduct)
			}
			return builtProducts
		}
		#expect(builtProducts.count == 1)
		#expect(instantiationCount.withLock { $0 } == 1)
	}

	private final class BuiltProduct: Sendable {}
}
