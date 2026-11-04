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

/// The name of the module that compiles a build tool plugin command's files, as the Xcode project plugin reports it:
/// the build system expands `${PRODUCT_MODULE_NAME}` in the command's arguments when the command runs, as it does the
/// settings `BuildSettingCompilationConditions` reads.
///
/// It is not a module name for `ModuleMembership`: the Xcode project plugin cannot say which module declares a file
/// that a `#SafeDIConfiguration`'s `additionalDirectoriesToInclude` adds, so a run given only this option still knows
/// no module. `generate` reads it for one purpose: generated code never imports the module it is compiled into.
enum BuildSettingProductModuleName {
	/// The option that carries `${PRODUCT_MODULE_NAME}`.
	static let optionName = "build-setting-product-module-name"

	/// The module name, or `nil` when the option is missing or was not expanded.
	/// - Parameter bracketedProductModuleName: `[${PRODUCT_MODULE_NAME}]` as received.
	static func moduleName(_ bracketedProductModuleName: String?) throws -> String? {
		guard let bracketedProductModuleName else {
			return nil
		}
		let productModuleName = try BuildSettingCompilationConditions.unbracketed(bracketedProductModuleName, optionName: optionName, settingName: "PRODUCT_MODULE_NAME")
		return BuildSettingCompilationConditions.isUnexpanded(productModuleName) ? nil : productModuleName
	}
}
