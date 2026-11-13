// Ghidra headless post-script for Tools/ghidra-compare/compare.sh.
// Prints every function's signature and decompiled C, in address order,
// to the file named by the first script argument.
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.io.*;

public class DumpDecomp extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(new FileWriter(args[0]));
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext() && !monitor.isCancelled()) {
            Function f = it.next();
            if (f.isThunk() || f.isExternal()) continue;
            out.println("=== " + f.getEntryPoint() + " " + f.getName(true));
            out.println("// signature: " + f.getSignature().getPrototypeString(true));
            DecompileResults r = d.decompileFunction(f, 60, monitor);
            if (r != null && r.decompileCompleted()) {
                out.println(r.getDecompiledFunction().getC());
            } else {
                out.println("// decompile failed: " + (r == null ? "null" : r.getErrorMessage()));
            }
        }
        d.dispose();
        out.close();
    }
}
