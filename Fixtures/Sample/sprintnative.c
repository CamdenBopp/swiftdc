// Runs the sprint fixtures natively and prints what each function did.
// SprintNativeOracleTests compares these observations with what swiftdc
// renders: a fixture's comment says what its code does, and this is the
// check that it does.
//
// One line per call: OBS <image> <case> <outcome> [key=value ...]
//   outcome is returned, threw, trapped or hung.
// A Swift function throws by returning with x21 non-zero, so a throwing
// function is called through a trampoline that clears x21, calls, and
// hands x21 back. A call that may trap or hang runs in a child process.
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

// long call_throwing(void *fn, long a0, long a1, long a2, long *error)
__attribute__((naked)) static long call_throwing(void *fn, long a0, long a1, long a2, long *error) {
    __asm__("stp x29, x30, [sp, #-48]!\n"
            "mov x29, sp\n"
            "stp x19, x21, [sp, #16]\n"
            "str x20, [sp, #32]\n"
            "mov x19, x4\n"
            "mov x9, x0\n"
            "mov x0, x1\n"
            "mov x1, x2\n"
            "mov x2, x3\n"
            "mov x21, #0\n"
            "mov x20, #0\n"
            "blr x9\n"
            "str x21, [x19]\n"
            "ldr x20, [sp, #32]\n"
            "ldp x19, x21, [sp, #16]\n"
            "ldp x29, x30, [sp], #48\n"
            "ret\n");
}

static char directory[4096];
static int observations;

static void *image(const char *name) {
    char path[4200];
    snprintf(path, sizeof path, "%s/%s", directory, name);
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "cannot load %s: %s\n", path, dlerror()); exit(2); }
    return handle;
}
static void *symbol(void *handle, const char *name) {
    void *address = dlsym(handle, name);
    if (!address) { fprintf(stderr, "no symbol %s\n", name); exit(2); }
    return address;
}

// A throwing call: returned (x21 zero) with its result, or threw.
static void throwing(const char *image, const char *test, void *fn, long a0, long a1, long a2,
                     const char *extraKey, long *extra) {
    long error = 0;
    long result = call_throwing(fn, a0, a1, a2, &error);
    observations++;
    if (error) printf("OBS %s %s threw", image, test);
    else printf("OBS %s %s returned result=%ld", image, test, result);
    if (extraKey) printf(" %s=%ld", extraKey, *extra);
    printf("\n");
}

// A call that may not return: in a child, with a one-second alarm.
static void guarded(const char *image, const char *test, long (*fn)(long, long), long a0, long a1) {
    fflush(stdout);
    int channel[2];
    if (pipe(channel)) exit(2);
    pid_t child = fork();
    if (child == 0) {
        signal(SIGALRM, SIG_DFL);
        alarm(1);
        long result = fn(a0, a1);
        write(channel[1], &result, sizeof result);
        _exit(0);
    }
    close(channel[1]);
    int status = 0;
    waitpid(child, &status, 0);
    observations++;
    long result = 0;
    if (WIFSIGNALED(status)) {
        printf("OBS %s %s %s\n", image, test, WTERMSIG(status) == SIGALRM ? "hung" : "trapped");
    } else if (read(channel[0], &result, sizeof result) == sizeof result) {
        printf("OBS %s %s returned result=%ld\n", image, test, result);
    } else {
        printf("OBS %s %s lost\n", image, test);
    }
    close(channel[0]);
}

static void plain(const char *image, const char *test, long result) {
    observations++;
    printf("OBS %s %s returned result=%ld\n", image, test, result);
}

int main(int argc, char **argv) {
    // Fixtures sit beside this executable.
    strlcpy(directory, argv[0], sizeof directory);
    char *slash = strrchr(directory, '/');
    if (slash) *slash = 0; else strlcpy(directory, ".", sizeof directory);
    setvbuf(stdout, NULL, _IOLBF, 0);

    // errorlookalike: each returns normally, whatever its callee is named.
    void *lookalike = image("libErrorLookalike.dylib");
    throwing("ErrorLookalike", "viaAllocLog", symbol(lookalike, "$s9Lookalike11viaAllocLogyS2iKF"), 1, 0, 0, NULL, NULL);
    throwing("ErrorLookalike", "viaLocalAlloc", symbol(lookalike, "$s9Lookalike13viaLocalAllocyS2iKF"), 1, 0, 0, NULL, NULL);
    throwing("ErrorLookalike", "viaWillThrowLog", symbol(lookalike, "$s9Lookalike15viaWillThrowLogyS2iKF"), 1, 0, 0, NULL, NULL);

    // hookpath: the arm without the hook throws or returns as its argument
    // is non-zero or zero. The "error" is a bare non-zero word; the hook
    // does not look inside it.
    void *hook = image("libHookPath.dylib");
    void *either = symbol(hook, "$s8HookPath6eitherySiSb_SitKF");
    void *merged = symbol(hook, "$s8HookPath6mergedySiSb_SitKF");
    void *always = symbol(hook, "$s8HookPath6alwaysySiSb_SitKF");
    throwing("HookPath", "either-hook-nonzero", either, 1, 9, 0, NULL, NULL);
    throwing("HookPath", "either-nohook-nonzero", either, 0, 9, 0, NULL, NULL);
    throwing("HookPath", "either-nohook-zero", either, 0, 0, 0, NULL, NULL);
    throwing("HookPath", "merged-hook-nonzero", merged, 1, 9, 0, NULL, NULL);
    throwing("HookPath", "merged-nohook-nonzero", merged, 0, 9, 0, NULL, NULL);
    throwing("HookPath", "merged-nohook-zero", merged, 0, 0, 0, NULL, NULL);
    throwing("HookPath", "always-nonzero", always, 0, 9, 0, NULL, NULL);

    // traptail, with and without symbols: the wrapped body may trap or loop.
    const char *tails[] = { "libTrapTail.dylib", "libTrapTail.stripped.dylib" };
    const char *tailNames[] = { "TrapTail", "TrapTail.stripped" };
    for (int index = 0; index < 2; index++) {
        void *tail = image(tails[index]);
        long (*nonZero)(long, long) = symbol(tail, "$s8TrapTail11wrapNonZeroyS2iF");
        long (*aboveThree)(long, long) = symbol(tail, "$s8TrapTail14wrapAboveThreeyS2i_SitF");
        long (*unlessNine)(long, long) = symbol(tail, "$s8TrapTail14wrapUnlessNineyS2iF");
        long (*same)(long, long) = symbol(tail, "$s8TrapTail8wrapSameyS2iF");
        guarded(tailNames[index], "wrapNonZero-5", nonZero, 5, 0);
        guarded(tailNames[index], "wrapNonZero-0", nonZero, 0, 0);
        guarded(tailNames[index], "wrapAboveThree-5-9", aboveThree, 5, 9);
        guarded(tailNames[index], "wrapAboveThree-5-2", aboveThree, 5, 2);
        guarded(tailNames[index], "wrapUnlessNine-5", unlessNine, 5, 0);
        guarded(tailNames[index], "wrapUnlessNine-9", unlessNine, 9, 0);
        guarded(tailNames[index], "wrapSame-5", same, 5, 0);
    }

    // accesstwin: a block of memory stands for the object. Its first
    // stored field is at offset 16; neither function retains it.
    void *twin = image("libAccessTwin.dylib");
    long (*acrossEnd)(long *) = symbol(twin, "$s10AccessTwin9acrossEndySiAA5MeterCF");
    long meter[4] = { 0, 0, 5, 0 };
    long difference = acrossEnd(meter);
    observations++;
    printf("OBS AccessTwin acrossEnd returned result=%ld n=%ld\n", difference, meter[2]);

    // deferthrow: the deferred store happens on the throwing path too.
    void *deferred = image("libDeferThrow.dylib");
    void *storeThenExit = symbol(deferred, "$s10DeferThrow13storeThenExityyAA6LedgerC_SitKF");
    void *plainExit = symbol(deferred, "$s10DeferThrow9plainExityyAA6LedgerC_SitKF");
    long ledger[4] = { 0, 0, 0, 0 };   // entries at 16, last at 24
    throwing("DeferThrow", "storeThenExit-3", storeThenExit, (long)ledger, 3, 0, "entries", &ledger[2]);
    ledger[2] = 0;
    throwing("DeferThrow", "storeThenExit-4", storeThenExit, (long)ledger, 4, 0, "entries", &ledger[2]);
    observations++;
    printf("OBS DeferThrow storeThenExit-4-last returned result=%ld\n", ledger[3]);
    throwing("DeferThrow", "plainExit-3", plainExit, (long)ledger, 3, 0, NULL, NULL);
    throwing("DeferThrow", "plainExit-4", plainExit, (long)ledger, 4, 0, NULL, NULL);

    // int64fields and optionsubset: scalars in, a scalar out. A struct of
    // integer fields is one register per field, as C passes them.
    void *fields = image("libInt64Fields.dylib");
    unsigned long (*wideCombine)(unsigned long, unsigned long, unsigned long) =
        symbol(fields, "$s11Int64Fields11wideCombineys6UInt64VAA4WideV_ADtF");
    long (*signedLess)(long, long) = symbol(fields, "$s11Int64Fields10signedLessySbAA6SignedVF");
    unsigned long (*flagsUnion)(unsigned long, unsigned long) =
        symbol(fields, "$s11Int64Fields10flagsUnionys6UInt64VAA5FlagsV_AFtF");
    plain("Int64Fields", "wideCombine-100-7-3", (long)wideCombine(100, 7, 3));
    plain("Int64Fields", "signedLess-neg1-2", signedLess(-1, 2) & 1);
    plain("Int64Fields", "signedLess-2-neg1", signedLess(2, -1) & 1);
    plain("Int64Fields", "flagsUnion-5-10", (long)flagsUnion(5, 10));
    void *subset = image("libOptionSubset.dylib");
    long (*allows)(unsigned long, unsigned long) = symbol(subset, "$s12OptionSubset6allowsySbAA6AccessV_ADtF");
    plain("OptionSubset", "allows-7-5", allows(7, 5) & 1);
    plain("OptionSubset", "allows-5-7", allows(5, 7) & 1);

    // selectorstubshape: the caller of the branching stub adds 7.
    void *stub = image("libSelectorStubShape.dylib");
    long (*branching)(long) = symbol(stub, "calls_branching_stub");
    plain("SelectorStubShape", "calls_branching_stub-5", branching(5));

    // lateimp: sent as a message, the late implementation gets _cmd and
    // returns its first keyword argument, as the listed method does.
    image("libLateIMP.dylib");
    id crate = class_createInstance(objc_getClass("LICrate"), 0);
    long (*send)(id, SEL, long, long) = (long (*)(id, SEL, long, long))objc_msgSend;
    plain("LateIMP", "late-5-9", send(crate, sel_registerName("late:with:"), 5, 9));
    plain("LateIMP", "listed-5-9", send(crate, sel_registerName("listed:with:"), 5, 9));

    printf("PASS sprint native: %d observations\n", observations);
    return 0;
}
