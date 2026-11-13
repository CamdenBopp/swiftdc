// tbz/tbnz on bits other than 0, and bit tests by mask.
extern void sink(int);
// EXPECT structured * _bit5_63 :: (arg0 & 32) != 0)
// FORBID structured * _bit5_63 :: re:arg0 & (16|64)\)
// EXPECT structured O1,O2,Os _bit5_63 :: if (arg0 < 0)
// EXPECT structured * _sign32 :: < 0)
// FORBID structured * _sign32 :: re:(>|<|>=|<=)ᵁ 0\)
// EXPECT structured * _mask30 :: (arg0 & 48)
// each_bit (-O1 up): `cmp w19, #2; lsr w19, w19, #1; b.lo/b.hs`. The flags
// read w19 BEFORE the shift; at the branch w19 holds the shifted value, so
// `w19 <ᵁ 2` there is one step off (true condition: shifted w19 == 0).
// FORBID structured O1,O2,Os _each_bit :: re:w19 (<ᵁ|>=ᵁ) 2\)

// TRUE: sink(5) iff bit 5 of x is set; sink(6) iff bit 63 is clear.
void bit5_63(unsigned long x) {
  if (x & (1UL << 5)) sink(5);
  if (!(x & (1UL << 63))) sink(6);
}

// Sign test on a 32-bit value: `tbnz w0, #31`. TRUE: sink(7) iff x < 0.
void sign32(int x) { if (x < 0) sink(7); }

// Bit 12 drives the return. TRUE: returns 40 if bit 12 set, else 41.
int bit12(unsigned x) { if (x & 0x1000) return 40; return 41; }

// Loop over set bits of a mask: TRUE: sink(i) for each set bit i in 0..31,
// with a tbz on bit 0 of the shifted value.
void each_bit(unsigned m) {
  for (int i = 0; m; i++, m >>= 1)
    if (m & 1) sink(i);
}

// Mask test that is not a single bit: `tst w0, #0x30`. TRUE: sink(8) iff
// (x & 0x30) != 0.
void mask30(unsigned x) { if (x & 0x30) sink(8); }

// Both bits: TRUE: sink(9) iff (x & 0x41) == 0x41.
void both_bits(unsigned x) { if ((x & 0x41) == 0x41) sink(9); }
