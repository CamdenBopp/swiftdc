// 0x870000 bytes of zero fill at the end of __DATA: vmsize > filesize, so
// every segment after __DATA has a larger VM offset than file offset.
// See slidsegments.swift.
.zerofill __DATA,__bigzero,_slidsegments_zerofill,0x86f000,4
.globl _slidsegments_zerofill
