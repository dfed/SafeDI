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

/// The layers of work a run of `generate` computes, each of which `DependencyTreeGenerator.generate(_:)` computes once and
/// hands down: the tests count them to check that no layer is computed twice in one run. Handed to `observer`, which the
/// tests set, never the tool.
public enum GenerationLayerObservation {
	/// A layer of a run's work.
	public enum Layer: Hashable, Sendable {
		/// The signatures of the seams of the module named `moduleName`, computed over the declarations that module sees,
		/// or over those the modules that call this run's module see when `inCallersView`.
		case seamSignatures(ofModule: String?, inCallersView: Bool)
		/// A proof of every type's access (`TypeAccessProof`) over the declarations the module named `moduleName` sees,
		/// or over those the modules that call this run's module see when `inCallersView`.
		case accessProof(ofModule: String?, inCallersView: Bool)
		/// The tree of a root, or of a seam this module generates, of the type `TypeDescription`.
		case dependencyTree(of: TypeDescription)
		/// The tree of another module's seam of the type `TypeDescription`, built inline with the fills this module
		/// generates, which only a tree that can hold a label a lazy cycle cannot pass is built for
		/// (`DependencyTreeGenerator.canHoldUnpassableCycleLabel(inTreeRootedAt:)`).
		case inlineTreeOfForeignSeam(of: TypeDescription)
		/// The mock scopes of the module named `moduleName`, which its mocks, or the plans of its public mocks, are built
		/// from: built by a generator over the declarations that module sees, or, for this run's module, over those its
		/// callers see.
		case mockScopes(ofModule: String?)
	}

	/// Called once for each layer a run computes, with the name of the module the run generates, when set: by the tests,
	/// never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (_ runModuleName: String?, _ layer: Layer) -> Void>?

	/// The run a generator over another module's declarations computes that module's public mock plans for, while it does:
	/// the layers that generator computes are that run's.
	@TaskLocal static var runOfOtherModulesGenerator: Run?

	/// The run of `generate` for the module named `moduleName`.
	struct Run: Sendable {
		let moduleName: String?
	}

	/// Tells `observer`, when set, that the run of the module named `runModuleName`, or the run a generator over another
	/// module's declarations computes for (`runOfOtherModulesGenerator`), computed `layer`.
	static func record(_ layer: Layer, inRunOf runModuleName: String?) {
		if let observer {
			observer(runOfOtherModulesGenerator.map(\.moduleName) ?? runModuleName, layer)
		}
	}
}
