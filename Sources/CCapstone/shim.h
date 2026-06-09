// Bridges the Homebrew-installed Capstone C library into Swift.
// Header/lib paths come from the `capstone` pkg-config file (see Package.swift).
// Note: capstone.pc's Cflags point -I *into* the capstone/ dir, and capstone.h
// uses same-dir relative includes — so this is <capstone.h>, not <capstone/…>.
#include <capstone.h>
