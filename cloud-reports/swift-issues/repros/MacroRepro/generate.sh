#!/bin/bash
# generate.sh N: writes N copies of Service (Service0…) to Types.swift and constructs each in Use.swift.
N=$1; cd "$(dirname "$0")/Sources/Client"
{ echo "import NoopMacros"; for i in $(seq 0 $((N-1))); do cat <<SWIFT

@NoopMember
public final class Service$i {
    @NoopPeer var a: Int = 0
    @NoopPeer var b: String = ""
    @NoopPeer var c: Int { a }
    @NoopPeer func d() {}
    public init() {}
    public var description: String { "" }
}
SWIFT
done; } > Types.swift
{ echo "public func use() {"; for i in $(seq 0 $((N-1))); do echo "    _ = Service$i()"; done; echo "}"; } > Use.swift
