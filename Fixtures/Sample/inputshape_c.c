// Three functions, two of them hidden, so `strip -x` leaves one symbol. With
// -no_function_starts nothing else marks where `triple` and `shout` begin.
//
// True behaviour: `triple` multiplies by 3, `shout` prints triple(x) and
// returns x + 1, `entry` returns shout(x) + triple(x + 1). As an object,
// `bl _printf` is a relocation: the instruction's own offset field is 0.
#include <stdio.h>

__attribute__((noinline, visibility("hidden"))) int triple(int x) { return x * 3; }

__attribute__((noinline, visibility("hidden"))) int shout(int x) {
    printf("%d\n", triple(x));
    return x + 1;
}

int entry(int x) { return shout(x) + triple(x + 1); }
