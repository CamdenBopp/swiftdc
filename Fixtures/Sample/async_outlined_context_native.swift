import AsyncOutlinedContext
@main struct NativeOracle {
 static func main() async {
  let cases: [(Int64, Int64)] = [(0,0), (17,29), (-73,91), (.max,1), (.min,-1), (.min,.max), (0x12345678,-0x12345678)]
  for (a,b) in cases {
   configure(a,b)
   let result = await sequence()
   precondition(result == a &+ b)
   print("OBS",a,b,result)
  }
  print("PASS native outlined async context: \(cases.count) observations")
 }
}
