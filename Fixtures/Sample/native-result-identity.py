#!/usr/bin/env python3
"""Check one real-object lifetime in a fresh process after ABI/origin checks."""
from pathlib import Path
import argparse, importlib.util, json, os

if not __debug__:
    raise RuntimeError("Native ABI and origin validation requires Python assertions enabled")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--case", required=True, choices=["run", "twice", "immediate"])
    options = parser.parse_args()
    spec = importlib.util.spec_from_file_location("arc_origin_checks", Path(__file__).with_name("native-arc-origin.py"))
    checks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checks)
    library = options.library.resolve(strict=True)
    proof = json.loads(Path(str(library) + ".abi.json").read_text())
    assert proof["schema"] == 1 and proof["compiler_ABI_verified"] is True
    assert proof["library_file"] == library.name and proof["library_sha256"] == checks.sha(library)
    assert proof["level"] in ["Onone", "O", "Osize"]
    assert (proof["expected_value"], proof["expected_constructions"], proof["expected_destructions"]) == (7, 1, 1)
    expected = {"result_identity_make": ("ptr", []), "result_identity_sink": ("i64", ["ptr"]),
                "result_identity_destroy": ("void", ["ptr"]), "result_identity_count": ("i64", []),
                "result_identity_destroyed": ("i64", []), "result_identity_reset": ("void", [])}
    assert set(proof["providers"]) == set(expected)
    for name, (result, parameters) in expected.items():
        abi = proof["providers"][name]
        assert abi["symbol"] == name and abi["calling_convention"] == "C"
        assert abi["return_type"] == result and abi["parameter_types"] == parameters
    assert set(proof["entries"]) == {"run", "twice", "immediate"}
    for name, abi in proof["entries"].items():
        symbol = "$s" + str(len(proof["module"])) + proof["module"] + str(len(name)) + name + "SiyF"
        assert abi["symbol"] == symbol and abi["mach_symbol"] == "_" + symbol
        assert abi["calling_convention"] == "swift"
        assert abi["return_type"] == "i64" and abi["parameter_types"] == []
    runtime = proof["runtime"]
    assert runtime["symbol"] == "swift_bridgeObjectRetain" and runtime["calling_convention"] == "C"
    assert runtime["return_type"] == "ptr" and runtime["parameter_types"] == ["ptr"]
    assert proof["actual_runtime_calls"] and all("ptr returned " in line for line in proof["actual_runtime_calls"])
    target = "_swift_bridgeObjectRetain"
    image = checks.macho(library, target=target)
    assert image["binding_format"] == proof.get("binding_format", "chained")
    assert image["image_id"] == "@rpath/" + library.name and image["rpaths"] == []
    assert image["libraries"] == ["/usr/lib/libSystem.B.dylib", "/usr/lib/libobjc.A.dylib", "/usr/lib/swift/libswiftCore.dylib"]
    assert image["target_symbols"] == [{"name": target, "type": 1, "section": 0, "description": 3 << 8, "value": 0}]
    assert [item for item in image["imports"] if item["name"] == target] == [
        {"name": target, "ordinal": 3, "library": "/usr/lib/swift/libswiftCore.dylib"}]
    if image["binding_format"] == "legacy":
        bindings = [item for item in image["legacy_bindings"] if item["name"] == target]
        assert len(bindings) == 1 and bindings[0]["addend"] == 0 and not bindings[0]["weak"]
    assert set("_" + name for name in expected).issubset(image["exports"])
    assert all(abi["mach_symbol"] in image["exports"] for abi in proof["entries"].values())
    forbidden = {"DYLD_INSERT_LIBRARIES", "DYLD_FORCE_FLAT_NAMESPACE", "DYLD_LIBRARY_PATH",
                 "DYLD_FRAMEWORK_PATH", "DYLD_VERSIONED_LIBRARY_PATH", "DYLD_VERSIONED_FRAMEWORK_PATH", "LD_PRELOAD"}
    assert not forbidden.intersection(os.environ)

    import ctypes
    handle = ctypes.CDLL(str(library), mode=os.RTLD_LOCAL | os.RTLD_NOW)
    def function(name, result, arguments):
        value = getattr(handle, name)
        value.restype, value.argtypes = result, arguments
        return value
    reset = function("result_identity_reset", None, [])
    count = function("result_identity_count", ctypes.c_int64, [])
    destroyed = function("result_identity_destroyed", ctypes.c_int64, [])
    sink = function("result_identity_sink", ctypes.c_int64, [ctypes.c_void_p])
    destroy = function("result_identity_destroy", None, [ctypes.c_void_p])
    entry = function(proof["entries"][options.case]["symbol"], ctypes.c_int64, [])
    reset()
    assert count() == 0 and destroyed() == 0
    value = entry()
    if options.case == "immediate":
        assert value != 0 and count() == 1 and destroyed() == 0
        pointer = ctypes.c_void_p(value & ((1 << 64) - 1))
        value = sink(pointer)
        destroy(pointer)
    actual = (value, count(), destroyed())
    print(json.dumps({"level": proof["level"], "case": options.case,
                      "value": actual[0], "constructions": actual[1], "destructions": actual[2],
                      "passed": actual == (7, 1, 1)}))
    assert actual == (7, 1, 1)


if __name__ == "__main__":
    main()
