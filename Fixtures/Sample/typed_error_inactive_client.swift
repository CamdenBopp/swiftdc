import TypedErrorProbe

@_silgen_name("$s15TypedErrorProbe12probeWrappedyAA8BigValueVSiAA11TinyFailureOYKF")
func probeWrapped(_ mode: Int) throws(TinyFailure) -> BigValue

@main struct Main {
    static func main() {
        for mode in [-1, 0, 1] {
            do {
                let value = try probeWrapped(mode)
                print("wrapped", mode, value.a, value.b, value.c, value.d, value.e)
            } catch { print("wrapped", mode, error) }

            do {
                let (floating, integer) = try probeDirect(mode)
                print("direct", mode, floating, integer)
            } catch { print("direct", mode, error) }

            do {
                let value = try probeFour(mode)
                print("four", mode, value.a, value.b, value.c, value.d)
            } catch { print("four", mode, error) }
        }
    }
}
