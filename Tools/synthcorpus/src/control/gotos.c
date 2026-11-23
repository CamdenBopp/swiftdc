// goto-heavy C and computed returns with several exits.
extern int check(int);
extern void sink(int);
extern void cleanup(int);
// ladder: two cleanup calls, cleanup(2) falling into cleanup(1).
// EXPECT structured * _ladder :: re:cleanup\(…\)(.|\n)*cleanup\(…\)
// classify: x < 0 is a sign test; 10 and 100 bound the middle arms.
// EXPECT structured O1,O2,Os _classify :: (((arg0 << 32) >>ˢ 32) < 0)
// EXPECT structured O2,Os _classify :: (arg0 & 0xffffffff) >ᵁ 99)
// EXPECT structured O0 _classify :: >>ˢ 32) >= 100)
// retry -O1: `add w19, w19, #1; cmp w19, #5; b.ne`: the cmp reads the new w19.
// EXPECT structured O1 _retry :: if (w19 != 5)
// into_loop (-O1 up): after sink(1), sink(2) the code returns to check(9)
// and leaves when it is 0. A `while (true) { sink; sink }` with no test
// is an infinite loop the binary does not have.
// FORBID structured O1,O2,Os _into_loop :: re:while \(true\) \{\n\s+sink\(…\)\n\s+sink\(…\)\n\s+\}

// The classic cleanup ladder. TRUE: returns 0 on success; on check(1)==0
// returns -1 with no cleanup; check(2)==0 → cleanup(1), -2; check(3)==0 →
// cleanup(2), cleanup(1), -3.
int ladder(void) {
  int rc;
  if (!check(1)) { rc = -1; goto out; }
  if (!check(2)) { rc = -2; goto undo1; }
  if (!check(3)) { rc = -3; goto undo2; }
  sink(0);
  return 0;
undo2: cleanup(2);
undo1: cleanup(1);
out:   return rc;
}

// A goto loop with a retry. TRUE: calls check(n) for n=0,1,2,... until it
// returns nonzero or n reaches 5; returns n on success, -1 after 5 tries.
int retry(void) {
  int n = 0;
again:
  if (check(n)) return n;
  if (++n < 5) goto again;
  return -1;
}

// Several exits computed from the input. TRUE: x<0 → -1; x==0 → 0;
// x<10 → x*2; x<100 → x+1000; else check(x).
int classify(int x) {
  if (x < 0) return -1;
  if (x == 0) return 0;
  if (x < 10) return x * 2;
  if (x < 100) return x + 1000;
  return check(x);
}

// Jumping into a loop body. TRUE: if start, sink(1), sink(2) run first;
// then (or first, when start is 0) check(9): 0 returns, else sink(1), sink(2) again.
void into_loop(int start) {
  if (start) goto mid;
top:
  if (!check(9)) return;
mid:
  sink(1);
  sink(2);
  goto top;
}
