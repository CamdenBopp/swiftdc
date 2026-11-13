// Jump-table switches, C. Case bodies call distinct externs f<N>, where N is
// the case value (n<N> for negative N); default calls fdef. Result+1 is returned.
#define D(n) extern int f##n(void);
D(0) D(1) D(2) D(3) D(4) D(5) D(6) D(7) D(8) D(9) D(10) D(11) D(12) D(13) D(14) D(15) D(16) D(17) D(18) D(19) D(20) D(21) D(22) D(23) D(24) D(25)
D(100) D(101) D(102) D(103) D(104) D(105) D(106) D(107) D(108) D(109) D(110) D(111)
extern int fdef(void), n1(void), n2(void), n3(void), n4(void);
#define C(n) case n: r = f##n(); break;
// bias 100: x in 100..111 -> f<x>, else fdef. Table index = x - 100.
int bias(int x) {
  int r;
  switch (x) { C(100) C(101) C(102) C(103) C(104) C(105) C(106) C(107) C(108) C(109) C(110) C(111)
  default: r = fdef(); }
  return r + 1;
}
// holes and shared bodies: 0,2 -> f0 ; 1 -> f1 ; 3,8 -> fdef (holes) ; 4,6 -> f4 ; 5 -> f5 ; 7 -> f7 ; 9..13 -> f<x>; else fdef
int holes(int x) {
  int r;
  switch (x) {
  case 0: case 2: r = f0(); break;
  C(1)
  case 4: case 6: r = f4(); break;
  C(5) C(7) C(9) C(10) C(11) C(12) C(13)
  default: r = fdef(); }
  return r + 1;
}
// fallthrough: 0 -> f0,f1,f2 ; 1 -> f1,f2 ; 2 -> f2 ; 3..11 -> f<x> only ; else nothing. returns 0.
int fall(int x) {
  int r = 0;
  switch (x) {
  case 0: f0();
  case 1: f1();
  case 2: f2(); break;
  C(3) C(4) C(5) C(6) C(7) C(8) C(9) C(10) C(11)
  }
  return r;
}
// switch in a loop: 0 -> f0 ; 1 -> continue (skips acc++) ; 2 -> leave loop ;
// 3..12 -> f<x> ; else fdef ; then acc++. returns acc.
int inloop(const int *ops, int n) {
  int acc = 0, r;
  for (int i = 0; i < n; i++) {
    switch (ops[i]) {
    case 0: f0(); break;
    case 1: continue;
    case 2: goto out;
    C(3) C(4) C(5) C(6) C(7) C(8) C(9) C(10) C(11) C(12)
    default: fdef(); break;
    }
    acc++;
  }
out:
  return acc;
}
// negative bias: -4..-1 -> n4,n3,n2,n1 ; 0..7 -> f<x> ; else fdef
int negbias(int x) {
  int r;
  switch (x) {
  case -4: r = n4(); break; case -3: r = n3(); break; case -2: r = n2(); break; case -1: r = n1(); break;
  C(0) C(1) C(2) C(3) C(4) C(5) C(6) C(7)
  default: r = fdef(); }
  return r + 1;
}
// unsigned char subject 'a'(97)..'l'(108): 'a'+k -> f<k>; else fdef
int chars(unsigned char c) {
  int r;
  switch (c) {
  case 'a': r=f0(); break; case 'b': r=f1(); break; case 'c': r=f2(); break; case 'd': r=f3(); break;
  case 'e': r=f4(); break; case 'f': r=f5(); break; case 'g': r=f6(); break; case 'h': r=f7(); break;
  case 'i': r=f8(); break; case 'j': r=f9(); break; case 'k': r=f10(); break; case 'l': r=f11(); break;
  default: r = fdef(); }
  return r + 1;
}
// 64-bit subject, values 0..15
long wide64(unsigned long x) {
  int r;
  switch (x) { C(0) C(1) C(2) C(3) C(4) C(5) C(6) C(7) C(8) C(9) C(10) C(11) C(12) C(13) C(14) C(15)
  default: r = fdef(); }
  return r + 1;
}
