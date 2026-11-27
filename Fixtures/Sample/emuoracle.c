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
// The image is loaded as dyld would leave it: chained fixups or the older
// bind opcodes are applied, a rebase to its target and a bind to an
// address of its own in a page that is not mapped, so a call or a load through an import is known by
// which import it was. Every run starts from the same machine: registers
// and vector registers zero, a zeroed stack, and the image's writable
// segments as loaded.
//
//   emu-oracle <image>          then one request per line on stdin:
//   run <start> [limit=<n>] [x<n>=<v>] [d<n>=<v>] [peek=<n>] [poison=<v>]
//
// `poison=<v>` leaves x0…x17, v0…v7 and the flags holding a pattern made
// from <v> after each call out of the image, where the real callee would
// leave values this emulator cannot know. A fact that is the same under
// two patterns did not come from them.
//
// Values are hex with 0x, or decimal. `@<offset>` is an address inside a
// zeroed 64 KiB scratch buffer, for a pointer argument. One reply line:
//
//   OUT <outcome> pc=<pc> last=<pc of the last instruction run> x0=… … x28=… d0=… d1=…
//       abi=<ok | the callee-saved registers and sp a returned run left changed>
//       branches=<pc>:<t|n>,… calls=<pc>><target>(x0,x1,x2,x3)[!],… mem=<w0>,…
//
//   A call marked `!` was handed an address inside this machine's stack,
//   scratch buffer or the image's writable segments: the real callee
//   could have written there.
//
//   outcome: returned (reached the return address), trapped (brk, udf),
//   unsupported (an instruction this emulator does not implement: no
//   observation of the program), hung (instruction limit), overflowed
//   (more branches or calls ran than a reply lists: none is listed), faulted
//   (unmapped access), external (the run returned after calling out of
//   the image; each call returned at once, so what follows it is the real
//   machine's only where it does not depend on what the callee did).
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <mach-o/fixup-chains.h>
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
#define IMPORT_BASE 0x7d0000000ull   // never mapped: import n is IMPORT_BASE + 16 * n
#define IMPORT_SIZE 0x1000000ull
#define MAX_EVENTS 4096

typedef struct { uint64_t start, end; } Range;

static Range image[64];      // mapped segments
static int imageCount;
static Range stubs[16];      // import stub sections
static int stubCount;
static Range writable[64];   // segments a run may write, and each one's bytes as loaded
static uint8_t *loaded[64];
static int writableCount;
static uint64_t poison;
static int hasPoison;
static int overflowed;

static uint64_t branchPC[MAX_EVENTS];
static char branchTaken[MAX_EVENTS];
static int branchCount;
static uint64_t pendingBranch;   // a conditional branch whose outcome the next pc decides
static int hasPending;

typedef struct { uint64_t pc, target, x[4]; int handed; } Call;
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

static int isImport(uint64_t address) { return address >= IMPORT_BASE && address < IMPORT_BASE + IMPORT_SIZE; }

/// A call out of the image at `target`, about to return to `lr`: what it
/// was given, and whether any of it points into this machine's memory.
static void leaveImage(uc_engine *uc, uint64_t target) {
    uint64_t lr = 0;
    uc_reg_read(uc, UC_ARM64_REG_LR, &lr);
    if (callCount < MAX_EVENTS) {
        Call *call = &calls[callCount++];
        call->pc = lr - 4;
        call->target = target;
        call->handed = 0;
        for (int reg = 0; reg < 8; reg++) {
            uint64_t v = 0;
            uc_reg_read(uc, UC_ARM64_REG_X0 + reg, &v);
            if (reg < 4) call->x[reg] = v;
            if ((v >= STACK_BASE && v < STACK_BASE + STACK_SIZE) || (v >= SCRATCH_BASE && v < SCRATCH_BASE + SCRATCH_SIZE)
                || inRanges(writable, writableCount, v))
                call->handed = 1;
        }
    } else {
        overflowed = 1;
    }
    if (hasPoison) {
        for (int reg = 0; reg <= 17; reg++) {
            uint64_t v = poison ^ (0x0101010101010101ull * (uint64_t)(reg + 1));
            uc_reg_write(uc, UC_ARM64_REG_X0 + reg, &v);
        }
        for (int reg = 0; reg < 8; reg++) {
            uint64_t v[2] = { ~poison ^ (0x1111111111111111ull * (uint64_t)(reg + 1)), poison };
            uc_reg_write(uc, UC_ARM64_REG_V0 + reg, v);
        }
        uint64_t nzcv = (poison & 0xf) << 28;
        uc_reg_write(uc, UC_ARM64_REG_NZCV, &nzcv);
    }
    wentExternal = 1;
    redirect = lr;
    hasRedirect = 1;
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
        } else {
            overflowed = 1;
        }
        hasPending = 0;
    }
    // A call out of the image: into an import stub, or anywhere unmapped
    // is reported by the fetch fault instead.
    if (inRanges(stubs, stubCount, address)) {
        leaveImage(uc, address);
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

static uint64_t imageBase;
static int fixupsApplied;      // slots rewritten
static int fixupsUnsupported;  // a pointer format this does not read: the image stays as on disk

/// Rewrite each chained slot as dyld would. A rebase becomes its target.
/// A bind becomes the address this machine gives that import.
static void applyChainedFixups(uc_engine *uc, const uint8_t *data) {
    const struct dyld_chained_fixups_header *header = (const struct dyld_chained_fixups_header *)data;
    const struct dyld_chained_starts_in_image *starts =
        (const struct dyld_chained_starts_in_image *)(data + header->starts_offset);
    for (uint32_t s = 0; s < starts->seg_count; s++) {
        if (starts->seg_info_offset[s] == 0) continue;
        const struct dyld_chained_starts_in_segment *segment =
            (const struct dyld_chained_starts_in_segment *)((const uint8_t *)starts + starts->seg_info_offset[s]);
        if (segment->pointer_format != DYLD_CHAINED_PTR_64 && segment->pointer_format != DYLD_CHAINED_PTR_64_OFFSET) {
            fixupsUnsupported = 1;
            continue;
        }
        for (uint32_t page = 0; page < segment->page_count; page++) {
            uint16_t start = segment->page_start[page];
            if (start == DYLD_CHAINED_PTR_START_NONE) continue;
            if (start & DYLD_CHAINED_PTR_START_MULTI) { fixupsUnsupported = 1; continue; }
            uint64_t address = imageBase + segment->segment_offset + (uint64_t)page * segment->page_size + start;
            for (;;) {
                uint64_t raw = 0;
                if (uc_mem_read(uc, address, &raw, 8) != UC_ERR_OK) break;
                uint64_t next = (raw >> 51) & 0xfff, value;
                if (raw >> 63) {
                    value = IMPORT_BASE + 16 * (raw & 0xffffff) + ((raw >> 24) & 0xff);
                } else {
                    uint64_t target = raw & 0xfffffffffull, high = (raw >> 36) & 0xff;
                    value = (segment->pointer_format == DYLD_CHAINED_PTR_64_OFFSET ? imageBase + target : target)
                        | (high << 56);
                }
                uc_mem_write(uc, address, &value, 8);
                fixupsApplied += 1;
                if (next == 0) break;
                address += next * 4;
            }
        }
    }
}

static uint64_t uleb(const uint8_t **cursor, const uint8_t *end) {
    uint64_t value = 0;
    int shift = 0;
    while (*cursor < end) {
        uint8_t byte = *(*cursor)++;
        if (shift < 64) value |= (uint64_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80)) break;
    }
    return value;
}

static char importNames[4096][96];   // imports of an opcode-bound image, in order of first use
static int importNameCount;

static uint64_t importAddress(const char *name) {
    for (int index = 0; index < importNameCount; index++)
        if (strncmp(importNames[index], name, 95) == 0) return IMPORT_BASE + 16 * (uint64_t)index;
    if (importNameCount == 4096) { fixupsUnsupported = 1; return IMPORT_BASE; }
    strncpy(importNames[importNameCount], name, 95);
    return IMPORT_BASE + 16 * (uint64_t)importNameCount++;
}

/// The LC_DYLD_INFO bind stream: each bound slot becomes the address this
/// machine gives that import, plus its addend. An image's rebases need
/// nothing here: with no slide a rebased slot already holds its target.
/// Lazy binds are left alone: a call through a stub is taken at the stub.
static void applyBindOpcodes(uc_engine *uc, const uint8_t *cursor, const uint8_t *end,
                             const uint64_t *segmentAddress, int segmentCount) {
    const char *name = "";
    uint64_t address = 0, addend = 0;
    while (cursor < end) {
        uint8_t byte = *cursor++, opcode = byte & 0xf0, immediate = byte & 0x0f;
        uint64_t count = 1, skip = 0;
        switch (opcode) {
        case BIND_OPCODE_DONE: return;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM: case BIND_OPCODE_SET_TYPE_IMM:
            continue;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB: uleb(&cursor, end); continue;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
            name = (const char *)cursor;
            while (cursor < end && *cursor) cursor++;
            cursor++;
            continue;
        case BIND_OPCODE_SET_ADDEND_SLEB: {
            uint64_t value = 0; int shift = 0; uint8_t part = 0;
            do { part = cursor < end ? *cursor++ : 0; value |= (uint64_t)(part & 0x7f) << shift; shift += 7; }
            while ((part & 0x80) && shift < 64);
            if ((part & 0x40) && shift < 64) value |= ~0ull << shift;
            addend = value;
            continue;
        }
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            if (immediate >= segmentCount) { fixupsUnsupported = 1; return; }
            address = segmentAddress[immediate] + uleb(&cursor, end);
            continue;
        case BIND_OPCODE_ADD_ADDR_ULEB: address += uleb(&cursor, end); continue;
        case BIND_OPCODE_DO_BIND: break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB: skip = uleb(&cursor, end); break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED: skip = (uint64_t)immediate * 8; break;
        case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: count = uleb(&cursor, end); skip = uleb(&cursor, end); break;
        default: fixupsUnsupported = 1; return;   // threaded binds and anything newer
        }
        for (uint64_t index = 0; index < count; index++) {
            uint64_t value = importAddress(name) + addend;
            uc_mem_write(uc, address, &value, 8);
            fixupsApplied += 1;
            address += 8 + skip;
        }
    }
}

static void mapImage(uc_engine *uc, const char *path) {
    const uint8_t *fixups = NULL;
    const struct dyld_info_command *opcodes = NULL;
    uint64_t segmentAddress[64];
    int segmentCount = 0;
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
            if (segmentCount < 64) segmentAddress[segmentCount++] = segment->vmaddr;
            if (segment->vmsize && strcmp(segment->segname, "__PAGEZERO") != 0) {
                uint64_t start = segment->vmaddr & ~(PAGE - 1);
                uint64_t end = (segment->vmaddr + segment->vmsize + PAGE - 1) & ~(PAGE - 1);
                if (uc_mem_map(uc, start, end - start, UC_PROT_ALL) != UC_ERR_OK) die("cannot map a segment");
                if (segment->filesize && segment->fileoff + segment->filesize <= (uint64_t)length)
                    uc_mem_write(uc, segment->vmaddr, bytes + segment->fileoff, segment->filesize);
                if (imageCount < 64) image[imageCount++] = (Range){ start, end };
                if (segment->fileoff == 0 && segment->filesize) imageBase = segment->vmaddr;
                if ((segment->initprot & VM_PROT_WRITE) && writableCount < 64) {
                    writable[writableCount] = (Range){ start, end };
                    loaded[writableCount++] = NULL;
                }
                const struct section_64 *section = (const struct section_64 *)(segment + 1);
                for (uint32_t s = 0; s < segment->nsects; s++, section++) {
                    int isStub = (section->flags & SECTION_TYPE) == S_SYMBOL_STUBS
                        || strncmp(section->sectname, "__objc_stubs", 16) == 0;
                    if (isStub && stubCount < 16)
                        stubs[stubCount++] = (Range){ section->addr, section->addr + section->size };
                }
            }
        }
        if (command->cmd == LC_DYLD_CHAINED_FIXUPS) {
            const struct linkedit_data_command *data = (const struct linkedit_data_command *)cursor;
            if ((uint64_t)data->dataoff + data->datasize <= (uint64_t)length) fixups = bytes + data->dataoff;
        }
        if (command->cmd == LC_DYLD_INFO || command->cmd == LC_DYLD_INFO_ONLY)
            opcodes = (const struct dyld_info_command *)cursor;
        cursor += command->cmdsize;
    }
    if (fixups) applyChainedFixups(uc, fixups);
    if (opcodes) {
        if ((uint64_t)opcodes->bind_off + opcodes->bind_size <= (uint64_t)length)
            applyBindOpcodes(uc, bytes + opcodes->bind_off, bytes + opcodes->bind_off + opcodes->bind_size,
                             segmentAddress, segmentCount);
    }
    // What a run may write is put back before the next one.
    for (int index = 0; index < writableCount; index++) {
        size_t size = (size_t)(writable[index].end - writable[index].start);
        loaded[index] = malloc(size);
        if (!loaded[index] || uc_mem_read(uc, writable[index].start, loaded[index], size) != UC_ERR_OK)
            die("cannot keep a segment as loaded");
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
    // Unicorn's default model is a Cortex-A72: no LSE atomics, no pointer
    // authentication, no `fjcvtzs`. Apple code uses all three, and on the
    // A72 each would stop the run as if it were a trap.
    if (uc_ctl_set_cpu_model(uc, UC_CPU_ARM64_MAX) != UC_ERR_OK) die("cannot select the CPU model");
    mapImage(uc, argv[1]);
    if (uc_mem_map(uc, STACK_BASE, STACK_SIZE, UC_PROT_READ | UC_PROT_WRITE) != UC_ERR_OK) die("cannot map a stack");
    if (uc_mem_map(uc, SCRATCH_BASE, SCRATCH_SIZE, UC_PROT_READ | UC_PROT_WRITE) != UC_ERR_OK) die("cannot map scratch");
    if (uc_mem_map(uc, RETURN_ADDRESS, PAGE, UC_PROT_ALL) != UC_ERR_OK) die("cannot map the return page");
    uc_hook hook;
    uc_hook_add(uc, &hook, UC_HOOK_CODE, onCode, NULL, 1, 0);
    setvbuf(stdout, NULL, _IOLBF, 0);

    static uint8_t zero[STACK_SIZE];
    char line[4096];
    while (fgets(line, sizeof line, stdin)) {
        char *token = strtok(line, " \t\r\n");
        if (!token || strcmp(token, "run") != 0) continue;
        token = strtok(NULL, " \t\r\n");
        if (!token) { printf("OUT invalid\n"); continue; }
        uint64_t start = strtoull(token, NULL, 0);
        uint64_t limit = 1000000, peek = 0;
        hasPoison = 0;

        // A clean machine for every run: registers zero, FP enabled, a
        // fresh stack and scratch buffer.
        for (int reg = 0; reg <= 28; reg++) { uint64_t v = 0; uc_reg_write(uc, UC_ARM64_REG_X0 + reg, &v); }
        for (int reg = 0; reg < 32; reg++) { uint64_t v[2] = { 0, 0 }; uc_reg_write(uc, UC_ARM64_REG_V0 + reg, v); }
        uint64_t fp = 0, lr = RETURN_ADDRESS, sp = STACK_BASE + STACK_SIZE - 0x1000, nzcv = 0;
        uint64_t cpacr = 3ull << 20;
        uc_reg_write(uc, UC_ARM64_REG_CPACR_EL1, &cpacr);
        uc_reg_write(uc, UC_ARM64_REG_FP, &fp);
        uc_reg_write(uc, UC_ARM64_REG_LR, &lr);
        uc_reg_write(uc, UC_ARM64_REG_SP, &sp);
        uc_reg_write(uc, UC_ARM64_REG_NZCV, &nzcv);
        uc_mem_write(uc, SCRATCH_BASE, zero, SCRATCH_SIZE);
        uc_mem_write(uc, STACK_BASE, zero, STACK_SIZE);
        for (int index = 0; index < writableCount; index++)
            uc_mem_write(uc, writable[index].start, loaded[index], (size_t)(writable[index].end - writable[index].start));

        while ((token = strtok(NULL, " \t\r\n"))) {
            char *equals = strchr(token, '=');
            if (!equals) continue;
            *equals = 0;
            const char *value = equals + 1;
            if (strcmp(token, "limit") == 0) limit = strtoull(value, NULL, 0);
            else if (strcmp(token, "peek") == 0) peek = strtoull(value, NULL, 0);
            else if (strcmp(token, "poison") == 0) { poison = strtoull(value, NULL, 0); hasPoison = 1; }
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

        branchCount = callCount = hasPending = wentExternal = hasRedirect = overflowed = 0;
        lastPC = 0;
        uint64_t saved[12];   // x19…x28, x29, sp as the run begins
        for (int reg = 0; reg < 10; reg++) uc_reg_read(uc, UC_ARM64_REG_X19 + reg, &saved[reg]);
        saved[10] = fp;
        saved[11] = sp;
        const char *outcome = "returned";
        uint64_t pc = start, executed = 0;
        for (;;) {
            hasRedirect = 0;
            uc_err error = uc_emu_start(uc, pc, RETURN_ADDRESS, 0, (size_t)(limit - executed));
            uc_reg_read(uc, UC_ARM64_REG_PC, &pc);
            // A branch to an import's own address, through a pointer the
            // loader bound: the same call out as one through a stub.
            if (!hasRedirect && error == UC_ERR_FETCH_UNMAPPED && isImport(pc)) leaveImage(uc, pc);
            if (hasRedirect) { pc = redirect; executed += 1; if (executed >= limit) { outcome = "hung"; break; } continue; }
            if (error == UC_ERR_OK) { outcome = pc == RETURN_ADDRESS ? "returned" : "hung"; break; }
            if (error == UC_ERR_EXCEPTION || error == UC_ERR_INSN_INVALID) {
                // A trap is a `brk` or a `udf` the program wrote. Any other
                // instruction that stops the run is one the emulator does
                // not have: that says nothing about the program.
                uint32_t word = 0;
                int wrote = uc_mem_read(uc, pc, &word, 4) == UC_ERR_OK
                    && ((word & 0xffe0001f) == 0xd4200000 || (word >> 16) == 0);
                outcome = wrote ? "trapped" : "unsupported";
                break;
            }
            outcome = "faulted";
            break;
        }
        if (wentExternal && strcmp(outcome, "returned") == 0) outcome = "external";
        if (overflowed) { outcome = "overflowed"; branchCount = callCount = 0; }

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
        printf(" abi=");
        int changed = 0;
        if (strcmp(outcome, "returned") == 0 || strcmp(outcome, "external") == 0) {
            for (int reg = 0; reg < 12; reg++) {
                uint64_t v = 0;
                uc_reg_read(uc, reg < 10 ? UC_ARM64_REG_X19 + reg : reg == 10 ? UC_ARM64_REG_FP : UC_ARM64_REG_SP, &v);
                if (v == saved[reg]) continue;
                if (reg < 11) printf("%sx%d", changed ? "," : "", 19 + reg); else printf("%ssp", changed ? "," : "");
                changed = 1;
            }
        }
        if (!changed) printf("ok");
        printf(" branches=");
        for (int index = 0; index < branchCount; index++)
            printf("%s0x%llx:%c", index ? "," : "", (unsigned long long)branchPC[index], branchTaken[index]);
        printf(" calls=");
        for (int index = 0; index < callCount; index++)
            printf("%s0x%llx>0x%llx(0x%llx;0x%llx;0x%llx;0x%llx)%s", index ? "," : "",
                   (unsigned long long)calls[index].pc, (unsigned long long)calls[index].target,
                   (unsigned long long)calls[index].x[0], (unsigned long long)calls[index].x[1],
                   (unsigned long long)calls[index].x[2], (unsigned long long)calls[index].x[3],
                   calls[index].handed ? "!" : "");
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
