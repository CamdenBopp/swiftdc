import Foundation
import Testing
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftDecompilerCore

private func allocatorWrapperIndex(helper: [UInt32]? = nil, helperName: String? = nil,
                                   hints: Bool, helperIsStart: Bool = true,
                                   twoAllocations: Bool = false, frameStore: Bool = false,
                                   oldFrameFact: Int = 0, joinedFrame: Bool = false, runtimeName: String? = "swift_task_alloc") throws -> AsyncFuncletIndex {
    func branch(_ from: UInt64, _ to: UInt64, link: Bool) -> UInt32 {
        (link ? 0x94000000 : 0x14000000)
            | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ffffff)
    }
    var entry: [UInt32] = [0xd10083ff, 0x910043fd]
    if frameStore { entry.append(0xaa1403fd) } // mov x29,x20: no incoming native-frame proof
    func appendCall() { entry.append(branch(0x1000 + UInt64(entry.count * 4), 0x3000, link: true)) }
    if twoAllocations || oldFrameFact == 3 {
        appendCall()
        entry.append(oldFrameFact == 3 ? 0xaa0003fd : 0xaa0003f3) // mov x19,x0: the earlier allocation
    }
    if oldFrameFact == 1 {
        let pc = 0x1000 + UInt64(entry.count * 4), delta = UInt64(0x2000) - pc
        entry.append(0x1000001d | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5)
    } else if oldFrameFact == 2 {
        entry.append(0xb000001d) // adrp x29,0x2000 at caller's 0x1000 page
    }
    appendCall()
    if joinedFrame {
        // Exceed the bounded path window: only the CFG MUST transfer can
        // carry the wrapper's frame setup into the merged allocation block.
        entry += [0xb4000009 | UInt32(21 << 5)]
        entry += Array(repeating:UInt32(0x14000001),count:20)
        entry.append(branch(0x1000 + UInt64(entry.count * 4), 0x4000, link:true))
    }
    let pc = 0x1000 + UInt64(entry.count * 4), delta = UInt64(0x2000) - pc
    entry.append(oldFrameFact == 2 ? 0x910003a8
        : 0x10000008 | UInt32(delta & 3) << 29 | UInt32(delta >> 2) << 5)
    if oldFrameFact == 3 {
        entry += [0xaa1d03f3, 0xf9000668, 0xaa1303f6] // copy stale x29 to x19; store and hand it over
    } else {
        entry += [oldFrameFact == 1 ? 0xa9007416 : 0xa9002016, 0xaa0003f6]
    }
    if twoAllocations { entry.append(0xf900067f) } // str xzr,[x19,#8]
    if frameStore { entry.append(0xf90007bf) } // str xzr,[x29,#8]
    entry.append(branch(0x1000 + UInt64(entry.count * 4), 0x5000, link: false))
    // Actual default-Osize allocation wrapper: caller stack spill, frame
    // pointer setup, async descriptor and size loads, then task_alloc.
    let canonical: [UInt32] = [0xf90007f6, 0x910043fd, 0x90000008,
                                0xf9400908, 0xb9400500,
                                branch(0x3014, 0x4000, link: false)]
    let bodies: [UInt64: [UInt32]] = [0x1000:entry, 0x2000:[0xd65f03c0],
                                    0x3000:helper ?? canonical,
                                    0x4000:[0xd65f03c0], 0x5000:[0xd65f03c0]]
    let engine = try #require(CapstoneEngine())
    var decoded: [UInt64: [Instruction]] = [:]
    for (address, code) in bodies {
        decoded[address] = engine.disassemble(code.withUnsafeBytes { Data($0) }, address: address).map {
            Instruction(address:$0.address, text:$0.text, controlFlow:$0.controlFlow,
                        branchTarget:$0.branchTarget, detail:$0.detail)
        }
        try #require(decoded[address]?.count == code.count)
    }
    var starts=Set(bodies.keys)
    if !helperIsStart { starts.remove(0x3000) }
    return AsyncFuncletIndex.build(
        hints:hints ? .init(entries:[0x1000], awaitReturns:[0x2000], continuations:[]) : nil,
        functionStarts:starts, instructions:{ decoded[$0] ?? [] },
        nameOf:{ address in
            switch address {
            case 0x3000:helperName
            case 0x4000:runtimeName
            case 0x5000:"Own.worker() async -> Swift.Int64"
            default:nil
            }
        })
}

@Test func outlinedTaskAllocatorProvesFreshContextAtEachOuterCall() throws {
    for hints in [true,false] {
        for name: String? in [nil,"OUTLINED_FUNCTION_1","ordinaryName"] {
            for twice in [false,true] {
                for gotOffset in [16,24] {
                    let helper:[UInt32]=[0xf90007f6,0x910043fd,0x90000008,
                        0xf9400108 | UInt32((gotOffset / 8) << 10),0xb9400500,0x140003fb]
                    let index=try allocatorWrapperIndex(helper:helper,helperName:name,hints:hints,twoAllocations:twice)
                    #expect(index.chains[0x1000] == [0x1000,0x2000])
                    #expect(index.funclets[0x2000]?.parent == 0x1000)
                    #expect(index.suspension(into:0x2000)?.suspension.callee == 0x5000)
                }
            }
        }
    }
}

@Test func outlinedTaskAllocatorPreservesItsProvedFrameSetup() throws {
    for hints in [true,false] {
        for joined in [false,true] {
            let index=try allocatorWrapperIndex(hints:hints,frameStore:true,joinedFrame:joined)
            #expect(index.chains[0x1000] == [0x1000,0x2000])
            #expect(index.suspension(into:0x2000) != nil)
        }
    }
}

@Test func outlinedTaskAllocatorNeedsTheCompleteBodyAndRuntimeTail() throws {
    let malformed: [[UInt32]] = [
        [0xd65f03c0], // a name alone establishes nothing
        [0xf90007f6,0x910043fd,0x90000008,0xf9400908,0xb9400500,0xaa1603fd,0x140003fa], // extra frame overwrite

        [0xf8296bf6,0x910043fd,0x90000008,0xf9400908,0xb9400500,0x140003fb], // indexed stack write
        [0xf90007f6,0x110043fd,0x90000008,0xf9400908,0xb9400500,0x140003fb], // truncated frame
        [0xf90007f6,0x910042dd,0x90000008,0xf9400908,0xb9400500,0x140003fb], // context-based frame
        [0xf90007f6,0x914043fd,0x90000008,0xf9400908,0xb9400500,0x140003fb], // shifted frame offset
        [0xf90007f6,0x910043fd,0x90000016,0xf9400908,0xb9400500,0x140003fb], // ADRP clobbers context
        [0xf90007f6,0x910043fd,0x90000008,0xf9400916,0xb9400500,0x140003fb], // load clobbers context
        [0xf90007f6,0x910043fd,0x90000008,0xf8410d08,0xb9400500,0x140003fb], // descriptor writeback
        [0xf90007f6,0x910043fd,0x90000008,0xf9400908,0xb9400516,0x140003fb], // size load clobbers context
        [0xf90007f6,0x910043fd,0x90000008,0xf9400908,0xb9000500,0x140003fb], // writes through descriptor
        [0xf90007f6,0x910043fd,0x90000008,0xf9400908,0xf9400500,0x140003fb], // wrong size width

        [0xf90006d6,0x910043fd,0x90000008,0xf9400908,0xb9400500,0x140003fb], // spill through x22
        [0xf90007f6,0x910043f6,0x90000008,0xf9400908,0xb9400500,0x140003fb], // overwrites x22
        [0xf90007f6,0x910043fd,0x90000008,0xf9400908,0xb9400500,0x940003fb], // BL then no return
        [0xf90007f6,0x910043fd,0x90000008,0xf9400908,0xb9400500,0xd65f03c0], // no allocator
    ]
    for hints in [true,false] {
        for helper in malformed {
            let index=try allocatorWrapperIndex(helper:helper,helperName:"OUTLINED_FUNCTION_1",hints:hints)
            #expect(index.funclets[0x2000]?.parent == nil)
            #expect(index.suspension(into:0x2000) == nil)
        }
        for runtime: String? in [nil,"swift_task_dealloc","Own.swift_task_alloc"] {
            let wrong=try allocatorWrapperIndex(hints:hints,runtimeName:runtime)
            #expect(wrong.funclets[0x2000]?.parent == nil)
        }
        let missing=try allocatorWrapperIndex(hints:hints,helperIsStart:false)
        #expect(missing.funclets[0x2000]?.parent == nil)
    }
}

@Test func outlinedTaskAllocatorDiscardsEveryOldFrameRegisterFact() throws {
    for hints in [true,false] {
        for fact in 1...3 {
            let index=try allocatorWrapperIndex(hints:hints,oldFrameFact:fact)
            #expect(index.funclets[0x2000]?.parent == nil)
            #expect(index.suspension(into:0x2000) == nil)
        }
    }
}

@Test(arguments:[
    "Fixtures/Sample/libAsyncOutlinedContext.Onone.dylib",
    "Fixtures/Sample/libAsyncOutlinedContext.O.dylib",
    "Fixtures/Sample/libAsyncOutlinedContext.Osize.dylib",
])
func outlinedTaskAllocatorLinksBothCompleteProducerChainsAcrossAPIsIfPresent(path:String) async throws {
    guard FileManager.default.fileExists(atPath:path) else { return }
    let image=try BinaryLoader.load(path:path)
    var entries:[String:UInt64]=[:]
    let names=["first","second"].flatMap { name in
        let full="AsyncOutlinedContext."+name+"() async -> Swift.Int64"
        return [full,"(1) await resume partial function for "+full,
                "(2) suspend resume partial function for "+full]
    }
    for symbol in image.symbols where symbol.offset != 0 && symbol.name.hasPrefix("_$s") {
        let name=try await demangleAsNode(String(symbol.name.dropFirst())).print(using:.default)
        if names.contains(name) {
            try #require(entries[name] == nil)
            entries[name]=UInt64(symbol.offset)
        }
    }
    try #require(entries.count==6)
    let starts=Set(Disassembler().functionStarts(of:image))
    try #require(Set(entries.values).isSubset(of:starts))
    let selectedAddresses=Set(entries.values)
    for stage in 0..<4 {
        let functions:[DisassembledFunction]=try await withStableDependencies {
            switch stage {
            case 0:return try await Disassembler().disassemble(path:path)
            case 1:return await Disassembler().disassemble(machO:image)
            case 2:return try await Disassembler().disassemble(path:path,functionFilter:"AsyncOutlinedContext.")
            default:
                let all:[DisassembledFunction?]=await Disassembler().disassembleStreaming(
                    machO:image,transform:{ selectedAddresses.contains($0.startAddress) ? $0 : nil })
                return all.compactMap { $0 }
            }
        }
        let selected=functions.filter { selectedAddresses.contains($0.startAddress) }
        try #require(selected.count==6)
        for producer in stride(from:0,to:6,by:3) {
            let chain=try names[producer..<(producer+3)].map { try #require(entries[$0]) }
            for ordinal in 0..<3 {
                let info=try #require(selected.first { $0.startAddress==chain[ordinal] }?.asyncFunclet)
                #expect(info.parent==chain[0])
                #expect(info.ordinal==ordinal)
                #expect(info.chain==chain)
                if ordinal > 0 { #expect(info.predecessor==chain[ordinal-1]) }
            }
        }
    }
}
