// Calls to SDK C functions the binary carries no signature for (-O2). A
// call's arguments were laid out by position from the x registers the
// tracer knew, and its result was taken to be x0 whatever it returned.
// glTexCoord2f and glVertex3f take only floats (v registers) and return
// void, so with neither known drawQuad rendered
// `glEnd(glVertex3f(glTexCoord2f(...)))`: each call the next one's
// argument. strchr takes a pointer and an int, both loaded through an
// unknown pointer here, and rendered `strchr()`.
//
// True behaviour: drawQuad calls glBegin(GL_QUADS), glTexCoord2f(v[0],
// v[1]), glVertex3f(v[2], v[3], v[4]) and glEnd() in turn; drawConstant
// calls glVertex3f(1.0f, 2.0f, 0.5f); findChar returns strchr(j->s, j->c);
// flushThenNotify calls glFlush(), which returns void, then notifyDone(), an
// undeclared external whose arity nothing gives, which the void result
// in x0 must not reach as an argument. insetVertex calls
// CGRectInset, which returns a CGRect in d0-d3, and passes the inset
// rect's origin.x (d0) and height (d3) to glVertex2d: d0 is one field of the
// result, not the call itself. parseThenNotify keeps strtod's double (d0,
// saved across the call) and calls notifyDone with nothing: x0 after strtod
// is not its result. fillNull calls CGContextFillRect(NULL, rect): the
// context is in x0, the CGRect in d0-d3, so only the context is placed and
// the rect is `?`. offsetConstant calls CGRectOffset(CGRectMake(1, 2, 3,
// 4), 5, 6): the rect is d0-d3 and the offsets d4 and d5, so a layout that
// took the rect as one register would read 2.0 and 3.0 as the offsets.
#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
#include <string.h>

struct finder { const char *s; int c; };

void drawQuad(const float *v) {
    glBegin(GL_QUADS);
    glTexCoord2f(v[0], v[1]);
    glVertex3f(v[2], v[3], v[4]);
    glEnd();
}

void drawConstant(void) { glVertex3f(1.0f, 2.0f, 0.5f); }

char *findChar(struct finder *j) { return strchr(j->s, j->c); }

extern void notifyDone();
void flushThenNotify(void) { glFlush(); notifyDone(); }

void insetVertex(CGRect r) {
    CGRect s = CGRectInset(r, 0.5, 0.5);
    glVertex2d(s.origin.x, s.size.height);
}

double parseThenNotify(const char *text) {
    double r = strtod(text, 0);
    notifyDone();
    return r;
}

void fillNull(CGRect r) { CGContextFillRect(NULL, r); }

CGRect offsetConstant(void) { return CGRectOffset(CGRectMake(1, 2, 3, 4), 5, 6); }
