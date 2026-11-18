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

/// The names a body that holds loops of builders gives what it declares for them: the box of a boxed loop's payloads,
/// and a member's `__safeDI_<label>_received` function. Both are claimed from one allocator, which reserves every name in
/// scope where they are declared or read (`ScopeGenerator.namesReceivedFunctionsAvoid`), member by member in the order
/// the body generates them, and for each member the box before the `_received` function: a different order moves names.
struct LoopMemberNames {
	private var allocator: GeneratedNameAllocator

	init(reserving reservedNames: Set<String>) {
		allocator = GeneratedNameAllocator(reserving: reservedNames)
	}

	/// The names of what a member whose builder function is named `functionName` declares: the box of its loop's payloads
	/// where `bindsLoopsBox`, which only the first member of a boxed loop does, then its `_received` function where it
	/// `takesCycleParameters`.
	mutating func claim(forMemberBuiltBy functionName: String, bindsLoopsBox: Bool, takesCycleParameters: Bool) -> (loopLevelsName: String?, receivedFunctionName: String?) {
		let loopLevelsName = bindsLoopsBox ? allocator.claim(ReservedName.loopLevelsName(of: functionName)) : nil
		let receivedFunctionName = takesCycleParameters ? allocator.claim(ReservedName.receivedBuilderFunctionName(of: functionName)) : nil
		return (loopLevelsName, receivedFunctionName)
	}
}
