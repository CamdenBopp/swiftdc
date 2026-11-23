// Switch lowerings, C. True behaviour stated per function.
extern int ext(int);
extern int e0(void),e1(void),e2(void),e3(void),e4(void),e5(void),e6(void),e7(void);
// dense with bias: x in 10..17 -> distinct calls; default returns -1. Table index = x-10.
int dense_bias(int x) {
  switch (x) {
  case 10: return e0();
  case 11: return e1();
  case 12: return e2();
  case 13: return e3();
  case 14: return e4();
  case 15: return e5();
  case 16: return e6();
  case 17: return e7();
  default: return -1;
  }
}
// constant-return switch: lowered to a lookup table. x=0->7,1->3,2->9,3->1,4->8,5->2 ; else 0
int lookup(unsigned x) {
  switch (x) {
  case 0: return 7; case 1: return 3; case 2: return 9;
  case 3: return 1; case 4: return 8; case 5: return 2;
  default: return 0;
  }
}
// sparse: binary search. 5->ext(1) 100->ext(2) 1000->ext(3) 7777->ext(4) 50000->ext(5) else 0
int sparse(int x) {
  switch (x) {
  case 5: return ext(1);
  case 100: return ext(2);
  case 1000: return ext(3);
  case 7777: return ext(4);
  case 50000: return ext(5);
  default: return 0;
  }
}
// bit-test: x in {1,3,5,8,13} -> ext(9) ; x in {2,4} -> ext(8); else ext(0)
int bittest(int x) {
  switch (x) {
  case 1: case 3: case 5: case 8: case 13: return ext(9);
  case 2: case 4: return ext(8);
  default: return ext(0);
  }
}
// duplicate targets: 0,2,4 -> ext(20); 1,3 -> ext(31); 5 -> ext(55); 6 -> ext(66); else ext(-1)
int duptargets(int x) {
  switch (x) {
  case 0: case 2: case 4: return ext(20);
  case 1: case 3: return ext(31);
  case 5: return ext(55);
  case 6: return ext(66);
  default: return ext(-1);
  }
}
// switch in loop with continue/break: sums; op 0: acc+=1, 1: continue (skip), 2: break out of loop, 3: acc*=2, 4: acc-=3
int loopsw(const int *ops, int n) {
  int acc = 0;
  for (int i = 0; i < n; i++) {
    switch (ops[i]) {
    case 0: acc += 1; break;
    case 1: continue;
    case 2: goto out;
    case 3: acc *= 2; break;
    case 4: acc -= 3; break;
    default: acc = ext(acc); break;
    }
    acc ^= i;
  }
out:
  return acc;
}
// computed goto: op codes 0 inc, 1 dbl, 2 neg, 3 halt; returns accumulator
int interp(const unsigned char *code) {
  static void *labels[] = { &&inc, &&dbl, &&neg, &&halt };
  int acc = 1;
  goto *labels[*code++];
inc: acc += 1; goto *labels[*code++];
dbl: acc *= 2; goto *labels[*code++];
neg: acc = -acc; goto *labels[*code++];
halt: return acc;
}
// large table, 2-byte entries: 300-case switch would be big; use cases with bodies far apart
#define C(n) case n: r = ext(n*3+1); break;
int wide(int x) {
  int r = 0;
  switch (x) {
  C(0) C(1) C(2) C(3) C(4) C(5) C(6) C(7) C(8) C(9) C(10) C(11) C(12) C(13) C(14) C(15)
  C(16) C(17) C(18) C(19) C(20) C(21) C(22) C(23) C(24) C(25) C(26) C(27) C(28) C(29) C(30) C(31)
  C(32) C(33) C(34) C(35) C(36) C(37) C(38) C(39) C(40) C(41) C(42) C(43) C(44) C(45) C(46) C(47)
  C(48) C(49) C(50) C(51) C(52) C(53) C(54) C(55) C(56) C(57) C(58) C(59) C(60) C(61) C(62) C(63)
  C(64) C(65) C(66) C(67) C(68) C(69) C(70) C(71) C(72) C(73) C(74) C(75) C(76) C(77) C(78) C(79)
  }
  return r;
}
