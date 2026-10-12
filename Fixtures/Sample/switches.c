// Fixture for jump tables: clang -O1 lowers a dense switch to LLVM's
// compressed table (adrp/add table, adr anchor, ldrb or ldrh entry, add, br),
// bounded by `cmp; b.hi default`. Built by `build.sh` into libSwitches.dylib.

__attribute__((noinline)) long sink(long a, long b) { return a * 31 + b; }

// Ten cases, byte entries; the arms rejoin, so no tail call collapses them.
long pickByte(long x, long y) {
    long r;
    switch (x) {
    case 0: r = sink(y, 1); break;
    case 1: r = sink(y * 3, 2); break;
    case 2: r = sink(y - 7, y); break;
    case 3: r = sink(5, y ^ 5); break;
    case 4: r = sink(y, y + 9); break;
    case 5: r = sink(y * y, 4); break;
    case 6: r = sink(1, 3); break;
    case 7: r = sink(y, 1); break;
    case 8: r = sink(y, 8); break;
    case 9: r = sink(9, y); break;
    default: r = -1; break;
    }
    return r + sink(r, y);
}

// Long arms with a callee each: the later arms sit more than 1020 bytes past
// the anchor, so a byte entry (offset / 4) cannot reach them and the table
// uses halfwords.
__attribute__((noinline)) long sink0(long a, long b) { return a * 2 + b; }
__attribute__((noinline)) long sink1(long a, long b) { return a * 3 + b; }
__attribute__((noinline)) long sink2(long a, long b) { return a * 4 + b; }
__attribute__((noinline)) long sink3(long a, long b) { return a * 5 + b; }
__attribute__((noinline)) long sink4(long a, long b) { return a * 6 + b; }
__attribute__((noinline)) long sink5(long a, long b) { return a * 7 + b; }
__attribute__((noinline)) long sink6(long a, long b) { return a * 8 + b; }
__attribute__((noinline)) long sink7(long a, long b) { return a * 9 + b; }
__attribute__((noinline)) long sink8(long a, long b) { return a * 10 + b; }
__attribute__((noinline)) long sink9(long a, long b) { return a * 11 + b; }
long pickHalf(long x, long y) {
    long r;
    switch (x) {
    case 0: r = y; r = sink0(r, 0); r = sink0(r, 1); r = sink0(r, 2); r = sink0(r, 3); r = sink0(r, 4); r = sink0(r, 5); r = sink0(r, 6); r = sink0(r, 7); r = sink0(r, 8); r = sink0(r, 9); r = sink0(r, 10); r = sink0(r, 11); r = sink0(r, 12); r = sink0(r, 13); r = sink0(r, 14); r = sink0(r, 15); r = sink0(r, 16); r = sink0(r, 17); r = sink0(r, 18); r = sink0(r, 19); break;
    case 1: r = y; r = sink1(r, 0); r = sink1(r, 1); r = sink1(r, 2); r = sink1(r, 3); r = sink1(r, 4); r = sink1(r, 5); r = sink1(r, 6); r = sink1(r, 7); r = sink1(r, 8); r = sink1(r, 9); r = sink1(r, 10); r = sink1(r, 11); r = sink1(r, 12); r = sink1(r, 13); r = sink1(r, 14); r = sink1(r, 15); r = sink1(r, 16); r = sink1(r, 17); r = sink1(r, 18); r = sink1(r, 19); break;
    case 2: r = y; r = sink2(r, 0); r = sink2(r, 1); r = sink2(r, 2); r = sink2(r, 3); r = sink2(r, 4); r = sink2(r, 5); r = sink2(r, 6); r = sink2(r, 7); r = sink2(r, 8); r = sink2(r, 9); r = sink2(r, 10); r = sink2(r, 11); r = sink2(r, 12); r = sink2(r, 13); r = sink2(r, 14); r = sink2(r, 15); r = sink2(r, 16); r = sink2(r, 17); r = sink2(r, 18); r = sink2(r, 19); break;
    case 3: r = y; r = sink3(r, 0); r = sink3(r, 1); r = sink3(r, 2); r = sink3(r, 3); r = sink3(r, 4); r = sink3(r, 5); r = sink3(r, 6); r = sink3(r, 7); r = sink3(r, 8); r = sink3(r, 9); r = sink3(r, 10); r = sink3(r, 11); r = sink3(r, 12); r = sink3(r, 13); r = sink3(r, 14); r = sink3(r, 15); r = sink3(r, 16); r = sink3(r, 17); r = sink3(r, 18); r = sink3(r, 19); break;
    case 4: r = y; r = sink4(r, 0); r = sink4(r, 1); r = sink4(r, 2); r = sink4(r, 3); r = sink4(r, 4); r = sink4(r, 5); r = sink4(r, 6); r = sink4(r, 7); r = sink4(r, 8); r = sink4(r, 9); r = sink4(r, 10); r = sink4(r, 11); r = sink4(r, 12); r = sink4(r, 13); r = sink4(r, 14); r = sink4(r, 15); r = sink4(r, 16); r = sink4(r, 17); r = sink4(r, 18); r = sink4(r, 19); break;
    case 5: r = y; r = sink5(r, 0); r = sink5(r, 1); r = sink5(r, 2); r = sink5(r, 3); r = sink5(r, 4); r = sink5(r, 5); r = sink5(r, 6); r = sink5(r, 7); r = sink5(r, 8); r = sink5(r, 9); r = sink5(r, 10); r = sink5(r, 11); r = sink5(r, 12); r = sink5(r, 13); r = sink5(r, 14); r = sink5(r, 15); r = sink5(r, 16); r = sink5(r, 17); r = sink5(r, 18); r = sink5(r, 19); break;
    case 6: r = y; r = sink6(r, 0); r = sink6(r, 1); r = sink6(r, 2); r = sink6(r, 3); r = sink6(r, 4); r = sink6(r, 5); r = sink6(r, 6); r = sink6(r, 7); r = sink6(r, 8); r = sink6(r, 9); r = sink6(r, 10); r = sink6(r, 11); r = sink6(r, 12); r = sink6(r, 13); r = sink6(r, 14); r = sink6(r, 15); r = sink6(r, 16); r = sink6(r, 17); r = sink6(r, 18); r = sink6(r, 19); break;
    case 7: r = y; r = sink7(r, 0); r = sink7(r, 1); r = sink7(r, 2); r = sink7(r, 3); r = sink7(r, 4); r = sink7(r, 5); r = sink7(r, 6); r = sink7(r, 7); r = sink7(r, 8); r = sink7(r, 9); r = sink7(r, 10); r = sink7(r, 11); r = sink7(r, 12); r = sink7(r, 13); r = sink7(r, 14); r = sink7(r, 15); r = sink7(r, 16); r = sink7(r, 17); r = sink7(r, 18); r = sink7(r, 19); break;
    case 8: r = y; r = sink8(r, 0); r = sink8(r, 1); r = sink8(r, 2); r = sink8(r, 3); r = sink8(r, 4); r = sink8(r, 5); r = sink8(r, 6); r = sink8(r, 7); r = sink8(r, 8); r = sink8(r, 9); r = sink8(r, 10); r = sink8(r, 11); r = sink8(r, 12); r = sink8(r, 13); r = sink8(r, 14); r = sink8(r, 15); r = sink8(r, 16); r = sink8(r, 17); r = sink8(r, 18); r = sink8(r, 19); break;
    case 9: r = y; r = sink9(r, 0); r = sink9(r, 1); r = sink9(r, 2); r = sink9(r, 3); r = sink9(r, 4); r = sink9(r, 5); r = sink9(r, 6); r = sink9(r, 7); r = sink9(r, 8); r = sink9(r, 9); r = sink9(r, 10); r = sink9(r, 11); r = sink9(r, 12); r = sink9(r, 13); r = sink9(r, 14); r = sink9(r, 15); r = sink9(r, 16); r = sink9(r, 17); r = sink9(r, 18); r = sink9(r, 19); break;
    default: r = -2; break;
    }
    return r + sink(r, y);
}
