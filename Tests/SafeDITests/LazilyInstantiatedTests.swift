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

import Testing
@testable import SafeDI

struct LazilyInstantiatedTests {
	@Test @MainActor
	func init_doesNotInstantiate() {
		var instantiationCount = 0
		_ = LazilyInstantiated {
			instantiationCount += 1
			return BuiltProduct()
		}
		#expect(instantiationCount == 0)
	}

	@Test @MainActor
	func instance_returnsSameObjectEachTime() {
		let systemUnderTest = LazilyInstantiated { BuiltProduct() }
		let firstBuiltProduct = systemUnderTest.instance
		let secondBuiltProduct = systemUnderTest.instance
		#expect(firstBuiltProduct === secondBuiltProduct)
	}

	@Test @MainActor
	func instance_instantiatesOnce_whenReadMoreThanOnce() {
		var instantiationCount = 0
		let systemUnderTest = LazilyInstantiated {
			instantiationCount += 1
			return BuiltProduct()
		}
		_ = systemUnderTest.instance
		_ = systemUnderTest.instance
		#expect(instantiationCount == 1)
	}

	@Test @MainActor
	func instance_instantiatesNestedLazilyInstantiated_whenInstantiatorReadsAnotherInstance() {
		let dependency = LazilyInstantiated { BuiltProduct() }
		let systemUnderTest = LazilyInstantiated { BuiltProductWithDependency(dependency: dependency.instance) }
		#expect(systemUnderTest.instance.dependency === dependency.instance)
	}

	private final class BuiltProduct {}

	private final class BuiltProductWithDependency {
		init(dependency: BuiltProduct) {
			self.dependency = dependency
		}

		let dependency: BuiltProduct
	}
}
