# swift-argument-parser examples: `repeat`

Built from [https://github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) at `d7b6cebecb27`. Every `func` declared in `Examples/repeat/Repeat.swift`, in source order: its source, then swiftdc's rendering, then Ghidra's, both for the same address in the same release binary.

swiftdc `5b97024`, Ghidra 12.2, Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1). Regenerate with `Tools/samples/build.sh` and `Tools/samples/render.py`.

## `Repeat.run`

From `Examples/repeat/Repeat.swift`.

```swift
  mutating func run() throws {
    let repeatCount = count ?? 2

    for i in 1...repeatCount {
      if includeCounter {
        print("\(i): \(phrase)")
      } else {
        print(phrase)
      }
    }
  }
```

### `repeat.Repeat.run() throws -> ()` at `0x100001fd4`

swiftdc:

```swift
repeat.Repeat.run() throws -> () {
    ArgumentParser.Option.wrappedValue.getter()
    if (x24 < 1) {
        trap()
    } else {
        while (true) {
            ArgumentParser.Flag.wrappedValue.getter()
            let r0 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
            mem128[x0 + 0x10] = (1, 2)
            if (w20 != 1) {
                ArgumentParser.Argument.wrappedValue.getter()
            } else {
                dispatch thunk of Swift.CustomStringConvertible.description.getter(self: local_a0)
                Swift.String.append(self: local_b0, ": ")
                ArgumentParser.Argument.wrappedValue.getter()
                Swift.String.append(self: local_b0, ?)
            }
            mem64[x28 + 0x38] = type metadata for Swift.String
            mem64[x28 + 0x20] = x8; mem64[x28 + 0x28] = x9
            Swift.print(_:separator:terminator:)(r0, " ", "\n")
            if (x24 == x25) {
                break
            } else {
                continue
            }
        }
        machine_return() /* unresolved Swift success/error exit */
    }
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Repeat param_1)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* repeat.Repeat.run() throws -> () */

void __swift_stdcall repeat::Repeat::_run(Repeat param_1)

{
  long lVar1;
  String SVar2;
  undefined8 uVar3;
  undefined8 uVar4;
  code *pcVar5;
  bool bVar6;
  Option OVar7;
  Flag FVar8;
  undefined8 uVar9;
  Argument AVar10;
  char *pcVar11;
  void *in_x3;
  long unaff_x20;
  long lVar12;
  String SVar13;
  String SVar14;
  String SVar15;
  String SVar16;
  String separator;
  char *local_c0;
  void *pvStack_b8;
  String local_b0;
  long local_a0;
  char cStack_98;
  
  OVar7.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Option<Swift_Int_>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Option<Swift_Int_>);
  ArgumentParser::Option::get_wrappedValue(OVar7);
  uVar4 = _UNK_100084228;
  uVar3 = _DAT_100084220;
  lVar1 = 2;
  if (cStack_98 != '\x01') {
    lVar1 = local_a0;
  }
  if (lVar1 < 1) {
                    /* WARNING: Does not return */
    pcVar5 = (code *)SoftwareBreakpoint(1,0x100002224);
    (*pcVar5)();
  }
  lVar12 = 1;
  while( true ) {
    FVar8.unknown =
         (undefined *)
         ___swift_instantiateConcreteTypeFromMangledNameV2
                   (&
                    __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                    ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
    ArgumentParser::Flag::get_wrappedValue(FVar8);
    uVar9 = ___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    pcVar11 = (char *)0x7;
    SVar14.str = (char *)_swift_allocObject(uVar9,0x40);
    *(undefined8 *)(SVar14.str + 0x18) = uVar4;
    *(undefined8 *)(SVar14.str + 0x10) = uVar3;
    if ((char)local_a0 == '\x01') {
      local_b0 = Swift::CustomStringConvertible::get_description();
      SVar13.bridgeObject = (void *)0xe200000000000000;
      SVar13.str = (char *)0x203a;
      SVar15.bridgeObject = in_x3;
      SVar15.str = pcVar11;
      Swift::String::append(SVar13,SVar15);
      local_a0 = *(long *)(unaff_x20 + 0x30);
      AVar10.unknown =
           (undefined *)
           ___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<Swift_String>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<Swift_String>
                     );
      ArgumentParser::Argument::get_wrappedValue(AVar10);
      SVar2.bridgeObject = pvStack_b8;
      SVar2.str = local_c0;
      SVar16.bridgeObject = in_x3;
      SVar16.str = pcVar11;
      Swift::String::append(SVar2,SVar16);
      _swift_bridgeObjectRelease(pvStack_b8);
    }
    else {
      local_a0 = *(long *)(unaff_x20 + 0x30);
      AVar10.unknown =
           (undefined *)
           ___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<Swift_String>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<Swift_String>
                     );
      ArgumentParser::Argument::get_wrappedValue(AVar10);
    }
    *(undefined **)(SVar14.str + 0x38) = PTR___type_metadata_for_Swift_String_10009dc58;
    *(char **)(SVar14.str + 0x20) = local_b0.str;
    *(void **)(SVar14.str + 0x28) = local_b0.bridgeObject;
    SVar14.bridgeObject = (void *)0x20;
    separator.bridgeObject = (void *)0xa;
    separator.str = (char *)0xe100000000000000;
    in_x3 = (void *)0xa;
    Swift::_print(SVar14,separator);
    _swift_release(SVar14.str);
    if (lVar1 == lVar12) break;
    bVar6 = SCARRY8(lVar12,1);
    lVar12 = lVar12 + 1;
    if (bVar6) {
                    /* WARNING: Does not return */
      pcVar5 = (code *)SoftwareBreakpoint(1,0x1000021fc);
      (*pcVar5)();
    }
  }
  return;
}
```
