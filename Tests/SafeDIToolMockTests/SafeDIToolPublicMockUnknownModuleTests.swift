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

/// A mock that builds the tree of a type with a public mock whose module SafeDI does not know, in a plugin run that names
/// its own module: the type is declared in a directory a `#SafeDIConfiguration` adds, so naming the run does not name the
/// type's module, and the error asks for the type to be declared in a module SafeDI knows, rather than for the run to
/// learn the module, which naming the run cannot do.
struct SafeDIToolPublicMockUnknownModuleTests: ~Copyable {
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
	mutating func generate_throwsErrorAskingToDeclareTypeInKnownModule_whenRunThatNamesItsModuleReadsTypeWithPublicMockFromAdditionalDirectory() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["AdditionalDirectory/TokenCache.swift"]):2:1: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `TokenCache` is `internal`: it is declared in a directory a `#SafeDIConfiguration` adds, or in a file no target of the plugin's graph lists. Declare it in a file of a module SafeDI knows.
			\(fixtures["AdditionalDirectory/TokenCache.swift"]):3:5: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `TokenCache`’s initializer is `internal`: it is declared in a directory a `#SafeDIConfiguration` adds, or in a file no target of the plugin's graph lists. Declare it in a file of a module SafeDI knows.
			\(fixtures["AdditionalDirectory/TokenCache.swift"]):8:5: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `Service`’s initializer is `internal`: it is declared in a directory a `#SafeDIConfiguration` adds, or in a file no target of the plugin's graph lists. Declare it in a file of a module SafeDI knows.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable
					struct TokenCache: Instantiable {
					    init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					""",
				],
				pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false),
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "App"],
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
