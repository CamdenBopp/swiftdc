// Jump-table switches, C. Each case calls a distinct function eN (named for its
// case value) then the result +1 is returned; default calls edef.
extern int e10(void),e11(void),e12(void),e13(void),e14(void),e15(void),e16(void),e17(void),edef(void);
extern int e0(void),e1(void),e2(void),e3(void),e4(void),e5(void),e6(void);
// biased dense: index = x-10, x in 10..17 -> e<x>; else edef
int bias(int x) {
  int r;
  switch (x) {
  case 10: r = e10(); break; case 11: r = e11(); break; case 12: r = e12(); break;
  case 13: r = e13(); break; case 14: r = e14(); break; case 15: r = e15(); break;
  case 16: r = e16(); break; case 17: r = e17(); break;
  default: r = edef(); break;
  }
  return r + 1;
}
// holes + duplicates: 0,2 -> e0 ; 1 -> e1 ; 3 -> default ; 4,6 -> e4 ; 5 -> e5 ; 7 -> e6; else edef
int holes(int x) {
  int r;
  switch (x) {
  case 0: case 2: r = e0(); break;
  case 1: r = e1(); break;
  case 4: case 6: r = e4(); break;
  case 5: r = e5(); break;
  case 7: r = e6(); break;
  default: r = edef(); break;
  }
  return r + 1;
}
// fallthrough: 0 -> e0,e1,e2 ; 1 -> e1,e2 ; 2 -> e2 ; 3 -> e3 ; 4 -> e4 ; else nothing. returns 0.
int fall(int x) {
  switch (x) {
  case 0: e0();
  case 1: e1();
  case 2: e2(); break;
  case 3: e3(); break;
  case 4: e4(); break;
  }
  return 0;
}
// switch in a loop: 0 -> e0 then acc++ ; 1 -> continue (no acc++) ; 2 -> leave loop ; 3 -> e3 ; 4 -> e4 ; else edef
int inloop(const int *ops, int n) {
  int acc = 0;
  for (int i = 0; i < n; i++) {
    switch (ops[i]) {
    case 0: e0(); break;
    case 1: continue;
    case 2: goto out;
    case 3: e3(); break;
    case 4: e4(); break;
    default: edef(); break;
    }
    acc++;
  }
out:
  return acc;
}
// negative bias: x in -3..3: -3->e0 -2->e1 -1->e2 0->e3 1->e4 2->e5 3->e6 ; else edef
int negbias(int x) {
  int r;
  switch (x) {
  case -3: r = e0(); break; case -2: r = e1(); break; case -1: r = e2(); break;
  case 0: r = e3(); break; case 1: r = e4(); break; case 2: r = e5(); break; case 3: r = e6(); break;
  default: r = edef(); break;
  }
  return r + 1;
}
// unsigned char subject: 'a'..'f'
int chars(unsigned char c) {
  int r;
  switch (c) {
  case 'a': r = e0(); break; case 'b': r = e1(); break; case 'c': r = e2(); break;
  case 'd': r = e3(); break; case 'e': r = e4(); break; case 'f': r = e5(); break;
  default: r = edef(); break;
  }
  return r + 1;
}
