// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
import Feature
import Harness
import SafeDI

func handWrittenCallers() -> [Service] {
    [
        Service { DefaultUserService(analytics: Analytics(), session: nil) },
        Service(userServiceBuilder: { DefaultUserService(analytics: Analytics(), session: Session()) }),
    ]
}
