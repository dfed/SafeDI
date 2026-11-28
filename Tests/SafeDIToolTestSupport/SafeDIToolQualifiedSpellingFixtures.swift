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

/// Fixtures that spell SafeDI's names with its module name, shared by the tests of each integration and output that
/// read them.
enum SafeDIToolQualifiedSpellingFixtures {
	/// A graph that spells every attached macro of SafeDI's, and builds every wrapper of SafeDI's, with SafeDI's module
	/// name, whose root's `@SafeDI.Instantiable` takes `rootArguments`.
	static func fixtures(rootArguments: String) -> [String: String] {
		[
			"Root.swift": """
			@SafeDI.Instantiable(\(rootArguments))
			public struct Root: Instantiable {
			    public init(session: Session, screenBuilder: SafeDI.Instantiator<Screen>, sendableScreenBuilder: SafeDI.SendableInstantiator<Screen>, profileBuilder: SafeDI.ErasedInstantiator<User, AnyObject>, sendableProfileBuilder: SafeDI.SendableErasedInstantiator<User, Profile>, settings: SafeDI.LazilyInstantiated<Settings>, sendableSettings: SafeDI.SendableLazilyInstantiated<Settings>) {
			        self.session = session
			        self.screenBuilder = screenBuilder
			        self.sendableScreenBuilder = sendableScreenBuilder
			        self.profileBuilder = profileBuilder
			        self.sendableProfileBuilder = sendableProfileBuilder
			        self.settings = settings
			        self.sendableSettings = sendableSettings
			    }

			    @SafeDI.Instantiated let session: Session
			    @SafeDI.Instantiated let screenBuilder: SafeDI.Instantiator<Screen>
			    @SafeDI.Instantiated let sendableScreenBuilder: SafeDI.SendableInstantiator<Screen>
			    @SafeDI.Instantiated(fulfilledByType: "Profile") let profileBuilder: SafeDI.ErasedInstantiator<User, AnyObject>
			    @SafeDI.Instantiated(fulfilledByType: "Profile") let sendableProfileBuilder: SafeDI.SendableErasedInstantiator<User, Profile>
			    @SafeDI.Instantiated let settings: SafeDI.LazilyInstantiated<Settings>
			    @SafeDI.Instantiated let sendableSettings: SafeDI.SendableLazilyInstantiated<Settings>
			}
			""",
			"Screen.swift": """
			@SafeDI.Instantiable
			public final class Screen: Instantiable, Sendable {
			    public init(session: Session) {
			        self.session = session
			    }

			    @SafeDI.Received let session: Session
			}
			""",
			"Profile.swift": """
			public struct User: Sendable {}

			@SafeDI.Instantiable
			public final class Profile: Instantiable, Sendable {
			    public init(user: User) {
			        self.user = user
			    }

			    @SafeDI.Forwarded let user: User
			}
			""",
			"Session.swift": """
			@SafeDI.Instantiable
			public final class Session: Instantiable, Sendable {
			    public init() {}
			}
			""",
			"Settings.swift": """
			@SafeDI.Instantiable
			public final class Settings: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}
}
