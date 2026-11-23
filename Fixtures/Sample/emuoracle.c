// Runs code from an arm64 Mach-O image under emulation (Unicorn) and
// reports what the machine did: how the run ended, the registers at the
// end, which conditional branches were taken, and what was in the argument
// registers at each call out of the image.
//
// The native oracle (sprintnative.c) can only call what an image exports,
// in this process, and sees x0 and x21. This one starts at any address,
// stripped bodies included, sets and reads any register, and a trap or an
// endless loop is an outcome, not a crash. Nothing here is swiftdc's: it
// is an independent account of the same bytes.
//
//   emu-oracle <image>          then one request per line on stdin:
//   run <start> [limit=<n>] [x<n>=<v>] [d<n>=<v>] [peek=<n>]
//
// Values are hex with 0x, or decimal. `@<offset>` is an address inside a
// zeroed 64 KiB scratch buffer, for a pointer argument. One reply line:
//
//   OUT <outcome> pc=<pc> last=<pc of the last instruction run> x0=… … x28=… d0=… d1=…
//       branches=<pc>:<t|n>,… calls=<pc>><target>(x0,x1,x2,x3),… mem=<w0>,…
//
//   outcome: returned (reached the return address), trapped (brk, udf),
//   hung (instruction limit), faulted (unmapped access), external (the
//   run called out of the image; the call returned at once with every
//   register as it was, so nothing after it is the real machine's).
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unicorn/unicorn.h>

#define PAGE 0x4000ull
#define STACK_BASE 0x7f0000000ull
#define STACK_SIZE 0x100000ull
#define SCRATCH_BASE 0x600000000ull
#define SCRATCH_SIZE 0x10000ull
#define RETURN_ADDRESS 0x7e0000000ull
#define MAX_EVENTS 4096

typedef struct { uint64_t start, end; } Range;

static Range image[64];      // mapped segments
static int imageCount;
static Range stubs[16];      // import stub sections
static int stubCount;

static uint64_t branchPC[MAX_EVENTS];
static char branchTaken[MAX_EVENTS];
static int branchCount;
static uint64_t pendingBranch;   // a conditional branch whose outcome the next pc decides
static int hasPending;

typedef struct { uint64_t pc, target, x[4]; } Call;
static Call calls[MAX_EVENTS];
static int callCount;
static int wentExternal;
static uint64_t redirect;        // where to resume after an external call
static int hasRedirect;
static uint64_t lastPC;           // the last instruction executed inside the image

static int inRanges(const Range *ranges, int count, uint64_t address) {
    for (int index = 0; index < count; index++)
        if (address >= ranges[index].start && address < ranges[index].end) return 1;
    return 0;
}

static int isConditionalBranch(uint32_t word) {
    if ((word & 0xff000010) == 0x54000000) return 1;            // b.cond
    if ((word & 0x7e000000) == 0x34000000) return 1;            // cbz, cbnz
    if ((word & 0x7e000000) == 0x36000000) return 1;            // tbz, tbnz
    return 0;
}

static void onCode(uc_engine *uc, uint64_t address, uint32_t size, void *user) {
    (void)size; (void)user;
    if (address != RETURN_ADDRESS) lastPC = address;
    if (hasPending) {
        if (branchCount < MAX_EVENTS) {
            branchPC[branchCount] = pendingBranch;
            branchTaken[branchCount++] = address == pendingBranch + 4 ? 'n' : 't';
        }
        hasPending = 0;
    }
    // A call out of the image: into an import stub, or anywhere unmapped
    // is reported by the fetch fault instead.
    if (inRanges(stubs, stubCount, address)) {
        uint64_t lr = 0;
        uc_reg_read(uc, UC_ARM64_REG_LR, &lr);
        if (callCount < MAX_EVENTS) {
            Call *call = &calls[callCount++];
            call->pc = lr - 4;
            call->target = address;
            uc_reg_read(uc, UC_ARM64_REG_X0, &call->x[0]);
            uc_reg_read(uc, UC_ARM64_REG_X1, &call->x[1]);
            uc_reg_read(uc, UC_ARM64_REG_X2, &call->x[2]);
            uc_reg_read(uc, UC_ARM64_REG_X3, &call->x[3]);
        }
        wentExternal = 1;
        redirect = lr;
        hasRedirect = 1;
        uc_emu_stop(uc);
        return;
    }
    uint32_t word = 0;
    if (uc_mem_read(uc, address, &word, 4) == UC_ERR_OK && isConditionalBranch(word)) {
        pendingBranch = address;
        hasPending = 1;
    }
}

static void die(const char *message) { fprintf(stderr, "emu-oracle: %s\n", message); exit(2); }

static void mapImage(uc_engine *uc, const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) die("cannot open the image");
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    uint8_t *bytes = malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) die("cannot read the image");
    fclose(file);
    const struct mach_header_64 *header = (const struct mach_header_64 *)bytes;
    if (length < (long)sizeof *header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64)
        die("not a thin arm64 Mach-O image");
    const uint8_t *cursor = bytes + sizeof *header;
    for (uint32_t index = 0; index < header->ncmds; index++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if (segment->vmsize && strcmp(segment->segname, "__PAGEZERO") != 0) {
                uint64_t start = segment->vmaddr & ~(PAGE - 1);
                uint64_t end = (segment->vmaddr + segment->vmsize + PAGE - 1) & ~(PAGE - 1);
                if (uc_mem_map(uc, start, end - start, UC_PROT_ALL) != UC_ERR_OK) die("cannot map a segment");
                if (segment->filesize && segment->fileoff + segment->filesize <= (uint64_t)length)
                    uc_mem_write(uc, segment->vmaddr, bytes + segment->fileoff, segment->filesize);
                if (imageCount < 64) image[imageCount++] = (Range){ start, end };
                const struct section_64 *section = (const struct section_64 *)(segment + 1);
                for (uint32_t s = 0; s < segment->nsects; s++, section++) {
                    int isStub = (section->flags & SECTION_TYPE) == S_SYMBOL_STUBS
                        || strncmp(section->sectname, "__objc_stubs", 16) == 0;
                    if (isStub && stubCount < 16)
                        stubs[stubCount++] = (Range){ section->addr, section->addr + section->size };
                }
            }
        }
        cursor += command->cmdsize;
    }
    free(bytes);
}

static uint64_t parseValue(const char *text) {
    if (text[0] == '@') return SCRATCH_BASE + strtoull(text + 1, NULL, 0);
    return strtoull(text, NULL, 0);
}

int main(int argc, char **argv) {
    if (argc != 2) die("usage: emu-oracle <image>, requests on stdin");
    uc_engine *uc;
    if (uc_open(UC_ARCH_ARM64, UC_MODE_ARM, &uc) != UC_ERR_OK) die("cannot start the emulator");
    mapImage(uc, argv[1]);
    if (uc_mem_map(uc, STACK_BASE, STACK_SIZE, UC_PROT_READ | UC_PROT_WRITE) != UC_ERR_OK) die("cannot map a stack");
    if (uc_mem_map(uc, SCRATCH_BASE, SCRATCH_SIZE, UC_PROT_READ | UC_PROT_WRITE) != UC_ERR_OK) die("cannot map scratch");
    if (uc_mem_map(uc, RETURN_ADDRESS, PAGE, UC_PROT_ALL) != UC_ERR_OK) die("cannot map the return page");
    uc_hook hook;
    uc_hook_add(uc, &hook, UC_HOOK_CODE, onCode, NULL, 1, 0);
    setvbuf(stdout, NULL, _IOLBF, 0);

    static uint8_t zero[SCRATCH_SIZE];
    char line[4096];
    while (fgets(line, sizeof line, stdin)) {
        char *token = strtok(line, " \t\r\n");
        if (!token || strcmp(token, "run") != 0) continue;
        token = strtok(NULL, " \t\r\n");
        if (!token) { printf("OUT invalid\n"); continue; }
        uint64_t start = strtoull(token, NULL, 0);
        uint64_t limit = 1000000, peek = 0;

        // A clean machine for every run: registers zero, FP enabled, a
        // fresh stack and scratch buffer.
        for (int reg = 0; reg <= 28; reg++) { uint64_t v = 0; uc_reg_write(uc, UC_ARM64_REG_X0 + reg, &v); }
        for (int reg = 0; reg < 32; reg++) { uint64_t v = 0; uc_reg_write(uc, UC_ARM64_REG_D0 + reg, &v); }
        uint64_t fp = 0, lr = RETURN_ADDRESS, sp = STACK_BASE + STACK_SIZE - 0x1000, nzcv = 0;
        uint64_t cpacr = 3ull << 20;
        uc_reg_write(uc, UC_ARM64_REG_CPACR_EL1, &cpacr);
        uc_reg_write(uc, UC_ARM64_REG_FP, &fp);
        uc_reg_write(uc, UC_ARM64_REG_LR, &lr);
        uc_reg_write(uc, UC_ARM64_REG_SP, &sp);
        uc_reg_write(uc, UC_ARM64_REG_NZCV, &nzcv);
        uc_mem_write(uc, SCRATCH_BASE, zero, SCRATCH_SIZE);

        while ((token = strtok(NULL, " \t\r\n"))) {
            char *equals = strchr(token, '=');
            if (!equals) continue;
            *equals = 0;
            const char *value = equals + 1;
            if (strcmp(token, "limit") == 0) limit = strtoull(value, NULL, 0);
            else if (strcmp(token, "peek") == 0) peek = strtoull(value, NULL, 0);
            else if (token[0] == 'x') {
                int reg = atoi(token + 1);
                uint64_t v = parseValue(value);
                if (reg >= 0 && reg <= 28) uc_reg_write(uc, UC_ARM64_REG_X0 + reg, &v);
            } else if (token[0] == 'd') {
                int reg = atoi(token + 1);
                uint64_t v = parseValue(value);
                if (reg >= 0 && reg < 32) uc_reg_write(uc, UC_ARM64_REG_D0 + reg, &v);
            } else if (strncmp(token, "mem@", 4) == 0) {
                uint64_t address = SCRATCH_BASE + strtoull(token + 4, NULL, 0), v = parseValue(value);
                uc_mem_write(uc, address, &v, 8);
            }
        }

        branchCount = callCount = hasPending = wentExternal = hasRedirect = 0;
        lastPC = 0;
        const char *outcome = "returned";
        uint64_t pc = start, executed = 0;
        for (;;) {
            hasRedirect = 0;
            uc_err error = uc_emu_start(uc, pc, RETURN_ADDRESS, 0, (size_t)(limit - executed));
            uc_reg_read(uc, UC_ARM64_REG_PC, &pc);
            if (hasRedirect) { pc = redirect; executed += 1; if (executed >= limit) { outcome = "hung"; break; } continue; }
            if (error == UC_ERR_OK) { outcome = pc == RETURN_ADDRESS ? "returned" : "hung"; break; }
            if (error == UC_ERR_EXCEPTION || error == UC_ERR_INSN_INVALID) { outcome = "trapped"; break; }
            outcome = "faulted";
            break;
        }
        if (wentExternal && strcmp(outcome, "returned") == 0) outcome = "external";

        printf("OUT %s pc=0x%llx last=0x%llx", outcome, (unsigned long long)pc, (unsigned long long)lastPC);
        for (int reg = 0; reg <= 28; reg++) {
            uint64_t v = 0;
            uc_reg_read(uc, UC_ARM64_REG_X0 + reg, &v);
            printf(" x%d=0x%llx", reg, (unsigned long long)v);
        }
        for (int reg = 0; reg < 2; reg++) {
            uint64_t v = 0;
            uc_reg_read(uc, UC_ARM64_REG_D0 + reg, &v);
            printf(" d%d=0x%llx", reg, (unsigned long long)v);
        }
        printf(" branches=");
        for (int index = 0; index < branchCount; index++)
            printf("%s0x%llx:%c", index ? "," : "", (unsigned long long)branchPC[index], branchTaken[index]);
        printf(" calls=");
        for (int index = 0; index < callCount; index++)
            printf("%s0x%llx>0x%llx(0x%llx;0x%llx;0x%llx;0x%llx)", index ? "," : "",
                   (unsigned long long)calls[index].pc, (unsigned long long)calls[index].target,
                   (unsigned long long)calls[index].x[0], (unsigned long long)calls[index].x[1],
                   (unsigned long long)calls[index].x[2], (unsigned long long)calls[index].x[3]);
        printf(" mem=");
        for (uint64_t index = 0; index < peek && index < 64; index++) {
            uint64_t v = 0;
            uc_mem_read(uc, SCRATCH_BASE + index * 8, &v, 8);
            printf("%s0x%llx", index ? "," : "", (unsigned long long)v);
        }
        printf("\n");
    }
    uc_close(uc);
    return 0;
}
