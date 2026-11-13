// Switch shapes: a dense switch with a default (jump table at -O1 and up),
// a sparse switch (compare tree), a switch inside a loop, and fallthrough.
#include <stdint.h>
// sw_based: the guard `sub w8, w0, #10; cmp w8, #6; b.hi` is unsigned.
// EXPECT structured O1,O2,Os _sw_based :: - 10) & 0xffffffff) >ᵁ 6)
// FORBID structured * _sw_based :: re:- 10\) & 0xffffffff\) (>|>=|<|<=) 6\)
// sw_sparse: the tree splits on a signed `b.le` at 99 and tests -5 by cmn.
// EXPECT structured O1,O2,Os _sw_sparse :: >>ˢ 32) <= 99)
// EXPECT structured O1,O2,Os _sw_sparse :: == -5)
// FORBID structured * _sw_sparse :: <=ᵁ 99
// sw_fall at -O0 is `subs w8, w8, #N; b.eq` per case; case 1 is arg0 == 1
// (lab proves it), as cases 2..6 render.
// EXPECT structured O0 _sw_fall :: (arg0 & 0xffffffff) == 1)
// EXPECT structured O0 _sw_calls :: (arg0 & 0xffffffff) == 1)
// sw_loop: `cmp w8, #0x61; b.le L; ...; L: b.ne` reuses the flags of the
// cmp: the test is w8 != 0x61 (or `?`), never a half-printed condition.
// FORBID structured * _sw_loop :: (cond !=)
// EXPECT structured O1,O2,Os _sw_loop :: w8 <= 0x61
extern void sink(int);

// Dense 0..7 with a default: `sub; cmp #7; b.hi default; ldrsw/adr; br`.
// TRUE: k=0→10, 1→11, 2→13, 3→17, 4→19, 5→23, 6→29, 7→31, else -1.
// The guard is unsigned (b.hi), so negative k takes the default.
int sw_dense(int k) {
  switch (k) {
    case 0: return 10; case 1: return 11; case 2: return 13; case 3: return 17;
    case 4: return 19; case 5: return 23; case 6: return 29; case 7: return 31;
    default: return -1;
  }
}

// Dense with calls in each arm, so the table targets real blocks, not a
// value lookup. TRUE: k=1 sink(100), 2 sink(200), 3 sink(300), 4 sink(400),
// 5 sink(500), 6 sink(600), else sink(-7).
void sw_calls(int k) {
  switch (k) {
    case 1: sink(100); break; case 2: sink(200); break; case 3: sink(300); break;
    case 4: sink(400); break; case 5: sink(500); break; case 6: sink(600); break;
    default: sink(-7); break;
  }
}

// Sparse: a compare tree. TRUE: 3→1, 100→2, 1000→3, -5→4, 77777→5, else 0.
int sw_sparse(int k) {
  switch (k) {
    case 3: return 1; case 100: return 2; case 1000: return 3;
    case -5: return 4; case 77777: return 5; default: return 0;
  }
}

// Fallthrough: case 1 adds 1, then 2 adds 10, then 3 adds 100; 4 alone 1000.
// TRUE: k=1→111, 2→110, 3→100, 4→1000, else 0 (plus the base x).
int sw_fall(int k, int x) {
  switch (k) {
    case 1: x += 1;
    case 2: x += 10;
    case 3: x += 100; break;
    case 4: x += 1000; break;
    case 5: sink(x); x ^= 5; break;
    case 6: sink(x + 1); x ^= 6; break;
  }
  return x;
}

// A switch in a loop: each byte classifies, the loop accumulates.
// TRUE: 'a'→+1, 'b'→+2, 'c'→+4, 'd'→+8, 'e'→+16, 'f'→sink(i) and continue,
// 0 ends the loop, else +100.
int sw_loop(const unsigned char *s) {
  int acc = 0;
  for (int i = 0;; i++) {
    switch (s[i]) {
      case 0: return acc;
      case 'a': acc += 1; break;
      case 'b': acc += 2; break;
      case 'c': acc += 4; break;
      case 'd': acc += 8; break;
      case 'e': acc += 16; break;
      case 'f': sink(i); continue;
      default: acc += 100; break;
    }
  }
}

// Unsigned selector with a low base: cases 10..16, `sub w8, w0, #10; cmp w8, #6`.
// TRUE: 10→sink(1) ... 16→sink(7); otherwise nothing.
void sw_based(unsigned k) {
  switch (k) {
    case 10: sink(1); break; case 11: sink(2); break; case 12: sink(3); break;
    case 13: sink(4); break; case 14: sink(5); break; case 15: sink(6); break;
    case 16: sink(7); break;
  }
}
