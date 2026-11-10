// A C dylib whose segments map to the file at different slides: zero fill
// ends __DATA (slidsegments_zerofill.s), then build.sh moves `__data` into a
// __DATA_DIRTY segment after it and adds a __FONT_DATA segment of raw bytes
// (`-sectcreate`). Both are slid: VM offset = file offset + 0x870000.
// __DATA_DIRTY,__data holds rebased pointers (`table`), so it has fixup
// chains, whose starts give the segment's offset in memory, not in the file.
// __FONT_DATA holds no fixups and no metadata; code reaches it by address
// only.
// See slidsegments.swift.
// With SLIDSEGMENTS_FLAT the zero fill is left out and one slide remains:
// the twin the tests compare this image's renders with.
#ifdef SLIDSEGMENTS_FLAT
static char slidsegments_zerofill[1] = { 1 };
#else
extern char slidsegments_zerofill[];
#endif

static int one(void) { return 1; }
static int two(void) { return 2; }

int (*table[])(void) = { one, two };
char *zero_fill = slidsegments_zerofill;

int call(int index) { return table[index & 1](); }
// A load from a fixed slot of `table`, which a listing names by the slot's
// fixup: MachOKit walks __DATA_DIRTY's chains to find it.
int first(void) { return table[0](); }
