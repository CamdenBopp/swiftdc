/* Sinks that end the function without a `ret`, placed by the structurer's
   drain right above a detached labelled block. Each loop's "else" arm leaves
   the function, the loop's normal exit leaves it another way, and nothing
   ever runs after either.

   s9: `b B` and `b C` are tail calls. True behaviour: after C() the function
       is over; B() runs only from the loop's else arm.
   v9: `b Q` twice, a tail call whose result is the function's result.
   i9: `br x?` through the function pointer f: an indirect tail call.
   n9: `bl abort` with no instruction after it in the function.
   t9: B() then `brk`: a trap after a statement. */
#include <stdlib.h>
extern void A(void); extern void B(void); extern void C(void);
extern long P(long); extern long Q(long);
void s9(long a) { while (P(a)) { if (P(a+1)) { A(); } else { B(); return; } a++; } C(); }
long v9(long a) { while (P(a)) { if (P(a+1)) { A(); } else { return Q(a); } a++; } return Q(a + 7); }
void i9(long a, void (*f)(void)) { while (P(a)) { if (P(a+1)) { A(); } else { f(); return; } a++; } C(); }
void n9(long a) { while (P(a)) { if (P(a+1)) { A(); } else { abort(); } a++; } C(); }
void t9(long a) { while (P(a)) { if (P(a+1)) { A(); } else { B(); __builtin_trap(); } a++; } C(); }
