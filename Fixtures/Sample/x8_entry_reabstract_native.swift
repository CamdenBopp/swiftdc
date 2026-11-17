import ReabstractResult
@main struct Oracle {
    static func main() {
        for n in [Int.min,-1000000,-1,0,1,37,Int.max] { precondition(start(n) == n &+ 7) }
        print("PASS 7 native reabstracted result observations")
    }
}
