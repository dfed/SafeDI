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

// TODO: Document macro.
@attached(member, names: named(`init`), named(build), named(getDependencies), arbitrary)
public macro builder(_ propertyName: StaticString) = #externalMacro(module: "SafeDIMacros", type: "BuilderMacro")

// TODO: Document macro.
@attached(member, names: named(`init`))
public macro dependencies() = #externalMacro(module: "SafeDIMacros", type: "DependenciesMacro")

// TODO: Document macro.
@attached(member)
public macro constructed() = #externalMacro(module: "SafeDIMacros", type: "ConstructedMacro")

// TODO: Document macro.
@attached(member)
public macro singleton() = #externalMacro(module: "SafeDIMacros", type: "SingletonMacro")

#endif
