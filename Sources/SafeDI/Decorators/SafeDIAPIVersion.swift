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
/// The form of mock API SafeDI generates for a module.
///
/// Pass it as `apiVersion:` on SafeDIConfiguration(additionalImportedModules:additionalDirectoriesToInclude:additionalMocksToGenerate:mockConditionalCompilation:generatePlainDependencyTreeInitializers:apiVersion:).
/// Every module of an app sets the same value. SafeDI 3 removes the setting.
public enum SafeDIAPIVersion: Sendable {
	/// The mock API of SafeDI 2. The default.
	case v2
	/// A preview of the mock API of SafeDI 3, which may change in any release while it settles.
	case v3Unstable
}
