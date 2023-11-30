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

#if CI
// We don't set `-load-plugin-library` when building with xcodebuild, so we can't use the macros in CI.

#else

/// Marks a `class`, `struct`, or `actor` as capable of having properties that conform to this type decorated with `@Constructed` or `@Singleton`.
///
/// - Parameter fulfillingAdditionalTypes: The types (in addition to the type decorated with this macro) that can be decorated with `@Constructed` or `@Singleton` and yield a result of this type. The types provided *must* be either superclasses of this type or protocols to which this type conforms.
@attached(member, names: arbitrary)
public macro Constructable(fulfillingAdditionalTypes: [Any.Type] = []) = #externalMacro(module: "SafeDIMacros", type: "ConstructableMacro")

/// Marks a SafeDI dependency that is instantiated when its parent object is instantiated.
@attached(peer)
public macro Constructed() = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")

/// Marks a SafeDI dependency that is constructed by an object higher up in the dependency tree.
@attached(peer)
public macro Provided() = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")

/// Marks a SafeDI dependency that will only ever have one instance instantiated at a given time. Singleton dependencies may deallocate when all of the objects that use it deallocate. Singleton dependencies can not be marked with @Constructed.
@attached(peer)
public macro Singleton() = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")

/// Marks a SafeDI dependency that is injected into the parent object's initializer and provided to objects further down in the dependency tree.
@attached(peer)
public macro Propagated() = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")

#endif
