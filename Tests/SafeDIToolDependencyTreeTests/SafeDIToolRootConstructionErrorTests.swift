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

/// Each production root's tree is built on its own, and every error building them finds is reported in source order,
/// not only the error of the root that sorts first by type.
struct SafeDIToolRootConstructionErrorTests: ~Copyable {
	// MARK: Initialization

	init() throws {
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
	mutating func run_reportsEveryRootsConstructionErrorInSourceOrder_whenTypeOrderOfRootsDiffersFromSourceOrder() async {
		// `Zeta` is declared before `Alpha` in one file, so the roots' type order and their source order disagree.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Roots.swift"]):7:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Int, AnyChild>` on `Zeta` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				\(fixtures["Roots.swift"]):16:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Bool, AnyChild>` on `Alpha` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public final class AnyChild {
					    public init(_ child: Child) {}
					}

					@Instantiable
					public final class Child: Instantiable {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let name: String
					}
					""",
				],
				swiftFileContentByFilePath: [
					"Roots.swift": """
					@Instantiable(isRoot: true)
					public final class Zeta: Instantiable {
					    public init(childBuilder: ErasedInstantiator<Int, AnyChild>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>
					}

					@Instantiable(isRoot: true)
					public final class Alpha: Instantiable {
					    public init(childBuilder: ErasedInstantiator<Bool, AnyChild>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Bool, AnyChild>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsConstructionErrorOnce_whenTwoRootsReachOneDeclarationThatFails() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Shared.swift"]):7:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Int, AnyChild>` on `Shared` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class FirstRoot: Instantiable {
					    public init(shared: Shared) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: Shared
					}
					""",
					"""
					@Instantiable(isRoot: true)
					public final class SecondRoot: Instantiable {
					    public init(shared: Shared) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: Shared
					}
					""",
					"""
					@Instantiable
					public final class Shared: Instantiable {
					    public init(childBuilder: ErasedInstantiator<Int, AnyChild>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>
					}
					""",
					"""
					public final class AnyChild {
					    public init(_ child: Child) {}
					}

					@Instantiable
					public final class Child: Instantiable {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let name: String
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
