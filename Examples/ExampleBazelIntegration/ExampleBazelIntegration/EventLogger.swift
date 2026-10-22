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

import SafeDI

/// Records what the app does.
///
/// A different `@Instantiable` fulfills `EventLogger` in debug and release builds, so SafeDITool
/// has to know whether `DEBUG` is active to pick the right one. `DEBUG` reaches SafeDITool through the `safedi_compile` rule, which forwards it in the
/// `dbg` and `fastbuild` compilation modes along with the rule's `defines`.
public protocol EventLogger {
	func record(_ event: String)
}

#if DEBUG
	@Instantiable(fulfillingAdditionalTypes: [EventLogger.self])
	public final class ConsoleEventLogger: EventLogger, Instantiable {
		public init() {}

		public func record(_ event: String) {
			print("[ExampleBazelIntegration] \(event)")
		}
	}
#else
	@Instantiable(fulfillingAdditionalTypes: [EventLogger.self])
	public final class DisabledEventLogger: EventLogger, Instantiable {
		public init() {}

		public func record(_: String) {}
	}
#endif
