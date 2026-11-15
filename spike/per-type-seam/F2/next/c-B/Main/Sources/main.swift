import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
@MainActor func handWrittenCallers() -> [Home] {
    [
        Home { Cache() as AnyObject as! any Api },
        Home(apiBuilder: { Cache() as AnyObject as! any Api }),
    ]
}

print("rejected in 2.3.0: the struct and the readable initializer compile")
