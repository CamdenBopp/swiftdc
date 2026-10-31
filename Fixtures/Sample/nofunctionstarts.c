// Linked with -Wl,-no_function_starts, as Electron Framework is: symbols are
// the only boundaries. True behaviour: `first` is 2 instructions and ends
// where `second` begins; `second` follows it.
__attribute__((noinline)) int first(int x) { return x + 7; }
__attribute__((noinline)) int second(int x) { return first(x) * 3 + first(x + 1); }
