# Totals, recomputed by Tools/ghidra-compare/tally.py

Interface is correct / wrong / declined; body is correct / partial / wrong / declined.

| area | builds | Ghidra interface | swiftdc interface | Ghidra body | swiftdc body |
|---|---|---|---|---|---|
| noncopyable | 126 | 73 / 28 / 25 | 53 / 1 / 72 | 73 / 12 / 39 / 2 | 32 / 38 / 6 / 50 |
| property wrappers | 111 | 72 / 22 / 17 | 49 / 1 / 61 | 70 / 10 / 27 / 4 | 26 / 45 / 14 / 26 |
| actors | 191 | 72 / 21 / 98 | 133 / 6 / 52 | 77 / 71 / 43 / 0 | 30 / 114 / 18 / 29 |
| strings | 268 | 241 / 8 / 19 | 228 / 3 / 37 | 38 / 101 / 127 / 2 | 107 / 119 / 25 / 17 |
| collections | 175 | 144 / 29 / 2 | 175 / 0 / 0 | 110 / 7 / 58 / 0 | 3 / 114 / 43 / 15 |
| generics, packs | 206 | 125 / 21 / 60 | 157 / 0 / 49 | 62 / 49 / 81 / 14 | 29 / 69 / 44 / 64 |
| Objective-C runtime | 389 | 382 / 5 / 2 | 381 / 0 / 8 | 226 / 62 / 101 / 0 | 177 / 171 / 25 / 16 |
| integer arithmetic | 398 | 358 / 34 / 6 | 283 / 0 / 115 | 369 / 0 / 23 / 6 | 221 / 30 / 36 / 111 |
| switch lowering | 133 | 112 / 6 / 15 | 69 / 61 / 3 | 60 / 18 / 54 / 1 | 12 / 29 / 66 / 26 |
| linker transforms | 102 | 58 / 37 / 6 | 22 / 7 / 73 | 49 / 0 / 47 / 6 | 9 / 41 / 12 / 40 |
| globals | 153 | 141 / 8 / 4 | 101 / 20 / 32 | 103 / 34 / 15 / 1 | 23 / 76 / 24 / 30 |
| frames, sanitizers | 349 | 253 / 41 / 55 | 83 / 257 / 9 | 177 / 18 / 154 / 0 | 2 / 66 / 281 / 0 |
| **total** | **2,601** | **2031 / 260 / 309** | **1734 / 356 / 511** | **1414 / 382 / 769 / 36** | **671 / 912 / 594 / 424** |

| | swiftdc | Ghidra 12.2 |
|---|---|---|
| Swift areas (1,077 builds): interface wrong | 1% (11) | 12% (129) |
| Swift areas: body wrong | 14% (150) | 35% (375) |
| Swift areas: body correct | 21% | 40% |
| Swift areas: body partial or declined | 65% | 25% |
| All areas (2,601 builds): interface correct | 67% | 78% |
| All areas: interface wrong | 14% | 10% |
| All areas: body correct | 26% | 54% |
| All areas: body wrong | 23% | 30% |
