// A chained bind whose import carries a 64-bit addend with the top bit set.
// The direct retain/release runtime binds its mask this way
// (`__swift_retainRelease_slowpath_mask_v1 + 0x8000000000000000`), and the
// linker stores it as a DYLD_CHAINED_IMPORT_ADDEND64 entry. True behaviour:
// `_read_mask` loads the bound pointer and returns it; `_keep` retains its
// argument through an ordinary stub, which is what makes the fixup table
// get read.
        .text
        .globl _read_mask
        .p2align 2
_read_mask:
        adrp x8, _mask_slot@PAGE
        ldr x0, [x8, _mask_slot@PAGEOFF]
        ret

        .globl _keep
        .p2align 2
_keep:
        b _objc_retain

        .data
        .p2align 3
_mask_slot:
        .quad _malloc + 0x8000000000000000
