# Pinned source citation receipt

All eight audit files were present at validation. Checked 269 Swift and
LLVM/Clang blob citations covering 95 distinct repository/commit/path tuples,
using local git objects at the exact cited commits. Every cited path exists and
the cited line anchors are in range except report 03's Coro.h range L15–99.
The pinned file ends at L93. The exported report now uses L15–93. Citation counts in report
order are 22, 40, 33, 26, 45, 41, 32 and 30. This is a source citation check.

Machine-rule spot check confirmed the Darwin special register assignments
(x8/x15/x20–x23), SwiftError and SwiftTail mask deletions, and narrow Darwin
stack slots and split i128 shadow behavior in AArch64CallingConvention.td.
M02 and M07 report proof limits as source risks. No new incorrect machine
rendering or native result was measured. No builds or tests ran in this check.
