// MOVI's arrangement and shift decide the bits: `movi v0.4s, #0, msl #8` puts
// 0xff in every element. `// EXPECT name word` is each function's true result,
// which the test also checks by running it.
.text
nop
// EXPECT mslZero8Low 000000ff000000ff
.globl _$s9MoviProbe11mslZero8Lows6UInt64VyF
_$s9MoviProbe11mslZero8Lows6UInt64VyF:
    movi v0.4s, #0, msl #8
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT mslZero8High 000000ff000000ff
.globl _$s9MoviProbe12mslZero8Highs6UInt64VyF
_$s9MoviProbe12mslZero8Highs6UInt64VyF:
    movi v0.4s, #0, msl #8
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT mslZero16Low 0000ffff0000ffff
.globl _$s9MoviProbe12mslZero16Lows6UInt64VyF
_$s9MoviProbe12mslZero16Lows6UInt64VyF:
    movi v0.4s, #0, msl #16
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT mslZero16High 0000ffff0000ffff
.globl _$s9MoviProbe13mslZero16Highs6UInt64VyF
_$s9MoviProbe13mslZero16Highs6UInt64VyF:
    movi v0.4s, #0, msl #16
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT mslOne8Low 000001ff000001ff
.globl _$s9MoviProbe10mslOne8Lows6UInt64VyF
_$s9MoviProbe10mslOne8Lows6UInt64VyF:
    movi v0.4s, #1, msl #8
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT mslOne8High 000001ff000001ff
.globl _$s9MoviProbe11mslOne8Highs6UInt64VyF
_$s9MoviProbe11mslOne8Highs6UInt64VyF:
    movi v0.4s, #1, msl #8
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT mslOne16Low 0001ffff0001ffff
.globl _$s9MoviProbe11mslOne16Lows6UInt64VyF
_$s9MoviProbe11mslOne16Lows6UInt64VyF:
    movi v0.4s, #1, msl #16
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT mslOne16High 0001ffff0001ffff
.globl _$s9MoviProbe12mslOne16Highs6UInt64VyF
_$s9MoviProbe12mslOne16Highs6UInt64VyF:
    movi v0.4s, #1, msl #16
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT byteSevenLow 0707070707070707
.globl _$s9MoviProbe12byteSevenLows6UInt64VyF
_$s9MoviProbe12byteSevenLows6UInt64VyF:
    movi v0.16b, #7
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT byteSevenHigh 0707070707070707
.globl _$s9MoviProbe13byteSevenHighs6UInt64VyF
_$s9MoviProbe13byteSevenHighs6UInt64VyF:
    movi v0.16b, #7
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT halfShiftLow 0700070007000700
.globl _$s9MoviProbe12halfShiftLows6UInt64VyF
_$s9MoviProbe12halfShiftLows6UInt64VyF:
    movi v0.8h, #7, lsl #8
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT halfShiftHigh 0700070007000700
.globl _$s9MoviProbe13halfShiftHighs6UInt64VyF
_$s9MoviProbe13halfShiftHighs6UInt64VyF:
    movi v0.8h, #7, lsl #8
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT wordShiftLow 0700000007000000
.globl _$s9MoviProbe12wordShiftLows6UInt64VyF
_$s9MoviProbe12wordShiftLows6UInt64VyF:
    movi v0.4s, #7, lsl #24
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT wordShiftHigh 0700000007000000
.globl _$s9MoviProbe13wordShiftHighs6UInt64VyF
_$s9MoviProbe13wordShiftHighs6UInt64VyF:
    movi v0.4s, #7, lsl #24
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT mask64Low ff0000ff0000ffff
.globl _$s9MoviProbe9mask64Lows6UInt64VyF
_$s9MoviProbe9mask64Lows6UInt64VyF:
    movi v0.2d, #0xff0000ff0000ffff
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT mask64High ff0000ff0000ffff
.globl _$s9MoviProbe10mask64Highs6UInt64VyF
_$s9MoviProbe10mask64Highs6UInt64VyF:
    movi v0.2d, #0xff0000ff0000ffff
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT zeroLow 0000000000000000
.globl _$s9MoviProbe7zeroLows6UInt64VyF
_$s9MoviProbe7zeroLows6UInt64VyF:
    movi v0.2d, #0
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #0]
    add sp, sp, #16
    ret

// EXPECT zeroHigh 0000000000000000
.globl _$s9MoviProbe8zeroHighs6UInt64VyF
_$s9MoviProbe8zeroHighs6UInt64VyF:
    movi v0.2d, #0
    sub sp, sp, #16
    str q0, [sp]
    ldr x0, [sp, #8]
    add sp, sp, #16
    ret

// EXPECT halfWidthLow 0707070707070707
.globl _$s9MoviProbe12halfWidthLows6UInt64VyF
_$s9MoviProbe12halfWidthLows6UInt64VyF:
    movi v0.8b, #7
    sub sp, sp, #16
    str d0, [sp]
    ldr x0, [sp]
    add sp, sp, #16
    ret
