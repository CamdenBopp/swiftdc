// Ghidra headless post-script for Tools/samples/render.py.
// Decompiles only the functions at the addresses listed, one hex address
// per line, in the file named by the first script argument, and writes
// each one's prototype and C to the file named by the second, in the
// order listed. Ghidra's analysis is its default; nothing is tuned.
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import java.io.*;
import java.nio.file.*;

public class DumpSelected extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(new FileWriter(args[1]));
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        for (String line : Files.readAllLines(Paths.get(args[0]))) {
            String text = line.trim();
            if (text.isEmpty()) continue;
            Address address = toAddr(Long.parseUnsignedLong(text.replaceFirst("^0x", ""), 16));
            Function function = getFunctionAt(address);
            out.println("=== 0x" + text.replaceFirst("^0x", ""));
            if (function == null) {
                out.println("// Ghidra has no function at this address");
                continue;
            }
            out.println("// " + function.getSignature().getPrototypeString(true));
            DecompileResults result = decompiler.decompileFunction(function, 120, monitor);
            if (result != null && result.decompileCompleted()) {
                out.println(result.getDecompiledFunction().getC().strip());
            } else {
                out.println("// decompile failed: " + (result == null ? "no result" : result.getErrorMessage()));
            }
        }
        decompiler.dispose();
        out.close();
    }
}
