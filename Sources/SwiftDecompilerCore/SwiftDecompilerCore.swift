/// SwiftDecompilerCore — the analysis engine for the Swift binary decompiler.
///
/// Responsibilities (built up incrementally):
///   - Load a Mach-O binary (via MachOKit, through MachOSwiftSection).
///   - Reconstruct Swift type/protocol declarations from `__swift5_*` metadata
///     (via SwiftDump).
///   - Disassemble function bodies to ARM64, annotated with demangled symbols.
///
/// This file is a placeholder anchor; real APIs live in sibling files.
public enum SwiftDecompiler {
    /// Library version, surfaced by the CLI `--version`.
    public static let version = "0.0.1"
}
