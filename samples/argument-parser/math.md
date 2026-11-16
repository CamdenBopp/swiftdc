# swift-argument-parser examples: `math`

Built from [https://github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) at `d7b6cebecb27`. Every `func` declared in `Examples/math/Math.swift`, in source order: its source, then swiftdc's rendering, then Ghidra's, both for the same address in the same release binary.

swiftdc `5b97024`, Ghidra 12.2, Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1). Regenerate with `Tools/samples/build.sh` and `Tools/samples/render.py`.

## `Math.format`

From `Examples/math/Math.swift`.

```swift
  static func format(_ result: Int, usingHex: Bool) -> String {
    usingHex
      ? String(result, radix: 16)
      : String(result)
  }
```

The optimizer inlined it into every caller, so the binary has no body of its own to decompile.

## `Math.Add.run`

From `Examples/math/Math.swift`.

```swift
    mutating func run() {
      let result = options.values.reduce(0, +)
      print(format(result, usingHex: options.hexadecimalOutput))
    }
```

### `math.Math.Add.run() -> ()` at `0x1000024f0`

swiftdc:

```swift
math.Math.Add.run() -> () {
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Argument.wrappedValue.getter()
    sub_1000051b0(?, ?, ?)
    merged outlined consume of …(?, ?, ?)
    if (x8 == 0) {
        loc_1000025dc:
        let r0 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
        mem128[x0 + 0x10] = (1, 2)
        ArgumentParser.OptionGroup.wrappedValue.getter()
        ArgumentParser.Flag.wrappedValue.getter()
        sub_1000051b0(?, ?, ?)
        merged outlined consume of …(?, ?, ?)
        if (w8 != 1) {
            dispatch thunk of Swift.CustomStringConvertible.description.getter(self: local_e0)
        } else {
            Swift.String.init<A where A: Swift.BinaryInteger>(_:radix:uppercase:)(local_e0, 16, false)
        }
        mem64[x21 + 0x38] = type metadata for Swift.String
        mem64[x21 + 0x20] = x0; mem64[x21 + 0x28] = x1
        Swift.print(_:separator:terminator:)(r0, " ", "\n")
        return
    } else {
        while (true) {
            if (x8 != 0) {
                continue
            } else {
                break
            }
            break
        }
        goto loc_1000025dc
    }
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(Add param_1)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* math.Math.Add.run() -> () */

void __swift_stdcall math::Math::Add::run(Add param_1)

{
  code *pcVar1;
  bool bVar2;
  Argument AVar3;
  undefined8 uVar4;
  Flag FVar5;
  void *in_x2;
  void *pvVar6;
  long lVar7;
  long *plVar8;
  long *unaff_x20;
  long lVar9;
  OptionGroup OVar10;
  OptionGroup OVar11;
  undefined1 auVar12 [16];
  String SVar13;
  String SVar14;
  char local_110;
  undefined7 uStack_10f;
  undefined8 uStack_108;
  undefined1 local_100;
  undefined8 local_f8;
  undefined1 local_e8;
  long local_e0;
  long lStack_d8;
  long local_d0;
  long lStack_c8;
  long local_c0;
  long lStack_b8;
  long lStack_b0;
  long lStack_a8;
  long local_a0;
  long lStack_98;
  long lStack_90;
  long lStack_88;
  long local_80;
  long lStack_78;
  long lStack_70;
  long lStack_68;
  
  lStack_98 = unaff_x20[1];
  local_a0 = *unaff_x20;
  lStack_88 = unaff_x20[3];
  lStack_90 = unaff_x20[2];
  lStack_78 = unaff_x20[5];
  local_80 = unaff_x20[4];
  lStack_68 = unaff_x20[7];
  lStack_70 = unaff_x20[6];
  lStack_d8 = unaff_x20[1];
  local_e0 = *unaff_x20;
  lStack_c8 = unaff_x20[3];
  local_d0 = unaff_x20[2];
  lStack_b8 = unaff_x20[5];
  local_c0 = unaff_x20[4];
  lStack_a8 = unaff_x20[7];
  lStack_b0 = unaff_x20[6];
  OVar10._0_16_ =
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<math_Options>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<math_Options>
                 );
  OVar11._0_8_ = OVar10._0_8_;
  OVar10.title.bridgeObject = in_x2;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar10);
  local_d0 = CONCAT71(local_d0._1_7_,local_e8);
  AVar3.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_Int]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_Int]>);
  ArgumentParser::Argument::get_wrappedValue(AVar3);
  FUN_1000051b0(CONCAT71(uStack_10f,local_110),uStack_108,local_100);
  _outlined_consume();
  lVar7 = *(long *)(CONCAT71(uStack_10f,local_110) + 0x10);
  if (lVar7 == 0) {
    lVar9 = 0;
  }
  else {
    lVar9 = 0;
    plVar8 = (long *)(CONCAT71(uStack_10f,local_110) + 0x20);
    do {
      bVar2 = SCARRY8(lVar9,*plVar8);
      lVar9 = lVar9 + *plVar8;
      if (bVar2) {
                    /* WARNING: Does not return */
        pcVar1 = (code *)SoftwareBreakpoint(1,0x10000272c);
        (*pcVar1)();
      }
      lVar7 = lVar7 + -1;
      plVar8 = plVar8 + 1;
    } while (lVar7 != 0);
  }
  _swift_bridgeObjectRelease();
  uVar4 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                     ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>);
  pvVar6 = (void *)0x7;
  auVar12 = _swift_allocObject(uVar4,0x40);
  uVar4 = _DAT_10008c940;
  OVar11.title.str = auVar12._8_8_;
  SVar14.str = auVar12._0_8_;
  *(undefined8 *)(SVar14.str + 0x18) = _UNK_10008c948;
  *(undefined8 *)(SVar14.str + 0x10) = uVar4;
  lStack_d8 = lStack_98;
  local_e0 = local_a0;
  lStack_c8 = lStack_88;
  local_d0 = lStack_90;
  lStack_b8 = lStack_78;
  local_c0 = local_80;
  lStack_a8 = lStack_68;
  lStack_b0 = lStack_70;
  OVar11.title.bridgeObject = pvVar6;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar11);
  local_d0 = CONCAT71(local_d0._1_7_,local_100);
  FVar5.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar5);
  FUN_1000051b0(CONCAT71(uStack_10f,local_110),uStack_108,local_100);
  _outlined_consume();
  local_e0 = lVar9;
  if (local_110 == '\x01') {
    __int64::_lazy_protocol_witness_table_accessor();
    SVar13 = Swift::String::_init
                       (&local_e0,0x10,0,PTR___type_metadata_for_Swift_Int_1000a6730,local_f8);
  }
  else {
    SVar13 = Swift::CustomStringConvertible::get_description();
  }
  *(undefined **)(SVar14.str + 0x38) = PTR___type_metadata_for_Swift_String_1000a6558;
  *(String *)(SVar14.str + 0x20) = SVar13;
  SVar14.bridgeObject = (void *)0x20;
  SVar13.bridgeObject = (void *)0xa;
  SVar13.str = (char *)0xe100000000000000;
  Swift::_print(SVar14,SVar13);
  _swift_release(SVar14.str);
  return;
}
```

## `Math.Multiply.run`

From `Examples/math/Math.swift`.

```swift
    mutating func run() {
      let result = options.values.reduce(1, *)
      print(format(result, usingHex: options.hexadecimalOutput))
    }
```

### `math.Math.Multiply.run() -> ()` at `0x100002958`

swiftdc:

```swift
math.Math.Multiply.run() -> () {
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Argument.wrappedValue.getter()
    sub_1000051b0(?, ?, ?)
    merged outlined consume of …(?, ?, ?)
    if (x8 == 0) {
        loc_100002a50:
        let r0 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
        mem128[x0 + 0x10] = (1, 2)
        ArgumentParser.OptionGroup.wrappedValue.getter()
        ArgumentParser.Flag.wrappedValue.getter()
        sub_1000051b0(?, ?, ?)
        merged outlined consume of …(?, ?, ?)
        if (w8 != 1) {
            dispatch thunk of Swift.CustomStringConvertible.description.getter(self: local_e0)
        } else {
            Swift.String.init<A where A: Swift.BinaryInteger>(_:radix:uppercase:)(local_e0, 16, false)
        }
        mem64[x21 + 0x38] = type metadata for Swift.String
        mem64[x21 + 0x20] = x0; mem64[x21 + 0x28] = x1
        Swift.print(_:separator:terminator:)(r0, " ", "\n")
        return
    } else {
        while (true) {
            if (x10 != (x27 >>ˢ 63)) {
                trap()
            } else {
                if (x8 != 0) {
                    continue
                } else {
                    break
                }
                break
            }
        }
        goto loc_100002a50
    }
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(Multiply param_1)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* math.Math.Multiply.run() -> () */

void __swift_stdcall math::Math::Multiply::run(Multiply param_1)

{
  code *pcVar1;
  Argument AVar2;
  undefined8 uVar3;
  Flag FVar4;
  void *in_x2;
  void *pvVar5;
  long lVar6;
  long *plVar7;
  long lVar8;
  long *unaff_x20;
  long lVar9;
  OptionGroup OVar10;
  OptionGroup OVar11;
  undefined1 auVar12 [16];
  String SVar13;
  String SVar14;
  char local_110;
  undefined7 uStack_10f;
  undefined8 uStack_108;
  undefined1 local_100;
  undefined8 local_f8;
  undefined1 local_e8;
  long local_e0;
  long lStack_d8;
  long local_d0;
  long lStack_c8;
  long local_c0;
  long lStack_b8;
  long lStack_b0;
  long lStack_a8;
  long local_a0;
  long lStack_98;
  long lStack_90;
  long lStack_88;
  long local_80;
  long lStack_78;
  long lStack_70;
  long lStack_68;
  
  lStack_98 = unaff_x20[1];
  local_a0 = *unaff_x20;
  lStack_88 = unaff_x20[3];
  lStack_90 = unaff_x20[2];
  lStack_78 = unaff_x20[5];
  local_80 = unaff_x20[4];
  lStack_68 = unaff_x20[7];
  lStack_70 = unaff_x20[6];
  lStack_d8 = unaff_x20[1];
  local_e0 = *unaff_x20;
  lStack_c8 = unaff_x20[3];
  local_d0 = unaff_x20[2];
  lStack_b8 = unaff_x20[5];
  local_c0 = unaff_x20[4];
  lStack_a8 = unaff_x20[7];
  lStack_b0 = unaff_x20[6];
  OVar10._0_16_ =
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<math_Options>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<math_Options>
                 );
  OVar11._0_8_ = OVar10._0_8_;
  OVar10.title.bridgeObject = in_x2;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar10);
  local_d0 = CONCAT71(local_d0._1_7_,local_e8);
  AVar2.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_Int]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_Int]>);
  ArgumentParser::Argument::get_wrappedValue(AVar2);
  FUN_1000051b0(CONCAT71(uStack_10f,local_110),uStack_108,local_100);
  _outlined_consume();
  lVar6 = *(long *)(CONCAT71(uStack_10f,local_110) + 0x10);
  if (lVar6 == 0) {
    lVar9 = 1;
  }
  else {
    plVar7 = (long *)(CONCAT71(uStack_10f,local_110) + 0x20);
    lVar8 = 1;
    do {
      lVar9 = lVar8 * *plVar7;
      if (SUB168(SEXT816(lVar8) * SEXT816(*plVar7),8) != lVar9 >> 0x3f) {
                    /* WARNING: Does not return */
        pcVar1 = (code *)SoftwareBreakpoint(1,0x100002ba0);
        (*pcVar1)();
      }
      lVar6 = lVar6 + -1;
      plVar7 = plVar7 + 1;
      lVar8 = lVar9;
    } while (lVar6 != 0);
  }
  _swift_bridgeObjectRelease();
  uVar3 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                     ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>);
  pvVar5 = (void *)0x7;
  auVar12 = _swift_allocObject(uVar3,0x40);
  uVar3 = _DAT_10008c940;
  OVar11.title.str = auVar12._8_8_;
  SVar14.str = auVar12._0_8_;
  *(undefined8 *)(SVar14.str + 0x18) = _UNK_10008c948;
  *(undefined8 *)(SVar14.str + 0x10) = uVar3;
  lStack_d8 = lStack_98;
  local_e0 = local_a0;
  lStack_c8 = lStack_88;
  local_d0 = lStack_90;
  lStack_b8 = lStack_78;
  local_c0 = local_80;
  lStack_a8 = lStack_68;
  lStack_b0 = lStack_70;
  OVar11.title.bridgeObject = pvVar5;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar11);
  local_d0 = CONCAT71(local_d0._1_7_,local_100);
  FVar4.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar4);
  FUN_1000051b0(CONCAT71(uStack_10f,local_110),uStack_108,local_100);
  _outlined_consume();
  local_e0 = lVar9;
  if (local_110 == '\x01') {
    __int64::_lazy_protocol_witness_table_accessor();
    SVar13 = Swift::String::_init
                       (&local_e0,0x10,0,PTR___type_metadata_for_Swift_Int_1000a6730,local_f8);
  }
  else {
    SVar13 = Swift::CustomStringConvertible::get_description();
  }
  *(undefined **)(SVar14.str + 0x38) = PTR___type_metadata_for_Swift_String_1000a6558;
  *(String *)(SVar14.str + 0x20) = SVar13;
  SVar14.bridgeObject = (void *)0x20;
  SVar13.bridgeObject = (void *)0xa;
  SVar13.str = (char *)0xe100000000000000;
  Swift::_print(SVar14,SVar13);
  _swift_release(SVar14.str);
  return;
}
```

## `Math.Statistics.Average.validate`

From `Examples/math/Math.swift`.

```swift
    func validate() throws {
      if (kind == .median || kind == .mode) && values.isEmpty {
        throw ValidationError(
          "Please provide at least one value to calculate the \(kind).")
      }
    }
```

### `math.Math.Statistics.Average.validate() throws -> ()` at `0x10000345c`

swiftdc:

```swift
math.Math.Statistics.Average.validate() throws -> () {
    ArgumentParser.Option.wrappedValue.getter()
    if (w8 == 1) {
        loc_1000034e4:
        ArgumentParser.Argument.wrappedValue.getter()
        if (x20 == 0) {
            Swift._StringGuts.grow(self: local_50, 54)
            Swift.String.append(self: local_60, "Please provide at least one value to calculate the ")
            ArgumentParser.Option.wrappedValue.getter()
            Swift._print_unlocked<A, B where B: Swift.TextOutputStream>(local_61, local_60)
            Swift.String.append(self: local_60, ".")
            let r0 = swift_allocError(0x1000a2058, lazy protocol witness table accessor for type ArgumentParser.ValidationError and conformance ArgumentParser.ValidationError : Swift.Error in ArgumentParser(), 0, false)
            mem64[x1] = x19; mem64[x1 + 0x8] = x20
            swift_willThrow(r0)
            throw ?
        }
    } else {
        ArgumentParser.Option.wrappedValue.getter()
        if (w8 == 2) {
            goto loc_1000034e4
        }
    }
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $validate(Average param_1)
/* math.Math.Statistics.Average.validate() throws -> () */

void __swift_stdcall math::Math::Statistics::Average::_validate(Average param_1)

{
  long lVar1;
  Option OVar2;
  Argument AVar3;
  undefined8 uVar4;
  _StringGuts extraout_x1;
  long *extraout_x1_00;
  char *in_x2;
  char *pcVar5;
  void *in_x3;
  undefined *puVar6;
  undefined8 *unaff_x20;
  long lVar7;
  String SVar8;
  String SVar9;
  String SVar10;
  String SVar11;
  undefined1 uStack_61;
  long local_60;
  long lStack_58;
  long local_50;
  long lStack_48;
  undefined1 local_40;
  
  lStack_48 = unaff_x20[1];
  local_50 = *unaff_x20;
  local_40 = *(undefined1 *)(unaff_x20 + 2);
  OVar2.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Option<math_Math_Statistics_Average_Kind>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_Option<math_Math_Statistics_Average_Kind>
                 );
  ArgumentParser::Option::get_wrappedValue(OVar2);
  if ((char)local_60 != '\x01') {
    lStack_48 = unaff_x20[1];
    local_50 = *unaff_x20;
    local_40 = *(undefined1 *)(unaff_x20 + 2);
    ArgumentParser::Option::get_wrappedValue(OVar2);
    if ((char)local_60 != '\x02') {
      return;
    }
  }
  lStack_48 = unaff_x20[4];
  local_50 = unaff_x20[3];
  local_40 = *(undefined1 *)(unaff_x20 + 5);
  AVar3.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                 );
  ArgumentParser::Argument::get_wrappedValue(AVar3);
  lVar7 = *(long *)(local_60 + 0x10);
  _swift_bridgeObjectRelease();
  if (lVar7 == 0) {
    local_50 = 0;
    lStack_48 = -0x2000000000000000;
    Swift::_StringGuts::grow(0x36,extraout_x1);
    local_60 = local_50;
    lStack_58 = lStack_48;
    SVar8.bridgeObject = (void *)0x8000000100088a60;
    SVar8.str = (char *)0xd000000000000033;
    SVar10.bridgeObject = in_x3;
    SVar10.str = in_x2;
    Swift::String::append(SVar8,SVar10);
    lStack_48 = unaff_x20[1];
    local_50 = *unaff_x20;
    local_40 = *(undefined1 *)(unaff_x20 + 2);
    ArgumentParser::Option::get_wrappedValue(OVar2);
    pcVar5 = "\x01\x02";
    puVar6 = PTR___type_metadata_for_Swift_DefaultStringInterpolation_1000a6c50;
    Swift::__print_unlocked
              (&uStack_61,&local_60,&__type_metadata_for_math_Math_Statistics_Average_Kind,
               PTR___type_metadata_for_Swift_DefaultStringInterpolation_1000a6c50,
               PTR___protocol_witness_table_for_Swift_DefaultStringInterpolation___Swift_TextOutputStream_in_Swift_1000a6c60
              );
    SVar9.bridgeObject = (void *)0xe100000000000000;
    SVar9.str = (char *)0x2e;
    uVar4 = 0x2e;
    SVar11.bridgeObject = puVar6;
    SVar11.str = pcVar5;
    Swift::String::append(SVar9,SVar11);
    lVar1 = lStack_58;
    lVar7 = local_60;
    ArgumentParser::ValidationError::_lazy_protocol_witness_table_accessor();
    _swift_allocError(&__type_metadata_for_ArgumentParser_ValidationError,uVar4,0,0);
    *extraout_x1_00 = lVar7;
    extraout_x1_00[1] = lVar1;
    _swift_willThrow();
  }
  return;
}
```

## `Math.Statistics.Average.calculateMean`

From `Examples/math/Math.swift`.

```swift
    func calculateMean() -> Double {
      guard !values.isEmpty else {
        return 0
      }

      let sum = values.reduce(0, +)
      return sum / Double(values.count)
    }
```

The binary keeps it only as the specialization below, a copy the optimizer rewrote for its callers.

### `function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMean() -> Swift.Double` at `0x100008bf4`

swiftdc:

```swift
function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMean() -> Swift.Double {
    ArgumentParser.Argument.wrappedValue.getter()
    if (x20 != 0) {
        ArgumentParser.Argument.wrappedValue.getter()
        if (x8 != 0) {
            if (x8 >=ᵁ 8) {
                while (x11 != 0) {
                }
                if (x8 != x9) {
                    loc_100008cfc:
                    while (x8 != 0) {
                    }
                }
            } else {
                goto loc_100008cfc
            }
        }
        ArgumentParser.Argument.wrappedValue.getter()
    }
    return ?
}
```

Ghidra:

```c
// double __swift_stdcall $calculateMean(Average param_1)
/* function signature specialization <Arg[0] = Exploded> of
   math.Math.Statistics.Average.calculateMean() -> Swift.Double */

double __swift_stdcall math::Math::Statistics::Average::_calculateMean(Average param_1)

{
  Argument AVar1;
  ulong uVar2;
  ulong uVar3;
  double *pdVar4;
  ulong uVar5;
  long lVar6;
  double dVar7;
  double dVar8;
  undefined8 uVar9;
  long local_70;
  
  AVar1.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                 );
  ArgumentParser::Argument::get_wrappedValue(AVar1);
  lVar6 = *(long *)(local_70 + 0x10);
  _swift_bridgeObjectRelease();
  if (lVar6 == 0) {
    return 0.0;
  }
  ArgumentParser::Argument::get_wrappedValue(AVar1);
  uVar2 = *(ulong *)(local_70 + 0x10);
  if (uVar2 == 0) {
    dVar8 = 0.0;
  }
  else {
    if (uVar2 < 8) {
      uVar3 = 0;
      dVar8 = 0.0;
    }
    else {
      uVar3 = uVar2 & 0x7ffffffffffffff8;
      pdVar4 = (double *)(local_70 + 0x50);
      dVar8 = 0.0;
      uVar5 = uVar3;
      do {
        dVar8 = dVar8 + pdVar4[-6] + pdVar4[-5] + pdVar4[-4] + pdVar4[-3] + pdVar4[-2] + pdVar4[-1]
                + *pdVar4 + pdVar4[1];
        pdVar4 = pdVar4 + 8;
        uVar5 = uVar5 - 8;
      } while (uVar5 != 0);
      if (uVar2 == uVar3) goto LAB_100008d18;
    }
    lVar6 = uVar2 - uVar3;
    pdVar4 = (double *)(local_70 + uVar3 * 8 + 0x20);
    do {
      dVar8 = dVar8 + *pdVar4;
      lVar6 = lVar6 + -1;
      pdVar4 = pdVar4 + 1;
    } while (lVar6 != 0);
  }
LAB_100008d18:
  _swift_bridgeObjectRelease();
  ArgumentParser::Argument::get_wrappedValue(AVar1);
  uVar9 = *(undefined8 *)(local_70 + 0x10);
  _swift_bridgeObjectRelease();
  dVar7 = (double)NEON_ucvtf(uVar9);
  return dVar8 / dVar7;
}
```

## `Math.Statistics.Average.calculateMedian`

From `Examples/math/Math.swift`.

```swift
    func calculateMedian() -> Double {
      guard !values.isEmpty else {
        return 0
      }

      let sorted = values.sorted()
      let mid = sorted.count / 2
      if sorted.count.isMultiple(of: 2) {
        return (sorted[mid - 1] + sorted[mid]) / 2
      } else {
        return sorted[mid]
      }
    }
```

The binary keeps it only as the specialization below, a copy the optimizer rewrote for its callers.

### `function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMedian() -> Swift.Double` at `0x100008d64`

swiftdc:

```swift
function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMedian() -> Swift.Double {
    ArgumentParser.Argument.wrappedValue.getter()
    if (x20 == 0) {
        loc_100008e7c:
        return ?
    } else {
        ArgumentParser.Argument.wrappedValue.getter()
        if (!isKnownUniquelyReferenced(?)) {
            generic specialization <Swift.Double> of Swift._ContiguousArrayBuffer._consumeAndCreateNew()
        }
        generic specialization <Swift.Double> of Swift.UnsafeMutableBufferPointer._stableSortImpl(by:)(self: local_68, …)
        if (bit 0 of w9 set) {
            goto loc_100008e7c
        } else {
            if (x9 <ᵁ 2) {
                trap()
            } else {
                goto loc_100008e7c
            }
        }
    }
}
```

Ghidra:

```c
// double __swift_stdcall $calculateMedian(Average param_1)
/* function signature specialization <Arg[0] = Exploded> of
   math.Math.Statistics.Average.calculateMedian() -> Swift.Double */

double __swift_stdcall math::Math::Statistics::Average::_calculateMedian(Average param_1)

{
  code *pcVar1;
  Argument AVar2;
  ulong uVar3;
  _ContiguousArrayBuffer _Var4;
  long lVar5;
  double dVar6;
  double dVar7;
  _ContiguousArrayBuffer local_70;
  
  AVar2.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                 );
  ArgumentParser::Argument::get_wrappedValue(AVar2);
  lVar5 = *(long *)(local_70.unknown + 0x10);
  _swift_bridgeObjectRelease();
  if (lVar5 == 0) {
    dVar6 = 0.0;
  }
  else {
    ArgumentParser::Argument::get_wrappedValue(AVar2);
    _swift_bridgeObjectRetain(local_70.unknown);
    uVar3 = _swift_isUniquelyReferenced_nonNull_native();
    _Var4.unknown = local_70.unknown;
    if ((uVar3 & 1) == 0) {
      _Var4.unknown = (undefined *)Swift::_ContiguousArrayBuffer::_consumeAndCreateNew(local_70);
    }
    Swift::UnsafeMutableBufferPointer::__stableSortImpl((UnsafeMutableBufferPointer)0x1000071a8);
    _swift_bridgeObjectRelease(local_70.unknown);
    uVar3 = *(ulong *)(_Var4.unknown + 0x10);
    if ((uVar3 & 1) == 0) {
      if (uVar3 < 2) {
                    /* WARNING: Does not return */
        pcVar1 = (code *)SoftwareBreakpoint(1,0x100008e9c);
        (*pcVar1)();
      }
      dVar6 = *(double *)((long)(_Var4.unknown + (uVar3 >> 1) * 8 + 0x20) + -8);
      dVar7 = *(double *)(_Var4.unknown + (uVar3 >> 1) * 8 + 0x20);
      _swift_release(_Var4.unknown);
      dVar6 = (dVar6 + dVar7) * 0.5;
    }
    else {
      dVar6 = *(double *)(_Var4.unknown + (uVar3 >> 1) * 8 + 0x20);
      _swift_release(_Var4.unknown);
    }
  }
  return dVar6;
}
```

## `Math.Statistics.Average.calculateMode`

From `Examples/math/Math.swift`.

```swift
    func calculateMode() -> [Double] {
      guard !values.isEmpty else {
        return []
      }

      let grouped = Dictionary(grouping: values, by: { $0 })
      let highestFrequency = grouped.lazy.map { $0.value.count }.max() ?? 0
      return grouped.filter { _, v in v.count == highestFrequency }
        .map { k, _ in k }
    }
```

The binary keeps it only as the specialization below, a copy the optimizer rewrote for its callers.

### `function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMode() -> [Swift.Double]` at `0x1000090a4`

swiftdc:

```swift
function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMode() -> Swift.Array<Swift.Double> {
    ArgumentParser.Argument.wrappedValue.getter()
    if (x20 == 0) {
        loc_100009278:
        return ?
    } else {
        ArgumentParser.Argument.wrappedValue.getter()
        let r0 = function signature specialization <Arg[0] = Owned To Guaranteed> of function signature specialization <Arg[1] = [Closure Propagated : $s4math4MathV10StatisticsV7AverageV13calculateModeSaySdGyFS2dXEfU_, Argument Types : []> of generic specialization <Swift.Double, Swift.Array<Swift.Double>, Swift.Never> of Swift.Dictionary.init<A, B where B == Swift.Array<A1.Element>, A1: Swift.Sequence, B1: Swift.Error>(grouping:by:)(?)
        generic specialization <Swift.Dictionary<Swift.Double, Swift.Array<Swift.Double>>, Swift.Int> of Swift.LazyMapSequence.Iterator.next(self: local_88, r0)
        if ((w1 & 0xff) != 1) {
            if (x10 == 0) {
                while (true) {
                    while (true) {
                        if (x11 >= x8) {
                            goto loc_100009244
                        } else {
                            if (x10 != 0) {
                                goto loc_100009208
                            } else {
                                if (?) {
                                    continue
                                } else {
                                    goto loc_100009204
                                }
                                goto loc_100009204
                            }
                        }
                    }
                    loc_1000091dc:
                    goto loc_10000920c  // loop
                    loc_100009208:
                    loc_10000920c:
                    while (true) {
                        if (x10 != 0) {
                            goto loc_1000091dc
                        } else {
                            goto loc_100009240
                        }
                    }
                    loc_100009240:
                    continue
                }
            } else {
                goto loc_1000091dc
            }
        } else {
            loc_10000924c:
            let r1 = function signature specialization <Arg[0] = [Closure Propagated : $s4math4MathV10StatisticsV7AverageV13calculateModeSaySdGyFSbSd_AItXEfU1_, Argument Types : [Swift.Int]> of generic specialization <Swift.Double, Swift.Array<Swift.Double>, Swift.Never> of Swift._NativeDictionary.filter<A where A1: Swift.Error>(r0, ?)
            function signature specialization <Arg[0] = [Closure Propagated : $sSdSaySdGSdIgygd_Sd3key_AA5valuetSds5NeverOIegnrzr_TR71$s4math4MathV10StatisticsV7AverageV13calculateModeSaySdGyFS2d_AItXEfU2_Tf3nnnpf_n, Argument Types : []> of generic specialization <Swift.Dictionary<Swift.Double, Swift.Array<Swift.Double>>, Swift.Double, Swift.Never> of (extension in Swift):Swift.Collection.map<A, B where B1: Swift.Error>(r1)
            goto loc_100009278
        }
    }
    loc_100009204:
    trap()
    loc_100009244:
    goto loc_10000924c
}
```

Ghidra:

```c
// Array<double> __swift_stdcall $calculateMode(Average param_1)
/* function signature specialization <Arg[0] = Exploded> of
   math.Math.Statistics.Average.calculateMode() -> [Swift.Double] */

undefined * __swift_stdcall math::Math::Statistics::Average::_calculateMode(Average param_1)

{
  code *pcVar1;
  Argument AVar2;
  Dictionary<undefined,Array<undefined>> DVar3;
  _NativeDictionary<undefined,undefined> _Var4;
  _NativeDictionary<undefined,undefined> _Var5;
  ulong uVar6;
  ulong uVar7;
  ulong uVar8;
  long lVar9;
  long lVar10;
  undefined1 auVar11 [12];
  long lStack_70;
  long local_48;
  
  AVar2.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                 );
  ArgumentParser::Argument::get_wrappedValue(AVar2);
  lVar10 = *(long *)(local_48 + 0x10);
  _swift_bridgeObjectRelease();
  if (lVar10 == 0) {
    _Var5.unknown = PTR___swiftEmptyArrayStorage_1000a6f38;
  }
  else {
    ArgumentParser::Argument::get_wrappedValue(AVar2);
    DVar3 = Swift::Dictionary::_init();
    _swift_bridgeObjectRelease(local_48);
    uVar6 = -1L << ((ulong)(byte)DVar3.unknown[0x20] & 0x3f);
    uVar7 = -uVar6;
    uVar8 = 0xffffffffffffffff;
    if (uVar7 < 0x40) {
      uVar8 = ~(-1L << (uVar7 & 0x3f));
    }
    uVar8 = uVar8 & *(ulong *)(DVar3.unknown + 0x40);
    lStack_70 = 0;
    auVar11 = _swift_bridgeObjectRetain(DVar3.unknown);
    Swift::LazyMapSequence::Iterator::_next((Iterator)auVar11._0_8_);
    lVar10 = auVar11._0_8_;
    if ((auVar11._8_4_ & 0xff) != 1) {
      if (uVar8 == 0) goto joined_r0x0001000091e8;
      do {
        do {
          uVar7 = (uVar8 & 0xaaaaaaaaaaaaaaaa) >> 1 | (uVar8 & 0x5555555555555555) << 1;
          uVar7 = (uVar7 & 0xcccccccccccccccc) >> 2 | (uVar7 & 0x3333333333333333) << 2;
          uVar7 = (uVar7 & 0xf0f0f0f0f0f0f0f0) >> 4 | (uVar7 & 0xf0f0f0f0f0f0f0f) << 4;
          uVar7 = (uVar7 & 0xff00ff00ff00ff00) >> 8 | (uVar7 & 0xff00ff00ff00ff) << 8;
          uVar7 = (uVar7 & 0xffff0000ffff0000) >> 0x10 | (uVar7 & 0xffff0000ffff) << 0x10;
          uVar8 = uVar8 - 1 & uVar8;
          lVar9 = *(long *)(*(long *)(*(long *)(DVar3.unknown + 0x38) +
                                      LZCOUNT(uVar7 >> 0x20 | uVar7 << 0x20) * 8 + lStack_70 * 0x200
                                     ) + 0x10);
          if (lVar10 <= lVar9) {
            lVar10 = lVar9;
          }
        } while (uVar8 != 0);
joined_r0x0001000091e8:
        do {
          if (SCARRY8(lStack_70,1)) {
                    /* WARNING: Does not return */
            pcVar1 = (code *)SoftwareBreakpoint(1,0x100009298);
            (*pcVar1)();
          }
          lStack_70 = lStack_70 + 1;
          if ((long)(~uVar6 + 0x40 >> 6) <= lStack_70) {
            _outlined_consume((_Variant)(__int8)DVar3.unknown);
            goto LAB_10000924c;
          }
          uVar8 = *(ulong *)((long)(DVar3.unknown + 0x40) + lStack_70 * 8);
        } while (uVar8 == 0);
      } while( true );
    }
    _outlined_consume((_Variant)(__int8)DVar3.unknown);
LAB_10000924c:
    _Var4 = Swift::_NativeDictionary::_filter((_NativeDictionary)DVar3.unknown);
    _swift_bridgeObjectRelease(DVar3.unknown);
    _Var5 = _Var4;
    (extension_Swift)::Swift::Collection::_map();
    _swift_release(_Var4.unknown);
  }
  return _Var5.unknown;
}
```

## `Math.Statistics.Average.run`

From `Examples/math/Math.swift`.

```swift
    mutating func run() {
      switch kind {
      case .mean:
        print(calculateMean())
      case .median:
        print(calculateMedian())
      case .mode:
        let result = calculateMode()
          .map(String.init(describing:))
          .joined(separator: " ")
        print(result)
      }
    }
```

### `math.Math.Statistics.Average.run() -> ()` at `0x10000381c`

swiftdc:

```swift
math.Math.Statistics.Average.run() -> () {
    ArgumentParser.Option.wrappedValue.getter()
    if (w8 == 0) {
        swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
        mem128[x0 + 0x10] = (1, 2)
        function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMean(self._values[0..<8], self._values[8..<16], (self._values[16..<17] & 0xffffffff))
        loc_1000038f8:
        mem64[x20 + 0x38] = type metadata for Swift.Double
        mem64[x20 + 0x20] = d0
    } else {
        if (w8 != 1) {
            function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMode(self._values[0..<8], self._values[8..<16], (self._values[16..<17] & 0xffffffff))
            if (x22 != 0) {
                generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_70, …)
                while (true) {
                    Swift.Double.description.getter()
                    if (x25 >=ᵁ (x8 >>ᵁ 1)) {
                        generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_70, …)
                    }
                    mem64[x19 + 0x10] = x23
                    mem64[x8 + 0x20] = x0; mem64[x8 + 0x28] = x1
                    if (x22 != 0) {
                        continue
                    } else {
                        break
                    }
                    break
                }
            }
            (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(self: local_70, " ", type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x1000a85b8, 0x1000a85b0, 0x10008cf00, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
            swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
            mem128[x0 + 0x10] = (1, 2)
            mem64[x0 + 0x38] = type metadata for Swift.String
            mem64[x0 + 0x20] = x21; mem64[x0 + 0x28] = x22
        } else {
            swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
            mem128[x0 + 0x10] = (1, 2)
            function signature specialization <Arg[0] = Exploded> of math.Math.Statistics.Average.calculateMedian(self._values[0..<8], self._values[8..<16], (self._values[16..<17] & 0xffffffff))
            goto loc_1000038f8
        }
    }
    Swift.print(_:separator:terminator:)(?, " ", "\n")
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(Average param_1)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* math.Math.Statistics.Average.run() -> () */

void __swift_stdcall math::Math::Statistics::Average::run(Average param_1)

{
  ulong uVar1;
  Option OVar2;
  undefined8 uVar3;
  char *pcVar4;
  Average AVar5;
  ContiguousArray in_x3;
  undefined *puVar6;
  long unaff_x20;
  long minimumCapacity;
  long lVar7;
  double dVar8;
  String SVar9;
  String SVar10;
  String separator;
  char local_71;
  
  OVar2.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Option<math_Math_Statistics_Average_Kind>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_Option<math_Math_Statistics_Average_Kind>
                 );
  ArgumentParser::Option::get_wrappedValue(OVar2);
  if (local_71 == '\0') {
    uVar3 = ___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    pcVar4 = (char *)_swift_allocObject(uVar3,0x40,7);
    uVar3 = _DAT_10008c940;
    *(undefined8 *)(pcVar4 + 0x18) = _UNK_10008c948;
    *(undefined8 *)(pcVar4 + 0x10) = uVar3;
    dVar8 = _calculateMean((Average)*(undefined **)(unaff_x20 + 0x18));
  }
  else {
    if (local_71 != '\x01') {
      AVar5.unknown = *(undefined **)(unaff_x20 + 0x18);
      _calculateMode(AVar5);
      puVar6 = PTR___swiftEmptyArrayStorage_1000a6f38;
      minimumCapacity = *(long *)(AVar5.unknown + 0x10);
      if (minimumCapacity == 0) {
        _swift_bridgeObjectRelease(AVar5.unknown);
        puVar6 = PTR___swiftEmptyArrayStorage_1000a6f38;
      }
      else {
        Swift::ContiguousArray::_createNewBuffer(false,minimumCapacity,false,in_x3);
        lVar7 = 0x20;
        do {
          SVar9 = double::get_description(*(double *)(AVar5.unknown + lVar7));
          uVar1 = *(ulong *)(puVar6 + 0x10);
          if (*(ulong *)(puVar6 + 0x18) >> 1 <= uVar1) {
            Swift::ContiguousArray::_createNewBuffer
                      (1 < *(ulong *)(puVar6 + 0x18),uVar1 + 1,true,in_x3);
          }
          *(ulong *)(puVar6 + 0x10) = uVar1 + 1;
          *(String *)(puVar6 + uVar1 * 0x10 + 0x20) = SVar9;
          lVar7 = lVar7 + 8;
          minimumCapacity = minimumCapacity + -1;
        } while (minimumCapacity != 0);
        _swift_bridgeObjectRelease(AVar5.unknown);
      }
      ___swift_instantiateConcreteTypeFromMangledNameV2
                (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
                 &__mangled_name_ref_for_type_metadata_for__Swift_String_);
      ArgumentParser::OptionGroup<Options>::_lazy_protocol_witness_table_accessor();
      SVar9.bridgeObject = (void *)0xe100000000000000;
      SVar9.str = (char *)0x20;
      SVar9 = (extension_Swift)::Swift::BidirectionalCollection::_joined(SVar9);
      _swift_bridgeObjectRelease(puVar6);
      uVar3 = ___swift_instantiateConcreteTypeFromMangledNameV2
                        (&
                         __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                         ,&
                          __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                        );
      pcVar4 = (char *)_swift_allocObject(uVar3,0x40,7);
      uVar3 = _DAT_10008c940;
      *(undefined8 *)(pcVar4 + 0x18) = _UNK_10008c948;
      *(undefined8 *)(pcVar4 + 0x10) = uVar3;
      *(undefined **)(pcVar4 + 0x38) = PTR___type_metadata_for_Swift_String_1000a6558;
      *(String *)(pcVar4 + 0x20) = SVar9;
      goto LAB_100003a7c;
    }
    uVar3 = ___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    pcVar4 = (char *)_swift_allocObject(uVar3,0x40,7);
    uVar3 = _DAT_10008c940;
    *(undefined8 *)(pcVar4 + 0x18) = _UNK_10008c948;
    *(undefined8 *)(pcVar4 + 0x10) = uVar3;
    dVar8 = _calculateMedian((Average)*(undefined **)(unaff_x20 + 0x18));
  }
  *(undefined **)(pcVar4 + 0x38) = PTR___type_metadata_for_Swift_Double_1000a66e0;
  *(double *)(pcVar4 + 0x20) = dVar8;
LAB_100003a7c:
  SVar10.bridgeObject = (void *)0x20;
  SVar10.str = pcVar4;
  separator.bridgeObject = (void *)0xa;
  separator.str = (char *)0xe100000000000000;
  Swift::_print(SVar10,separator);
  _swift_release(pcVar4);
  return;
}
```

## `Math.Statistics.StandardDeviation.run`

From `Examples/math/Math.swift`.

```swift
    mutating func run() {
      if values.isEmpty {
        print(0.0)
      } else {
        let sum = values.reduce(0, +)
        let mean = sum / Double(values.count)
        let squaredErrors =
          values
          .map { $0 - mean }
          .map { $0 * $0 }
        let variance = squaredErrors.reduce(0, +) / Double(values.count)
        let result = variance.squareRoot()
        print(result)
      }
    }
```

### `math.Math.Statistics.StandardDeviation.run() -> ()` at `0x100003e48`

swiftdc:

```swift
math.Math.Statistics.StandardDeviation.run() -> () {
    ArgumentParser.Argument.wrappedValue.getter()
    if (x20 != 0) {
        ArgumentParser.Argument.wrappedValue.getter()
        if (x8 != 0) {
            if (x8 >=ᵁ 8) {
                while (x11 != 0) {
                }
                if (x8 != x9) {
                    loc_100003f54:
                    while (x8 != 0) {
                    }
                }
            } else {
                goto loc_100003f54
            }
        }
        ArgumentParser.Argument.wrappedValue.getter()
        ArgumentParser.Argument.wrappedValue.getter()
        if (x23 == 0) {
            if (x22 != 0) {
                loc_100004088:
                generic specialization <Swift.Double> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_88, …)
                while (true) {
                    if (x25 >=ᵁ (x8 >>ᵁ 1)) {
                        generic specialization <Swift.Double> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_88, …)
                    }
                    mem64[x20 + 0x10] = x23
                    mem64[x8 + 0x20] = d0
                    if (x22 != 0) {
                        continue
                    } else {
                        break
                    }
                    break
                }
            }
        } else {
            generic specialization <Swift.Double> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_88, …)
            while (true) {
                if (x24 >=ᵁ (x8 >>ᵁ 1)) {
                    generic specialization <Swift.Double> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_88, …)
                }
                mem64[x21 + 0x10] = x25
                mem64[x8 + 0x20] = d0
                if (x23 != 0) {
                    continue
                } else {
                    break
                }
                break
            }
            if (x22 != 0) {
                goto loc_100004088
            }
        }
        if (x8 != 0) {
            if (x8 >=ᵁ 8) {
                while (x11 != 0) {
                }
                if (x8 != x9) {
                    loc_100004190:
                    while (x8 != 0) {
                    }
                }
            } else {
                goto loc_100004190
            }
        }
        ArgumentParser.Argument.wrappedValue.getter()
    }
    let r0 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
    mem128[x0 + 0x10] = (1, 2)
    mem64[x0 + 0x38] = type metadata for Swift.Double
    mem64[x0 + 0x20] = d8
    Swift.print(_:separator:terminator:)(r0, " ", "\n")
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(StandardDeviation param_1)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* math.Math.Statistics.StandardDeviation.run() -> () */

void __swift_stdcall math::Math::Statistics::StandardDeviation::run(StandardDeviation param_1)

{
  undefined *puVar1;
  undefined *puVar2;
  Argument AVar3;
  ContiguousArray in_x3;
  ulong uVar4;
  ulong uVar5;
  double *pdVar6;
  ulong uVar7;
  long lVar8;
  long lVar9;
  double dVar10;
  double dVar11;
  undefined8 uVar12;
  double dVar13;
  String SVar14;
  String separator;
  long local_90;
  
  AVar3.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_Double]>
                 );
  ArgumentParser::Argument::get_wrappedValue(AVar3);
  lVar8 = *(long *)(local_90 + 0x10);
  _swift_bridgeObjectRelease();
  if (lVar8 == 0) {
    dVar11 = 0.0;
    goto LAB_1000041e4;
  }
  ArgumentParser::Argument::get_wrappedValue(AVar3);
  uVar4 = *(ulong *)(local_90 + 0x10);
  if (uVar4 == 0) {
    dVar11 = 0.0;
  }
  else {
    if (uVar4 < 8) {
      uVar5 = 0;
      dVar11 = 0.0;
    }
    else {
      uVar5 = uVar4 & 0x7ffffffffffffff8;
      pdVar6 = (double *)(local_90 + 0x50);
      dVar11 = 0.0;
      uVar7 = uVar5;
      do {
        dVar11 = dVar11 + pdVar6[-6] + pdVar6[-5] + pdVar6[-4] + pdVar6[-3] + pdVar6[-2] +
                 pdVar6[-1] + *pdVar6 + pdVar6[1];
        pdVar6 = pdVar6 + 8;
        uVar7 = uVar7 - 8;
      } while (uVar7 != 0);
      if (uVar4 == uVar5) goto LAB_100003f70;
    }
    lVar8 = uVar4 - uVar5;
    pdVar6 = (double *)(local_90 + uVar5 * 8 + 0x20);
    do {
      dVar11 = dVar11 + *pdVar6;
      lVar8 = lVar8 + -1;
      pdVar6 = pdVar6 + 1;
    } while (lVar8 != 0);
  }
LAB_100003f70:
  _swift_bridgeObjectRelease();
  ArgumentParser::Argument::get_wrappedValue(AVar3);
  uVar12 = *(undefined8 *)(local_90 + 0x10);
  _swift_bridgeObjectRelease();
  ArgumentParser::Argument::get_wrappedValue(AVar3);
  puVar2 = PTR___swiftEmptyArrayStorage_1000a6f38;
  lVar8 = *(long *)(local_90 + 0x10);
  if (lVar8 == 0) {
    _swift_bridgeObjectRelease(local_90);
    lVar8 = *(long *)(PTR___swiftEmptyArrayStorage_1000a6f38 + 0x10);
    puVar1 = puVar2;
    puVar2 = PTR___swiftEmptyArrayStorage_1000a6f38;
  }
  else {
    dVar10 = (double)NEON_ucvtf(uVar12);
    Swift::ContiguousArray::_createNewBuffer(false,lVar8,false,in_x3);
    lVar9 = 0x20;
    uVar4 = *(ulong *)(puVar2 + 0x10);
    do {
      dVar13 = *(double *)(local_90 + lVar9);
      uVar7 = uVar4 + 1;
      if (*(ulong *)(puVar2 + 0x18) >> 1 <= uVar4) {
        Swift::ContiguousArray::_createNewBuffer(1 < *(ulong *)(puVar2 + 0x18),uVar7,true,in_x3);
      }
      *(ulong *)(puVar2 + 0x10) = uVar7;
      *(double *)(puVar2 + uVar4 * 8 + 0x20) = dVar13 - dVar11 / dVar10;
      lVar9 = lVar9 + 8;
      lVar8 = lVar8 + -1;
      uVar4 = uVar7;
    } while (lVar8 != 0);
    _swift_bridgeObjectRelease(local_90);
    lVar8 = *(long *)(puVar2 + 0x10);
    puVar1 = PTR___swiftEmptyArrayStorage_1000a6f38;
  }
  if (lVar8 != 0) {
    Swift::ContiguousArray::_createNewBuffer(false,lVar8,false,in_x3);
    lVar9 = 0x20;
    uVar4 = *(ulong *)(puVar1 + 0x10);
    do {
      dVar11 = *(double *)(puVar2 + lVar9);
      uVar7 = uVar4 + 1;
      if (*(ulong *)(puVar1 + 0x18) >> 1 <= uVar4) {
        Swift::ContiguousArray::_createNewBuffer(1 < *(ulong *)(puVar1 + 0x18),uVar7,true,in_x3);
      }
      *(ulong *)(puVar1 + 0x10) = uVar7;
      *(double *)(puVar1 + uVar4 * 8 + 0x20) = dVar11 * dVar11;
      lVar9 = lVar9 + 8;
      lVar8 = lVar8 + -1;
      uVar4 = uVar7;
    } while (lVar8 != 0);
  }
  _swift_bridgeObjectRelease(puVar2);
  uVar4 = *(ulong *)(puVar1 + 0x10);
  if (uVar4 == 0) {
    dVar11 = 0.0;
  }
  else {
    if (uVar4 < 8) {
      uVar5 = 0;
      dVar11 = 0.0;
    }
    else {
      uVar5 = uVar4 & 0x7ffffffffffffff8;
      pdVar6 = (double *)(puVar1 + 0x50);
      dVar11 = 0.0;
      uVar7 = uVar5;
      do {
        dVar11 = dVar11 + pdVar6[-6] + pdVar6[-5] + pdVar6[-4] + pdVar6[-3] + pdVar6[-2] +
                 pdVar6[-1] + *pdVar6 + pdVar6[1];
        pdVar6 = pdVar6 + 8;
        uVar7 = uVar7 - 8;
      } while (uVar7 != 0);
      if (uVar4 == uVar5) goto LAB_1000041ac;
    }
    lVar8 = uVar4 - uVar5;
    pdVar6 = (double *)(puVar1 + uVar5 * 8 + 0x20);
    do {
      dVar11 = dVar11 + *pdVar6;
      lVar8 = lVar8 + -1;
      pdVar6 = pdVar6 + 1;
    } while (lVar8 != 0);
  }
LAB_1000041ac:
  _swift_bridgeObjectRelease(puVar1);
  ArgumentParser::Argument::get_wrappedValue(AVar3);
  uVar12 = *(undefined8 *)(local_90 + 0x10);
  _swift_bridgeObjectRelease();
  dVar10 = (double)NEON_ucvtf(uVar12);
  dVar11 = SQRT(dVar11 / dVar10);
LAB_1000041e4:
  uVar12 = ___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>)
  ;
  SVar14.str = (char *)_swift_allocObject(uVar12,0x40,7);
  uVar12 = _DAT_10008c940;
  *(undefined8 *)(SVar14.str + 0x18) = _UNK_10008c948;
  *(undefined8 *)(SVar14.str + 0x10) = uVar12;
  *(undefined **)(SVar14.str + 0x38) = PTR___type_metadata_for_Swift_Double_1000a66e0;
  *(double *)(SVar14.str + 0x20) = dVar11;
  SVar14.bridgeObject = (void *)0x20;
  separator.bridgeObject = (void *)0xa;
  separator.str = (char *)0xe100000000000000;
  Swift::_print(SVar14,separator);
  _swift_release(SVar14.str);
  return;
}
```

## `Math.Statistics.Quantiles.validate`

From `Examples/math/Math.swift`.

```swift
    func validate() throws {
      if testSuccessExitCode {
        throw ExitCode.success
      }

      if testFailureExitCode {
        throw ExitCode.failure
      }

      if testValidationExitCode {
        throw ExitCode.validationFailure
      }

      if let exitCode = testCustomExitCode {
        throw ExitCode(exitCode)
      }
    }
```

### `math.Math.Statistics.Quantiles.validate() throws -> ()` at `0x1000045e4`

swiftdc:

```swift
math.Math.Statistics.Quantiles.validate() throws -> () {
    ArgumentParser.Flag.wrappedValue.getter()
    if (w8 != 1) {
        ArgumentParser.Flag.wrappedValue.getter()
        if (w8 != 1) {
            ArgumentParser.Flag.wrappedValue.getter()
            if (w8 != 1) {
                ArgumentParser.Option.wrappedValue.getter()
                if (w8 != 1) {
                    loc_1000046fc:
                    let r0 = swift_allocError(0x1000a2080, lazy protocol witness table accessor for type ArgumentParser.ExitCode and conformance ArgumentParser.ExitCode : Swift.Error in ArgumentParser(), 0, false)
                    mem32[x1] = w20
                    swift_willThrow(r0)
                    throw ?
                }
            } else {
                ArgumentParser.ExitCode.validationFailure.unsafeMutableAddressor()
                goto loc_1000046fc
            }
        } else {
            ArgumentParser.ExitCode.failure.unsafeMutableAddressor()
            goto loc_1000046fc
        }
    } else {
        ArgumentParser.ExitCode.success.unsafeMutableAddressor()
        goto loc_1000046fc
    }
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $validate(Quantiles param_1)
/* math.Math.Statistics.Quantiles.validate() throws -> () */

void __swift_stdcall math::Math::Statistics::Quantiles::_validate(Quantiles param_1)

{
  Flag FVar1;
  Flag FVar2;
  undefined4 *extraout_x1;
  undefined4 local_58;
  char local_54;
  
  FVar1.unknown =
       (undefined *)
       ___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  FVar2.unknown = FVar1.unknown;
  ArgumentParser::Flag::get_wrappedValue(FVar1);
  if ((char)local_58 == '\x01') {
    ArgumentParser::ExitCode::success::unsafeMutableAddressor();
    local_58 = *(undefined4 *)FVar2.unknown;
    FVar1.unknown = FVar2.unknown;
  }
  else {
    FVar2.unknown = FVar1.unknown;
    ArgumentParser::Flag::get_wrappedValue(FVar1);
    if ((char)local_58 == '\x01') {
      ArgumentParser::ExitCode::failure::unsafeMutableAddressor();
      local_58 = *(undefined4 *)FVar2.unknown;
      FVar1.unknown = FVar2.unknown;
    }
    else {
      ArgumentParser::Flag::get_wrappedValue(FVar1);
      if ((char)local_58 == '\x01') {
        ArgumentParser::ExitCode::validationFailure::unsafeMutableAddressor();
        local_58 = *(undefined4 *)FVar1.unknown;
      }
      else {
        FVar1.unknown =
             (undefined *)
             ___swift_instantiateConcreteTypeFromMangledNameV2
                       (&
                        __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Option<Swift_Int32_>
                        ,&
                         __mangled_name_ref_for_type_metadata_for_ArgumentParser_Option<Swift_Int32_>
                       );
        ArgumentParser::Option::get_wrappedValue((Option)FVar1.unknown);
        if (local_54 == '\x01') {
          return;
        }
      }
    }
  }
  ArgumentParser::ExitCode::_lazy_protocol_witness_table_accessor();
  _swift_allocError(&__type_metadata_for_ArgumentParser_ExitCode,FVar1.unknown,0,0);
  *extraout_x1 = local_58;
  _swift_willThrow();
  return;
}
```

## `customCompletion`

From `Examples/math/Math.swift`.

```swift
func customCompletion(_ s: [String], _: Int, _: String) -> [String] {
  (s.last ?? "").starts(with: "a")
    ? ["aardvark", "aaaaalbert"]
    : ["hello", "helicopter", "heliotrope"]
}
```

### `math.customCompletion([Swift.String], Swift.Int, Swift.String) -> [Swift.String]` at `0x100004b18`

swiftdc:

```swift
math.customCompletion(Swift.Array<Swift.String>, Swift.Int, Swift.String) -> Swift.Array<Swift.String> {
    let r0 = generic specialization <Swift.String, Swift.String> of (extension in Swift):Swift.Sequence< where A.Element: Swift.Equatable>.starts<A where A1: Swift.Sequence, A.Element == A1.Element>(with:)(…)
    return swift_initStaticObject(type metadata for Swift._ContiguousArrayStorage<Swift.String>, ((((r0 & 1) != 0) ? 0x1000a87d0 : 0x1000a8778) + 8))
}
```

Ghidra:

```c
// Array<String> __swift_stdcall customCompletion(Array<String> param_1, __int64 param_2, String param_3)
/* math.customCompletion([Swift.String], Swift.Int, Swift.String) -> [Swift.String] */

void __swift_stdcall math::customCompletion(long param_1)

{
  long *plVar1;
  code *pcVar2;
  bool bVar3;
  undefined8 uVar4;
  long lVar5;
  long lVar6;
  
  lVar5 = *(long *)(param_1 + 0x10);
  if (lVar5 == 0) {
    lVar5 = 0;
    lVar6 = -0x2000000000000000;
  }
  else {
    plVar1 = (long *)(param_1 + 0x10) + lVar5 * 2;
    lVar5 = *plVar1;
    lVar6 = plVar1[1];
    _swift_bridgeObjectRetain(lVar6);
  }
  bVar3 = (extension_Swift)::Swift::Sequence::_starts(0x61,0xe100000000000000,lVar5,lVar6);
  _swift_bridgeObjectRelease(lVar6);
  uVar4 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                    );
  pcVar2 = _customCompletion;
  if (!bVar3) {
    pcVar2 = _customCompletion;
  }
  _swift_initStaticObject(uVar4,pcVar2 + 8);
  return;
}
```

## `customDeprecatedCompletion`

From `Examples/math/Math.swift`.

```swift
func customDeprecatedCompletion(_ s: [String]) -> [String] {
  (s.last ?? "").starts(with: "a")
    ? ["aardvark", "aaaaalbert"]
    : ["hello", "helicopter", "heliotrope"]
}
```

### `math.customDeprecatedCompletion([Swift.String]) -> [Swift.String]` at `0x100004cfc`

swiftdc:

```swift
math.customDeprecatedCompletion(Swift.Array<Swift.String>) -> Swift.Array<Swift.String> {
    let r0 = generic specialization <Swift.String, Swift.String> of (extension in Swift):Swift.Sequence< where A.Element: Swift.Equatable>.starts<A where A1: Swift.Sequence, A.Element == A1.Element>(with:)(…)
    return swift_initStaticObject(type metadata for Swift._ContiguousArrayStorage<Swift.String>, ((((r0 & 1) != 0) ? 0x1000a8730 : 0x1000a86d8) + 8))
}
```

Ghidra:

```c
// Array<String> __swift_stdcall customDeprecatedCompletion(Array<String> param_1)
/* math.customDeprecatedCompletion([Swift.String]) -> [Swift.String] */

void __swift_stdcall math::customDeprecatedCompletion(long param_1)

{
  long *plVar1;
  code *pcVar2;
  bool bVar3;
  undefined8 uVar4;
  long lVar5;
  long lVar6;
  
  lVar5 = *(long *)(param_1 + 0x10);
  if (lVar5 == 0) {
    lVar5 = 0;
    lVar6 = -0x2000000000000000;
  }
  else {
    plVar1 = (long *)(param_1 + 0x10) + lVar5 * 2;
    lVar5 = *plVar1;
    lVar6 = plVar1[1];
    _swift_bridgeObjectRetain(lVar6);
  }
  bVar3 = (extension_Swift)::Swift::Sequence::_starts(0x61,0xe100000000000000,lVar5,lVar6);
  _swift_bridgeObjectRelease(lVar6);
  uVar4 = ___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                    );
  pcVar2 = _customDeprecatedCompletion;
  if (!bVar3) {
    pcVar2 = _customDeprecatedCompletion;
  }
  _swift_initStaticObject(uVar4,pcVar2 + 8);
  return;
}
```
