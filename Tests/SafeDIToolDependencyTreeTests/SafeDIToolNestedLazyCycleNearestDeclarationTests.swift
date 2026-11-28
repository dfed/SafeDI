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

/// Two lazy cycles that share a type: `W` builds `U`, which builds `W` again and also `P`, which builds `U` again. A
/// label `P` declares is the nearest declaration for everything `U` builds beneath `P`, the `W` that `U` builds again
/// included, although on `W`'s own path to the scope that builds it again (`W` -> `U` -> `W`) nothing declares the
/// label. So the labels declared between `U` and the scope that builds `U` again are also declared between `W` and the
/// scope that builds `W` again, and each builder function on the way takes the label as a parameter. Each generated tree
/// is compared by value with a tree built by hand to the Manual's rule: a `@Received` property takes the nearest
/// declaration above it.
struct SafeDIToolNestedLazyCycleNearestDeclarationTests: ~Copyable {
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
	mutating func generate_passesNearestDeclaration_whenReceiverIsReachedOnlyThroughSecondCycleClosedInsideFirst() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(),
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: L) -> U {
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l) })
			        }
			        func u(l: L) -> U {
			            U(pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(l: stepL, uBuilder: Instantiator<U> { u(l: stepL) })
			            }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
		)
	}

	/// Each type declares its properties in the other order: `U` builds `W` again before it builds `P`, `W` builds `V` before `U`, and `P` builds `U` again before it declares `l`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenTypesDeclareCycleClosingPropertiesFirst() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(
				wDeclares: ["@Instantiated let vBuilder: Instantiator<V>", "@Instantiated let uBuilder: Instantiator<U>"],
				uDeclares: ["@Instantiated let wBuilder: Instantiator<W>", "@Instantiated let pBuilder: Instantiator<P>"],
				pDeclares: ["@Instantiated let uBuilder: Instantiator<U>", "@Instantiated let l: L"],
			),
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_wBuilder(l: L) -> W {
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return W(vBuilder: vBuilder, uBuilder: uBuilder)
				        }
				        func __safeDI_uBuilder(l: L) -> U {
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            return U(wBuilder: wBuilder, pBuilder: pBuilder)
				        }
				        func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(uBuilder: uBuilder, l: l)
				        }
				        func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(vBuilder: Instantiator<V> { V(l: l) }, uBuilder: Instantiator<U> { u(l: l) })
			        }
			        func u(l: L) -> U {
			            U(wBuilder: Instantiator<W> { w(l: l) }, pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(uBuilder: Instantiator<U> { u(l: stepL) }, l: stepL)
			            })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
		)
	}

	/// `U` builds `T`, which builds `U` again and `P`, which builds `T` again: the label `P` declares reaches `V` through the functions of `T`, `U` and `W`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenThreeCyclesAreClosedOneInsideAnother() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(
				uDeclares: ["@Instantiated let tBuilder: Instantiator<T>", "@Instantiated let wBuilder: Instantiator<W>"],
				pDeclares: ["@Instantiated let l: L", "@Instantiated let tBuilder: Instantiator<T>"],
				otherTypes: [seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let uBuilder: Instantiator<U>"])],
			),
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: L) -> U {
				            let tBuilder = Instantiator<T> {
				                __safeDI_tBuilder(l: l)
				            }
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(tBuilder: tBuilder, wBuilder: wBuilder)
				        }
				        func __safeDI_tBuilder(l: L) -> T {
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return T(pBuilder: pBuilder, uBuilder: uBuilder)
				        }
				        func __safeDI_pBuilder() -> P {
				            let l = L()
				            let tBuilder = Instantiator<T> {
				                __safeDI_tBuilder(l: l)
				            }
				            return P(l: l, tBuilder: tBuilder)
				        }
				        func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l) })
			        }
			        func u(l: L) -> U {
			            U(tBuilder: Instantiator<T> { t(l: l) }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        func t(l: L) -> T {
			            T(pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(l: stepL, tBuilder: Instantiator<T> { t(l: stepL) })
			            }, uBuilder: Instantiator<U> { u(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
		)
	}

	/// `Root` and `U` hold `W` by value, `U` holds `P` lazily, and `P` declares `l` lazily: each function takes the wrapper, and `V` reads its instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestLazilyInstantiatedDeclaration_whenCyclesAreClosedByConstantAndBuiltLazily() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(
				rootDeclares: ["@Instantiated let l: L", "@Instantiated let w: W"],
				uDeclares: ["@Instantiated let p: LazilyInstantiated<P>", "@Instantiated let w: W"],
				pDeclares: ["@Instantiated let l: LazilyInstantiated<L>", "@Instantiated let uBuilder: Instantiator<U>"],
			),
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_w(l: LazilyInstantiated<L>) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: LazilyInstantiated<L>) -> U {
				            let p = LazilyInstantiated<P>(__safeDI_p)
				            let w: W = __safeDI_w(l: l)
				            return U(p: p, w: w)
				        }
				        func __safeDI_p() -> P {
				            let l = LazilyInstantiated<L>(__safeDI_l)
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        func __safeDI_l() -> L {
				            L()
				        }
				        func __safeDI_vBuilder(l: LazilyInstantiated<L>) -> V {
				            V(l: l.instance)
				        }
				        let w: W = __safeDI_w(l: LazilyInstantiated<L> { l })
				        self.init(l: l, w: w)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: LazilyInstantiated<L>) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l.instance) })
			        }
			        func u(l: LazilyInstantiated<L>) -> U {
			            U(p: LazilyInstantiated<P> {
			                let stepL = LazilyInstantiated<L> { L() }
			                return P(l: stepL, uBuilder: Instantiator<U> { u(l: stepL) })
			            }, w: w(l: l))
			        }
			        let l = L()
			        self.init(l: l, w: w(l: LazilyInstantiated<L> { l }))
			    }
			}
			""",
		)
	}

	/// `W` and `P` hold `U` in an `ErasedInstantiator` of `AnyU`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenCyclesAreClosedThroughErasedInstantiators() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(
				wDeclares: [#"@Instantiated(fulfilledByType: "U", erasedToConcreteExistential: true) let uBuilder: ErasedInstantiator<(), AnyU>"#, "@Instantiated let vBuilder: Instantiator<V>"],
				pDeclares: ["@Instantiated let l: L", #"@Instantiated(fulfilledByType: "U", erasedToConcreteExistential: true) let uBuilder: ErasedInstantiator<(), AnyU>"#],
				otherTypes: [Self.erasedUFixture],
			),
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = ErasedInstantiator<(), AnyU> {
				                AnyU(__safeDI_uBuilder(l: l))
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: L) -> U {
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = ErasedInstantiator<(), AnyU> {
				                AnyU(__safeDI_uBuilder(l: l))
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(uBuilder: ErasedInstantiator<(), AnyU> { AnyU(u(l: l)) }, vBuilder: Instantiator<V> { V(l: l) })
			        }
			        func u(l: L) -> U {
			            U(pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(l: stepL, uBuilder: ErasedInstantiator<(), AnyU> { AnyU(u(l: stepL)) })
			            }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
			probeBeneathP: """
			{ () -> [AnyObject] in
			    let p = (Root().wBuilder.instantiate().uBuilder.instantiate().u as! U).pBuilder.instantiate()
			    return [p, (p.uBuilder.instantiate().u as! U).wBuilder.instantiate()]
			}()
			""",
		)
	}

	/// Every type is `Sendable` and every builder a `SendableInstantiator`, so each builder function is `@Sendable` and takes the label as the plain functions do.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenCyclesAreClosedThroughSendableInstantiators() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(
				rootDeclares: ["@Instantiated let l: L", "@Instantiated let wBuilder: SendableInstantiator<W>"],
				wDeclares: ["@Instantiated let uBuilder: SendableInstantiator<U>", "@Instantiated let vBuilder: SendableInstantiator<V>"],
				uDeclares: ["@Instantiated let pBuilder: SendableInstantiator<P>", "@Instantiated let wBuilder: SendableInstantiator<W>"],
				pDeclares: ["@Instantiated let l: L", "@Instantiated let uBuilder: SendableInstantiator<U>"],
				conformances: ", Sendable",
			),
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        @Sendable nonisolated func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = SendableInstantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = SendableInstantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        @Sendable nonisolated func __safeDI_uBuilder(l: L) -> U {
				            let pBuilder = SendableInstantiator<P>(__safeDI_pBuilder)
				            let wBuilder = SendableInstantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        @Sendable nonisolated func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = SendableInstantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        @Sendable nonisolated func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = SendableInstantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        @Sendable func w(l: L) -> W {
			            W(uBuilder: SendableInstantiator<U> { u(l: l) }, vBuilder: SendableInstantiator<V> { V(l: l) })
			        }
			        @Sendable func u(l: L) -> U {
			            U(pBuilder: SendableInstantiator<P> {
			                let stepL = L()
			                return P(l: stepL, uBuilder: SendableInstantiator<U> { u(l: stepL) })
			            }, wBuilder: SendableInstantiator<W> { w(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: SendableInstantiator<W> { w(l: l) })
			    }
			}
			""",
		)
	}

	/// `P` is forwarded `l`, and `V` receives `l` under another name.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestForwardedDeclaration_whenReceiverRenamesLabel() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(
				pDeclares: ["@Forwarded let l: L", "@Instantiated let uBuilder: Instantiator<U>"],
				vDeclares: [#"@Received(fulfilledByDependencyNamed: "l", ofType: L.self) let renamed: L"#],
			),
			equals: { output in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: L) -> U {
				            let pBuilder = Instantiator<P> {
				                __safeDI_pBuilder(l: $0)
				            }
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        func __safeDI_pBuilder(l: L) -> P {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        func __safeDI_vBuilder(l: L) -> V {
				            #sourceLocation(file: "\(output.fixtures["V.swift"])", line: 7)
				            let renamed: L = l
				            #sourceLocation()
				            return V(renamed: renamed)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(renamed: l) })
			        }
			        func u(l: L) -> U {
			            U(pBuilder: Instantiator<P> { forwardedL in
			                P(l: forwardedL, uBuilder: Instantiator<U> { u(l: forwardedL) })
			            }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
			probeBeneathP: "Root().wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate(L())",
		)
	}

	/// `Root` declares no `l` and `V` receives it only if available: a `V` beneath no `P` is passed `nil`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclarationOrNil_whenReceiverReceivesOnlyIfAvailableAndRootDeclaresNothing() async throws {
		try await expectGeneratedTree(
			of: Self.fixture(
				rootDeclares: ["@Instantiated let wBuilder: Instantiator<W>"],
				vDeclares: ["@Received(onlyIfAvailable: true) let l: L?"],
			),
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        func __safeDI_wBuilder(l: L?) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: L?) -> U {
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        func __safeDI_vBuilder(l: L?) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: nil)
				        }
				        self.init(wBuilder: wBuilder)
				    }
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L?) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l) })
			        }
			        func u(l: L?) -> U {
			            U(pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(l: stepL, uBuilder: Instantiator<U> { u(l: stepL) })
			            }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        self.init(wBuilder: Instantiator<W> { w(l: nil) })
			    }
			}
			""",
		)
	}

	/// `Root` generates its own dependency tree as a seam.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenRootIsSeam() async throws {
		try await expectGeneratedTree(
			of: Self.fixture().map { $0.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(generateDependencyTree: true)") },
			equals: { _ in
				"""
				extension Root {
				    /// Code you write and code SafeDI generates can both call this initializer.
				    public convenience init() {
				        let l = L()
				        @inline(never) func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        @inline(never) func __safeDI_uBuilder(l: L) -> U {
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        @inline(never) func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        @inline(never) func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}

				extension Root {
				    public enum __safeDI_Root_CBF29CE484222325 {}
				}
				"""
			},
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l) })
			        }
			        func u(l: L) -> U {
			            U(pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(l: stepL, uBuilder: Instantiator<U> { u(l: stepL) })
			            }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
		)
	}

	/// `Root` generates its mock, whose builder functions are nested: each takes the label as the production functions do, and the override of `V` is handed the value `V` would be.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNearestDeclaration_whenReceiverIsReachedOnlyThroughSecondCycleClosedInsideFirst() async throws {
		try await expectGeneratedTree(
			of: Self.fixture().map { $0.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)") },
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: L) -> U {
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			mock: """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            l: (() -> L)? = nil,
			            wBuilder: W.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                l: l,
			                wBuilder: wBuilder
			            )
			        }

			        var l: (() -> L)? { __safeDI_storage.l }
			        var wBuilder: W.SafeDIMockConfiguration { __safeDI_storage.wBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                l: (() -> L)?,
			                wBuilder: W.SafeDIMockConfiguration
			            ) {
			                self.l = l
			                self.wBuilder = wBuilder
			            }

			            let l: (() -> L)?
			            let wBuilder: W.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let l = if let safeDIBuilder = safeDIOverrides.l { safeDIBuilder() } else { L() }
			        func __safeDI_wBuilder(l: L) -> W {
			            func __safeDI_uBuilder(l: L) -> U {
			                func __safeDI_pBuilder() -> P {
			                    let l = L()
			                    let uBuilder = Instantiator<U> {
			                        __safeDI_uBuilder(l: l)
			                    }
			                    return P(l: l, uBuilder: uBuilder)
			                }
			                let pBuilder = Instantiator<P>(__safeDI_pBuilder)
			                let wBuilder = Instantiator<W> {
			                    __safeDI_wBuilder(l: l)
			                }
			                return U(pBuilder: pBuilder, wBuilder: wBuilder)
			            }
			            let uBuilder = Instantiator<U> {
			                __safeDI_uBuilder(l: l)
			            }
			            func __safeDI_vBuilder() -> V {
			                if let safeDIBuilder = safeDIOverrides.wBuilder.vBuilder { safeDIBuilder(l) } else { V(l: l) }
			            }
			            let vBuilder = Instantiator<V>(__safeDI_vBuilder)
			            return if let safeDIBuilder = safeDIOverrides.wBuilder.safeDIBuilder { safeDIBuilder(uBuilder, vBuilder) } else { W(uBuilder: uBuilder, vBuilder: vBuilder) }
			        }
			        let wBuilder = Instantiator<W> {
			            __safeDI_wBuilder(l: l)
			        }
			        return Root(l: l, wBuilder: wBuilder)
			    }
			}
			#endif
			""",
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l) })
			        }
			        func u(l: L) -> U {
			            U(pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(l: stepL, uBuilder: Instantiator<U> { u(l: stepL) })
			            }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
		)
	}

	/// `Root` generates a public mock.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNearestDeclaration_whenMockIsPublic() async throws {
		try await expectGeneratedTree(
			of: Self.fixture().map { $0.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: .public)") },
			equals: { _ in
				"""
				extension Root {
				    public convenience init() {
				        let l = L()
				        func __safeDI_wBuilder(l: L) -> W {
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            let vBuilder = Instantiator<V> {
				                __safeDI_vBuilder(l: l)
				            }
				            return W(uBuilder: uBuilder, vBuilder: vBuilder)
				        }
				        func __safeDI_uBuilder(l: L) -> U {
				            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
				            let wBuilder = Instantiator<W> {
				                __safeDI_wBuilder(l: l)
				            }
				            return U(pBuilder: pBuilder, wBuilder: wBuilder)
				        }
				        func __safeDI_pBuilder() -> P {
				            let l = L()
				            let uBuilder = Instantiator<U> {
				                __safeDI_uBuilder(l: l)
				            }
				            return P(l: l, uBuilder: uBuilder)
				        }
				        func __safeDI_vBuilder(l: L) -> V {
				            V(l: l)
				        }
				        let wBuilder = Instantiator<W> {
				            __safeDI_wBuilder(l: l)
				        }
				        self.init(l: l, wBuilder: wBuilder)
				    }
				}
				"""
			},
			mock: """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            l: (() -> L)? = nil,
			            wBuilder: __safeDI_W_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                l: l,
			                wBuilder: wBuilder
			            )
			        }

			        public var l: (() -> L)? { __safeDI_storage.l }
			        public var wBuilder: __safeDI_W_MockConfiguration { __safeDI_storage.wBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                l: (() -> L)?,
			                wBuilder: __safeDI_W_MockConfiguration
			            ) {
			                self.l = l
			                self.wBuilder = wBuilder
			            }

			            let l: (() -> L)?
			            let wBuilder: __safeDI_W_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let l = if let safeDIBuilder = safeDIOverrides.l { safeDIBuilder() } else { L() }
			        func __safeDI_wBuilder(l: L) -> W {
			            func __safeDI_uBuilder(l: L) -> U {
			                func __safeDI_pBuilder() -> P {
			                    let l = L()
			                    let uBuilder = Instantiator<U> {
			                        __safeDI_uBuilder(l: l)
			                    }
			                    return P.__safeDI_init(l: l, uBuilder: uBuilder, safeDIBuilder: nil)
			                }
			                let pBuilder = Instantiator<P>(__safeDI_pBuilder)
			                let wBuilder = Instantiator<W> {
			                    __safeDI_wBuilder(l: l)
			                }
			                return U.__safeDI_init(pBuilder: pBuilder, wBuilder: wBuilder, safeDIBuilder: nil)
			            }
			            let uBuilder = Instantiator<U> {
			                __safeDI_uBuilder(l: l)
			            }
			            func __safeDI_vBuilder() -> V {
			                if let safeDIBuilder = safeDIOverrides.wBuilder.vBuilder { safeDIBuilder(l) } else { V(l: l) }
			            }
			            let vBuilder = Instantiator<V>(__safeDI_vBuilder)
			            return W.__safeDI_init(uBuilder: uBuilder, vBuilder: vBuilder, safeDIBuilder: safeDIOverrides.wBuilder.safeDIBuilder)
			        }
			        let wBuilder = Instantiator<W> {
			            __safeDI_wBuilder(l: l)
			        }
			        return Root(l: l, wBuilder: wBuilder)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func w(l: L) -> W {
			            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l) })
			        }
			        func u(l: L) -> U {
			            U(pBuilder: Instantiator<P> {
			                let stepL = L()
			                return P(l: stepL, uBuilder: Instantiator<U> { u(l: stepL) })
			            }, wBuilder: Instantiator<W> { w(l: l) })
			        }
			        let l = L()
			        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
			    }
			}
			""",
		)
	}

	/// `W` also builds `X`, which receives `l` only if available as a `LazilyInstantiated`: no one parameter of the function
	/// that builds `W` carries both forms, so the label `P` declares cannot be passed to the `W` that `U` builds again.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableCycleLabel_whenTypeBuiltAgainThroughSecondCycleReceivesLabelInTwoForms() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["V.swift"]):7:5: error: @Received property `l: L` is received in chain: W -> V. A dependency cycle builds `W` again beneath `P`, which declares `l: L` with the same label, and SafeDI hands each `W` one value of `l`. `W` and the types it builds receive `l` as `l: L` and `l: LazilyInstantiated<L>?`, which one value cannot carry together. Receive `l: L` and `l: LazilyInstantiated<L>?` under different labels to fix.
			\(fixtures["P.swift"]):8:5: note: `l: L` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixture(
					wDeclares: ["@Instantiated let uBuilder: Instantiator<U>", "@Instantiated let vBuilder: Instantiator<V>", "@Instantiated let xBuilder: Instantiator<X>"],
					otherTypes: [seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let l: LazilyInstantiated<L>?"])],
				),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `U` declares `l` too, so two declarations of the label are between `W` and the `W` built again: `U`'s own, and the
	/// one of the type that builds `U` again, which reaches `W` only through `U`'s cycle. The note names the one that comes
	/// first in source order, here `P`'s, in `P.swift`, whichever the walk met first.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_notesDeclarationOfSecondCycle_whenItPrecedesDeclarationOfTypeBetweenInSourceOrder() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["V.swift"]):7:5: error: @Received property `l: L` is received in chain: W -> V. A dependency cycle builds `W` again beneath `P`, which declares `l: L` with the same label, and SafeDI hands each `W` one value of `l`. `W` and the types it builds receive `l` as `l: L` and `l: LazilyInstantiated<L>?`, which one value cannot carry together. Receive `l: L` and `l: LazilyInstantiated<L>?` under different labels to fix.
			\(fixtures["P.swift"]):8:5: note: `l: L` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixtureWhereTypeBetweenDeclaresLabelToo(typeBuildingUAgain: "P"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// The same graph with the type that builds `U` again named `Z`, so `U`'s declaration, in `U.swift`, comes first.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_notesDeclarationOfTypeBetween_whenItPrecedesDeclarationOfSecondCycleInSourceOrder() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["V.swift"]):7:5: error: @Received property `l: L` is received in chain: W -> V. A dependency cycle builds `W` again beneath `U`, which declares `l: L` with the same label, and SafeDI hands each `W` one value of `l`. `W` and the types it builds receive `l` as `l: L` and `l: LazilyInstantiated<L>?`, which one value cannot carry together. Receive `l: L` and `l: LazilyInstantiated<L>?` under different labels to fix.
			\(fixtures["U.swift"]):9:5: note: `l: L` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixtureWhereTypeBetweenDeclaresLabelToo(typeBuildingUAgain: "Z"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `U` also builds `Y` after `W` again, and `Y` receives `l` only if available as a `LazilyInstantiated`. The walk of
	/// the function that builds `W` meets no receive of `l` before the call `P` makes of the function that builds `U`,
	/// which hands that function its parameter: the first receive is `Y`'s, reached through that call, and its chain runs
	/// through it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableCycleLabelAtReceiveReachedThroughCallOfAnotherCycle_whenWalkMeetsNoReceiveBeforeIt() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Y.swift"]):7:5: error: @Received property `l: LazilyInstantiated<L>?` is received in chain: W -> U -> P -> U -> Y. A dependency cycle builds `W` again beneath `P`, which declares `l: L` with the same label, and SafeDI hands each `W` one value of `l`. `W` and the types it builds receive `l` as `l: L` and `l: LazilyInstantiated<L>?`, which one value cannot carry together. Receive `l: L` and `l: LazilyInstantiated<L>?` under different labels to fix.
			\(fixtures["P.swift"]):8:5: note: `l: L` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixture(
					uDeclares: ["@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let wBuilder: Instantiator<W>", "@Instantiated let yBuilder: Instantiator<Y>"],
					otherTypes: [seamFixtureType(named: "Y", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let l: LazilyInstantiated<L>?"])],
				),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The graph of `fixture()` in which `U` instantiates an `l` of its own before it builds `W` again, `W` also builds
	/// `X`, which receives `l` only if available as a `LazilyInstantiated`, and the type that instantiates `l` and builds
	/// `U` again is named `typeBuildingUAgain`, which decides whether its file precedes `U`'s.
	private static func fixtureWhereTypeBetweenDeclaresLabelToo(typeBuildingUAgain: String) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let l: L", "@Instantiated let wBuilder: Instantiator<W>"]),
			seamFixtureType(named: "W", isFinalClass: true, declarations: ["@Instantiated let uBuilder: Instantiator<U>", "@Instantiated let vBuilder: Instantiator<V>", "@Instantiated let xBuilder: Instantiator<X>"]),
			seamFixtureType(named: "U", isFinalClass: true, declarations: ["@Instantiated let l: L", "@Instantiated let stepBuilder: Instantiator<\(typeBuildingUAgain)>", "@Instantiated let wBuilder: Instantiator<W>"]),
			seamFixtureType(named: typeBuildingUAgain, isFinalClass: true, declarations: ["@Instantiated let l: L", "@Instantiated let uBuilder: Instantiator<U>"]),
			seamFixtureType(named: "V", isFinalClass: true, declarations: ["@Received let l: L"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let l: LazilyInstantiated<L>?"]),
			seamFixtureType(named: "L", isFinalClass: true, declarations: []),
		]
	}

	/// `Root` instantiates `l` and `W`; `W` instantiates `U` and `V`, which receives `l`; `U` instantiates `P` and `W`
	/// again; `P` instantiates its own `l` and `U` again.
	private static func fixture(
		rootDeclares: [String] = ["@Instantiated let l: L", "@Instantiated let wBuilder: Instantiator<W>"],
		wDeclares: [String] = ["@Instantiated let uBuilder: Instantiator<U>", "@Instantiated let vBuilder: Instantiator<V>"],
		uDeclares: [String] = ["@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let wBuilder: Instantiator<W>"],
		pDeclares: [String] = ["@Instantiated let l: L", "@Instantiated let uBuilder: Instantiator<U>"],
		vDeclares: [String] = ["@Received let l: L"],
		conformances: String = "",
		otherTypes: [String] = [],
	) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclares, conformances: conformances),
			seamFixtureType(named: "W", isFinalClass: true, declarations: wDeclares, conformances: conformances),
			seamFixtureType(named: "U", isFinalClass: true, declarations: uDeclares, conformances: conformances),
			seamFixtureType(named: "P", isFinalClass: true, declarations: pDeclares, conformances: conformances),
			seamFixtureType(named: "V", isFinalClass: true, declarations: vDeclares, conformances: conformances),
			seamFixtureType(named: "L", isFinalClass: true, declarations: [], conformances: conformances),
		] + otherTypes
	}

	/// `UProtocol`, which `U` conforms to, and `AnyU`, which erases it: the type an erased `uBuilder` hands out.
	private static let erasedUFixture = """
	public protocol UProtocol: AnyObject {}
	public final class AnyU {
	    public init(_ u: some UProtocol) {
	        self.u = u
	    }

	    public let u: any UProtocol
	}
	extension U: UProtocol {}
	"""

	/// Generates `fixture`, expects `Root`'s generated tree to be `expectedTree` and, when `expectedMock` is given, its
	/// mock to be `expectedMock`, and compares the values each builds with those `handBuiltTree` builds: a tree built by
	/// hand in which each `V` is handed the `l` of the nearest `P` above it, or the root's. The describer calls no erased
	/// builder and no builder that is forwarded a value, so a fixture whose `V` beneath `P` lies behind one names it in
	/// `probeBeneathP`: an expression that calls those builders itself and holds `P` beside the `W` built again beneath it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectGeneratedTree(
		of fixture: [String],
		equals expectedTree: (TestOutput) -> String,
		mock expectedMock: String? = nil,
		buildsTheSameValuesAs handBuiltTree: String,
		probeBeneathP: String? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": generatedFileHeader + expectedTree(output)], sourceLocation: sourceLocation)
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == expectedMock.map { generatedFileHeader + $0 }, sourceLocation: sourceLocation)
		let comparesMock = expectedMock != nil
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: [
				"Root+SafeDI.swift": handBuiltTree + (comparesMock ? "\n\nextension Root {\n    static func mock() -> Root {\n        Root()\n    }\n}" : ""),
			]),
			probes: [DifferentialValueProbe("Root()")] + (comparesMock ? [DifferentialValueProbe("Root.mock()")] : []) + (probeBeneathP.map { [DifferentialValueProbe($0)] } ?? []),
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// `files` named as `executeSafeDIToolTest` names them, after the type each declares.
	private static func fixtureFiles(_ files: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for file in files {
			let name = file.split(separator: "\n").compactMap { line -> String? in
				guard let classRange = line.range(of: "final class ") else { return nil }
				return String(line[classRange.upperBound...].prefix { $0 != ":" && $0 != " " })
			}.first ?? "File"
			fixtureFiles["\(name).swift"] = file
		}
		return fixtureFiles
	}
}
