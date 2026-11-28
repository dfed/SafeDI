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
@testable import SafeDIToolTestSupport

/// The checked mapping between today's code and the per-type cycle build's (`CycleVariantFunctionMapping`). Today's code
/// in each test is what the type key lays out where two entry orders into one cycle split its functions; the per-type
/// code is what one function per type gives.
struct CycleVariantFunctionMappingTests {
	@Test
	func problems_areNone_whenPerTypeCodeDropsDuplicatesOfTwoEntryOrders() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: Self.todaysCode, perTypeCode: """
		extension Root {
		    public convenience init() {
		        let p = P()
		        let q = Q()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let k = K(q: q)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let m = M(p: p)
		            return B(aBuilder: aBuilder, m: m)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(p: p, q: q, aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}
		""") == [])
	}

	@Test
	func problems_areNone_whenPerTypeFunctionsTakeAsParametersWhatTodaysCapture() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: """
		extension Root {
		    public convenience init() {
		        let x = X()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let k = K(x: x)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        self.init(x: x, aBuilder: aBuilder)
		    }
		}
		""", perTypeCode: """
		extension Root {
		    public convenience init() {
		        let x = X()
		        func __safeDI_aBuilder(x: X) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(x: x)
		            }
		            let k = K(x: x)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder(x: X) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(x: x)
		            }
		            return B(aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(x: x)
		        }
		        self.init(x: x, aBuilder: aBuilder)
		    }
		}
		""") == [])
	}

	@Test
	func problems_nameTheLine_whenACallsArgumentsDifferOutsideTheBodysFunctions() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: """
		extension Root {
		    public convenience init() {
		        let x = X()
		        let k = K(x: x)
		        self.init(k: k)
		    }
		}
		""", perTypeCode: """
		extension Root {
		    public convenience init() {
		        let x = X()
		        let k = K(x: nil)
		        self.init(k: k)
		    }
		}
		""") == ["line 4 differs outside the mapping: today’s, mapped, is `        let k = K(x: x)`, the per-type code’s is `        let k = K(x: nil)`"])
	}

	@Test
	func erasingParameters_keepsAClosureThatTakesAValue_whenItCallsAFunctionOfTheBody() {
		#expect(CycleVariantFunctionMapping.erasingParameters(of: """
		extension Root {
		    public convenience init() {
		        func __safeDI_bBuilder(id: Int) -> B {
		            B(id: id)
		        }
		        let bBuilder = Instantiator<B> { id in
		            __safeDI_bBuilder(id: id)
		        }
		        self.init(bBuilder: bBuilder)
		    }
		}
		""") == """
		extension Root {
		    public convenience init() {
		        func __safeDI_bBuilder() -> B {
		            B(id: id)
		        }
		        let bBuilder = Instantiator<B> { id in
		            __safeDI_bBuilder()
		        }
		        self.init(bBuilder: bBuilder)
		    }
		}
		""")
	}

	@Test
	func problems_areNone_whenCodeIsTheSame() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: Self.todaysCode, perTypeCode: Self.todaysCode) == [])
	}

	@Test
	func problems_nameTheLine_whenAStatementOutsideTheFunctionsDiffers() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: Self.todaysCode, perTypeCode: """
		extension Root {
		    public convenience init() {
		        let p = P()
		        let q = Q()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let k = K(q: q)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let m = M(p: p)
		            return B(aBuilder: aBuilder, m: m)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let bBuilder = Instantiator<B>(__safeDI_aBuilder)
		        self.init(p: p, q: q, aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}
		""") == ["line 16 differs outside the mapping: today’s, mapped, is `        let bBuilder = Instantiator<B>(__safeDI_bBuilder)`, the per-type code’s is `        let bBuilder = Instantiator<B>(__safeDI_aBuilder)`"])
	}

	@Test
	func problems_nameTheFunctions_whenAFunctionOfThePerTypeCodeDiffersFromItsDuplicates() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: Self.todaysCode, perTypeCode: """
		extension Root {
		    public convenience init() {
		        let p = P()
		        let q = Q()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let k = K(q: q)
		            return A(bBuilder: bBuilder, k: k)
		        }
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let m = M(p: P())
		            return B(aBuilder: aBuilder, m: m)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(p: p, q: q, aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}
		""") == [
			"body 0: today’s __safeDI_aBuilder, __safeDI_aBuilder_ has no function of the per-type code",
			"body 0: today’s __safeDI_bBuilder, __safeDI_bBuilder_ has no function of the per-type code",
			"body 0: the per-type code’s __safeDI_aBuilder stands for no function of today’s",
			"body 0: the per-type code’s __safeDI_bBuilder stands for no function of today’s",
		])
	}

	@Test
	func problems_nameTheFunctions_whenDuplicatesCannotPairOneToOne() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: """
		extension Root {
		    public convenience init() {
		        func __safeDI_a() -> A {
		            A()
		        }
		        func __safeDI_a_() -> A {
		            A()
		        }
		        func __safeDI_a__() -> A {
		            A()
		        }
		        self.init(a: __safeDI_a(), b: __safeDI_a_(), c: __safeDI_a__())
		    }
		}
		""", perTypeCode: """
		extension Root {
		    public convenience init() {
		        func __safeDI_a() -> A {
		            A()
		        }
		        func __safeDI_a_() -> A {
		            A()
		        }
		        self.init(a: __safeDI_a(), b: __safeDI_a_(), c: __safeDI_a())
		    }
		}
		""") == ["body 0: today’s __safeDI_a, __safeDI_a_, __safeDI_a__ are alike, as are the per-type code’s __safeDI_a, __safeDI_a_, and no pairing is one to one"])
	}

	@Test
	func problems_countBodies_whenTheFilesHoldDifferentBodies() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: Self.todaysCode, perTypeCode: "") == ["today’s code has 1 bodies, the per-type code 0"])
	}

	@Test
	func problems_countLines_whenThePerTypeCodeEndsLater() {
		#expect(CycleVariantFunctionMapping.problems(todaysCode: Self.todaysCode, perTypeCode: Self.todaysCode + "\n") == ["today’s code, mapped, has 29 lines, the per-type code 30"])
	}

	/// What the type key lays out today for a root that enters the cycle of `A` and `B` from both.
	private static let todaysCode = """
	extension Root {
	    public convenience init() {
	        let p = P()
	        let q = Q()
	        func __safeDI_aBuilder() -> A {
	            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
	            let k = K(q: q)
	            return A(bBuilder: bBuilder, k: k)
	        }
	        func __safeDI_bBuilder() -> B {
	            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
	            let m = M(p: p)
	            return B(aBuilder: aBuilder, m: m)
	        }
	        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
	        func __safeDI_bBuilder_() -> B {
	            let aBuilder = Instantiator<A>(__safeDI_aBuilder_)
	            let m = M(p: p)
	            return B(aBuilder: aBuilder, m: m)
	        }
	        func __safeDI_aBuilder_() -> A {
	            let bBuilder = Instantiator<B>(__safeDI_bBuilder_)
	            let k = K(q: q)
	            return A(bBuilder: bBuilder, k: k)
	        }
	        let bBuilder = Instantiator<B>(__safeDI_bBuilder_)
	        self.init(p: p, q: q, aBuilder: aBuilder, bBuilder: bBuilder)
	    }
	}
	"""
}
