import EntryResults
@main struct Oracle {
    static func main() {
        for k in [-1000, -1, 0, 1, 37, 1000, Int.max &- 4] {
            let a=wide(k); precondition([a.a,a.b,a.c,a.d,a.e] == (0..<5).map { k &+ $0 })
            let b=wideForward(k); precondition([b.a,b.b,b.c,b.d,b.e] == (0..<5).map { k &+ $0 })
            let c=small(k); precondition([c.a,c.b] == [k,k &+ 1])
            precondition(scalar(k) == k &+ 7)
            let d=generic(a); precondition([d.a,d.b,d.c,d.d,d.e] == [a.a,a.b,a.c,a.d,a.e])
            let e=mixed(a); precondition(e.0.e == a.e && e.1 == 37)
            let f=wideAndInt(k); precondition(f.0.e == k &+ 4 && f.1 == 37)
        }
        print("PASS 49 native entry-result observations")
    }
}
