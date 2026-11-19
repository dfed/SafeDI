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
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The production type key (R1): places that build one type alike share one builder function, placed in the lowest body
/// every call passes through, which captures a read every call site resolves to one visible declaration, is handed `nil`
/// for a read no call site provides, and takes every other read as a parameter. Each test pins one rule with the whole
/// generated tree, and checks that the expected tree compiles and builds the values the generated one does.
///
/// Written before the type key exists, against the path key's output: each test fails until R1 switches production
/// bodies to the type key, except the review's guards, which pin output the path key already gives and the type key
/// must keep.
struct SafeDIToolTypeKeyTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSharedTypeInOneFunction_whenTypeIsBuiltAtTwoPlacesWithTheSameReads() async throws {
		// `Leaf` is built under `A` and under `B`, and both places read the root's `service`, so one function serves both and captures it.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let service: Service", "@Instantiated let a: A", "@Instantiated let b: B"),
				Self.type("A", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received let service: Service"),
				Self.type("Service"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        func __safeDI_leafBuilder() -> Leaf {
			            Leaf(service: service)
			        }
			        func __safeDI_a() -> A {
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            return A(leafBuilder: leafBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            return B(leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(service: service, a: a, b: b)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReadAsParameter_whenPlacesResolveLabelToDifferentDeclarations() async throws {
		// `A` and `B` each declare their own `cache`, so the shared `Leaf` function takes `cache` as a parameter and each place passes its own.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let a: A", "@Instantiated let b: B"),
				Self.type("A", "@Instantiated let cache: Cache", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated let cache: Cache", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received let cache: Cache"),
				Self.type("Cache"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_leafBuilder(cache: Cache) -> Leaf {
			            Leaf(cache: cache)
			        }
			        func __safeDI_a() -> A {
			            let cache = Cache()
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: cache)
			            }
			            return A(cache: cache, leafBuilder: leafBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let cache = Cache()
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: cache)
			            }
			            return B(cache: cache, leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(a: a, b: b)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOptionalParameter_whenOnePlaceReadsNilAndAnotherAValue() async throws {
		// `Leaf` reads `cache` only if available. `A` declares it and `B` does not, so the parameter is optional and `B` passes `nil`.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let a: A", "@Instantiated let b: B"),
				Self.type("A", "@Instantiated let cache: Cache", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received(onlyIfAvailable: true) let cache: Cache?"),
				Self.type("Cache"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_leafBuilder(cache: Cache?) -> Leaf {
			            Leaf(cache: cache)
			        }
			        func __safeDI_a() -> A {
			            let cache = Cache()
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: cache)
			            }
			            return A(cache: cache, leafBuilder: leafBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: nil)
			            }
			            return B(leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(a: a, b: b)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilInsideSharedFunction_whenEveryPlaceReadsNil() async throws {
		// No place provides `cache`, so the shared function passes `nil` itself and takes no parameter.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let a: A", "@Instantiated let b: B"),
				Self.type("A", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received(onlyIfAvailable: true) let cache: Cache?"),
				Self.type("Cache"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_leafBuilder() -> Leaf {
			            Leaf(cache: nil)
			        }
			        func __safeDI_a() -> A {
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            return A(leafBuilder: leafBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            return B(leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(a: a, b: b)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachLoopMemberInOneFunction_whenInstantiatorLoopReentersType() async throws {
		// `Screen` and `Step` build each other, and the root builds both, so `Step` has two places: one function per member, declared together in the root's body.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let stepBuilder: Instantiator<Step>"),
				Self.type("Screen", "@Instantiated let stepBuilder: Instantiator<Step>"),
				Self.type("Step", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            return Screen(stepBuilder: stepBuilder)
			        }
			        func __safeDI_stepBuilder() -> Step {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Step(screenBuilder: screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			        self.init(screenBuilder: screenBuilder, stepBuilder: stepBuilder)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsLazyInstanceAtFirstRead_whenLazyCycleClosesOnSharedFunction() async throws {
		// `Mid` declares `x` again between `A` and the call that builds `A` again, so `A`'s function takes `x`. Only `D` reads it, when `dBuilder` is instantiated: each call hands the wrapper, and `D`'s function reads `instance`, so instantiating `aBuilder` creates no `X`. The probe counts the `X`s instantiating `aBuilder` creates: none.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("A", "@Instantiated let midBuilder: Instantiator<Mid>", "@Instantiated let dBuilder: Instantiator<D>"),
				Self.type("Mid", "@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("D", "@Received let x: X"),
				Self.stampedX,
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_x() -> X {
			            X()
			        }
			        let x = LazilyInstantiated<X>(__safeDI_x)
			        func __safeDI_aBuilder(x: LazilyInstantiated<X>) -> A {
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            func __safeDI_dBuilder() -> D {
			                D(x: x.instance)
			            }
			            let dBuilder = Instantiator<D>(__safeDI_dBuilder)
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = LazilyInstantiated<X>(__safeDI_x)
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(x: x)
			        }
			        self.init(x: x, aBuilder: aBuilder)
			    }
			}
			""",
			probes: [DifferentialValueProbe("{ let root = Root(); let before = Stamp.next(); _ = root.aBuilder.instantiate(); return Stamp.next() - before - 1 }()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesTwoFunctions_whenTypeIsBuiltInsideAndOutsideSendableBuilder() async throws {
		// `Leaf` is built at the root and inside `Host`'s `@Sendable` builder function: one function per family. `Item`'s builders are `@Sendable` at both places, so they share one.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let leaf: Leaf", "@Instantiated let hostBuilder: SendableInstantiator<Host>"),
				Self.sendableType("Host", "@Instantiated let leaf: Leaf"),
				Self.sendableType("Leaf", "@Instantiated let itemBuilder: SendableInstantiator<Item>"),
				Self.sendableType("Item"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_itemBuilder() -> Item {
			            Item()
			        }
			        func __safeDI_leaf() -> Leaf {
			            let itemBuilder = SendableInstantiator<Item>(__safeDI_itemBuilder)
			            return Leaf(itemBuilder: itemBuilder)
			        }
			        let leaf: Leaf = __safeDI_leaf()
			        @Sendable func __safeDI_hostBuilder() -> Host {
			            func __safeDI_leaf_() -> Leaf {
			                let itemBuilder = SendableInstantiator<Item>(__safeDI_itemBuilder)
			                return Leaf(itemBuilder: itemBuilder)
			            }
			            let leaf: Leaf = __safeDI_leaf_()
			            return Host(leaf: leaf)
			        }
			        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
			        self.init(leaf: leaf, hostBuilder: hostBuilder)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesSendableFamilyFunctionUndecorated_whenItCapturesBuildersNonSendableLocals() async throws {
		// `Leaf` is built twice inside `Host`'s `@Sendable` builder function and reads `Host`'s `cache`, which is not `Sendable`. The shared function is in the `Sendable` family but captures `cache`, so it is not written `@Sendable`; Swift 6 rejects the decorated form, so the compile check is the test.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let hostBuilder: SendableInstantiator<Host>"),
				Self.type("Host", "@Instantiated let cache: Cache", "@Instantiated let a: A", "@Instantiated let b: B"),
				Self.type("A", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received let cache: Cache"),
				Self.type("Cache"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_hostBuilder() -> Host {
			            let cache = Cache()
			            func __safeDI_leafBuilder() -> Leaf {
			                Leaf(cache: cache)
			            }
			            func __safeDI_a() -> A {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return A(leafBuilder: leafBuilder)
			            }
			            let a: A = __safeDI_a()
			            func __safeDI_b() -> B {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return B(leafBuilder: leafBuilder)
			            }
			            let b: B = __safeDI_b()
			            return Host(cache: cache, a: a, b: b)
			        }
			        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
			        self.init(hostBuilder: hostBuilder)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_placesSharedFunctionInLowestCommonBody_whenEveryPlaceIsBeneathOneChild() async throws {
		// `Leaf` has six places beneath `Screen`, whose parents `Screen` declares in an order that is neither their file order nor its reverse, and one near miss under `Other`, which reads the root's lazy `service` and so is another class. The six share one function in `Screen`'s body; the near miss keeps its own.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let service: LazilyInstantiated<Service>", "@Instantiated let screen: Screen", "@Instantiated let other: Other"),
				Self.type("Screen", "@Instantiated let service: Service", "@Instantiated let p3: P3", "@Instantiated let p0: P0", "@Instantiated let p5: P5", "@Instantiated let p1: P1", "@Instantiated let p4: P4", "@Instantiated let p2: P2"),
				Self.type("P0", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("P1", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("P2", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("P3", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("P4", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("P5", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Other", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received let service: Service"),
				Self.type("Service"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_service() -> Service {
			            Service()
			        }
			        let service = LazilyInstantiated<Service>(__safeDI_service)
			        func __safeDI_screen() -> Screen {
			            let service = Service()
			            func __safeDI_leafBuilder() -> Leaf {
			                Leaf(service: service)
			            }
			            func __safeDI_p3() -> P3 {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return P3(leafBuilder: leafBuilder)
			            }
			            let p3: P3 = __safeDI_p3()
			            func __safeDI_p0() -> P0 {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return P0(leafBuilder: leafBuilder)
			            }
			            let p0: P0 = __safeDI_p0()
			            func __safeDI_p5() -> P5 {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return P5(leafBuilder: leafBuilder)
			            }
			            let p5: P5 = __safeDI_p5()
			            func __safeDI_p1() -> P1 {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return P1(leafBuilder: leafBuilder)
			            }
			            let p1: P1 = __safeDI_p1()
			            func __safeDI_p4() -> P4 {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return P4(leafBuilder: leafBuilder)
			            }
			            let p4: P4 = __safeDI_p4()
			            func __safeDI_p2() -> P2 {
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			                return P2(leafBuilder: leafBuilder)
			            }
			            let p2: P2 = __safeDI_p2()
			            return Screen(service: service, p3: p3, p0: p0, p5: p5, p1: p1, p4: p4, p2: p2)
			        }
			        let screen: Screen = __safeDI_screen()
			        func __safeDI_other() -> Other {
			            func __safeDI_leafBuilder_() -> Leaf {
			                Leaf(service: service.instance)
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder_)
			            return Other(leafBuilder: leafBuilder)
			        }
			        let other: Other = __safeDI_other()
			        self.init(service: service, screen: screen, other: other)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesSharedFunctionFromFirstReachedLabel_whenPlacesUseDifferentLabels() async throws {
		// Six places of one key under six labels. The root reaches them in an order that is not the parents' file order, the labels' order or either reversed, so naming the function from any of those fails.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let p3: P3", "@Instantiated let p0: P0", "@Instantiated let p5: P5", "@Instantiated let p1: P1", "@Instantiated let p4: P4", "@Instantiated let p2: P2"),
				Self.type("P0", "@Instantiated let delta: Instantiator<Leaf>"),
				Self.type("P1", "@Instantiated let alpha: Instantiator<Leaf>"),
				Self.type("P2", "@Instantiated let foxtrot: Instantiator<Leaf>"),
				Self.type("P3", "@Instantiated let charlie: Instantiator<Leaf>"),
				Self.type("P4", "@Instantiated let echo: Instantiator<Leaf>"),
				Self.type("P5", "@Instantiated let bravo: Instantiator<Leaf>"),
				Self.type("Leaf", "@Instantiated let itemBuilder: Instantiator<Item>"),
				Self.type("Item"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_charlie() -> Leaf {
			            func __safeDI_itemBuilder() -> Item {
			                Item()
			            }
			            let itemBuilder = Instantiator<Item>(__safeDI_itemBuilder)
			            return Leaf(itemBuilder: itemBuilder)
			        }
			        func __safeDI_p3() -> P3 {
			            let charlie = Instantiator<Leaf>(__safeDI_charlie)
			            return P3(charlie: charlie)
			        }
			        let p3: P3 = __safeDI_p3()
			        func __safeDI_p0() -> P0 {
			            let delta = Instantiator<Leaf>(__safeDI_charlie)
			            return P0(delta: delta)
			        }
			        let p0: P0 = __safeDI_p0()
			        func __safeDI_p5() -> P5 {
			            let bravo = Instantiator<Leaf>(__safeDI_charlie)
			            return P5(bravo: bravo)
			        }
			        let p5: P5 = __safeDI_p5()
			        func __safeDI_p1() -> P1 {
			            let alpha = Instantiator<Leaf>(__safeDI_charlie)
			            return P1(alpha: alpha)
			        }
			        let p1: P1 = __safeDI_p1()
			        func __safeDI_p4() -> P4 {
			            let echo = Instantiator<Leaf>(__safeDI_charlie)
			            return P4(echo: echo)
			        }
			        let p4: P4 = __safeDI_p4()
			        func __safeDI_p2() -> P2 {
			            let foxtrot = Instantiator<Leaf>(__safeDI_charlie)
			            return P2(foxtrot: foxtrot)
			        }
			        let p2: P2 = __safeDI_p2()
			        self.init(p3: p3, p0: p0, p5: p5, p1: p1, p4: p4, p2: p2)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesLazyWrapper_whenSharedFunctionReadsInstanceOfWrapperBoundAtEachPlace() async throws {
		// `A` and `B` each declare their own `service: LazilyInstantiated<Service>` and `Leaf` reads it by value, so the shared function takes the wrapper and reads `instance` inside.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let a: A", "@Instantiated let b: B"),
				Self.type("A", "@Instantiated let service: LazilyInstantiated<Service>", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated let service: LazilyInstantiated<Service>", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received let service: Service"),
				Self.type("Service"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_service() -> Service {
			            Service()
			        }
			        func __safeDI_leafBuilder(service: LazilyInstantiated<Service>) -> Leaf {
			            Leaf(service: service.instance)
			        }
			        func __safeDI_a() -> A {
			            let service = LazilyInstantiated<Service>(__safeDI_service)
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return A(service: service, leafBuilder: leafBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let service = LazilyInstantiated<Service>(__safeDI_service)
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return B(service: service, leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(a: a, b: b)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesParameterOptional_whenOneDeclarationIsOptionalAndAnotherIsNot() async throws {
		// Review 2, B1. `Leaf` reads `x` only if available; `A` forwards `x: X?` and `B` declares `x: X`. The parameter is `X?`, so both calls compile.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let b: B"),
				Self.type("A", "@Forwarded let x: X?", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated let x: X", "@Instantiated let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received(onlyIfAvailable: true) let x: X?"),
				Self.type("X"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_leafBuilder(x: X?) -> Leaf {
			            Leaf(x: x)
			        }
			        func __safeDI_aBuilder(x: X?) -> A {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(x: x)
			            }
			            return A(x: x, leafBuilder: leafBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(x: $0)
			        }
			        func __safeDI_b() -> B {
			            let x = X()
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(x: x)
			            }
			            return B(x: x, leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(aBuilder: aBuilder, b: b)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneParameterPerLabel_whenSharedSubtreeReadsLabelInTwoForms() async throws {
		// Review 2, B3. Beneath the shared `N`, `K1` reads `x` as `Instantiator<X>?` and `K2` as `X?`, both only if available. One parameter carries the label, typed by the form the declarations provide; `K1` gets `nil`, since no declaration provides its form.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let a: A", "@Instantiated let b: B"),
				Self.type("A", "@Instantiated let x: X", "@Instantiated let nBuilder: Instantiator<N>"),
				Self.type("B", "@Instantiated let nBuilder: Instantiator<N>"),
				Self.type("N", "@Instantiated let k1: K1", "@Instantiated let k2: K2"),
				Self.type("K1", "@Received(onlyIfAvailable: true) let x: Instantiator<X>?"),
				Self.type("K2", "@Received(onlyIfAvailable: true) let x: X?"),
				Self.type("X"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_nBuilder(x: X?) -> N {
			            let k1 = K1(x: nil)
			            let k2 = K2(x: x)
			            return N(k1: k1, k2: k2)
			        }
			        func __safeDI_a() -> A {
			            let x = X()
			            let nBuilder = Instantiator<N> {
			                __safeDI_nBuilder(x: x)
			            }
			            return A(x: x, nBuilder: nBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let nBuilder = Instantiator<N> {
			                __safeDI_nBuilder(x: nil)
			            }
			            return B(nBuilder: nBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(a: a, b: b)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesCloserItsOwnNearestDeclaration_whenClosingEdgeResolvesReadOtherwiseThanPlace() async throws {
		// Review 2, A1. `S` builds `E` again beneath `P`, which declares `x` again, so the second lap's `K` must read `P`'s `x`, not the root's. The loop `P` -> `S` -> `E` is placed in the first `E`'s body, where `P`'s `x` is not visible, so `S` and the second `E` take it as a parameter and `P` passes its own.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: X", "@Instantiated let e: E"),
				Self.type("E", "@Instantiated let k: K", "@Instantiated let p: P"),
				Self.type("K", "@Received let x: X"),
				Self.type("P", "@Instantiated let x: X", "@Instantiated let sBuilder: Instantiator<S>"),
				Self.type("S", "@Instantiated let eBuilder: Instantiator<E>"),
				Self.type("X"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        let x = X()
			        func __safeDI_e() -> E {
			            let k = K(x: x)
			            func __safeDI_p() -> P {
			                let x = X()
			                let sBuilder = Instantiator<S> {
			                    __safeDI_sBuilder(x: x)
			                }
			                return P(x: x, sBuilder: sBuilder)
			            }
			            func __safeDI_sBuilder(x: X) -> S {
			                let eBuilder = Instantiator<E> {
			                    __safeDI_eBuilder(x: x)
			                }
			                return S(eBuilder: eBuilder)
			            }
			            func __safeDI_eBuilder(x: X) -> E {
			                let k = K(x: x)
			                let p: P = __safeDI_p()
			                return E(k: k, p: p)
			            }
			            let p: P = __safeDI_p()
			            return E(k: k, p: p)
			        }
			        let e: E = __safeDI_e()
			        self.init(x: x, e: e)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_decidesEveryReadOutcome_whenInstantiatorLoopReadsRootValue() async throws {
		// Review 2, B4. `B` reads the root's `x` inside the loop `A` -> `B` -> `A`. Capturing and passing `x` were both consistent answers when resolution read the type key's own parameters; resolving against the per-path tree, every call site resolves `x` to the root's, so the loop's block captures it.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("B", "@Received let x: X", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("X"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        let x = X()
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(x: x, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(x: x, aBuilder: aBuilder)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsValueSiteAWrapper_whenRootDeclaresValueAndCycleRedeclaresItLazily() async throws {
		// `Root` declares `x` by value and `Mid` declares it again as a `LazilyInstantiated` between `A` and the call that builds `A` again. `A`'s function takes the wrapper: `Root`'s call wraps its own `x` without creating another, and `Mid`'s call hands its wrapper, so instantiating `Mid`'s `aBuilder` creates no `X`. The probe counts the `X`s that call creates: none.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("A", "@Instantiated let midBuilder: Instantiator<Mid>", "@Instantiated let dBuilder: Instantiator<D>"),
				Self.type("Mid", "@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("D", "@Received let x: X"),
				Self.stampedX,
			],
			equals: """
			extension Root {
			    public convenience init() {
			        let x = X()
			        func __safeDI_aBuilder(x: LazilyInstantiated<X>) -> A {
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            func __safeDI_dBuilder() -> D {
			                D(x: x.instance)
			            }
			            let dBuilder = Instantiator<D>(__safeDI_dBuilder)
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            func __safeDI_x() -> X {
			                X()
			            }
			            let x = LazilyInstantiated<X>(__safeDI_x)
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(x: LazilyInstantiated<X> { x })
			        }
			        self.init(x: x, aBuilder: aBuilder)
			    }
			}
			""",
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("{ let root = Root(); let mid = root.aBuilder.instantiate().midBuilder.instantiate(); let before = Stamp.next(); _ = mid.aBuilder.instantiate(); return Stamp.next() - before - 1 }()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsValueSiteAWrapper_whenRootDeclaresWrapperAndCycleRedeclaresItByValue() async throws {
		// The mirror: `Root` declares `x` as a `LazilyInstantiated` and `Mid` declares it again by value. `A`'s function takes the wrapper, `Root`'s call hands its wrapper and `Mid`'s call wraps its own `x`. The probe counts the `X`s instantiating `Root`'s `aBuilder` creates: none.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("A", "@Instantiated let midBuilder: Instantiator<Mid>", "@Instantiated let dBuilder: Instantiator<D>"),
				Self.type("Mid", "@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("D", "@Received let x: X"),
				Self.stampedX,
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_x() -> X {
			            X()
			        }
			        let x = LazilyInstantiated<X>(__safeDI_x)
			        func __safeDI_aBuilder(x: LazilyInstantiated<X>) -> A {
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            func __safeDI_dBuilder() -> D {
			                D(x: x.instance)
			            }
			            let dBuilder = Instantiator<D>(__safeDI_dBuilder)
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: LazilyInstantiated<X> { x })
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(x: x)
			        }
			        self.init(x: x, aBuilder: aBuilder)
			    }
			}
			""",
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("{ let root = Root(); let before = Stamp.next(); _ = root.aBuilder.instantiate(); return Stamp.next() - before - 1 }()")],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesValueParameter_whenEveryCallSiteDeclaresValue() async throws {
		// The near miss: `Root` and `Mid` both declare `x` by value, so `A`'s function takes `x: X` and no call makes a wrapper.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("A", "@Instantiated let midBuilder: Instantiator<Mid>", "@Instantiated let dBuilder: Instantiator<D>"),
				Self.type("Mid", "@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("D", "@Received let x: X"),
				Self.stampedX,
			],
			equals: """
			extension Root {
			    public convenience init() {
			        let x = X()
			        func __safeDI_aBuilder(x: X) -> A {
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            func __safeDI_dBuilder() -> D {
			                D(x: x)
			            }
			            let dBuilder = Instantiator<D>(__safeDI_dBuilder)
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(x: x)
			        }
			        self.init(x: x, aBuilder: aBuilder)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSharedTypeInOneFunction_whenTypeIsBuiltInsideAndOutsideCycle() async throws {
		// `T` is built at `Root` outside a cycle and again inside `N`'s cycle, and both builds start `dep` before `a`, so one function serves both. No production tree starts one type's children in two orders: the re-creation that could (`Scope.swift:447`) runs only for a tree holding a hole's site (`ScopeGenerator.swift:1316`), and every build of a type starts its children in one order (`ScopeGenerator.swift:4661–4669`). The seam form of that pin is R2a's.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let t: T", "@Instantiated let nBuilder: Instantiator<N>"),
				Self.type("T", "@Instantiated let a: A", "@Instantiated let dep: Dep"),
				Self.type("A", "@Instantiated let nBuilder: Instantiator<N>"),
				Self.type("N", "@Received(onlyIfAvailable: true) let dep: Dep?", "@Instantiated let tBuilder: Instantiator<T>"),
				Self.type("Dep"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_t() -> T {
			            let dep = Dep()
			            let a: A = __safeDI_a(dep: dep)
			            return T(a: a, dep: dep)
			        }
			        func __safeDI_a(dep: Dep?) -> A {
			            let nBuilder = Instantiator<N> {
			                __safeDI_nBuilder(dep: dep)
			            }
			            return A(nBuilder: nBuilder)
			        }
			        func __safeDI_nBuilder(dep: Dep?) -> N {
			            let tBuilder = Instantiator<T>(__safeDI_t)
			            return N(dep: dep, tBuilder: tBuilder)
			        }
			        let t: T = __safeDI_t()
			        let nBuilder = Instantiator<N> {
			            __safeDI_nBuilder(dep: nil)
			        }
			        self.init(t: t, nBuilder: nBuilder)
			    }
			}
			""",
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectTypeKeyTree(
		of fixture: [String],
		equals expectedTree: String,
		probes: [DifferentialValueProbe] = [DifferentialValueProbe("Root()")],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": generatedFileHeader + expectedTree], sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: ["Root+SafeDI.swift": generatedFileHeader + expectedTree]),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// `X`, which draws a creation stamp, so that a probe can count the `X`s a call creates.
	private static let stampedX = """
	@Instantiable
	public final class X: Instantiable {
	    public init() {}

	    \(DifferentialValueCreationStamp.property(counterNamed: "Stamp"))
	}

	""" + DifferentialValueCreationStamp.counterDeclaration(named: "Stamp")

	private static func type(_ name: String, isRoot: Bool = false, _ declarations: String...) -> String {
		seamFixtureType(named: name, isRoot: isRoot, isFinalClass: true, declarations: declarations)
	}

	private static func sendableType(_ name: String, _ declarations: String...) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", Sendable")
	}

	/// `files` named as `executeSafeDIToolTest` names them, after the type each declares.
	private static func fixtureFiles(_ files: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for file in files {
			let name = file.split(separator: "\n").compactMap { line -> String? in
				guard let declarationRange = line.range(of: "final class ") ?? line.range(of: "public struct ") else { return nil }
				return String(line[declarationRange.upperBound...].prefix { $0 != ":" })
			}.first ?? "File"
			fixtureFiles["\(name).swift"] = file
		}
		return fixtureFiles
	}
}
