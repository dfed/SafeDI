nonisolated(unsafe) var liveM = 0
final class M { let tag: String; init(_ t: String) { tag = t; liveM += 1 }; deinit { liveM -= 1 } }
final class Service {}
final class Instantiator<T> { let b: () -> T; init(_ b: @escaping () -> T) { self.b = b } }
final class A { let m: M; let s: Service; init(m: M, s: Service) { self.m = m; self.s = s } }
final class B { let m: M; let s: Service; init(m: M, s: Service) { self.m = m; self.s = s } }
final class P { let a: Instantiator<A>; let b: Instantiator<B>; init(a: Instantiator<A>, b: Instantiator<B>) { self.a = a; self.b = b } }
// Case 1: P binds ma, mb; A's hole reads ma, B's reads mb; the seam passes `service` to both.
func inlineP() -> P { let service = Service(); let ma = M("a"); let mb = M("b")
    return P(a: Instantiator { A(m: ma, s: service) }, b: Instantiator { B(m: mb, s: service) }) }
final class ACarrier { let m: () -> M; init(m: @escaping () -> M) { self.m = m } }
final class BCarrier { let m: () -> M; init(m: @escaping () -> M) { self.m = m } }
final class PCarrier { let enterA: (M, M) -> ACarrier; let enterB: (M, M) -> BCarrier
    init(enterA: @escaping (M, M) -> ACarrier, enterB: @escaping (M, M) -> BCarrier) { self.enterA = enterA; self.enterB = enterB } }
final class ZoneA { let ma: M; init(ma: M) { self.ma = ma } }
final class ZoneB { let mb: M; init(mb: M) { self.mb = mb } }
func callerCarrier() -> PCarrier {
    PCarrier(enterA: { ma, _ in let z = ZoneA(ma: ma); return ACarrier(m: { z.ma }) }, enterB: { _, mb in let z = ZoneB(mb: mb); return BCarrier(m: { z.mb }) }) }
final class PSeamContextShared { let a: ACarrier; let b: BCarrier; let service: Service; init(a: ACarrier, b: BCarrier, service: Service) { self.a = a; self.b = b; self.service = service } }
func v4SharedP(_ c: PCarrier) -> P { let service = Service(); let ma = M("a"); let mb = M("b")
    let context = PSeamContextShared(a: c.enterA(ma, mb), b: c.enterB(ma, mb), service: service)
    return P(a: Instantiator { A(m: context.a.m(), s: context.service) }, b: Instantiator { B(m: context.b.m(), s: context.service) }) }
final class WrapA { let a: ACarrier; let service: Service; init(a: ACarrier, service: Service) { self.a = a; self.service = service } }
final class WrapB { let b: BCarrier; let service: Service; init(b: BCarrier, service: Service) { self.b = b; self.service = service } }
func v4PerWrapperP(_ c: PCarrier) -> P { let service = Service(); let ma = M("a"); let mb = M("b")
    let wa = WrapA(a: c.enterA(ma, mb), service: service); let wb = WrapB(b: c.enterB(ma, mb), service: service)
    return P(a: Instantiator { A(m: wa.a.m(), s: wa.service) }, b: Instantiator { B(m: wb.b.m(), s: wb.service) }) }
func holdB(_ make: () -> P) -> Int { let b = make().b; return withExtendedLifetime(b) { liveM } }
print("case 1, live M holding only B's builder: inline \(holdB(inlineP))  v4 shared seam context \(holdB { v4SharedP(callerCarrier()) })  per-wrapper context \(holdB { v4PerWrapperP(callerCarrier()) })")
// Case 2: root values ra, rb; Screen's hole reads rb, Detail's hole (beneath Screen) reads ra; Detail is a `let` child.
final class Detail { let m: M; init(m: M) { self.m = m } }
final class Screen { let m: M; let detail: Instantiator<Detail>; init(m: M, detail: Instantiator<Detail>) { self.m = m; self.detail = detail } }
func inlineScreen() -> Instantiator<Screen> { let ra = M("ra"); let rb = M("rb")
    return Instantiator { Screen(m: rb, detail: Instantiator { Detail(m: ra) }) } }
final class DetailCarrier { let m: () -> M; init(m: @escaping () -> M) { self.m = m } }
final class ScreenCarrier { let m: () -> M; let detail: DetailCarrier; init(m: @escaping () -> M, detail: DetailCarrier) { self.m = m; self.detail = detail } }
final class RootZone { let ra: M; let rb: M; init(ra: M, rb: M) { self.ra = ra; self.rb = rb } }
final class DetailZone { let ra: M; init(ra: M) { self.ra = ra } }
func seamScreen(_ c: ScreenCarrier) -> Instantiator<Screen> { Instantiator { let d = c.detail; return Screen(m: c.m(), detail: Instantiator { Detail(m: d.m()) }) } }
func v4OneZone() -> Instantiator<Screen> { let z = RootZone(ra: M("ra"), rb: M("rb"))
    return seamScreen(ScreenCarrier(m: { z.rb }, detail: DetailCarrier(m: { z.ra }))) }
func v4NarrowedAtFormation() -> Instantiator<Screen> { let z = RootZone(ra: M("ra"), rb: M("rb")); let dz = DetailZone(ra: z.ra)
    return seamScreen(ScreenCarrier(m: { z.rb }, detail: DetailCarrier(m: { dz.ra }))) }
func holdDetail(_ make: () -> Instantiator<Screen>) -> Int { let d = make().b().detail; return withExtendedLifetime(d) { liveM } }
print("case 2, live M holding only the Detail builder: inline \(holdDetail(inlineScreen))  v4 one zone \(holdDetail(v4OneZone))  narrower context formed with the parent zone \(holdDetail(v4NarrowedAtFormation))")
