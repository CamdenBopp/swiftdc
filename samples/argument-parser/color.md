# swift-argument-parser examples: `color`

Built from [https://github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) at `d7b6cebecb27`. Every `func` declared in `Examples/color/Color.swift`, in source order: its source, then swiftdc's rendering, then Ghidra's, both for the same address in the same release binary.

swiftdc `5b97024`, Ghidra 12.2, Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1). Regenerate with `Tools/samples/build.sh` and `Tools/samples/render.py`.

## `Color.run`

From `Examples/color/Color.swift`.

```swift
  func run() {
    print("My favorite color is \(fav.rawValue)")
    if let second {
      print("...And my second favorite is \(second.rawValue)!")
    }
  }
```

### `color.Color.run() -> ()` at `0x100001fd4`

swiftdc:

```swift
color.Color.run() -> () {
    let r0 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
    mem128[x0 + 0x10] = (1, 2)
    Swift._StringGuts.grow(self: local_80, 23)
    ArgumentParser.Option.wrappedValue.getter()
    Swift.String.append(self: local_60, ?)
    mem64[x23 + 0x38] = type metadata for Swift.String
    mem64[x23 + 0x20] = x8; mem64[x23 + 0x28] = x9
    Swift.print(_:separator:terminator:)(r0, " ", "\n")
    ArgumentParser.Option.wrappedValue.getter()
    if (w22 != 3) {
        let r1 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
        mem128[x0 + 0x10] = (1, 2)
        Swift._StringGuts.grow(self: local_80, 32)
        Swift.String.append(self: local_80, ?)
        Swift.String.append(self: local_80, "!")
        mem64[x21 + 0x38] = type metadata for Swift.String
        mem64[x21 + 0x20] = x8; mem64[x21 + 0x28] = x9
        Swift.print(_:separator:terminator:)(r1, " ", "\n")
    }
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(Color param_1)
/* WARNING: Removing unreachable block (ram,0x0001000021b8) */
/* WARNING: Removing unreachable block (ram,0x0001000021c8) */
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* color.Color.run() -> () */

void __swift_stdcall color::Color::run(Color param_1)

{
  char *pcVar1;
  void *pvVar2;
  undefined8 uVar3;
  undefined8 uVar4;
  undefined *puVar5;
  undefined8 uVar6;
  Option OVar7;
  char *pcVar8;
  void *in_x3;
  char *pcVar9;
  undefined1 auVar10 [16];
  String SVar11;
  String SVar12;
  String SVar13;
  String SVar14;
  String SVar15;
  String SVar16;
  String separator;
  String SVar17;
  String SVar18;
  String separator_00;
  char local_81;
  
  uVar6 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                     ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>);
  pcVar8 = (char *)0x7;
  auVar10 = _swift_allocObject(uVar6,0x40);
  uVar4 = _UNK_1000847e8;
  uVar3 = _DAT_1000847e0;
  SVar12.str = auVar10._0_8_;
  *(undefined8 *)(SVar12.str + 0x18) = _UNK_1000847e8;
  *(undefined8 *)(SVar12.str + 0x10) = uVar3;
  Swift::_StringGuts::grow(0x17,(_StringGuts)auVar10._8_8_);
  _swift_bridgeObjectRelease(0xe000000000000000);
  OVar7.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Option<color_ColorOptions>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_Option<color_ColorOptions>
                 );
  ArgumentParser::Option::get_wrappedValue(OVar7);
  pcVar9 = (char *)0x65756c62;
  if (local_81 != '\x01') {
    pcVar9 = (char *)0x776f6c6c6579;
  }
  separator.bridgeObject = (void *)0xe400000000000000;
  if (local_81 != '\x01') {
    separator.bridgeObject = (void *)0xe600000000000000;
  }
  pcVar1 = (char *)0x646572;
  if (local_81 != '\0') {
    pcVar1 = pcVar9;
  }
  pvVar2 = (void *)0xe300000000000000;
  if (local_81 != '\0') {
    pvVar2 = separator.bridgeObject;
  }
  SVar11.bridgeObject = pvVar2;
  SVar11.str = pcVar1;
  SVar16.bridgeObject = in_x3;
  SVar16.str = pcVar8;
  Swift::String::append(SVar11,SVar16);
  _swift_bridgeObjectRelease(pvVar2);
  puVar5 = PTR___type_metadata_for_Swift_String_10009dd58;
  *(undefined **)(SVar12.str + 0x38) = PTR___type_metadata_for_Swift_String_10009dd58;
  SVar12.str[0x20] = '\x15';
  SVar12.str[0x21] = '\0';
  SVar12.str[0x22] = '\0';
  SVar12.str[0x23] = '\0';
  SVar12.str[0x24] = '\0';
  SVar12.str[0x25] = '\0';
  SVar12.str[0x26] = '\0';
  SVar12.str[0x27] = -0x30;
  SVar12.str[0x28] = -0x70;
  SVar12.str[0x29] = '\t';
  SVar12.str[0x2a] = '\b';
  SVar12.str[0x2b] = '\0';
  SVar12.str[0x2c] = '\x01';
  SVar12.str[0x2d] = '\0';
  SVar12.str[0x2e] = '\0';
  SVar12.str[0x2f] = -0x80;
  SVar12.bridgeObject = (void *)0x20;
  separator.bridgeObject = (void *)0xa;
  separator.str = (char *)0xe100000000000000;
  separator.bridgeObject = (void *)0xa;
  Swift::_print(SVar12,separator);
  _swift_release(SVar12.str);
  OVar7.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Option<color_ColorOptions_>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_Option<color_ColorOptions_>
                 );
  ArgumentParser::Option::get_wrappedValue(OVar7);
  pcVar9 = (char *)0x7;
  auVar10 = _swift_allocObject(uVar6,0x40);
  SVar15.str = auVar10._0_8_;
  *(undefined8 *)(SVar15.str + 0x18) = uVar4;
  *(undefined8 *)(SVar15.str + 0x10) = uVar3;
  Swift::_StringGuts::grow(0x20,(_StringGuts)auVar10._8_8_);
  _swift_bridgeObjectRelease(0xe000000000000000);
  SVar13.bridgeObject = (void *)0xe600000000000000;
  SVar13.str = (char *)0x776f6c6c6579;
  SVar17.bridgeObject = separator.bridgeObject;
  SVar17.str = pcVar9;
  Swift::String::append(SVar13,SVar17);
  _swift_bridgeObjectRelease(0xe600000000000000);
  SVar14.bridgeObject = (void *)0xe100000000000000;
  SVar14.str = (char *)0x21;
  SVar18.bridgeObject = separator.bridgeObject;
  SVar18.str = pcVar9;
  Swift::String::append(SVar14,SVar18);
  *(undefined **)(SVar15.str + 0x38) = puVar5;
  SVar15.str[0x20] = '\x1d';
  SVar15.str[0x21] = '\0';
  SVar15.str[0x22] = '\0';
  SVar15.str[0x23] = '\0';
  SVar15.str[0x24] = '\0';
  SVar15.str[0x25] = '\0';
  SVar15.str[0x26] = '\0';
  SVar15.str[0x27] = -0x30;
  SVar15.str[0x28] = -0x50;
  SVar15.str[0x29] = '\t';
  SVar15.str[0x2a] = '\b';
  SVar15.str[0x2b] = '\0';
  SVar15.str[0x2c] = '\x01';
  SVar15.str[0x2d] = '\0';
  SVar15.str[0x2e] = '\0';
  SVar15.str[0x2f] = -0x80;
  SVar15.bridgeObject = (void *)0x20;
  separator_00.bridgeObject = (void *)0xa;
  separator_00.str = (char *)0xe100000000000000;
  Swift::_print(SVar15,separator_00);
  _swift_release(SVar15.str);
  return;
}
```
