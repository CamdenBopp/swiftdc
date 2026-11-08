// Loops inside catch handlers. A handler is entered only by the unwinder, so
// no CFG edge reaches it from the function's entry, and these loops never
// exit: their blocks tie for immediate post-dominator. Each function is an
// independent chance for hash order to leak into the structured output.
extern void g(int);
extern void h(int);
extern int k(int);

void spin1(int n) {
    if (n > 3) g(n); else h(n);
    try { g(n + 1); } catch (...) { for (;;) { if (k(n)) h(n); else g(n); } }
}
void spin2(int n) {
    if (n > 5) h(n); else g(n);
    try { h(n + 2); } catch (...) { for (;;) { if (k(n + 1)) g(n); else h(n); } }
}
void spin3(int n) {
    if (n & 1) g(n); else h(n);
    try { g(n * 3); } catch (...) { for (;;) { if (k(n)) g(n + 1); else h(n + 1); } }
}
void spin4(int n) {
    if (n < 0) h(-n); else g(n);
    try { k(n); } catch (...) { for (;;) { if (k(n * 2)) h(n * 2); else g(n * 2); } }
}
