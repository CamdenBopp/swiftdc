// A Swift symbol past __DATA's file bytes, spelled as a metadata instantiation
// cache: it has no file offset, and the one it would have had lies with the
// bytes stored after __DATA. Linked after slidsegments_zerofill.s, into the
// executable only. See slidsegments.swift.
.zerofill __DATA,__bigzero,"_$s12SlidSegments4TailCMI",0x1000,4
.globl "_$s12SlidSegments4TailCMI"
