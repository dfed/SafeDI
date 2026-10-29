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

#if prebuilt && sourceBuild
	#warning("Both 'prebuilt' and 'sourceBuild' SafeDI Package Traits are enabled. The prebuilt binary will be used and changes to SafeDITool source will be ignored. Enable only one trait. (This warning also fires during swift-docc-plugin documentation builds, where it is harmless — DocC does not invoke the SafeDIGenerator build-tool plugin.)")
#endif

/// Provides build-time configuration for SafeDI's code generation plugin.
///
/// `#SafeDIConfiguration` is a freestanding declaration macro that must appear at the top level of a Swift file (not nested inside a type).
/// Each module may have at most one `#SafeDIConfiguration` invocation. All arguments must be literal values.
///
/// Declare it in a file named `SafeDIConfiguration.swift`. SafeDI reads that file before scanning the rest of the
/// module, so the configuration decides how every other file is scanned. A configuration in any other file still
/// works, but SafeDI must scan the module to find it, and scan it again when `mockConditionalCompilation` is not
/// `"DEBUG"`; `SafeDITool` warns in that case.
///
/// - Parameters:
///   - additionalImportedModules: Module names to import in the generated dependency tree, in addition to the import statements found in files that declare `@Instantiable` types.
///   - additionalDirectoriesToInclude: Directories containing Swift files to include, relative to the executing directory. An entry may also name a single Swift file. Only the SPM build-tool plugin declares the files it reaches as build inputs, so under the Bazel and Tuist integrations list every Swift source via the build target itself instead. SafeDI warns about an entry from which it can read no Swift file.
///   - additionalMocksToGenerate: Type names from dependent modules to generate `mock()` methods for in this module. The types must be decorated with `@Instantiable` in their home module. Generation fails for an entry that names no `@Instantiable` type. See the "Cross-module mock generation" section of the manual.
///   - mockConditionalCompilation: The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`). Set to `nil` to generate mocks without conditional compilation.
///
/// Example:
///
///     #SafeDIConfiguration(
///         additionalImportedModules: ["MyModule", "OtherModule"],
///         additionalDirectoriesToInclude: ["Sources/OtherModule"]
///     )
@freestanding(declaration)
public macro SafeDIConfiguration(
	additionalImportedModules: [StaticString] = [],
	additionalDirectoriesToInclude: [StaticString] = [],
	additionalMocksToGenerate: [StaticString] = [],
	mockConditionalCompilation: StaticString? = "DEBUG",
) = #externalMacro(module: "SafeDIMacros", type: "SafeDIConfigurationMacro")
