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
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(x: x)
			            }
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = LazilyInstantiated<X>(__safeDI_x)
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        func __safeDI_dBuilder(x: LazilyInstantiated<X>) -> D {
			            D(x: x.instance)
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
			        @Sendable nonisolated func __safeDI_itemBuilder() -> Item {
			            Item()
			        }
			        func __safeDI_leaf() -> Leaf {
			            let itemBuilder = SendableInstantiator<Item>(__safeDI_itemBuilder)
			            return Leaf(itemBuilder: itemBuilder)
			        }
			        let leaf: Leaf = __safeDI_leaf()
			        @Sendable nonisolated func __safeDI_leaf_() -> Leaf {
			            let itemBuilder = SendableInstantiator<Item>(__safeDI_itemBuilder)
			            return Leaf(itemBuilder: itemBuilder)
			        }
			        @Sendable nonisolated func __safeDI_hostBuilder() -> Host {
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
	mutating func generate_decoratesSendableFamilyFunction_whenItTakesBuildersNonSendableLocalAsParameter() async throws {
		// `Leaf` is built twice inside `Host`'s `@Sendable` builder function and reads `Host`'s `cache`, which is not `Sendable`. Every builder function is declared in the root's body, so the shared function takes `cache` as a parameter, captures nothing, and is written `@Sendable` with the rest of its family; Swift 6 accepts it, so the compile check is the test.
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
			        @Sendable nonisolated func __safeDI_a(cache: Cache) -> A {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: cache)
			            }
			            return A(leafBuilder: leafBuilder)
			        }
			        @Sendable nonisolated func __safeDI_leafBuilder(cache: Cache) -> Leaf {
			            Leaf(cache: cache)
			        }
			        @Sendable nonisolated func __safeDI_b(cache: Cache) -> B {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: cache)
			            }
			            return B(leafBuilder: leafBuilder)
			        }
			        @Sendable nonisolated func __safeDI_hostBuilder() -> Host {
			            let cache = Cache()
			            let a: A = __safeDI_a(cache: cache)
			            let b: B = __safeDI_b(cache: cache)
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
	mutating func generate_placesSharedFunctionInRootBody_whenEveryPlaceIsBeneathOneChild() async throws {
		// `Leaf` has six places beneath `Screen`, whose parents `Screen` declares in an order that is neither their file order nor its reverse, and one near miss under `Other`, which reads the root's lazy `service` and so is another class. The six share one function in the root's body, which takes `Screen`'s `service` as a parameter; the near miss keeps its own.
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
			        func __safeDI_p3(service: Service) -> P3 {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return P3(leafBuilder: leafBuilder)
			        }
			        func __safeDI_leafBuilder(service: Service) -> Leaf {
			            Leaf(service: service)
			        }
			        func __safeDI_p0(service: Service) -> P0 {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return P0(leafBuilder: leafBuilder)
			        }
			        func __safeDI_p5(service: Service) -> P5 {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return P5(leafBuilder: leafBuilder)
			        }
			        func __safeDI_p1(service: Service) -> P1 {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return P1(leafBuilder: leafBuilder)
			        }
			        func __safeDI_p4(service: Service) -> P4 {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return P4(leafBuilder: leafBuilder)
			        }
			        func __safeDI_p2(service: Service) -> P2 {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(service: service)
			            }
			            return P2(leafBuilder: leafBuilder)
			        }
			        func __safeDI_screen() -> Screen {
			            let service = Service()
			            let p3: P3 = __safeDI_p3(service: service)
			            let p0: P0 = __safeDI_p0(service: service)
			            let p5: P5 = __safeDI_p5(service: service)
			            let p1: P1 = __safeDI_p1(service: service)
			            let p4: P4 = __safeDI_p4(service: service)
			            let p2: P2 = __safeDI_p2(service: service)
			            return Screen(service: service, p3: p3, p0: p0, p5: p5, p1: p1, p4: p4, p2: p2)
			        }
			        let screen: Screen = __safeDI_screen()
			        func __safeDI_leafBuilder_() -> Leaf {
			            Leaf(service: service.instance)
			        }
			        func __safeDI_other() -> Other {
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
			            let itemBuilder = Instantiator<Item>(__safeDI_itemBuilder)
			            return Leaf(itemBuilder: itemBuilder)
			        }
			        func __safeDI_itemBuilder() -> Item {
			            Item()
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
		// Review 2, A1. `S` builds `E` again beneath `P`, which declares `x` again, so the second lap's `K` must read `P`'s `x`, not the root's. The two builds of `E`, the root's constant and `S`'s instantiator, are one class, so `E`'s function takes `x`: the root passes its own, and `S`, beneath `P`, passes `P`'s.
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
			        func __safeDI_e(x: X) -> E {
			            let k = K(x: x)
			            let p: P = __safeDI_p()
			            return E(k: k, p: p)
			        }
			        func __safeDI_p() -> P {
			            let x = X()
			            let sBuilder = Instantiator<S> {
			                __safeDI_sBuilder(x: x)
			            }
			            return P(x: x, sBuilder: sBuilder)
			        }
			        func __safeDI_sBuilder(x: X) -> S {
			            let eBuilder = Instantiator<E> {
			                __safeDI_e(x: x)
			            }
			            return S(eBuilder: eBuilder)
			        }
			        let e: E = __safeDI_e(x: x)
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
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(x: x)
			            }
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = LazilyInstantiated<X>(__safeDI_x)
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        func __safeDI_x() -> X {
			            X()
			        }
			        func __safeDI_dBuilder(x: LazilyInstantiated<X>) -> D {
			            D(x: x.instance)
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
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(x: x)
			            }
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: LazilyInstantiated<X> { x })
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        func __safeDI_dBuilder(x: LazilyInstantiated<X>) -> D {
			            D(x: x.instance)
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
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(x: x)
			            }
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        func __safeDI_dBuilder(x: X) -> D {
			            D(x: x)
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesRequiredParameterByValue_whenCallSiteReadsParameterOfFunctionTypedLater() async throws {
		// `A`'s function is called from `Mid`'s, which declares `service`, and from `B`'s, which passes its own parameter
		// `service`, typed only after `A`'s is first computed. An unknown type is no `nil`, so `A` takes `service: Service`,
		// which `A` requires.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let midBuilder: Instantiator<Mid>"),
				Self.type("Mid", "@Instantiated let service: Service", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("A", "@Received let service: Service", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("B", "@Received let service: Service", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("Service"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder(service: Service) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(service: service)
			            }
			            return A(service: service, bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder(service: Service) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(service: service)
			            }
			            return B(service: service, aBuilder: aBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let service = Service()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(service: service)
			            }
			            return Mid(service: service, aBuilder: aBuilder)
			        }
			        let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			        self.init(midBuilder: midBuilder)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesSettledTree_whenClassesTakeASecondRefinementPass() async throws {
		// Places alike in what they build and how differ in the classes their bodies' calls reach, so the type key's
		// partition settles only on a second refinement pass (seed 2775 of the fuzzer's base corpus).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(t0Builder: Instantiator<T0>, t2Builder: SendableInstantiator<T2>) {
				        self.t0Builder = t0Builder
				        self.t2Builder = t2Builder
				    }

				    @Instantiated let t0Builder: Instantiator<T0>
				    @Instantiated let t2Builder: SendableInstantiator<T2>
				}
				""",
				"""
				@Instantiable
				public final class T0: Instantiable, @unchecked Sendable {
				    public init(t1Builder: Instantiator<T2>, t2Builder: SendableInstantiator<T2>) {
				        self.t1Builder = t1Builder
				        self.t2Builder = t2Builder
				    }

				    @Instantiated let t1Builder: Instantiator<T2>
				    @Received let t2Builder: SendableInstantiator<T2>
				}
				""",
				"""
				@Instantiable
				public final class T1: Instantiable, Sendable {
				    public init(t0: T0?, t2Builder: SendableInstantiator<T2>, anyT1Alias: AnyT1?, t1: T1?) {
				        self.t0 = t0
				        self.t2Builder = t2Builder
				        self.anyT1Alias = anyT1Alias
				        self.t1 = t1
				    }

				    @Forwarded let t0: T0?
				    @Instantiated let t2Builder: SendableInstantiator<T2>
				    @Received(fulfilledByDependencyNamed: "t1", ofType: T1.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let anyT1Alias: AnyT1?
				    @Received(onlyIfAvailable: true) let t1: T1?
				}

				public final class AnyT1: Sendable {
				    public init(_ value: T1) {
				        self.value = value
				    }

				    public let value: T1
				}
				""",
				"""
				@Instantiable
				public final class T2: Instantiable, Sendable {
				    public init(t1: T1, t1Builder: SendableInstantiator<T1>, t0: T1?) {
				        self.t1 = t1
				        self.t1Builder = t1Builder
				        self.t0 = t0
				    }

				    @Forwarded let t1: T1
				    @Instantiated let t1Builder: SendableInstantiator<T1>
				    @Received(onlyIfAvailable: true) let t0: T1?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_t2Builder(t1: T1) -> T2 {
		            let t1Builder = SendableInstantiator<T1> {
		                __safeDI_t1Builder(t0: $0, t1: t1)
		            }
		            return T2(t1: t1, t1Builder: t1Builder, t0: nil)
		        }
		        @Sendable nonisolated func __safeDI_t1Builder(t0: T0?, t1: T1) -> T1 {
		            let t2Builder = SendableInstantiator<T2> {
		                __safeDI_t2Builder(t1: $0)
		            }
		            let anyT1Alias: AnyT1? = AnyT1(t1) // Declared as T1.anyT1Alias
		            return T1(t0: t0, t2Builder: t2Builder, anyT1Alias: anyT1Alias, t1: t1)
		        }
		        let t2Builder = SendableInstantiator<T2> {
		            __safeDI_t2Builder(t1: $0)
		        }
		        func __safeDI_t1Builder_(t1: T1) -> T2 {
		            let t1Builder = SendableInstantiator<T1> {
		                __safeDI_t1Builder__(t0: $0, t1: t1)
		            }
		            return T2(t1: t1, t1Builder: t1Builder, t0: nil)
		        }
		        @Sendable nonisolated func __safeDI_t1Builder__(t0: T0?, t1: T1?) -> T1 {
		            let t2Builder = SendableInstantiator<T2> {
		                __safeDI_t2Builder_(t1: $0)
		            }
		            let anyT1Alias: AnyT1? = (t1 as T1?).map { AnyT1($0) } // Declared as T1.anyT1Alias
		            return T1(t0: t0, t2Builder: t2Builder, anyT1Alias: anyT1Alias, t1: t1)
		        }
		        @Sendable nonisolated func __safeDI_t2Builder_(t1: T1) -> T2 {
		            let t1Builder = SendableInstantiator<T1> {
		                __safeDI_t1Builder__(t0: $0, t1: t1)
		            }
		            return T2(t1: t1, t1Builder: t1Builder, t0: nil)
		        }
		        func __safeDI_t0Builder() -> T0 {
		            let t1Builder = Instantiator<T2> {
		                __safeDI_t1Builder_(t1: $0)
		            }
		            return T0(t1Builder: t1Builder, t2Builder: t2Builder)
		        }
		        let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		        self.init(t0Builder: t0Builder, t2Builder: t2Builder)
		    }
		}
		"""])
	}

	// MARK: Tests of merge order (R1b §2a)

	// Each cell below takes a cell whose places the construction memo keeps apart and the type key merges, and builds it at
	// twenty places, or beneath six parents, that the root declares in an order that is neither their names' order nor its
	// reverse, so that a merge taken in any order but the walk's changes the output.

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesParameterOptional_whenTwentyPlacesDeclareItOptionalOrNot() async throws {
		try await expectTypeKeyTree(of: Self.twentyParents(
			rootDeclaration: { index in index.isMultiple(of: 2) ? "@Instantiated let p\(index)Builder: Instantiator<P\(index)>" : "@Instantiated let p\(index): P\(index)" },
			parentDeclarations: { index in index.isMultiple(of: 2) ? ["@Forwarded let x: X?", "@Instantiated let leafBuilder: Instantiator<Leaf>"] : ["@Instantiated let x: X", "@Instantiated let leafBuilder: Instantiator<Leaf>"] },
		) + [Self.type("Leaf", "@Received(onlyIfAvailable: true) let x: X?"), Self.type("X")], equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_leafBuilder(x: X?) -> Leaf {
		            Leaf(x: x)
		        }
		        func __safeDI_p13() -> P13 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P13(x: x, leafBuilder: leafBuilder)
		        }
		        let p13: P13 = __safeDI_p13()
		        func __safeDI_p4Builder(x: X?) -> P4 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P4(x: x, leafBuilder: leafBuilder)
		        }
		        let p4Builder = Instantiator<P4> {
		            __safeDI_p4Builder(x: $0)
		        }
		        func __safeDI_p17() -> P17 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P17(x: x, leafBuilder: leafBuilder)
		        }
		        let p17: P17 = __safeDI_p17()
		        func __safeDI_p0Builder(x: X?) -> P0 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P0(x: x, leafBuilder: leafBuilder)
		        }
		        let p0Builder = Instantiator<P0> {
		            __safeDI_p0Builder(x: $0)
		        }
		        func __safeDI_p9() -> P9 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P9(x: x, leafBuilder: leafBuilder)
		        }
		        let p9: P9 = __safeDI_p9()
		        func __safeDI_p2Builder(x: X?) -> P2 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P2(x: x, leafBuilder: leafBuilder)
		        }
		        let p2Builder = Instantiator<P2> {
		            __safeDI_p2Builder(x: $0)
		        }
		        func __safeDI_p19() -> P19 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P19(x: x, leafBuilder: leafBuilder)
		        }
		        let p19: P19 = __safeDI_p19()
		        func __safeDI_p6Builder(x: X?) -> P6 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P6(x: x, leafBuilder: leafBuilder)
		        }
		        let p6Builder = Instantiator<P6> {
		            __safeDI_p6Builder(x: $0)
		        }
		        func __safeDI_p11() -> P11 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P11(x: x, leafBuilder: leafBuilder)
		        }
		        let p11: P11 = __safeDI_p11()
		        func __safeDI_p15() -> P15 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P15(x: x, leafBuilder: leafBuilder)
		        }
		        let p15: P15 = __safeDI_p15()
		        func __safeDI_p1() -> P1 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P1(x: x, leafBuilder: leafBuilder)
		        }
		        let p1: P1 = __safeDI_p1()
		        func __safeDI_p8Builder(x: X?) -> P8 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P8(x: x, leafBuilder: leafBuilder)
		        }
		        let p8Builder = Instantiator<P8> {
		            __safeDI_p8Builder(x: $0)
		        }
		        func __safeDI_p18Builder(x: X?) -> P18 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P18(x: x, leafBuilder: leafBuilder)
		        }
		        let p18Builder = Instantiator<P18> {
		            __safeDI_p18Builder(x: $0)
		        }
		        func __safeDI_p3() -> P3 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P3(x: x, leafBuilder: leafBuilder)
		        }
		        let p3: P3 = __safeDI_p3()
		        func __safeDI_p12Builder(x: X?) -> P12 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P12(x: x, leafBuilder: leafBuilder)
		        }
		        let p12Builder = Instantiator<P12> {
		            __safeDI_p12Builder(x: $0)
		        }
		        func __safeDI_p7() -> P7 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P7(x: x, leafBuilder: leafBuilder)
		        }
		        let p7: P7 = __safeDI_p7()
		        func __safeDI_p16Builder(x: X?) -> P16 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P16(x: x, leafBuilder: leafBuilder)
		        }
		        let p16Builder = Instantiator<P16> {
		            __safeDI_p16Builder(x: $0)
		        }
		        func __safeDI_p5() -> P5 {
		            let x = X()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P5(x: x, leafBuilder: leafBuilder)
		        }
		        let p5: P5 = __safeDI_p5()
		        func __safeDI_p10Builder(x: X?) -> P10 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P10(x: x, leafBuilder: leafBuilder)
		        }
		        let p10Builder = Instantiator<P10> {
		            __safeDI_p10Builder(x: $0)
		        }
		        func __safeDI_p14Builder(x: X?) -> P14 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(x: x)
		            }
		            return P14(x: x, leafBuilder: leafBuilder)
		        }
		        let p14Builder = Instantiator<P14> {
		            __safeDI_p14Builder(x: $0)
		        }
		        self.init(p13: p13, p4Builder: p4Builder, p17: p17, p0Builder: p0Builder, p9: p9, p2Builder: p2Builder, p19: p19, p6Builder: p6Builder, p11: p11, p15: p15, p1: p1, p8Builder: p8Builder, p18Builder: p18Builder, p3: p3, p12Builder: p12Builder, p7: p7, p16Builder: p16Builder, p5: p5, p10Builder: p10Builder, p14Builder: p14Builder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneParameterPerLabel_whenTwentyPlacesOfSharedSubtreeReadLabelInTwoForms() async throws {
		try await expectTypeKeyTree(of: Self.twentyParents(
			rootDeclaration: { index in "@Instantiated let p\(index): P\(index)" },
			parentDeclarations: { index in index.isMultiple(of: 3) ? ["@Instantiated let x: X", "@Instantiated let nBuilder: Instantiator<N>"] : ["@Instantiated let nBuilder: Instantiator<N>"] },
		) + [
			Self.type("N", "@Instantiated let k1: K1", "@Instantiated let k2: K2"),
			Self.type("K1", "@Received(onlyIfAvailable: true) let x: Instantiator<X>?"),
			Self.type("K2", "@Received(onlyIfAvailable: true) let x: X?"),
			Self.type("X"),
		], equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_nBuilder(x: X?) -> N {
		            let k1 = K1(x: nil)
		            let k2 = K2(x: x)
		            return N(k1: k1, k2: k2)
		        }
		        func __safeDI_p13() -> P13 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P13(nBuilder: nBuilder)
		        }
		        let p13: P13 = __safeDI_p13()
		        func __safeDI_p4() -> P4 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P4(nBuilder: nBuilder)
		        }
		        let p4: P4 = __safeDI_p4()
		        func __safeDI_p17() -> P17 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P17(nBuilder: nBuilder)
		        }
		        let p17: P17 = __safeDI_p17()
		        func __safeDI_p0() -> P0 {
		            let x = X()
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: x)
		            }
		            return P0(x: x, nBuilder: nBuilder)
		        }
		        let p0: P0 = __safeDI_p0()
		        func __safeDI_p9() -> P9 {
		            let x = X()
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: x)
		            }
		            return P9(x: x, nBuilder: nBuilder)
		        }
		        let p9: P9 = __safeDI_p9()
		        func __safeDI_p2() -> P2 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P2(nBuilder: nBuilder)
		        }
		        let p2: P2 = __safeDI_p2()
		        func __safeDI_p19() -> P19 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P19(nBuilder: nBuilder)
		        }
		        let p19: P19 = __safeDI_p19()
		        func __safeDI_p6() -> P6 {
		            let x = X()
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: x)
		            }
		            return P6(x: x, nBuilder: nBuilder)
		        }
		        let p6: P6 = __safeDI_p6()
		        func __safeDI_p11() -> P11 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P11(nBuilder: nBuilder)
		        }
		        let p11: P11 = __safeDI_p11()
		        func __safeDI_p15() -> P15 {
		            let x = X()
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: x)
		            }
		            return P15(x: x, nBuilder: nBuilder)
		        }
		        let p15: P15 = __safeDI_p15()
		        func __safeDI_p1() -> P1 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P1(nBuilder: nBuilder)
		        }
		        let p1: P1 = __safeDI_p1()
		        func __safeDI_p8() -> P8 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P8(nBuilder: nBuilder)
		        }
		        let p8: P8 = __safeDI_p8()
		        func __safeDI_p18() -> P18 {
		            let x = X()
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: x)
		            }
		            return P18(x: x, nBuilder: nBuilder)
		        }
		        let p18: P18 = __safeDI_p18()
		        func __safeDI_p3() -> P3 {
		            let x = X()
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: x)
		            }
		            return P3(x: x, nBuilder: nBuilder)
		        }
		        let p3: P3 = __safeDI_p3()
		        func __safeDI_p12() -> P12 {
		            let x = X()
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: x)
		            }
		            return P12(x: x, nBuilder: nBuilder)
		        }
		        let p12: P12 = __safeDI_p12()
		        func __safeDI_p7() -> P7 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P7(nBuilder: nBuilder)
		        }
		        let p7: P7 = __safeDI_p7()
		        func __safeDI_p16() -> P16 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P16(nBuilder: nBuilder)
		        }
		        let p16: P16 = __safeDI_p16()
		        func __safeDI_p5() -> P5 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P5(nBuilder: nBuilder)
		        }
		        let p5: P5 = __safeDI_p5()
		        func __safeDI_p10() -> P10 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P10(nBuilder: nBuilder)
		        }
		        let p10: P10 = __safeDI_p10()
		        func __safeDI_p14() -> P14 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(x: nil)
		            }
		            return P14(nBuilder: nBuilder)
		        }
		        let p14: P14 = __safeDI_p14()
		        self.init(p13: p13, p4: p4, p17: p17, p0: p0, p9: p9, p2: p2, p19: p19, p6: p6, p11: p11, p15: p15, p1: p1, p8: p8, p18: p18, p3: p3, p12: p12, p7: p7, p16: p16, p5: p5, p10: p10, p14: p14)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOptionalParameter_whenTwentyPlacesReadNilOrAValue() async throws {
		try await expectTypeKeyTree(of: Self.twentyParents(
			rootDeclaration: { index in "@Instantiated let p\(index): P\(index)" },
			parentDeclarations: { index in index % 3 == 1 ? ["@Instantiated let leafBuilder: Instantiator<Leaf>"] : ["@Instantiated let cache: Cache", "@Instantiated let leafBuilder: Instantiator<Leaf>"] },
		) + [Self.type("Leaf", "@Received(onlyIfAvailable: true) let cache: Cache?"), Self.type("Cache")], equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_leafBuilder(cache: Cache?) -> Leaf {
		            Leaf(cache: cache)
		        }
		        func __safeDI_p13() -> P13 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: nil)
		            }
		            return P13(leafBuilder: leafBuilder)
		        }
		        let p13: P13 = __safeDI_p13()
		        func __safeDI_p4() -> P4 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: nil)
		            }
		            return P4(leafBuilder: leafBuilder)
		        }
		        let p4: P4 = __safeDI_p4()
		        func __safeDI_p17() -> P17 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P17(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p17: P17 = __safeDI_p17()
		        func __safeDI_p0() -> P0 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P0(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p0: P0 = __safeDI_p0()
		        func __safeDI_p9() -> P9 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P9(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p9: P9 = __safeDI_p9()
		        func __safeDI_p2() -> P2 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P2(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p2: P2 = __safeDI_p2()
		        func __safeDI_p19() -> P19 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: nil)
		            }
		            return P19(leafBuilder: leafBuilder)
		        }
		        let p19: P19 = __safeDI_p19()
		        func __safeDI_p6() -> P6 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P6(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p6: P6 = __safeDI_p6()
		        func __safeDI_p11() -> P11 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P11(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p11: P11 = __safeDI_p11()
		        func __safeDI_p15() -> P15 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P15(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p15: P15 = __safeDI_p15()
		        func __safeDI_p1() -> P1 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: nil)
		            }
		            return P1(leafBuilder: leafBuilder)
		        }
		        let p1: P1 = __safeDI_p1()
		        func __safeDI_p8() -> P8 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P8(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p8: P8 = __safeDI_p8()
		        func __safeDI_p18() -> P18 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P18(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p18: P18 = __safeDI_p18()
		        func __safeDI_p3() -> P3 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P3(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p3: P3 = __safeDI_p3()
		        func __safeDI_p12() -> P12 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P12(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p12: P12 = __safeDI_p12()
		        func __safeDI_p7() -> P7 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: nil)
		            }
		            return P7(leafBuilder: leafBuilder)
		        }
		        let p7: P7 = __safeDI_p7()
		        func __safeDI_p16() -> P16 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: nil)
		            }
		            return P16(leafBuilder: leafBuilder)
		        }
		        let p16: P16 = __safeDI_p16()
		        func __safeDI_p5() -> P5 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P5(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p5: P5 = __safeDI_p5()
		        func __safeDI_p10() -> P10 {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: nil)
		            }
		            return P10(leafBuilder: leafBuilder)
		        }
		        let p10: P10 = __safeDI_p10()
		        func __safeDI_p14() -> P14 {
		            let cache = Cache()
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(cache: cache)
		            }
		            return P14(cache: cache, leafBuilder: leafBuilder)
		        }
		        let p14: P14 = __safeDI_p14()
		        self.init(p13: p13, p4: p4, p17: p17, p0: p0, p9: p9, p2: p2, p19: p19, p6: p6, p11: p11, p15: p15, p1: p1, p8: p8, p18: p18, p3: p3, p12: p12, p7: p7, p16: p16, p5: p5, p10: p10, p14: p14)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesSharedFunctionFromFirstReachedLabel_whenTwentyPlacesUseDifferentLabels() async throws {
		try await expectTypeKeyTree(of: Self.twentyParents(
			rootDeclaration: { index in "@Instantiated let p\(index): P\(index)" },
			parentDeclarations: { index in ["@Instantiated let \(Self.labels[index]): Instantiator<Leaf>"] },
		) + [Self.type("Leaf", "@Instantiated let itemBuilder: Instantiator<Item>"), Self.type("Item")], equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_hotel() -> Leaf {
		            let itemBuilder = Instantiator<Item>(__safeDI_itemBuilder)
		            return Leaf(itemBuilder: itemBuilder)
		        }
		        func __safeDI_itemBuilder() -> Item {
		            Item()
		        }
		        func __safeDI_p13() -> P13 {
		            let hotel = Instantiator<Leaf>(__safeDI_hotel)
		            return P13(hotel: hotel)
		        }
		        let p13: P13 = __safeDI_p13()
		        func __safeDI_p4() -> P4 {
		            let oscar = Instantiator<Leaf>(__safeDI_hotel)
		            return P4(oscar: oscar)
		        }
		        let p4: P4 = __safeDI_p4()
		        func __safeDI_p17() -> P17 {
		            let foxtrot = Instantiator<Leaf>(__safeDI_hotel)
		            return P17(foxtrot: foxtrot)
		        }
		        let p17: P17 = __safeDI_p17()
		        func __safeDI_p0() -> P0 {
		            let kilo = Instantiator<Leaf>(__safeDI_hotel)
		            return P0(kilo: kilo)
		        }
		        let p0: P0 = __safeDI_p0()
		        func __safeDI_p9() -> P9 {
		            let golf = Instantiator<Leaf>(__safeDI_hotel)
		            return P9(golf: golf)
		        }
		        let p9: P9 = __safeDI_p9()
		        func __safeDI_p2() -> P2 {
		            let tango = Instantiator<Leaf>(__safeDI_hotel)
		            return P2(tango: tango)
		        }
		        let p2: P2 = __safeDI_p2()
		        func __safeDI_p19() -> P19 {
		            let juliet = Instantiator<Leaf>(__safeDI_hotel)
		            return P19(juliet: juliet)
		        }
		        let p19: P19 = __safeDI_p19()
		        func __safeDI_p6() -> P6 {
		            let romeo = Instantiator<Leaf>(__safeDI_hotel)
		            return P6(romeo: romeo)
		        }
		        let p6: P6 = __safeDI_p6()
		        func __safeDI_p11() -> P11 {
		            let charlie = Instantiator<Leaf>(__safeDI_hotel)
		            return P11(charlie: charlie)
		        }
		        let p11: P11 = __safeDI_p11()
		        func __safeDI_p15() -> P15 {
		            let india = Instantiator<Leaf>(__safeDI_hotel)
		            return P15(india: india)
		        }
		        let p15: P15 = __safeDI_p15()
		        func __safeDI_p1() -> P1 {
		            let alpha = Instantiator<Leaf>(__safeDI_hotel)
		            return P1(alpha: alpha)
		        }
		        let p1: P1 = __safeDI_p1()
		        func __safeDI_p8() -> P8 {
		            let xray = Instantiator<Leaf>(__safeDI_hotel)
		            return P8(xray: xray)
		        }
		        let p8: P8 = __safeDI_p8()
		        func __safeDI_p18() -> P18 {
		            let november = Instantiator<Leaf>(__safeDI_hotel)
		            return P18(november: november)
		        }
		        let p18: P18 = __safeDI_p18()
		        func __safeDI_p3() -> P3 {
		            let delta = Instantiator<Leaf>(__safeDI_hotel)
		            return P3(delta: delta)
		        }
		        let p3: P3 = __safeDI_p3()
		        func __safeDI_p12() -> P12 {
		            let papa = Instantiator<Leaf>(__safeDI_hotel)
		            return P12(papa: papa)
		        }
		        let p12: P12 = __safeDI_p12()
		        func __safeDI_p7() -> P7 {
		            let echo = Instantiator<Leaf>(__safeDI_hotel)
		            return P7(echo: echo)
		        }
		        let p7: P7 = __safeDI_p7()
		        func __safeDI_p16() -> P16 {
		            let mike = Instantiator<Leaf>(__safeDI_hotel)
		            return P16(mike: mike)
		        }
		        let p16: P16 = __safeDI_p16()
		        func __safeDI_p5() -> P5 {
		            let bravo = Instantiator<Leaf>(__safeDI_hotel)
		            return P5(bravo: bravo)
		        }
		        let p5: P5 = __safeDI_p5()
		        func __safeDI_p10() -> P10 {
		            let lima = Instantiator<Leaf>(__safeDI_hotel)
		            return P10(lima: lima)
		        }
		        let p10: P10 = __safeDI_p10()
		        func __safeDI_p14() -> P14 {
		            let sierra = Instantiator<Leaf>(__safeDI_hotel)
		            return P14(sierra: sierra)
		        }
		        let p14: P14 = __safeDI_p14()
		        self.init(p13: p13, p4: p4, p17: p17, p0: p0, p9: p9, p2: p2, p19: p19, p6: p6, p11: p11, p15: p15, p1: p1, p8: p8, p18: p18, p3: p3, p12: p12, p7: p7, p16: p16, p5: p5, p10: p10, p14: p14)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSharedTypeInOneFunction_whenSixParentsReachTypeInsideAndOutsideCycle() async throws {
		try await expectTypeKeyTree(of: Self.sixParents(
			rootDeclarations: ["@Instantiated let t: T", "@Instantiated let nBuilder: Instantiator<N>"],
			parentDeclarations: { index in index.isMultiple(of: 2) ? ["@Instantiated let t: T"] : ["@Instantiated let nBuilder: Instantiator<N>"] },
		) + [
			Self.type("T", "@Instantiated let a: A", "@Instantiated let dep: Dep"),
			Self.type("A", "@Instantiated let nBuilder: Instantiator<N>"),
			Self.type("N", "@Received(onlyIfAvailable: true) let dep: Dep?", "@Instantiated let tBuilder: Instantiator<T>"),
			Self.type("Dep"),
		], equals: """
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
		        func __safeDI_w3() -> W3 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(dep: nil)
		            }
		            return W3(nBuilder: nBuilder)
		        }
		        let w3: W3 = __safeDI_w3()
		        func __safeDI_w0() -> W0 {
		            let t: T = __safeDI_t()
		            return W0(t: t)
		        }
		        let w0: W0 = __safeDI_w0()
		        func __safeDI_w5() -> W5 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(dep: nil)
		            }
		            return W5(nBuilder: nBuilder)
		        }
		        let w5: W5 = __safeDI_w5()
		        func __safeDI_w1() -> W1 {
		            let nBuilder = Instantiator<N> {
		                __safeDI_nBuilder(dep: nil)
		            }
		            return W1(nBuilder: nBuilder)
		        }
		        let w1: W1 = __safeDI_w1()
		        func __safeDI_w4() -> W4 {
		            let t: T = __safeDI_t()
		            return W4(t: t)
		        }
		        let w4: W4 = __safeDI_w4()
		        func __safeDI_w2() -> W2 {
		            let t: T = __safeDI_t()
		            return W2(t: t)
		        }
		        let w2: W2 = __safeDI_w2()
		        self.init(t: t, nBuilder: nBuilder, w3: w3, w0: w0, w5: w5, w1: w1, w4: w4, w2: w2)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachLoopMemberInOneFunction_whenSixParentsEnterInstantiatorLoop() async throws {
		try await expectTypeKeyTree(of: Self.sixParents(
			rootDeclarations: ["@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let stepBuilder: Instantiator<Step>"],
			parentDeclarations: { index in index.isMultiple(of: 2) ? ["@Instantiated let screenBuilder: Instantiator<Screen>"] : ["@Instantiated let stepBuilder: Instantiator<Step>"] },
		) + [
			Self.type("Screen", "@Instantiated let stepBuilder: Instantiator<Step>"),
			Self.type("Step", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		], equals: """
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
		        func __safeDI_w3() -> W3 {
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return W3(stepBuilder: stepBuilder)
		        }
		        let w3: W3 = __safeDI_w3()
		        func __safeDI_w0() -> W0 {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return W0(screenBuilder: screenBuilder)
		        }
		        let w0: W0 = __safeDI_w0()
		        func __safeDI_w5() -> W5 {
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return W5(stepBuilder: stepBuilder)
		        }
		        let w5: W5 = __safeDI_w5()
		        func __safeDI_w1() -> W1 {
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return W1(stepBuilder: stepBuilder)
		        }
		        let w1: W1 = __safeDI_w1()
		        func __safeDI_w4() -> W4 {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return W4(screenBuilder: screenBuilder)
		        }
		        let w4: W4 = __safeDI_w4()
		        func __safeDI_w2() -> W2 {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return W2(screenBuilder: screenBuilder)
		        }
		        let w2: W2 = __safeDI_w2()
		        self.init(screenBuilder: screenBuilder, stepBuilder: stepBuilder, w3: w3, w0: w0, w5: w5, w1: w1, w4: w4, w2: w2)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesCloserItsOwnNearestDeclaration_whenSixParentsReachClosingEdge() async throws {
		try await expectTypeKeyTree(of: Self.sixParents(
			rootDeclarations: ["@Instantiated let x: X", "@Instantiated let e: E"],
			parentDeclarations: { index in index.isMultiple(of: 2) ? ["@Instantiated let e: E"] : ["@Instantiated let x: X", "@Instantiated let e: E"] },
		) + [
			Self.type("E", "@Instantiated let k: K", "@Instantiated let p: P"),
			Self.type("K", "@Received let x: X"),
			Self.type("P", "@Instantiated let x: X", "@Instantiated let sBuilder: Instantiator<S>"),
			Self.type("S", "@Instantiated let eBuilder: Instantiator<E>"),
			Self.type("X"),
		], equals: """
		extension Root {
		    public convenience init() {
		        let x = X()
		        func __safeDI_e(x: X) -> E {
		            let k = K(x: x)
		            let p: P = __safeDI_p()
		            return E(k: k, p: p)
		        }
		        func __safeDI_p() -> P {
		            let x = X()
		            let sBuilder = Instantiator<S> {
		                __safeDI_sBuilder(x: x)
		            }
		            return P(x: x, sBuilder: sBuilder)
		        }
		        func __safeDI_sBuilder(x: X) -> S {
		            let eBuilder = Instantiator<E> {
		                __safeDI_e(x: x)
		            }
		            return S(eBuilder: eBuilder)
		        }
		        let e: E = __safeDI_e(x: x)
		        func __safeDI_w3() -> W3 {
		            let x = X()
		            let e: E = __safeDI_e(x: x)
		            return W3(x: x, e: e)
		        }
		        let w3: W3 = __safeDI_w3()
		        func __safeDI_w0() -> W0 {
		            let e: E = __safeDI_e(x: x)
		            return W0(e: e)
		        }
		        let w0: W0 = __safeDI_w0()
		        func __safeDI_w5() -> W5 {
		            let x = X()
		            let e: E = __safeDI_e(x: x)
		            return W5(x: x, e: e)
		        }
		        let w5: W5 = __safeDI_w5()
		        func __safeDI_w1() -> W1 {
		            let x = X()
		            let e: E = __safeDI_e(x: x)
		            return W1(x: x, e: e)
		        }
		        let w1: W1 = __safeDI_w1()
		        func __safeDI_w4() -> W4 {
		            let e: E = __safeDI_e(x: x)
		            return W4(e: e)
		        }
		        let w4: W4 = __safeDI_w4()
		        func __safeDI_w2() -> W2 {
		            let e: E = __safeDI_e(x: x)
		            return W2(e: e)
		        }
		        let w2: W2 = __safeDI_w2()
		        self.init(x: x, e: e, w3: w3, w0: w0, w5: w5, w1: w1, w4: w4, w2: w2)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachCloserItsTargetsDeclaration_whenTwoPlacesOfOneTypeDifferOnlyInClosingTarget() async throws {
		// `B` reads nothing of its own: its closer calls the function of the nearest `A`, which reads `x` through `K`. The root's
		// `A` and `P`'s `A` resolve `x` to different declarations, so the two places of `B` differ only in the target their
		// closer calls. Each passes that target's `x`: the root's under the root's `A`, `P`'s under `P`'s.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: X", "@Instantiated let a: A", "@Instantiated let p: P"),
				Self.type("P", "@Instantiated let x: X", "@Instantiated let a: A"),
				Self.type("A", "@Instantiated let k: K", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("B", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("K", "@Received let x: X"),
				Self.type("X"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        let x = X()
			        func __safeDI_a(x: X) -> A {
			            let k = K(x: x)
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(x: x)
			            }
			            return A(k: k, bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder(x: X) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_a(x: x)
			            }
			            return B(aBuilder: aBuilder)
			        }
			        let a: A = __safeDI_a(x: x)
			        func __safeDI_p() -> P {
			            let x = X()
			            let a: A = __safeDI_a(x: x)
			            return P(x: x, a: a)
			        }
			        let p: P = __safeDI_p()
			        self.init(x: x, a: a, p: p)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachCloserItsTargetsDeclaration_whenOneViewClosesOnTwoMembersOfItsLoop() async throws {
		// `D`, inside the loop `A` -> `B` -> `C`, closes on two of its members: `A`, which reads `x`, and `B`, which reads `y`.
		// The loop is entered from the root and from `P`, which declares `x` again, so each of `D`'s closers passes the `x` of
		// the entry it is beneath, and `y`, which every place resolves to the root's, is captured.
		try await expectTypeKeyTree(
			of: [
				Self.type("Root", isRoot: true, "@Instantiated let x: X", "@Instantiated let y: Y", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let p: P"),
				Self.type("P", "@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"),
				Self.type("A", "@Instantiated let kx: KX", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("B", "@Instantiated let ky: KY", "@Instantiated let cBuilder: Instantiator<C>"),
				Self.type("C", "@Instantiated let d: D"),
				Self.type("D", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("KX", "@Received let x: X"),
				Self.type("KY", "@Received let y: Y"),
				Self.type("X"),
				Self.type("Y"),
			],
			equals: """
			extension Root {
			    public convenience init() {
			        let x = X()
			        let y = Y()
			        func __safeDI_aBuilder(x: X) -> A {
			            let kx = KX(x: x)
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(x: x)
			            }
			            return A(kx: kx, bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder(x: X) -> B {
			            let ky = KY(y: y)
			            let cBuilder = Instantiator<C> {
			                __safeDI_cBuilder(x: x)
			            }
			            return B(ky: ky, cBuilder: cBuilder)
			        }
			        func __safeDI_cBuilder(x: X) -> C {
			            let d: D = __safeDI_d(x: x)
			            return C(d: d)
			        }
			        func __safeDI_d(x: X) -> D {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(x: x)
			            }
			            return D(aBuilder: aBuilder, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(x: x)
			        }
			        func __safeDI_p() -> P {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return P(x: x, aBuilder: aBuilder)
			        }
			        let p: P = __safeDI_p()
			        self.init(x: x, y: y, aBuilder: aBuilder, p: p)
			    }
			}
			""",
		)
	}

	// MARK: Private

	/// The order the root declares the twenty parents of a merge-order cell in: neither their names' order nor its reverse.
	private static let twentyParentOrder = [13, 4, 17, 0, 9, 2, 19, 6, 11, 15, 1, 8, 18, 3, 12, 7, 16, 5, 10, 14]

	/// The order the root declares the six parents of a merge-order cell in.
	private static let sixParentOrder = [3, 0, 5, 1, 4, 2]

	/// Twenty labels whose order is neither the parents' order nor the order the root declares them in.
	private static let labels = ["kilo", "alpha", "tango", "delta", "oscar", "bravo", "romeo", "echo", "xray", "golf", "lima", "charlie", "papa", "hotel", "sierra", "india", "mike", "foxtrot", "november", "juliet"]

	/// A root declaring `P0` to `P19` in `twentyParentOrder`, each declared by `rootDeclaration` and holding `parentDeclarations`.
	private static func twentyParents(rootDeclaration: (Int) -> String, parentDeclarations: (Int) -> [String]) -> [String] {
		[seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: twentyParentOrder.map(rootDeclaration))]
			+ (0..<20).map { seamFixtureType(named: "P\($0)", isFinalClass: true, declarations: parentDeclarations($0)) }
	}

	/// A root holding `rootDeclarations` and `W0` to `W5`, declared in `sixParentOrder`, each holding `parentDeclarations`.
	private static func sixParents(rootDeclarations: [String], parentDeclarations: (Int) -> [String]) -> [String] {
		[seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclarations + sixParentOrder.map { "@Instantiated let w\($0): W\($0)" })]
			+ (0..<6).map { seamFixtureType(named: "W\($0)", isFinalClass: true, declarations: parentDeclarations($0)) }
	}

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
