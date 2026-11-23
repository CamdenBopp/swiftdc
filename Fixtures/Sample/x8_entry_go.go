// Go ABIInternal passes the ninth word in x8. It is data, not an AAPCS64
// indirect-result address, even in a leaf preserving all callee-saved registers.
package main

//go:noinline
func store9(dst *uint64, a, b, c, d, e, f, g, h uint64) { *dst = h }

func main() {
    for _, value := range []uint64{0, 1, 7, 99, 0xffff, 0xffffffff, 0xffffffffffffffff} {
        var stored uint64
        store9(&stored, 11, 22, 33, 44, 55, 66, 77, value)
        if stored != value { panic("ninth register data did not survive") }
    }
    println("PASS 7 native Go x8 data observations")
}
