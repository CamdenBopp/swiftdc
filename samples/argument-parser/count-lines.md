# swift-argument-parser examples: `count-lines`

Built from [https://github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) at `d7b6cebecb27`. Every `func` declared in `Examples/count-lines/CountLines.swift`, in source order: its source, then swiftdc's rendering, then Ghidra's, both for the same address in the same release binary.

swiftdc `5b97024`, Ghidra 12.2, Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1). Regenerate with `Tools/samples/build.sh` and `Tools/samples/render.py`.

## `CountLines.printCount`

From `Examples/count-lines/CountLines.swift`.

```swift
  func printCount(_ count: Int) {
    guard verbose else {
      print(count)
      return
    }

    if let filename = inputFile?.lastPathComponent {
      print("Lines in '\(filename)'", terminator: "")
    } else {
      print("Lines from stdin", terminator: "")
    }

    if let prefix {
      print(", prefixed by '\(prefix)'", terminator: "")
    }

    print(": \(count)")
  }
```

### `count_lines.CountLines.printCount(Swift.Int) -> ()` at `0x10000231c`

swiftdc:

```swift
count_lines.CountLines.printCount(Swift.Int) -> () {
    ArgumentParser.Flag.wrappedValue.getter()
    if (w8 != 1) {
        swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
        mem128[x0 + 0x10] = (1, 2)
        mem64[x0 + 0x38] = type metadata for Swift.Int
        mem64[x0 + 0x20] = arg0
    } else {
        ArgumentParser.Argument.wrappedValue.getter()
        let r0 = getEnumTagSinglePayload value witness for Foundation.URL(?, 1)
        if (r0 != 1) {
            let r2 = Foundation.URL.lastPathComponent.getter(self: ?, r0)
            destroy value witness for Foundation.URL(?)
            let r3 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
            mem128[x0 + 0x10] = (1, 2)
            Swift.String.append(self: local_80, r2)
            Swift.String.append("'")
            mem64[x23 + 0x38] = type metadata for Swift.String
            mem64[x23 + 0x20] = x9
        } else {
            let r1 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
            mem128[x0 + 0x10] = (1, 2)
            mem64[x0 + 0x38] = type metadata for Swift.String
            mem64[x0 + 0x20] = 0xd000000000000010
        }
        mem64[x23 + 0x28] = x8
        Swift.print(_:separator:terminator:)((((r0 & 0xffffffff) != 1) ? r3 : r1), " ", "")
        ArgumentParser.Option.wrappedValue.getter()
        if (x22 != 0) {
            let r4 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
            mem128[x0 + 0x10] = (1, 2)
            Swift._StringGuts.grow(18)
            Swift.String.append(?)
            Swift.String.append("'")
            mem64[x21 + 0x38] = type metadata for Swift.String
            mem64[x21 + 0x20] = x8; mem64[x21 + 0x28] = x9
            Swift.print(_:separator:terminator:)(r4, " ", "")
        }
        swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
        mem128[x0 + 0x10] = (1, 2)
        Swift.String.append(self: local_80, dispatch thunk of Swift.CustomStringConvertible.description.getter(self: local_90))
        mem64[x21 + 0x38] = type metadata for Swift.String
        mem64[x21 + 0x20] = x8; mem64[x21 + 0x28] = x9
    }
    Swift.print(_:separator:terminator:)(?, " ", "\n")
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall printCount(__int64 param_1, CountLines param_2)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* count_lines.CountLines.printCount(Swift.Int) -> () */

void __swift_stdcall count_lines::CountLines::printCount(__int64 param_1,CountLines param_2)

{
  undefined8 *puVar1;
  undefined *puVar2;
  long lVar3;
  CountLines CVar4;
  Flag FVar5;
  Argument AVar6;
  URL UVar7;
  URL UVar8;
  undefined8 uVar9;
  char *pcVar10;
  Option OVar11;
  char *pcVar12;
  void *in_x3;
  void *pvVar13;
  long extraout_x8;
  long unaff_x20;
  long lVar14;
  String SVar15;
  undefined1 auVar16 [16];
  String SVar17;
  String SVar18;
  String SVar19;
  String SVar20;
  String SVar21;
  String SVar22;
  String SVar23;
  String SVar24;
  String SVar25;
  String SVar26;
  String separator;
  char *local_90;
  void *local_88;
  undefined8 local_80;
  undefined8 uStack_78;
  undefined1 local_70;
  
  lVar3 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                     &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
  (*(code *)PTR____chkstk_darwin_10009da10)
            (*(long *)(*(long *)(lVar3 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  lVar3 = (long)&local_90 - extraout_x8;
  CVar4 = typeMetadataAccessor();
  puVar1 = (undefined8 *)(unaff_x20 + *(int *)(CVar4.unknown + 0x18));
  local_70 = *(undefined1 *)(puVar1 + 2);
  uStack_78 = puVar1[1];
  local_80 = *puVar1;
  FVar5.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar5);
  if ((char)local_90 == '\x01') {
    AVar6.unknown =
         (undefined *)
         ___swift_instantiateConcreteTypeFromMangledNameV2
                   (&
                    __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<Foundation_URL_>
                    ,&
                     __mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<Foundation_URL_>
                   );
    ArgumentParser::Argument::get_wrappedValue(AVar6);
    UVar7 = Foundation::URL::typeMetadataAccessor();
    lVar14 = *(long *)(UVar7.unknown + -8);
    UVar8.unknown = (undefined *)(**(code **)(lVar14 + 0x30))(lVar3,1,UVar7.unknown);
    puVar2 = PTR___type_metadata_for_Swift_String_10009dc40;
    if ((int)UVar8.unknown == 1) {
      __outlined_destroy_of_Foundation_URL_(lVar3);
      uVar9 = ___swift_instantiateConcreteTypeFromMangledNameV2
                        (&
                         __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                         ,&
                          __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                        );
      pcVar10 = (char *)_swift_allocObject(uVar9,0x40,7);
      uVar9 = _DAT_1000854a0;
      *(undefined8 *)(pcVar10 + 0x18) = _UNK_1000854a8;
      *(undefined8 *)(pcVar10 + 0x10) = uVar9;
      *(undefined **)(pcVar10 + 0x38) = puVar2;
      pcVar10[0x20] = '\x10';
      pcVar10[0x21] = '\0';
      pcVar10[0x22] = '\0';
      pcVar10[0x23] = '\0';
      pcVar10[0x24] = '\0';
      pcVar10[0x25] = '\0';
      pcVar10[0x26] = '\0';
      pcVar10[0x27] = -0x30;
      uVar9 = 0x8000000100081630;
    }
    else {
      SVar20 = Foundation::URL::get_lastPathComponent(UVar8);
      (**(code **)(lVar14 + 8))(lVar3,UVar7.unknown);
      uVar9 = ___swift_instantiateConcreteTypeFromMangledNameV2
                        (&
                         __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                         ,&
                          __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                        );
      pcVar12 = (char *)0x7;
      pcVar10 = (char *)_swift_allocObject(uVar9,0x40);
      uVar9 = _DAT_1000854a0;
      *(undefined8 *)(pcVar10 + 0x18) = _UNK_1000854a8;
      *(undefined8 *)(pcVar10 + 0x10) = uVar9;
      local_80 = 0x6e692073656e694c;
      uStack_78 = 0xea00000000002720;
      SVar22.bridgeObject = in_x3;
      SVar22.str = pcVar12;
      Swift::String::append(SVar20,SVar22);
      _swift_bridgeObjectRelease(SVar20.bridgeObject);
      SVar20.bridgeObject = (void *)0xe100000000000000;
      SVar20.str = (char *)0x27;
      SVar23.bridgeObject = in_x3;
      SVar23.str = pcVar12;
      Swift::String::append(SVar20,SVar23);
      *(undefined **)(pcVar10 + 0x38) = puVar2;
      *(undefined8 *)(pcVar10 + 0x20) = local_80;
      uVar9 = uStack_78;
    }
    *(undefined8 *)(pcVar10 + 0x28) = uVar9;
    SVar15.bridgeObject = (void *)0x20;
    SVar15.str = pcVar10;
    pvVar13 = (void *)0x0;
    Swift::_print(SVar15,(String)ZEXT816(0xe100000000000000));
    _swift_release(pcVar10);
    puVar1 = (undefined8 *)(unaff_x20 + *(int *)(CVar4.unknown + 0x14));
    local_70 = *(undefined1 *)(puVar1 + 2);
    uStack_78 = puVar1[1];
    local_80 = *puVar1;
    OVar11.unknown =
         (undefined *)
         ___swift_instantiateConcreteTypeFromMangledNameV2
                   (&
                    __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Option<Swift_String_>
                    ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Option<Swift_String_>)
    ;
    ArgumentParser::Option::get_wrappedValue(OVar11);
    if (local_88 != (void *)0x0) {
      uVar9 = ___swift_instantiateConcreteTypeFromMangledNameV2
                        (&
                         __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                         ,&
                          __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                        );
      pcVar10 = (char *)0x7;
      auVar16 = _swift_allocObject(uVar9,0x40);
      uVar9 = _DAT_1000854a0;
      SVar19.str = auVar16._0_8_;
      *(undefined8 *)(SVar19.str + 0x18) = _UNK_1000854a8;
      *(undefined8 *)(SVar19.str + 0x10) = uVar9;
      local_80 = 0;
      uStack_78 = 0xe000000000000000;
      Swift::_StringGuts::grow(0x12,(_StringGuts)auVar16._8_8_);
      _swift_bridgeObjectRelease(uStack_78);
      local_80 = 0x786966657270202c;
      uStack_78 = 0xef27207962206465;
      SVar17.bridgeObject = local_88;
      SVar17.str = local_90;
      SVar24.bridgeObject = pvVar13;
      SVar24.str = pcVar10;
      Swift::String::append(SVar17,SVar24);
      _swift_bridgeObjectRelease(local_88);
      SVar18.bridgeObject = (void *)0xe100000000000000;
      SVar18.str = (char *)0x27;
      SVar25.bridgeObject = pvVar13;
      SVar25.str = pcVar10;
      Swift::String::append(SVar18,SVar25);
      *(undefined **)(SVar19.str + 0x38) = puVar2;
      *(undefined8 *)(SVar19.str + 0x20) = local_80;
      *(undefined8 *)(SVar19.str + 0x28) = uStack_78;
      SVar19.bridgeObject = (void *)0x20;
      pvVar13 = (void *)0x0;
      Swift::_print(SVar19,(String)ZEXT816(0xe100000000000000));
      _swift_release(SVar19.str);
    }
    uVar9 = ___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    pcVar12 = (char *)0x7;
    pcVar10 = (char *)_swift_allocObject(uVar9,0x40);
    uVar9 = _DAT_1000854a0;
    *(undefined8 *)(pcVar10 + 0x18) = _UNK_1000854a8;
    *(undefined8 *)(pcVar10 + 0x10) = uVar9;
    local_80 = 0x203a;
    uStack_78 = 0xe200000000000000;
    local_90 = (char *)param_1;
    SVar20 = Swift::CustomStringConvertible::get_description();
    SVar26.bridgeObject = pvVar13;
    SVar26.str = pcVar12;
    Swift::String::append(SVar20,SVar26);
    _swift_bridgeObjectRelease(SVar20.bridgeObject);
    *(undefined **)(pcVar10 + 0x38) = puVar2;
    *(undefined8 *)(pcVar10 + 0x20) = local_80;
    *(undefined8 *)(pcVar10 + 0x28) = uStack_78;
  }
  else {
    uVar9 = ___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    pcVar10 = (char *)_swift_allocObject(uVar9,0x40,7);
    uVar9 = _DAT_1000854a0;
    *(undefined8 *)(pcVar10 + 0x18) = _UNK_1000854a8;
    *(undefined8 *)(pcVar10 + 0x10) = uVar9;
    *(undefined **)(pcVar10 + 0x38) = PTR___type_metadata_for_Swift_Int_10009de08;
    *(__int64 *)(pcVar10 + 0x20) = param_1;
  }
  SVar21.bridgeObject = (void *)0x20;
  SVar21.str = pcVar10;
  separator.bridgeObject = (void *)0xa;
  separator.str = (char *)0xe100000000000000;
  Swift::_print(SVar21,separator);
  _swift_release(pcVar10);
  return;
}
```

## `CountLines.run`

From `Examples/count-lines/CountLines.swift`.

```swift
  mutating func run() async throws {
    var lineCount = 0
    for try await line in try fileHandle.bytes.lines {
      if let prefix {
        lineCount += line.starts(with: prefix) ? 1 : 0
      } else {
        lineCount += 1
      }
    }
    printCount(lineCount)
  }
```

### `count_lines.CountLines.run() async throws -> ()` at `0x100002738`

swiftdc:

```swift
count_lines.CountLines.run() async throws -> () {
    // async function: 4 resume funclet(s): resume #1 @0x100002800, resume #2 @0x100002958, resume #3 @0x100002b2c, resume #4 @0x1000029bc
    await hop_to_executor(generic)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(CountLines param_1)
/* count_lines.CountLines.run() async throws -> () */

void __swift_stdcall count_lines::CountLines::_run(CountLines param_1)

{
  long lVar1;
  undefined8 uVar2;
  AsyncBytes AVar3;
  undefined8 unaff_x20;
  long unaff_x22;
  
  *(undefined8 *)(unaff_x22 + 0x38) = unaff_x20;
  lVar1 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Foundation_AsyncLineSequence<(extension_in_Foundation):__C_NSFileHandle_AsyncBytes>
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Foundation_AsyncLineSequence<(extension_in_Foundation):__C_NSFileHandle_AsyncBytes>
                    );
  *(long *)(unaff_x22 + 0x40) = lVar1;
  lVar1 = *(long *)(lVar1 + -8);
  *(long *)(unaff_x22 + 0x48) = lVar1;
  uVar2 = _swift_task_alloc(*(long *)(lVar1 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x50) = uVar2;
  AVar3 = AsyncBytes::_typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x58) = AVar3.unknown;
  lVar1 = *(long *)(AVar3.unknown + -8);
  *(long *)(unaff_x22 + 0x60) = lVar1;
  uVar2 = _swift_task_alloc(*(long *)(lVar1 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x68) = uVar2;
  lVar1 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Foundation_AsyncLineSequence<(extension_in_Foundation):__C_NSFileHandle_AsyncBytes>_AsyncIterator
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Foundation_AsyncLineSequence<(extension_in_Foundation):__C_NSFileHandle_AsyncBytes>_AsyncIterator
                    );
  *(long *)(unaff_x22 + 0x70) = lVar1;
  lVar1 = *(long *)(lVar1 + -8);
  *(long *)(unaff_x22 + 0x78) = lVar1;
  uVar2 = _swift_task_alloc(*(long *)(lVar1 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x80) = uVar2;
  _swift_task_switch(_run,0,0);
  return;
}
```
