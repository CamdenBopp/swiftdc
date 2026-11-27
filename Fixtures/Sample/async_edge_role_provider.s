// The callees async_edge_role.s imports. Their bodies are in another image,
// so a caller there knows each only by its name.
.text
.p2align 2
// endpoint() async. Stores 11 to slot 16 of the context x22 holds, then
// returns to the caller that reached it with `bl`.
.globl _$s9AsyncEdge8endpointyyYaF
_$s9AsyncEdge8endpointyyYaF:
 mov x8,#11
 str x8,[x22,#16]
 ret
// plain(() async -> ()) -> Int. Synchronous: returns 0 and writes no memory.
.globl _$s9AsyncEdge5plainySiyyYaXEF
_$s9AsyncEdge5plainySiyyYaXEF:
 mov x0,#0
 ret
// A C function. Returns 0 and writes no memory.
.globl _async_edge_role_c_import
_async_edge_role_c_import:
 mov x0,#0
 ret
