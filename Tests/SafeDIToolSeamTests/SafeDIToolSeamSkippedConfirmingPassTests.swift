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

/// A seam that settles after its first signature pass, without the pass that would confirm it, only when that pass could
/// find nothing new (`DependencyTreeGenerator.confirmingPassFindsNothingNew`). The test executors run the skipped pass
/// anyway and compare (`SkippedConfirmingPassChecks`); these fixtures are the shapes where skipping it would be wrong.
struct SafeDIToolSeamSkippedConfirmingPassTests: ~Copyable {
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
	mutating func generate_passesItsOwnBuilderToItsCallOfItself_whenSeamWithHoleBuildsItselfThroughInstantiator() async throws {
		// `Feature`'s first pass calls `Feature` with the signature it starts from, which takes no builder, and finds the
		// hole `api`. Only a second pass, which calls `Feature` with that hole, passes the builder on to the call.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public protocol Api {}

					@Instantiable(generateDependencyTree: true)
					public final class Feature: Instantiable {
					    public init(api: any Api, featureBuilder: Instantiator<Feature>) {
					        self.api = api
					        self.featureBuilder = featureBuilder
					    }

					    @Instantiated let api: any Api
					    @Instantiated let featureBuilder: Instantiator<Feature>
					}
					""",
				]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Feature {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Instantiator<Feature>) -> __safeDI_Built
		        public let featureBuilder: () -> Feature.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(api: @escaping (Instantiator<Feature>) -> __safeDI_Built, featureBuilder: @escaping () -> Feature.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.api = api
		            self.featureBuilder = featureBuilder
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        @inline(never) func __safeDI_featureBuilder() -> Feature {
		            _ = Feature.__safeDI_Feature_57C4DCF55CDC41B4.self
		            return Feature(__safeDI_apiBuilder: __safeDI_apiBuilder.featureBuilder())
		        }
		        let featureBuilder = Instantiator<Feature>(__safeDI_featureBuilder)
		        let api: any Api = __safeDI_apiBuilder.api(featureBuilder)
		        self.init(api: api, featureBuilder: featureBuilder)
		    }
		}

		extension Feature {
		    public enum __safeDI_Feature_57C4DCF55CDC41B4 {}
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
