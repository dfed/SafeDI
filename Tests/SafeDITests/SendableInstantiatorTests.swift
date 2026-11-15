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
import Synchronization
import Testing
@testable import SafeDI

struct SendableInstantiatorTests {
	@Test
	func instantiate_returnsNewObjectEachTime() {
		let systemUnderTest = SendableInstantiator { BuiltProduct() }
		let firstBuiltProduct = systemUnderTest.instantiate()
		let secondBuiltProduct = systemUnderTest.instantiate()
		#expect(firstBuiltProduct !== secondBuiltProduct)
	}

	@Test
	func instantiate_withForwardedArgument_returnsNewObjectEachTime() {
		let systemUnderTest = SendableInstantiator { id in BuiltProductWithForwardedArgument(id: id) }
		let id = UUID().uuidString
		let firstBuiltProduct = systemUnderTest.instantiate(id)
		let secondBuiltProduct = systemUnderTest.instantiate(id)
		#expect(firstBuiltProduct !== secondBuiltProduct)
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func instantiate_keepsForwardedClosure_whenBuilderTypeClosureCreatesInstantiator() {
		let actionCallCount = Mutex(0)
		let builder: SendableInstantiator<BuiltProductWithForwardedAction>.Builder = { action in BuiltProductWithForwardedAction(action: action) }
		let systemUnderTest = SendableInstantiator(builder)
		let builtProduct = systemUnderTest.instantiate { actionCallCount.withLock { $0 += 1 } }
		builtProduct.action()
		#expect(actionCallCount.withLock { $0 } == 1)
	}

	private final class BuiltProduct: Instantiable {
		let id = UUID().uuidString
	}

	private final class BuiltProductWithForwardedAction: Instantiable {
		init(action: @escaping @Sendable () -> Void) {
			self.action = action
		}

		typealias ForwardedProperties = @Sendable () -> Void

		@Forwarded let action: @Sendable () -> Void
	}

	private final class BuiltProductWithForwardedArgument: Instantiable {
		init(id: String) {
			self.id = id
		}

		typealias ForwardedProperties = String

		@Forwarded let id: String
	}
}
