// A dylib with data and no code: `__text` is 0 bytes, yet the linker still
// writes LC_FUNCTION_STARTS, eight bytes of zeros. True behaviour: the first
// zero ends the list, so the image declares no function (`dyld_info
// -function_starts` lists none), and a whole decode finds nothing because
// there is nothing.
int noCodeValue = 7;
