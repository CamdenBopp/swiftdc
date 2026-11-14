# mas, the Mac App Store command line: `commands`

Built from [https://github.com/mas-cli/mas](https://github.com/mas-cli/mas) at `6c5032dc8da7`. Every `func` declared in `Sources/mas/Commands/MAS.Config.swift`, `Sources/mas/Commands/MAS.Get.swift`, `Sources/mas/Commands/MAS.Home.swift`, `Sources/mas/Commands/MAS.Install.swift`, `Sources/mas/Commands/MAS.List.swift`, `Sources/mas/Commands/MAS.Lookup.swift`, `Sources/mas/Commands/MAS.Lucky.swift`, `Sources/mas/Commands/MAS.Open.swift`, `Sources/mas/Commands/MAS.Outdated.swift`, `Sources/mas/Commands/MAS.Reset.swift`, `Sources/mas/Commands/MAS.Search.swift`, `Sources/mas/Commands/MAS.Seller.swift`, `Sources/mas/Commands/MAS.SignOut.swift`, `Sources/mas/Commands/MAS.Uninstall.swift`, `Sources/mas/Commands/MAS.Update.swift`, `Sources/mas/Commands/MAS.Version.swift`, in source order: its source, then swiftdc's rendering, then Ghidra's, both for the same address in the same release binary.

swiftdc `5b97024`, Ghidra 12.2, Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1). Regenerate with `Tools/samples/build.sh` and `Tools/samples/render.py`.

## `MAS.Config.run`

From `Sources/mas/Commands/MAS.Config.swift`.

```swift
		func run() {
			outputFormatOptionGroup.info(
				JSON.Object( // swiftformat:disable:this wrap wrapArguments
					dictionaryLiteral: // swiftlint:disable vertical_parameter_alignment_on_call
						("mas", .string(version)), // swiftformat:disable indent
						("slice", .string(runningSliceArchitecture)),
						("slices", .string(supportedSliceArchitectures.joined(separator: " "))),
						("dist", .string(distribution)),
						("origin", .string(gitOrigin)),
						("rev", .string(gitRevision)),
						("swift", .string(swiftVersion)),
						("driver", .string(swiftDriverVersion)),
						("store", .string(appStoreRegion)),
						("region", .string(macRegion)),
						("macos", .string(macOSVersion)),
						("build", .string(configStringValue("kern.osversion"))),
						("mac", .string(configStringValue("hw.product"))),
						("cpu", .string(configStringValue("machdep.cpu.brand_string"))),
						("arch", .string(configStringValue("hw.machine"))), // swiftlint:enable vertical_parameter_alignment_on_call
				), // swiftformat:enable indent
			)
		}
```

### `mas.MAS.Config.run() -> ()` at `0x100001dd4`

swiftdc:

```swift
mas.MAS.Config.run() -> () {
    ArgumentParser.OptionGroup.wrappedValue.getter()
    swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Any>, local_e8)
    mem128[x0 + 0x10] = (1, 2)
    let r0 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<(JSONAST.JSON.Key, JSONAST.JSON.Node)>, local_360)
    mem128[x0 + 0x10] = (15, 30)
    mem64[x9 + 0x20] = 0x73616d
    mem64[x0 + 0x28] = 0xe300000000000000
    mem128[x0 + 0x30] = (43, 0xe100000000000000)
    mem8[x0 + 0x40] = 32
    mem64[x0 + 0x48] = 0x6563696c73; mem64[x0 + 0x50] = 0xe500000000000000
    mem128[x0 + 0x58] = (0x34366d7261, 0xe500000000000000)
    mem8[x0 + 0x68] = 32
    mem64[x0 + 0x70] = 0x736563696c73; mem64[x0 + 0x78] = 0xe600000000000000
    mas.(supportedSliceArchitectures in _9B019CD41686B44C533F7CA58115A60C).getter()
    (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(self: local_90, " ", type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x10060b0a0, 0x10060b098, 0x10054ff80, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
    mem64[x26 + 0x80] = x20; mem64[x26 + 0x88] = x24
    mem8[x26 + 0x90] = 32
    mem64[x26 + 0x98] = 0x74736964; mem64[x26 + 0xa0] = 0xe400000000000000
    mem128[x26 + 0xa8] = (0x6e776f6e6b6e75, 0xe700000000000000)
    mem8[x26 + 0xb8] = 32
    mem64[x26 + 0xc0] = 0x6e696769726f; mem64[x26 + 0xc8] = 0xe600000000000000
    mem64[x26 + 0xd0] = 0xd000000000000022; mem64[x26 + 0xd8] = "https://github.com/mas-cli/mas.git"
    mem8[x26 + 0xe0] = 32
    mem64[x26 + 0xe8] = 0x766572
    mem64[x26 + 0xf0] = 0xe300000000000000; mem64[x26 + 0xf8] = 0xd000000000000028
    mem64[x26 + 0x100] = "6c5032dc8da74668c407b76d02463eea20b732a5"
    mem8[x26 + 0x108] = 32
    mem64[x26 + 0x110] = 0x7466697773; mem64[x26 + 0x118] = 0xe500000000000000
    mem64[x26 + 0x120] = 0xd00000000000002c; mem64[x26 + 0x128] = "6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)"
    mem8[x26 + 0x130] = 32
    mem64[x26 + 0x138] = 0x726576697264; mem64[x26 + 0x140] = 0xe600000000000000
    mem64[x26 + 0x148] = 0x362e3836312e31; mem64[x26 + 0x150] = 0xe700000000000000
    mem8[x26 + 0x158] = 32
    mem64[x26 + 0x160] = 0x65726f7473; mem64[x26 + 0x168] = 0xe500000000000000
    Foundation.Locale.region.getter(self: ?, static Foundation.Locale.current.getter())
    destroy value witness for Foundation.Locale(?)
    let r1 = getEnumTagSinglePayload value witness for Foundation.Locale.Region(?, 1)
    if (r1 != 1) {
        let r2 = Foundation.Locale.Region.identifier.getter(self: ?, r1)
        destroy value witness for Foundation.Locale.Region(?)
    }
    (extension in mas):Swift.String.(appStoreRegion in _5A1959CF2830529D62F19FF3DD6A82BC).getter((((r1 & 0xffffffff) != 1) ? r2 : 0x5355), ?)
    mem64[x26 + 0x170] = x22; mem64[x26 + 0x178] = x24
    mem8[x26 + 0x180] = 32
    mem64[x26 + 0x188] = 0x6e6f69676572; mem64[x26 + 0x190] = 0xe600000000000000
    Foundation.Locale.region.getter(static Foundation.Locale.current.getter())
    destroy value witness for Foundation.Locale(?)
    let r3 = getEnumTagSinglePayload value witness for Foundation.Locale.Region(?, 1)
    if (r3 != 1) {
        Foundation.Locale.Region.identifier.getter(self: ?, r3)
        destroy value witness for Foundation.Locale.Region(?)
    }
    mem64[x26 + 0x198] = x22; mem64[x26 + 0x1a0] = x20
    mem8[x26 + 0x1a8] = 32
    mem64[x26 + 0x1b0] = 0x736f63616d; mem64[x26 + 0x1b8] = 0xe500000000000000
    mas.(macOSVersion in _9B019CD41686B44C533F7CA58115A60C).getter()
    mem64[x26 + 0x1c0] = x0; mem64[x26 + 0x1c8] = x1
    mem8[x26 + 0x1d0] = 32
    mem64[x26 + 0x1d8] = 0x646c697562; mem64[x26 + 0x1e0] = 0xe500000000000000
    mas.(configStringValue in _9B019CD41686B44C533F7CA58115A60C)("kern.osversion")
    mem64[x26 + 0x1e8] = x0; mem64[x26 + 0x1f0] = x1
    mem8[x26 + 0x1f8] = w20
    mem64[x26 + 0x200] = 0x63616d
    mem64[x26 + 0x208] = 0xe300000000000000
    mas.(configStringValue in _9B019CD41686B44C533F7CA58115A60C)("hw.product")
    mem64[x26 + 0x210] = x0
    mem64[x26 + 0x218] = x1
    mem8[x26 + 0x220] = w20
    mem64[x26 + 0x228] = 0x757063
    mem64[x26 + 0x230] = x21
    mas.(configStringValue in _9B019CD41686B44C533F7CA58115A60C)("machdep.cpu.brand_string")
    mem64[x26 + 0x238] = x0
    mem64[x26 + 0x240] = x1
    mem8[x26 + 0x248] = w20
    mem64[x26 + 0x250] = 0x68637261
    mem64[x26 + 0x258] = 0xe400000000000000
    mas.(configStringValue in _9B019CD41686B44C533F7CA58115A60C)("hw.machine")
    mem64[x26 + 0x260] = x0
    mem64[x26 + 0x268] = x1
    mem8[x26 + 0x270] = w20
    generic specialization <serialized, (JSONAST.JSON.Key, JSONAST.JSON.Node), (key: JSONAST.JSON.Key, value: JSONAST.JSON.Node)> of Swift._arrayForceCast<A, B>(r0)
    swift_setDeallocating(r0)
    swift_arrayDestroy(?, 15)
    mem64[x24 + 0x38] = 0x1005eb3c0
    mem64[x21 + 0x20] = x20
    mas.OutputFormatOptionGroup.info(_:separator:terminator:)(self: ?, ?, " ", "\n")
    swift_setDeallocating(?)
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(Config param_1)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* mas.MAS.Config.run() -> () */

void __swift_stdcall mas::MAS::Config::run(Config param_1)

{
  char acVar1 [8];
  undefined1 *puVar2;
  char *pcVar3;
  long lVar4;
  undefined8 uVar5;
  long lVar6;
  Locale LVar7;
  Region RVar8;
  Region RVar9;
  void *in_x2;
  long extraout_x8;
  long extraout_x8_00;
  long lVar10;
  long extraout_x12;
  long extraout_x12_00;
  undefined8 *unaff_x20;
  void *pvVar11;
  code *pcVar12;
  long *plVar13;
  long lVar14;
  code *pcVar15;
  OptionGroup OVar16;
  String SVar17;
  String SVar18;
  undefined1 auVar19 [16];
  String SVar20;
  String separator;
  undefined1 auStack_3b0 [8];
  long local_3a8;
  long local_3a0;
  undefined1 *local_398;
  undefined8 *local_390;
  char *local_388;
  uint local_37c;
  undefined8 local_378;
  undefined8 uStack_370;
  Locale local_368;
  undefined1 auStack_360 [632];
  undefined1 auStack_e8 [64];
  undefined8 local_a8;
  undefined8 uStack_a0;
  byte local_98;
  long local_90;
  undefined8 uStack_88;
  undefined8 uStack_80;
  undefined8 uStack_78;
  undefined8 local_70;
  
  local_368 = Foundation::Locale::typeMetadataAccessor();
  local_3a8 = *(long *)(local_368.unknown + -8);
  (*(code *)PTR____chkstk_darwin_1005fba80)(*(undefined8 *)(local_3a8 + 0x40));
  local_398 = auStack_3b0 + -(extraout_x8 + 0xfU & 0xfffffffffffffff0);
  (*(code *)PTR____chkstk_darwin_1005fba80)();
  lVar14 = (long)(auStack_3b0 + -(extraout_x8 + 0xfU & 0xfffffffffffffff0)) - extraout_x12;
  lVar4 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__demangling_cache_variable_for_type_metadata_for_Foundation_Locale_Region_,
                     &__mangled_name_ref_for_type_metadata_for_Foundation_Locale_Region_);
  (*(code *)PTR____chkstk_darwin_1005fba80)(*(undefined8 *)(*(long *)(lVar4 + -8) + 0x40));
  lVar10 = lVar14 - (extraout_x8_00 + 0xfU & 0xfffffffffffffff0);
  local_3a0 = lVar10;
  (*(code *)PTR____chkstk_darwin_1005fba80)();
  lVar10 = lVar10 - extraout_x12_00;
  uStack_88 = unaff_x20[1];
  local_90 = *unaff_x20;
  uStack_78 = unaff_x20[3];
  uStack_80 = unaff_x20[2];
  local_70 = unaff_x20[4];
  auVar19 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                       ,&
                        __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                      );
  OVar16.title.bridgeObject = in_x2;
  OVar16._dummy = (bool)auVar19[0];
  OVar16._1_7_ = auVar19._1_7_;
  OVar16.title.str = (char *)auVar19._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar16);
  local_378 = uStack_a0;
  uStack_370 = local_a8;
  local_37c = (uint)local_98;
  uVar5 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                     ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>);
  local_388 = (char *)_swift_initStackObject(uVar5,auStack_e8);
  uVar5 = _DAT_10054fde0;
  *(undefined8 *)(local_388 + 0x18) = _UNK_10054fde8;
  *(undefined8 *)(local_388 + 0x10) = uVar5;
  uVar5 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<(JSONAST_JSON_Key,JSONAST_JSON_Node)>
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<(JSONAST_JSON_Key,JSONAST_JSON_Node)>
                    );
  lVar6 = _swift_initStackObject(uVar5,auStack_360);
  uVar5 = _DAT_10054fdf0;
  *(undefined8 *)(lVar6 + 0x18) = _UNK_10054fdf8;
  *(undefined8 *)(lVar6 + 0x10) = uVar5;
  local_390 = (undefined8 *)(lVar6 + 0x20);
  *local_390 = 0x73616d;
  *(undefined8 *)(lVar6 + 0x28) = 0xe300000000000000;
  uVar5 = _DAT_10054fe00;
  *(undefined8 *)(lVar6 + 0x38) = _UNK_10054fe08;
  *(undefined8 *)(lVar6 + 0x30) = uVar5;
  *(undefined1 *)(lVar6 + 0x40) = 0x20;
  *(undefined8 *)(lVar6 + 0x48) = 0x6563696c73;
  *(undefined8 *)(lVar6 + 0x50) = 0xe500000000000000;
  uVar5 = _s_arm64_10054fe10;
  *(undefined8 *)(lVar6 + 0x60) = _UNK_10054fe18;
  *(undefined8 *)(lVar6 + 0x58) = uVar5;
  *(undefined1 *)(lVar6 + 0x68) = 0x20;
  *(undefined8 *)(lVar6 + 0x70) = 0x736563696c73;
  *(undefined8 *)(lVar6 + 0x78) = 0xe600000000000000;
  lVar4 = lVar6;
  mas::_9B019CD41686B44C533F7CA58115A60C::get_supportedSliceArchitectures();
  local_90 = lVar4;
  ::___swift_instantiateConcreteTypeFromMangledNameV2
            (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
             &__mangled_name_ref_for_type_metadata_for__Swift_String_);
  ::Swift::Array<String>::_lazy_protocol_witness_table_accessor();
  SVar17.bridgeObject = (void *)0xe100000000000000;
  SVar17.str = (char *)0x20;
  SVar17 = (extension_Swift)::Swift::BidirectionalCollection::_joined(SVar17);
  LVar7.unknown = (undefined *)_swift_bridgeObjectRelease(lVar4);
  *(String *)(lVar6 + 0x80) = SVar17;
  *(undefined1 *)(lVar6 + 0x90) = 0x20;
  *(undefined8 *)(lVar6 + 0x98) = 0x74736964;
  *(undefined8 *)(lVar6 + 0xa0) = 0xe400000000000000;
  acVar1 = s_unknown_10054fe20;
  *(undefined8 *)(lVar6 + 0xb0) = _UNK_10054fe28;
  *(char (*) [8])(lVar6 + 0xa8) = acVar1;
  *(undefined1 *)(lVar6 + 0xb8) = 0x20;
  *(undefined8 *)(lVar6 + 0xc0) = 0x6e696769726f;
  *(undefined8 *)(lVar6 + 200) = 0xe600000000000000;
  *(undefined8 *)(lVar6 + 0xd0) = 0xd000000000000022;
  *(undefined8 *)(lVar6 + 0xd8) = 0x800000010059b070;
  *(undefined1 *)(lVar6 + 0xe0) = 0x20;
  *(undefined8 *)(lVar6 + 0xe8) = 0x766572;
  *(undefined8 *)(lVar6 + 0xf0) = 0xe300000000000000;
  *(undefined8 *)(lVar6 + 0xf8) = 0xd000000000000028;
  *(undefined8 *)(lVar6 + 0x100) = 0x800000010059b0a0;
  *(undefined1 *)(lVar6 + 0x108) = 0x20;
  *(undefined8 *)(lVar6 + 0x110) = 0x7466697773;
  *(undefined8 *)(lVar6 + 0x118) = 0xe500000000000000;
  *(undefined8 *)(lVar6 + 0x120) = 0xd00000000000002c;
  *(undefined8 *)(lVar6 + 0x128) = 0x800000010059b0d0;
  *(undefined1 *)(lVar6 + 0x130) = 0x20;
  *(undefined8 *)(lVar6 + 0x138) = 0x726576697264;
  *(undefined8 *)(lVar6 + 0x140) = 0xe600000000000000;
  *(undefined8 *)(lVar6 + 0x148) = 0x362e3836312e31;
  *(undefined8 *)(lVar6 + 0x150) = 0xe700000000000000;
  *(undefined1 *)(lVar6 + 0x158) = 0x20;
  *(undefined8 *)(lVar6 + 0x160) = 0x65726f7473;
  *(undefined8 *)(lVar6 + 0x168) = 0xe500000000000000;
  LVar7 = Foundation::Locale::get_current(LVar7);
  Foundation::Locale::_get_region(LVar7);
  pcVar15 = *(code **)(local_3a8 + 8);
  (*pcVar15)(lVar14,local_368.unknown);
  RVar8 = Foundation::Locale::Region::typeMetadataAccessor();
  lVar4 = *(long *)(RVar8.unknown + -8);
  pcVar12 = *(code **)(lVar4 + 0x30);
  RVar9.unknown = (undefined *)(*pcVar12)(lVar10,1,RVar8.unknown);
  if ((int)RVar9.unknown == 1) {
    __outlined_destroy_of_Foundation_Locale_Region_(lVar10);
    pvVar11 = (void *)0xe200000000000000;
  }
  else {
    SVar17 = Foundation::Locale::Region::get_identifier(RVar9);
    pvVar11 = SVar17.bridgeObject;
    (**(code **)(lVar4 + 8))(lVar10,RVar8.unknown);
  }
  SVar17 = (extension_mas)::Swift::String::_5A1959CF2830529D62F19FF3DD6A82BC::get_appStoreRegion();
  LVar7.unknown = (undefined *)_swift_bridgeObjectRelease(pvVar11);
  puVar2 = local_398;
  *(String *)(lVar6 + 0x170) = SVar17;
  *(undefined1 *)(lVar6 + 0x180) = 0x20;
  *(undefined8 *)(lVar6 + 0x188) = 0x6e6f69676572;
  *(undefined8 *)(lVar6 + 400) = 0xe600000000000000;
  LVar7 = Foundation::Locale::get_current(LVar7);
  lVar10 = local_3a0;
  Foundation::Locale::_get_region(LVar7);
  (*pcVar15)(puVar2,local_368.unknown);
  RVar9.unknown = (undefined *)(*pcVar12)(lVar10,1,RVar8.unknown);
  if ((int)RVar9.unknown == 1) {
    __outlined_destroy_of_Foundation_Locale_Region_(lVar10);
    SVar18.bridgeObject = (void *)0xe200000000000000;
    SVar18.str = (char *)0x5355;
  }
  else {
    SVar18 = Foundation::Locale::Region::get_identifier(RVar9);
    (**(code **)(lVar4 + 8))(lVar10,RVar8.unknown);
  }
  *(String *)(lVar6 + 0x198) = SVar18;
  *(undefined1 *)(lVar6 + 0x1a8) = 0x20;
  *(undefined8 *)(lVar6 + 0x1b0) = 0x736f63616d;
  *(undefined8 *)(lVar6 + 0x1b8) = 0xe500000000000000;
  SVar17 = mas::_9B019CD41686B44C533F7CA58115A60C::get_macOSVersion();
  *(String *)(lVar6 + 0x1c0) = SVar17;
  *(undefined1 *)(lVar6 + 0x1d0) = 0x20;
  *(undefined8 *)(lVar6 + 0x1d8) = 0x646c697562;
  *(undefined8 *)(lVar6 + 0x1e0) = 0xe500000000000000;
  auVar19 = __mas__configStringValue_in__9B019CD41686B44C533F7CA58115A60C__Swift_String___>_Swift_String
                      (0x76736f2e6e72656b,0xee006e6f69737265);
  *(undefined1 (*) [16])(lVar6 + 0x1e8) = auVar19;
  *(undefined1 *)(lVar6 + 0x1f8) = 0x20;
  *(undefined8 *)(lVar6 + 0x200) = 0x63616d;
  *(undefined8 *)(lVar6 + 0x208) = 0xe300000000000000;
  auVar19 = __mas__configStringValue_in__9B019CD41686B44C533F7CA58115A60C__Swift_String___>_Swift_String
                      (0x75646f72702e7768,0xea00000000007463);
  *(undefined1 (*) [16])(lVar6 + 0x210) = auVar19;
  *(undefined1 *)(lVar6 + 0x220) = 0x20;
  *(undefined8 *)(lVar6 + 0x228) = 0x757063;
  *(undefined8 *)(lVar6 + 0x230) = 0xe300000000000000;
  auVar19 = __mas__configStringValue_in__9B019CD41686B44C533F7CA58115A60C__Swift_String___>_Swift_String
                      (0xd000000000000018,0x800000010059b100);
  *(undefined1 (*) [16])(lVar6 + 0x238) = auVar19;
  *(undefined1 *)(lVar6 + 0x248) = 0x20;
  *(undefined8 *)(lVar6 + 0x250) = 0x68637261;
  *(undefined8 *)(lVar6 + 600) = 0xe400000000000000;
  auVar19 = __mas__configStringValue_in__9B019CD41686B44C533F7CA58115A60C__Swift_String___>_Swift_String
                      (0x696863616d2e7768,0xea0000000000656e);
  *(undefined1 (*) [16])(lVar6 + 0x260) = auVar19;
  *(undefined1 *)(lVar6 + 0x270) = 0x20;
  lVar4 = lVar6;
  ::Swift::__arrayForceCast();
  _swift_setDeallocating(lVar6);
  uVar5 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for__JSONAST_JSON_Key_JSONAST_JSON_Node_
                     ,&__mangled_name_ref_for_type_metadata_for__JSONAST_JSON_Key_JSONAST_JSON_Node_
                    );
  _swift_arrayDestroy(local_390,0xf,uVar5);
  pcVar3 = local_388;
  *(undefined **)(local_388 + 0x38) = &__type_metadata_for_JSONAST_JSON_Object;
  plVar13 = (long *)(local_388 + 0x20);
  *plVar13 = lVar4;
  SVar20.bridgeObject = (void *)0x20;
  SVar20.str = local_388;
  separator.bridgeObject = (void *)0xa;
  separator.str = (char *)0xe100000000000000;
  OutputFormatOptionGroup::_info(SVar20,separator,(OutputFormatOptionGroup)0xe100000000000000);
  ::_outlined_consume();
  _swift_setDeallocating(pcVar3);
  ___swift_destroy_boxed_opaque_existential_0Tm(plVar13);
  return;
}
```

## `configStringValue`

From `Sources/mas/Commands/MAS.Config.swift`.

```swift
private func configStringValue(_ name: String) -> String {
	var size = 0
	guard unsafe sysctlbyname(name, nil, &size, nil, 0) == 0 else {
		unsafe perror(sysCtlByName)
		return unknown
	}
	guard size > 0 else {
		return unknown
	}

	return unsafe withUnsafeTemporaryAllocation(of: CChar.self, capacity: size) { buffer in
		guard let baseAddress = buffer.baseAddress else {
			return unknown
		}
		guard unsafe sysctlbyname(name, unsafe baseAddress, &size, nil, 0) == 0 else {
			unsafe perror(sysCtlByName)
			return unknown
		}

		return unsafe .init(cString: unsafe baseAddress)
	}
}
```

The optimizer inlined it into every caller, so the binary has no body of its own to decompile.

## `MAS.Get.run`

From `Sources/mas/Commands/MAS.Get.swift`.

```swift
		func run() async {
			await AppStore.get.apps(withAppIDs: catalogAppsOptionGroup.appIDs, force: forceOptionGroup.force)
		}
```

### `mas.MAS.Get.run() async -> ()` at `0x100004d54`

swiftdc:

```swift
mas.MAS.Get.run() async -> () {
    // async function: 1 resume funclet(s): resume #1 @0x100004ee8
    ArgumentParser.OptionGroup.wrappedValue.getter()
    mas.CatalogAppsOptionGroup.appIDs.getter(self: (? + 96))
    mem64[x22 + 0x138] = x0
    mem128[x22 + 0xc8] = q0
    mem16[x22 + 0xd8] = w8
    mem128[x25] = q0
    mem128[x22 + 0xe0] = q0
    mem8[x22 + 0xf0] = w8
    merged outlined destroy of …(?, 0x10060b218, 0x100551a70)
    mem128[x22 + 0xa0] = q0; mem128[x22 + 0xb0] = q1
    mem64[x22 + 0xc0] = x8
    ArgumentParser.OptionGroup.wrappedValue.getter()
    mem64[x22 + 0x110] = x24; mem64[x22 + 0x118] = x25
    mem8[x22 + 0x120] = w26
    ArgumentParser.Flag.wrappedValue.getter()
    mem64[x22 + 0x140] = x0
    mem64[x0] = x22; mem64[x0 + 0x8] = (1) await resume partial function for mas.MAS.Get.run() async -> ()
    await mas.AppStoreAction.apps(withAppIDs:force:)(self: ?, ?, ?)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Get param_1)
/* mas.MAS.Get.run() async -> () */

void __swift_stdcall mas::MAS::Get::_run(Get param_1)

{
  undefined1 uVar1;
  undefined1 auVar2 [16];
  CatalogAppsOptionGroup CVar3;
  Flag FVar4;
  long *plVar5;
  ulong in_x1;
  void *in_x2;
  undefined *puVar6;
  undefined8 *unaff_x20;
  long unaff_x22;
  undefined8 uVar7;
  undefined8 uVar8;
  undefined8 uVar9;
  undefined8 uVar10;
  undefined8 uVar11;
  OptionGroup OVar12;
  OptionGroup OVar13;
  
  uVar8 = unaff_x20[8];
  uVar7 = unaff_x20[7];
  uVar9 = unaff_x20[9];
  uVar11 = unaff_x20[0xc];
  uVar10 = unaff_x20[0xb];
  *(undefined8 *)(unaff_x22 + 0x38) = unaff_x20[10];
  *(undefined8 *)(unaff_x22 + 0x30) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x48) = uVar11;
  *(undefined8 *)(unaff_x22 + 0x40) = uVar10;
  uVar9 = unaff_x20[0xd];
  *(undefined8 *)(unaff_x22 + 0x58) = unaff_x20[0xe];
  *(undefined8 *)(unaff_x22 + 0x50) = uVar9;
  uVar9 = unaff_x20[5];
  *(undefined8 *)(unaff_x22 + 0x18) = unaff_x20[6];
  *(undefined8 *)(unaff_x22 + 0x10) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar8;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar7;
  OVar12._0_16_ =
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_CatalogAppsOptionGroup>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_CatalogAppsOptionGroup>
                 );
  CVar3.unknown = OVar12._0_8_;
  OVar12.title.bridgeObject = in_x2;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar12);
  CatalogAppsOptionGroup::get_appIDs(CVar3);
  *(undefined **)(unaff_x22 + 0x138) = CVar3.unknown;
  *(undefined8 *)(unaff_x22 + 0xd0) = *(undefined8 *)(unaff_x22 + 0x68);
  *(undefined8 *)(unaff_x22 + 200) = *(undefined8 *)(unaff_x22 + 0x60);
  *(undefined2 *)(unaff_x22 + 0xd8) = *(undefined2 *)(unaff_x22 + 0x70);
  __outlined_destroy_of_ArgumentParser_Parsed<mas_ForceBundleIDOptionGroup>(unaff_x22 + 200);
  *(undefined8 *)(unaff_x22 + 0x130) = *(undefined8 *)(unaff_x22 + 0x80);
  *(undefined8 *)(unaff_x22 + 0x128) = *(undefined8 *)(unaff_x22 + 0x78);
  __outlined_destroy_of_Swift_String((undefined8 *)(unaff_x22 + 0x128));
  *(undefined8 *)(unaff_x22 + 0xe8) = *(undefined8 *)(unaff_x22 + 0x90);
  *(undefined8 *)(unaff_x22 + 0xe0) = *(undefined8 *)(unaff_x22 + 0x88);
  *(undefined1 *)(unaff_x22 + 0xf0) = *(undefined1 *)(unaff_x22 + 0x98);
  puVar6 = &__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>;
  __merged_outlined_destroy_of_ArgumentParser_Argument<[Swift_String]>
            (unaff_x22 + 0xe0,
             &
             __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
            );
  uVar7 = *unaff_x20;
  uVar9 = unaff_x20[3];
  uVar8 = unaff_x20[2];
  *(undefined8 *)(unaff_x22 + 0xa8) = unaff_x20[1];
  *(undefined8 *)(unaff_x22 + 0xa0) = uVar7;
  *(undefined8 *)(unaff_x22 + 0xb8) = uVar9;
  *(undefined8 *)(unaff_x22 + 0xb0) = uVar8;
  *(undefined8 *)(unaff_x22 + 0xc0) = unaff_x20[4];
  auVar2 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceOptionGroup>
                     );
  OVar13.title.bridgeObject = puVar6;
  OVar13._dummy = (bool)auVar2[0];
  OVar13._1_7_ = auVar2._1_7_;
  OVar13.title.str = (char *)auVar2._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar13);
  *(undefined8 *)(unaff_x22 + 0x110) = *(undefined8 *)(unaff_x22 + 0xf8);
  *(undefined8 *)(unaff_x22 + 0x118) = *(undefined8 *)(unaff_x22 + 0x100);
  *(undefined1 *)(unaff_x22 + 0x120) = *(undefined1 *)(unaff_x22 + 0x108);
  FVar4.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar4);
  ::_outlined_consume();
  uVar1 = *(undefined1 *)(unaff_x22 + 0x99);
  plVar5 = (long *)_swift_task_alloc(DAT_100552cfc);
  *(long **)(unaff_x22 + 0x140) = plVar5;
  *plVar5 = unaff_x22;
  plVar5[1] = (long)_run;
  AppStoreAction::_apps(param_1.unknown,in_x1 & 0xcfffffffffffffff,CVar3.unknown,uVar1,0);
  return;
}
```

## `MAS.Home.run`

From `Sources/mas/Commands/MAS.Home.swift`.

```swift
		func run() async {
			await run(catalogApps: await catalogAppsOptionGroup.appIDs.catalogApps)
		}
```

The optimizer inlined it into every caller, so the binary has no body of its own to decompile.

## `MAS.Home.run`

From `Sources/mas/Commands/MAS.Home.swift`.

```swift
		func run(catalogApps: [CatalogApp]) async {
			await catalogApps.forEach(attemptTo: "open") { catalogApp in
				guard let url = URL(string: catalogApp.appStorePageURLString) else {
					throw MASError.invalidURL(catalogApp.appStorePageURLString)
				}

				_ = try await url.open()
			}
		}
```

The binary keeps it only as the specialization below, a copy the optimizer rewrote for its callers.

### `function signature specialization <Arg[2] = Dead> of mas.MAS.Home.run(catalogApps: [mas.CatalogApp]) async -> ()` at `0x100006758`

swiftdc:

```swift
function signature specialization <Arg[2] = Dead> of mas.MAS.Home.run(catalogApps: Swift.Array<mas.CatalogApp>) async -> () {
    // async function: 4 resume funclet(s): resume #1 @0x100006f74, resume #2 @0x100006af0, resume #3 @0x100006eb0, resume #4 @0x100006b54
    if (x8 == 0) {
        return
    } else {
        outlined init with copy of mas.CatalogApp(?, ?)
        Foundation.URL.init(string:)(?)
        if (getEnumTagSinglePayload value witness for Foundation.URL(?, 1) != 1) {
            /* unresolved call @ 0x1000069a4 */ indirect_call(?, recovered_args: […])
            let r1 = [[NSWorkspaceOpenConfiguration allocWithZone:nil] init]
            let r2 = [NSWorkspace sharedWorkspace]
            let r3 = Foundation.URL._bridgeToObjectiveC()
            swift_continuation_init(?, 1)
            Swift.CheckedContinuation.init(continuation:function:)(?, ?)
            /* unresolved call @ 0x100006a78 */ indirect_call(?, recovered_args: [__swift_allocate_boxed_opaque_existential_0(?), …])
            [r2 openURL:r3 configuration:r1 completionHandler:?]
            /* unresolved call @ 0x100006ac8 */ indirect_call(?, recovered_args: [__swift_allocate_boxed_opaque_existential_0(?), …])
            swift_continuation_await()
            // no fall-through
        } else {
            merged outlined destroy of …(?, 0x10060b2a0, 0x100550530)
            let r0 = swift_allocError(0x1005e4420, lazy protocol witness table accessor for type mas.MASError and conformance mas.MASError : Swift.Error in mas(), 0, false)
            mem64[x1] = x21; mem64[x1 + 0x8] = x20
            mem8[x1 + 0x38] = 2
            swift_willThrow(r0)
            await generic specialization <Swift.Array<mas.CatalogApp>, Swift.Error> of closure #1 nonisolated(nonsending) (…)
            // no fall-through
        }
    }
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Array<CatalogApp> catalogApps, Home param_2)
/* WARNING: Function: _objc_opt_self replaced with injection: _objc_retain_fixup */
/* WARNING: Function: _objc_retainAutoreleasedReturnValue replaced with injection:
   _objc_retain_fixup */
/* function signature specialization <Arg[2] = Dead> of mas.MAS.Home.run(catalogApps:
   [mas.CatalogApp]) async -> () */

void __swift_stdcall mas::MAS::Home::_run(undefined8 param_1,undefined8 param_2,long param_3)

{
  undefined4 uVar1;
  int iVar2;
  long lVar3;
  undefined8 uVar4;
  undefined8 uVar5;
  URL UVar6;
  undefined8 uVar7;
  long *plVar8;
  ID IVar9;
  NSURL *pNVar10;
  UnsafeContinuation<undefined,undefined> continuation;
  undefined8 *puVar11;
  long unaff_x22;
  ulong uVar12;
  long lVar13;
  undefined8 uVar14;
  undefined8 uVar15;
  undefined8 uVar16;
  undefined8 uVar17;
  undefined8 uVar18;
  undefined1 auVar19 [16];
  String function;
  
  *(undefined8 *)(unaff_x22 + 0x160) = param_2;
  *(long *)(unaff_x22 + 0x168) = param_3;
  *(undefined8 *)(unaff_x22 + 0x158) = param_1;
  lVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift_CheckedContinuation<__C_NSRunningApplication,Swift_Error>
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Swift_CheckedContinuation<__C_NSRunningApplication,Swift_Error>
                    );
  *(long *)(unaff_x22 + 0x170) = lVar3;
  lVar3 = *(long *)(lVar3 + -8);
  *(long *)(unaff_x22 + 0x178) = lVar3;
  uVar4 = _swift_task_alloc(*(long *)(lVar3 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x180) = uVar4;
  lVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                     &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
  uVar5 = _swift_task_alloc(*(long *)(*(long *)(lVar3 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x188) = uVar5;
  UVar6 = Foundation::URL::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 400) = UVar6.unknown;
  lVar13 = *(long *)(UVar6.unknown + -8);
  *(long *)(unaff_x22 + 0x198) = lVar13;
  uVar7 = _swift_task_alloc(*(long *)(lVar13 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x1a0) = uVar7;
  lVar3 = *(long *)(param_3 + 0x10);
  *(long *)(unaff_x22 + 0x1a8) = lVar3;
  if (lVar3 == 0) {
    _swift_task_dealloc();
    _swift_task_dealloc(uVar5);
    _swift_task_dealloc(uVar4);
                    /* WARNING: Could not recover jumptable at 0x000100006974. Too many branches */
                    /* WARNING: Treating indirect jump as call */
    (**(code **)(unaff_x22 + 8))();
    return;
  }
  *(undefined8 *)(unaff_x22 + 0x1b0) = 0;
  uVar4 = *(undefined8 *)(param_3 + 0x20);
  uVar14 = *(undefined8 *)(param_3 + 0x38);
  uVar7 = *(undefined8 *)(param_3 + 0x30);
  *(undefined8 *)(unaff_x22 + 0x58) = *(undefined8 *)(param_3 + 0x28);
  *(undefined8 *)(unaff_x22 + 0x50) = uVar4;
  *(undefined8 *)(unaff_x22 + 0x68) = uVar14;
  *(undefined8 *)(unaff_x22 + 0x60) = uVar7;
  uVar7 = *(undefined8 *)(param_3 + 0x48);
  uVar4 = *(undefined8 *)(param_3 + 0x40);
  uVar15 = *(undefined8 *)(param_3 + 0x58);
  uVar14 = *(undefined8 *)(param_3 + 0x50);
  uVar16 = *(undefined8 *)(param_3 + 0x60);
  uVar18 = *(undefined8 *)(param_3 + 0x78);
  uVar17 = *(undefined8 *)(param_3 + 0x70);
  *(undefined8 *)(unaff_x22 + 0x98) = *(undefined8 *)(param_3 + 0x68);
  *(undefined8 *)(unaff_x22 + 0x90) = uVar16;
  *(undefined8 *)(unaff_x22 + 0xa8) = uVar18;
  *(undefined8 *)(unaff_x22 + 0xa0) = uVar17;
  *(undefined8 *)(unaff_x22 + 0x78) = uVar7;
  *(undefined8 *)(unaff_x22 + 0x70) = uVar4;
  *(undefined8 *)(unaff_x22 + 0x88) = uVar15;
  *(undefined8 *)(unaff_x22 + 0x80) = uVar14;
  uVar4 = *(undefined8 *)(unaff_x22 + 0x58);
  uVar7 = *(undefined8 *)(unaff_x22 + 0x60);
  __outlined_init_with_copy_of_mas_CatalogApp(unaff_x22 + 0x50,unaff_x22 + 0xb0);
  Foundation::URL::_init();
  iVar2 = (**(code **)(lVar13 + 0x30))(uVar5,1,UVar6.unknown);
  if (iVar2 == 1) {
    uVar5 = __merged_outlined_destroy_of_ArgumentParser_Argument<[Swift_String]>
                      (*(undefined8 *)(unaff_x22 + 0x188),
                       &__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                       &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
    MASError::_lazy_protocol_witness_table_accessor();
    auVar19 = _swift_allocError(&__type_metadata_for_mas_MASError,uVar5,0,0);
    puVar11 = auVar19._8_8_;
    *puVar11 = uVar4;
    puVar11[1] = uVar7;
    *(undefined1 *)(puVar11 + 7) = 2;
    _swift_willThrow();
    *(long *)(unaff_x22 + 0x1d8) = auVar19._0_8_;
    uVar1 = DAT_100552ce4;
    uVar12 = *(ulong *)(unaff_x22 + 0x160);
    _swift_bridgeObjectRetain(uVar7);
    plVar8 = (long *)_swift_task_alloc(uVar1);
    *(long **)(unaff_x22 + 0x1e0) = plVar8;
    *plVar8 = unaff_x22;
    plVar8[1] = (long)_run;
    __generic_specialization_<[mas_CatalogApp],Swift_Error>_of_closure__1_nonisolated_nonsending___A_Element_A1__async__>____in__extension_in_mas__Swift_Sequence_forEach<A_where_A1:_Swift_Error>_attemptTo__Swift_String____nonisolated_nonsending___A_Element__async_throws_A1___>_____async__>___
              (*(undefined8 *)(unaff_x22 + 0x158),uVar12 & 0xcfffffffffffffff,unaff_x22 + 0x50,
               auVar19._0_8_,0x6e65706f,0xe400000000000000);
    return;
  }
  lVar3 = *(long *)(unaff_x22 + 0x178);
  uVar4 = *(undefined8 *)(unaff_x22 + 0x180);
  uVar7 = *(undefined8 *)(unaff_x22 + 0x170);
  (**(code **)(*(long *)(unaff_x22 + 0x198) + 0x20))
            (*(undefined8 *)(unaff_x22 + 0x1a0),*(undefined8 *)(unaff_x22 + 0x188),
             *(undefined8 *)(unaff_x22 + 400));
  IVar9 = _objc_allocWithZone(PTR__OBJC_CLASS___NSWorkspaceOpenConfiguration_10060acc0);
  IVar9 = NSWorkspaceOpenConfiguration::init(IVar9);
  *(ID *)(unaff_x22 + 0x1b8) = IVar9;
  UVar6.unknown =
       (undefined *)NSWorkspace::sharedWorkspace((ID)PTR__OBJC_CLASS___NSWorkspace_10060acc8);
  *(undefined **)(unaff_x22 + 0x1c0) = UVar6.unknown;
  pNVar10 = Foundation::URL::_bridgeToObjectiveC(UVar6);
  *(NSURL **)(unaff_x22 + 0x1c8) = pNVar10;
  *(long *)(unaff_x22 + 0x38) = unaff_x22 + 0x150;
  *(long *)(unaff_x22 + 0x10) = unaff_x22;
  *(code **)(unaff_x22 + 0x18) = _run;
  continuation.unknown = (undefined *)_swift_continuation_init(unaff_x22 + 0x10,1);
  *(undefined8 *)(unaff_x22 + 0x148) = uVar7;
  uVar5 = ___swift_allocate_boxed_opaque_existential_0(unaff_x22 + 0x130);
  __C::NSRunningApplication::typeMetadataAccessor();
  ::___swift_instantiateConcreteTypeFromMangledNameV2
            (&__demangling_cache_variable_for_type_metadata_for_Swift_Error,
             &__mangled_name_ref_for_type_metadata_for_Swift_Error);
  function.bridgeObject = (void *)0x800000010059b2f0;
  function.str = (char *)0xd000000000000026;
  ::Swift::CheckedContinuation::init(continuation,function);
  (**(code **)(lVar3 + 0x20))(uVar5,uVar4,uVar7);
  *(undefined **)(unaff_x22 + 0x110) = PTR___NSConcreteStackBlock_1005fba70;
  *(undefined8 *)(unaff_x22 + 0x118) = DAT_100550488;
  *(code **)(unaff_x22 + 0x120) =
       __checked__objc_completion_handler_block_implementation_for__escaping__callee_unowned__convention_block___Sendable___unowned___C_NSRunningApplication___unowned___C_NSError____>____with_result_type___C_NSRunningApplication
  ;
  *(undefined **)(unaff_x22 + 0x128) = &_block_descriptor;
  NSWorkspace::openURL_configuration_completionHandler_
            ((ID)UVar6.unknown,pNVar10,IVar9,unaff_x22 + 0x110);
  (**(code **)(lVar3 + 8))(uVar5,uVar7);
  _swift_continuation_await(unaff_x22 + 0x10);
  return;
}
```

## `MAS.Install.run`

From `Sources/mas/Commands/MAS.Install.swift`.

```swift
		func run() async {
			await AppStore.install.apps(withAppIDs: catalogAppsOptionGroup.appIDs, force: forceOptionGroup.force)
		}
```

### `mas.MAS.Install.run() async -> ()` at `0x100007f1c`

swiftdc:

```swift
mas.MAS.Install.run() async -> () {
    // async function: 1 resume funclet(s): resume #1 @0x1000080b0
    ArgumentParser.OptionGroup.wrappedValue.getter()
    mas.CatalogAppsOptionGroup.appIDs.getter(self: (? + 96))
    mem64[x22 + 0x138] = x0
    mem128[x22 + 0xc8] = q0
    mem16[x22 + 0xd8] = w8
    mem128[x25] = q0
    mem128[x22 + 0xe0] = q0
    mem8[x22 + 0xf0] = w8
    merged outlined destroy of …(?, 0x10060b218, 0x100551a70)
    mem128[x22 + 0xa0] = q0; mem128[x22 + 0xb0] = q1
    mem64[x22 + 0xc0] = x8
    ArgumentParser.OptionGroup.wrappedValue.getter()
    mem64[x22 + 0x110] = x24; mem64[x22 + 0x118] = x25
    mem8[x22 + 0x120] = w26
    ArgumentParser.Flag.wrappedValue.getter()
    mem64[x22 + 0x140] = x0
    mem64[x0] = x22; mem64[x0 + 0x8] = (1) await resume partial function for mas.MAS.Install.run() async -> ()
    await mas.AppStoreAction.apps(withAppIDs:force:)(self: ?, ?, ?)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Install param_1)
/* mas.MAS.Install.run() async -> () */

void __swift_stdcall mas::MAS::Install::_run(Install param_1)

{
  undefined1 uVar1;
  undefined1 auVar2 [16];
  CatalogAppsOptionGroup CVar3;
  Flag FVar4;
  long *plVar5;
  ulong in_x1;
  void *in_x2;
  undefined *puVar6;
  undefined8 *unaff_x20;
  long unaff_x22;
  undefined8 uVar7;
  undefined8 uVar8;
  undefined8 uVar9;
  undefined8 uVar10;
  undefined8 uVar11;
  OptionGroup OVar12;
  OptionGroup OVar13;
  
  uVar8 = unaff_x20[8];
  uVar7 = unaff_x20[7];
  uVar9 = unaff_x20[9];
  uVar11 = unaff_x20[0xc];
  uVar10 = unaff_x20[0xb];
  *(undefined8 *)(unaff_x22 + 0x38) = unaff_x20[10];
  *(undefined8 *)(unaff_x22 + 0x30) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x48) = uVar11;
  *(undefined8 *)(unaff_x22 + 0x40) = uVar10;
  uVar9 = unaff_x20[0xd];
  *(undefined8 *)(unaff_x22 + 0x58) = unaff_x20[0xe];
  *(undefined8 *)(unaff_x22 + 0x50) = uVar9;
  uVar9 = unaff_x20[5];
  *(undefined8 *)(unaff_x22 + 0x18) = unaff_x20[6];
  *(undefined8 *)(unaff_x22 + 0x10) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar8;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar7;
  OVar12._0_16_ =
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_CatalogAppsOptionGroup>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_CatalogAppsOptionGroup>
                 );
  CVar3.unknown = OVar12._0_8_;
  OVar12.title.bridgeObject = in_x2;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar12);
  CatalogAppsOptionGroup::get_appIDs(CVar3);
  *(undefined **)(unaff_x22 + 0x138) = CVar3.unknown;
  *(undefined8 *)(unaff_x22 + 0xd0) = *(undefined8 *)(unaff_x22 + 0x68);
  *(undefined8 *)(unaff_x22 + 200) = *(undefined8 *)(unaff_x22 + 0x60);
  *(undefined2 *)(unaff_x22 + 0xd8) = *(undefined2 *)(unaff_x22 + 0x70);
  __outlined_destroy_of_ArgumentParser_Parsed<mas_ForceBundleIDOptionGroup>(unaff_x22 + 200);
  *(undefined8 *)(unaff_x22 + 0x130) = *(undefined8 *)(unaff_x22 + 0x80);
  *(undefined8 *)(unaff_x22 + 0x128) = *(undefined8 *)(unaff_x22 + 0x78);
  __outlined_destroy_of_Swift_String((undefined8 *)(unaff_x22 + 0x128));
  *(undefined8 *)(unaff_x22 + 0xe8) = *(undefined8 *)(unaff_x22 + 0x90);
  *(undefined8 *)(unaff_x22 + 0xe0) = *(undefined8 *)(unaff_x22 + 0x88);
  *(undefined1 *)(unaff_x22 + 0xf0) = *(undefined1 *)(unaff_x22 + 0x98);
  puVar6 = &__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>;
  __merged_outlined_destroy_of_ArgumentParser_Argument<[Swift_String]>
            (unaff_x22 + 0xe0,
             &
             __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
            );
  uVar7 = *unaff_x20;
  uVar9 = unaff_x20[3];
  uVar8 = unaff_x20[2];
  *(undefined8 *)(unaff_x22 + 0xa8) = unaff_x20[1];
  *(undefined8 *)(unaff_x22 + 0xa0) = uVar7;
  *(undefined8 *)(unaff_x22 + 0xb8) = uVar9;
  *(undefined8 *)(unaff_x22 + 0xb0) = uVar8;
  *(undefined8 *)(unaff_x22 + 0xc0) = unaff_x20[4];
  auVar2 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceOptionGroup>
                     );
  OVar13.title.bridgeObject = puVar6;
  OVar13._dummy = (bool)auVar2[0];
  OVar13._1_7_ = auVar2._1_7_;
  OVar13.title.str = (char *)auVar2._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar13);
  *(undefined8 *)(unaff_x22 + 0x110) = *(undefined8 *)(unaff_x22 + 0xf8);
  *(undefined8 *)(unaff_x22 + 0x118) = *(undefined8 *)(unaff_x22 + 0x100);
  *(undefined1 *)(unaff_x22 + 0x120) = *(undefined1 *)(unaff_x22 + 0x108);
  FVar4.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar4);
  ::_outlined_consume();
  uVar1 = *(undefined1 *)(unaff_x22 + 0x99);
  plVar5 = (long *)_swift_task_alloc(DAT_100552cfc);
  *(long **)(unaff_x22 + 0x140) = plVar5;
  *plVar5 = unaff_x22;
  plVar5[1] = (long)_run;
  AppStoreAction::_apps(param_1.unknown,in_x1 & 0xcfffffffffffffff,CVar3.unknown,uVar1,1);
  return;
}
```

## `MAS.List.run`

From `Sources/mas/Commands/MAS.List.swift`.

```swift
		func run() async {
			run(
				installedApps: // swiftformat:disable:next indent
					await installedAppsOptionGroup.installedApps(withFullJSON: outputFormatOptionGroup.shouldOutputJSON),
			)
		}
```

### `mas.MAS.List.run() async -> ()` at `0x1000093bc`

swiftdc:

```swift
mas.MAS.List.run() async -> () {
    // async function: 1 resume funclet(s): resume #1 @0x10000950c
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Flag.wrappedValue.getter()
    mas.InstalledAppsOptionGroup.appIDs.getter(self: (? + 96))
    mem64[x22 + 0x140] = x0
    mem64[x22 + 0x148] = x0
    mem64[x0] = x22; mem64[x0 + 0x8] = (1) await resume partial function for mas.MAS.List.run() async -> ()
    await indirect_call(?)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(List param_1)
/* mas.MAS.List.run() async -> () */

void __swift_stdcall mas::MAS::List::_run(List param_1)

{
  undefined1 uVar1;
  undefined1 auVar2 [16];
  Flag FVar3;
  InstalledAppsOptionGroup IVar4;
  long *plVar5;
  ulong in_x1;
  void *in_x2;
  long lVar6;
  undefined8 *unaff_x20;
  long unaff_x22;
  undefined8 uVar7;
  undefined8 uVar8;
  undefined8 uVar9;
  undefined8 uVar10;
  undefined8 uVar11;
  OptionGroup OVar12;
  OptionGroup OVar13;
  
  *(undefined8 **)(unaff_x22 + 0x138) = unaff_x20;
  uVar8 = unaff_x20[8];
  uVar7 = unaff_x20[7];
  uVar9 = unaff_x20[9];
  uVar11 = unaff_x20[0xc];
  uVar10 = unaff_x20[0xb];
  *(undefined8 *)(unaff_x22 + 0x38) = unaff_x20[10];
  *(undefined8 *)(unaff_x22 + 0x30) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x48) = uVar11;
  *(undefined8 *)(unaff_x22 + 0x40) = uVar10;
  uVar9 = unaff_x20[0xd];
  *(undefined8 *)(unaff_x22 + 0x58) = unaff_x20[0xe];
  *(undefined8 *)(unaff_x22 + 0x50) = uVar9;
  uVar9 = unaff_x20[5];
  *(undefined8 *)(unaff_x22 + 0x18) = unaff_x20[6];
  *(undefined8 *)(unaff_x22 + 0x10) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar8;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar7;
  auVar2 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_InstalledAppsOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_InstalledAppsOptionGroup>
                     );
  OVar12.title.bridgeObject = in_x2;
  OVar12._dummy = (bool)auVar2[0];
  OVar12._1_7_ = auVar2._1_7_;
  OVar12.title.str = (char *)auVar2._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar12);
  uVar7 = *unaff_x20;
  uVar9 = unaff_x20[3];
  uVar8 = unaff_x20[2];
  *(undefined8 *)(unaff_x22 + 0xa8) = unaff_x20[1];
  *(undefined8 *)(unaff_x22 + 0xa0) = uVar7;
  *(undefined8 *)(unaff_x22 + 0xb8) = uVar9;
  *(undefined8 *)(unaff_x22 + 0xb0) = uVar8;
  *(undefined8 *)(unaff_x22 + 0xc0) = unaff_x20[4];
  auVar2 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                     );
  OVar13.title.bridgeObject = in_x2;
  OVar13._dummy = (bool)auVar2[0];
  OVar13._1_7_ = auVar2._1_7_;
  OVar13.title.str = (char *)auVar2._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar13);
  IVar4.unknown = *(undefined **)(unaff_x22 + 0xf8);
  *(undefined **)(unaff_x22 + 0x110) = IVar4.unknown;
  *(undefined8 *)(unaff_x22 + 0x118) = *(undefined8 *)(unaff_x22 + 0x100);
  *(undefined1 *)(unaff_x22 + 0x120) = *(undefined1 *)(unaff_x22 + 0x108);
  FVar3.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar3);
  ::_outlined_consume();
  uVar1 = *(undefined1 *)(unaff_x22 + 0x99);
  InstalledAppsOptionGroup::get_appIDs(IVar4);
  *(undefined **)(unaff_x22 + 0x140) = IVar4.unknown;
  lVar6 = (long)
          __s3mas13installedApps10withAppIDs0D8FullJSON010unresolvedE9IDHandlerSayAA09InstalledE0VGSayAA0E2IDOG_SbyAJXEtYaF08_s3mas24kc31OptionGroupV09installedC012withg12JSONSayAA0B3e10VGSb_tYaFyS10J2IDOXEfU_Tf1nnnc_nTu
  ;
  plVar5 = (long *)_swift_task_alloc(DAT_10055303c);
  *(long **)(unaff_x22 + 0x148) = plVar5;
  *plVar5 = unaff_x22;
  plVar5[1] = (long)_run;
  (*(code *)((long)&
                   __s3mas13installedApps10withAppIDs0D8FullJSON010unresolvedE9IDHandlerSayAA09InstalledE0VGSayAA0E2IDOG_SbyAJXEtYaF08_s3mas24kc31OptionGroupV09installedC012withg12JSONSayAA0B3e10VGSb_tYaFyS10J2IDOXEfU_Tf1nnnc_nTu
            + lVar6))(param_1.unknown,in_x1 & 0xcfffffffffffffff,IVar4.unknown,uVar1);
  return;
}
```

## `MAS.List.run`

From `Sources/mas/Commands/MAS.List.swift`.

```swift
		func run(installedApps: [InstalledApp]) {
			guard !installedApps.isEmpty else {
				printer.warning( // editorconfig-checker-disable
					"""
					No installed apps found

					If this is unexpected, index apps in Spotlight (which might take some time):

					# Individual app (if the omitted apps are known). e.g., for Xcode:
					mdimport /Applications/Xcode.app

					# All apps:
					vol="$(/usr/libexec/PlistBuddy -c "Print :PreferredVolume:name" ~/Library/Preferences/com.apple.appstored.plist 2>/dev/null)"
					mdimport /Applications ${vol:+"/Volumes/${vol}/Applications"}

					# All volumes:
					sudo mdutil -Eai on
					""", // editorconfig-checker-enable
				)
				return
			}

			outputFormatOptionGroup.info(installedApps.map(String.init).joined(separator: "\n"))
		}
```

### `mas.MAS.List.run(installedApps: [mas.InstalledApp]) -> ()` at `0x1000095cc`

swiftdc:

```swift
mas.MAS.List.run(installedApps: Swift.Array<mas.InstalledApp>) -> () {
    if (x21 == 0) {
        if (x8 != -1) {
            swift_once(0x10060b908, one-time initialization function for printer, ?)
        }
        let r1 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Any>, local_138)
        mem128[x0 + 0x10] = (1, 2)
        mem64[x0 + 0x38] = type metadata for Swift.String
        mem64[x20 + 0x20] = 0xd0000000000001b7
        mem64[x0 + 0x28] = "No installed apps found\n\nIf this is unexpected, index apps in Spotlight (which might take some time):\n\n# Individual app (if the omitted apps are known). e.g., for Xcode:\nmdimport /Applications/Xcode.app\n\n# All apps:\nvol=\"$(/usr/libexec/PlistBuddy -c \"Print :PreferredVolume:name\" ~/Library/Preferences/com.apple.appstored.plist 2>/dev/null)\"\nmdimport /Applications ${vol:+\"/Volumes/${vol}/Applications\"}\n\n# All volumes:\nsudo mdutil -Eai on"
        function signature specialization <Arg[4] = Dead> of mas.Printer.warning(_:error:separator:terminator:)(r1, 0, " ", 10, 0xe100000000000000)
        swift_setDeallocating(r1)
        swift_arrayDestroy(?, ?, (type metadata for Any + 8))
    } else {
        ArgumentParser.OptionGroup.wrappedValue.getter()
        let r0 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Any>, local_f8)
        mem128[x0 + 0x10] = (1, 2)
        generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_b8, …)
        while (true) {
            os_unfair_lock_lock(?)
            if (w28 != 1) {
                /* unresolved call @ 0x10000973c */ indirect_call(?, recovered_args: […])
                mem64[x24 + 0x10] = x19; mem64[x24 + 0x18] = x21
                mem8[x24 + 0x20] = 1
            }
            os_unfair_lock_unlock(?)
            if (x23 >=ᵁ (x8 >>ᵁ 1)) {
                generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_b8, …)
            }
            mem64[x24 + 0x10] = x22
            mem64[x8 + 0x20] = x19; mem64[x8 + 0x28] = x21
            if (x20 != 0) {
                continue
            } else {
                break
            }
            break
        }
        (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(self: local_a0, 10, 0xe100000000000000, type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x10060b0a0, 0x10060b098, 0x10054ff80, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
        mem64[x23 + 0x38] = type metadata for Swift.String
        mem64[x21 + 0x20] = x19
        mem64[x23 + 0x28] = x20
        mas.OutputFormatOptionGroup.info(_:separator:terminator:)(self: ?, r0, " ", "\n")
        swift_setDeallocating(r0)
    }
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(Array<InstalledApp> installedApps, List param_2)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* mas.MAS.List.run(installedApps: [mas.InstalledApp]) -> () */

void __swift_stdcall
mas::MAS::List::run(long param_1,undefined8 param_2,void *param_3,ContiguousArray param_4)

{
  long lVar1;
  long lVar2;
  ulong uVar3;
  long lVar4;
  long lVar5;
  undefined1 auVar6 [16];
  code *pcVar7;
  undefined8 uVar8;
  code *pcVar9;
  undefined8 *unaff_x20;
  long lVar10;
  long lVar11;
  long lVar12;
  long lVar13;
  long *plVar14;
  long lVar15;
  OptionGroup OVar16;
  String SVar17;
  String SVar18;
  String separator;
  undefined1 auStack_138 [64];
  undefined1 auStack_f8 [64];
  code *local_b8;
  code *local_a0;
  undefined8 uStack_98;
  undefined8 uStack_90;
  undefined8 uStack_88;
  undefined8 local_80;
  
  lVar10 = *(long *)(param_1 + 0x10);
  if (lVar10 == 0) {
    if (__one_time_initialization_token_for_printer != -1) {
      _swift_once(&__one_time_initialization_token_for_printer,one_time_init_for_printer);
    }
    uVar8 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    lVar10 = _swift_initStackObject(uVar8,auStack_138);
    uVar8 = _DAT_10054fde0;
    *(undefined8 *)(lVar10 + 0x18) = _UNK_10054fde8;
    *(undefined8 *)(lVar10 + 0x10) = uVar8;
    *(undefined **)(lVar10 + 0x38) = PTR___type_metadata_for_Swift_String_1005fc368;
    *(undefined8 *)(lVar10 + 0x20) = 0xd0000000000001b7;
    *(undefined8 *)(lVar10 + 0x28) = 0x800000010059b390;
    Printer::_warning(lVar10,0,0x20,0xe100000000000000,10,0xe100000000000000);
    _swift_setDeallocating(lVar10);
    _swift_arrayDestroy((undefined8 *)(lVar10 + 0x20),*(undefined8 *)(lVar10 + 0x10),
                        PTR___type_metadata_for_Any_1005fda48 + 8);
  }
  else {
    uStack_98 = unaff_x20[1];
    local_a0 = (code *)*unaff_x20;
    uStack_88 = unaff_x20[3];
    uStack_90 = unaff_x20[2];
    local_80 = unaff_x20[4];
    auVar6 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                       (&
                        __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                        ,&
                         __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                       );
    OVar16.title.bridgeObject = param_3;
    OVar16._dummy = (bool)auVar6[0];
    OVar16._1_7_ = auVar6._1_7_;
    OVar16.title.str = (char *)auVar6._8_8_;
    ArgumentParser::OptionGroup::get_wrappedValue(OVar16);
    uVar8 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    SVar18.str = (char *)_swift_initStackObject(uVar8,auStack_f8);
    uVar8 = _DAT_10054fde0;
    *(undefined8 *)(SVar18.str + 0x18) = _UNK_10054fde8;
    *(undefined8 *)(SVar18.str + 0x10) = uVar8;
    local_b8 = (code *)PTR___swiftEmptyArrayStorage_1005fda60;
    ::Swift::ContiguousArray::_createNewBuffer(false,lVar10,false,param_4);
    plVar14 = (long *)(param_1 + 0x78);
    do {
      pcVar7 = local_b8;
      lVar11 = plVar14[-9];
      lVar12 = plVar14[-7];
      lVar15 = plVar14[-5];
      lVar1 = plVar14[-3];
      lVar4 = plVar14[-2];
      lVar2 = plVar14[-1];
      lVar5 = *plVar14;
      lVar13 = *(long *)(lVar5 + 0x10);
      _swift_bridgeObjectRetain(lVar11);
      _swift_bridgeObjectRetain(lVar12);
      _swift_bridgeObjectRetain(lVar15);
      _swift_bridgeObjectRetain(lVar1);
      _swift_bridgeObjectRetain(lVar4);
      _swift_retain(lVar2);
      _swift_retain(lVar5);
      _os_unfair_lock_lock(lVar13 + 0x24);
      pcVar9 = *(code **)(lVar13 + 0x10);
      uVar8 = *(undefined8 *)(lVar13 + 0x18);
      if (*(char *)(lVar13 + 0x20) == '\x01') {
        ::_outlined_copy((State)(__int8)pcVar9);
      }
      else {
        (*pcVar9)(&local_a0);
        ::_outlined_consume((State)(__int8)pcVar9);
        uVar8 = uStack_98;
        pcVar9 = local_a0;
        *(code **)(lVar13 + 0x10) = local_a0;
        *(undefined8 *)(lVar13 + 0x18) = uStack_98;
        *(undefined1 *)(lVar13 + 0x20) = 1;
        _swift_bridgeObjectRetain(uStack_98);
      }
      _os_unfair_lock_unlock(lVar13 + 0x24);
      _swift_release(lVar5);
      _swift_release(lVar2);
      _swift_bridgeObjectRelease(lVar4);
      _swift_bridgeObjectRelease(lVar1);
      _swift_bridgeObjectRelease(lVar15);
      _swift_bridgeObjectRelease(lVar12);
      _swift_bridgeObjectRelease(lVar11);
      uVar3 = *(ulong *)(pcVar7 + 0x10);
      local_b8 = pcVar7;
      if (*(ulong *)(pcVar7 + 0x18) >> 1 <= uVar3) {
        ::Swift::ContiguousArray::_createNewBuffer
                  (1 < *(ulong *)(pcVar7 + 0x18),uVar3 + 1,true,param_4);
      }
      pcVar7 = local_b8;
      plVar14 = plVar14 + 0xc;
      *(ulong *)(local_b8 + 0x10) = uVar3 + 1;
      *(code **)(local_b8 + uVar3 * 0x10 + 0x20) = pcVar9;
      *(undefined8 *)(local_b8 + uVar3 * 0x10 + 0x28) = uVar8;
      lVar10 = lVar10 + -1;
    } while (lVar10 != 0);
    local_a0 = local_b8;
    ::___swift_instantiateConcreteTypeFromMangledNameV2
              (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
               &__mangled_name_ref_for_type_metadata_for__Swift_String_);
    ::Swift::Array<String>::_lazy_protocol_witness_table_accessor();
    SVar17.bridgeObject = (void *)0xe100000000000000;
    SVar17.str = (char *)0xa;
    SVar17 = (extension_Swift)::Swift::BidirectionalCollection::_joined(SVar17);
    _swift_release(pcVar7);
    *(undefined **)(SVar18.str + 0x38) = PTR___type_metadata_for_Swift_String_1005fc368;
    *(String *)(SVar18.str + 0x20) = SVar17;
    SVar18.bridgeObject = (void *)0x20;
    separator.bridgeObject = (void *)0xa;
    separator.str = (char *)0xe100000000000000;
    OutputFormatOptionGroup::_info(SVar18,separator,(OutputFormatOptionGroup)0xe100000000000000);
    ::_outlined_consume();
    _swift_setDeallocating(SVar18.str);
    ___swift_destroy_boxed_opaque_existential_0Tm((String *)(SVar18.str + 0x20));
  }
  return;
}
```

## `MAS.Lookup.run`

From `Sources/mas/Commands/MAS.Lookup.swift`.

```swift
		func run() async {
			run(catalogApps: await catalogAppsOptionGroup.appIDs.catalogApps)
		}
```

The optimizer inlined it into every caller, so the binary has no body of its own to decompile.

## `MAS.Lookup.run`

From `Sources/mas/Commands/MAS.Lookup.swift`.

```swift
		func run(catalogApps: [CatalogApp]) {
			outputFormatOptionGroup.info(catalogApps.map(String.init).joined(separator: "\n"))
		}
```

### `mas.MAS.Lookup.run(catalogApps: [mas.CatalogApp]) -> ()` at `0x10000ac7c`

swiftdc:

```swift
mas.MAS.Lookup.run(catalogApps: Swift.Array<mas.CatalogApp>) -> () {
    ArgumentParser.OptionGroup.wrappedValue.getter()
    let r0 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Any>, local_e8)
    mem128[x0 + 0x10] = (1, 2)
    if (x25 != 0) {
        generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_a8, …)
        while (true) {
            os_unfair_lock_lock(?)
            if (w24 != 1) {
                /* unresolved call @ 0x10000add4 */ indirect_call(?, recovered_args: […])
                mem64[x21 + 0x10] = x28; mem64[x21 + 0x18] = x19
                mem8[x21 + 0x20] = 1
            }
            os_unfair_lock_unlock(?)
            if (x22 >=ᵁ (x8 >>ᵁ 1)) {
                generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_a8, …)
            }
            mem64[x20 + 0x10] = x21
            mem64[x8 + 0x20] = x28; mem64[x8 + 0x28] = x19
            if (x25 != 0) {
                continue
            } else {
                break
            }
            break
        }
    }
    (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(self: local_90, 10, 0xe100000000000000, type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x10060b0a0, 0x10060b098, 0x10054ff80, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
    mem64[x26 + 0x38] = type metadata for Swift.String
    mem64[x26 + 0x20] = x19; mem64[x26 + 0x28] = x20
    mas.OutputFormatOptionGroup.info(_:separator:terminator:)(self: ?, r0, " ", "\n")
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall run(Array<CatalogApp> catalogApps, Lookup param_2)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* mas.MAS.Lookup.run(catalogApps: [mas.CatalogApp]) -> () */

void __swift_stdcall
mas::MAS::Lookup::run(long param_1,undefined8 param_2,void *param_3,ContiguousArray param_4)

{
  ulong uVar1;
  long lVar2;
  undefined1 auVar3 [16];
  code *pcVar4;
  undefined8 uVar5;
  undefined8 uVar6;
  undefined8 uVar7;
  undefined8 uVar8;
  undefined8 *unaff_x20;
  code *pcVar9;
  long lVar10;
  undefined8 uVar11;
  undefined8 uVar12;
  long minimumCapacity;
  undefined8 *puVar13;
  OptionGroup OVar14;
  String SVar15;
  String SVar16;
  String separator;
  undefined1 auStack_e8 [64];
  code *local_a8;
  code *local_90;
  undefined8 uStack_88;
  undefined8 uStack_80;
  undefined8 uStack_78;
  undefined8 local_70;
  
  uStack_88 = unaff_x20[1];
  local_90 = (code *)*unaff_x20;
  uStack_78 = unaff_x20[3];
  uStack_80 = unaff_x20[2];
  local_70 = unaff_x20[4];
  auVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                     );
  OVar14.title.bridgeObject = param_3;
  OVar14._dummy = (bool)auVar3[0];
  OVar14._1_7_ = auVar3._1_7_;
  OVar14.title.str = (char *)auVar3._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar14);
  uVar5 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                     ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>);
  SVar16.str = (char *)_swift_initStackObject(uVar5,auStack_e8);
  uVar5 = _DAT_10054fde0;
  *(undefined8 *)(SVar16.str + 0x18) = _UNK_10054fde8;
  *(undefined8 *)(SVar16.str + 0x10) = uVar5;
  minimumCapacity = *(long *)(param_1 + 0x10);
  pcVar9 = (code *)PTR___swiftEmptyArrayStorage_1005fda60;
  if (minimumCapacity != 0) {
    local_a8 = (code *)PTR___swiftEmptyArrayStorage_1005fda60;
    ::Swift::ContiguousArray::_createNewBuffer(false,minimumCapacity,false,param_4);
    puVar13 = (undefined8 *)(param_1 + 0x40);
    do {
      pcVar4 = local_a8;
      uVar11 = puVar13[-2];
      uVar12 = *puVar13;
      uVar7 = puVar13[2];
      uVar6 = puVar13[4];
      uVar5 = puVar13[6];
      lVar2 = puVar13[7];
      lVar10 = *(long *)(lVar2 + 0x10);
      _swift_bridgeObjectRetain();
      _swift_bridgeObjectRetain(uVar5);
      _swift_retain(lVar2);
      _swift_bridgeObjectRetain(uVar11);
      _swift_bridgeObjectRetain(uVar12);
      _swift_bridgeObjectRetain(uVar7);
      _os_unfair_lock_lock(lVar10 + 0x24);
      pcVar9 = *(code **)(lVar10 + 0x10);
      uVar8 = *(undefined8 *)(lVar10 + 0x18);
      if (*(char *)(lVar10 + 0x20) == '\x01') {
        ::_outlined_copy((State)(__int8)pcVar9);
      }
      else {
        (*pcVar9)(&local_90);
        ::_outlined_consume((State)(__int8)pcVar9);
        uVar8 = uStack_88;
        pcVar9 = local_90;
        *(code **)(lVar10 + 0x10) = local_90;
        *(undefined8 *)(lVar10 + 0x18) = uStack_88;
        *(undefined1 *)(lVar10 + 0x20) = 1;
        _swift_bridgeObjectRetain(uStack_88);
      }
      _os_unfair_lock_unlock(lVar10 + 0x24);
      _swift_release(lVar2);
      _swift_bridgeObjectRelease(uVar5);
      _swift_bridgeObjectRelease(uVar6);
      _swift_bridgeObjectRelease(uVar7);
      _swift_bridgeObjectRelease(uVar12);
      _swift_bridgeObjectRelease(uVar11);
      uVar1 = *(ulong *)(pcVar4 + 0x10);
      local_a8 = pcVar4;
      if (*(ulong *)(pcVar4 + 0x18) >> 1 <= uVar1) {
        ::Swift::ContiguousArray::_createNewBuffer
                  (1 < *(ulong *)(pcVar4 + 0x18),uVar1 + 1,true,param_4);
      }
      puVar13 = puVar13 + 0xc;
      *(ulong *)(local_a8 + 0x10) = uVar1 + 1;
      *(code **)(local_a8 + uVar1 * 0x10 + 0x20) = pcVar9;
      *(undefined8 *)(local_a8 + uVar1 * 0x10 + 0x28) = uVar8;
      minimumCapacity = minimumCapacity + -1;
    } while (minimumCapacity != 0);
    pcVar9 = local_a8;
  }
  local_90 = pcVar9;
  ::___swift_instantiateConcreteTypeFromMangledNameV2
            (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
             &__mangled_name_ref_for_type_metadata_for__Swift_String_);
  ::Swift::Array<String>::_lazy_protocol_witness_table_accessor();
  SVar15.bridgeObject = (void *)0xe100000000000000;
  SVar15.str = (char *)0xa;
  SVar15 = (extension_Swift)::Swift::BidirectionalCollection::_joined(SVar15);
  _swift_bridgeObjectRelease(pcVar9);
  *(undefined **)(SVar16.str + 0x38) = PTR___type_metadata_for_Swift_String_1005fc368;
  *(String *)(SVar16.str + 0x20) = SVar15;
  SVar16.bridgeObject = (void *)0x20;
  separator.bridgeObject = (void *)0xa;
  separator.str = (char *)0xe100000000000000;
  OutputFormatOptionGroup::_info(SVar16,separator,(OutputFormatOptionGroup)0xe100000000000000);
  ::_outlined_consume();
  _swift_release(SVar16.str);
  return;
}
```

## `MAS.Lucky.run`

From `Sources/mas/Commands/MAS.Lucky.swift`.

```swift
		func run() async throws {
			let searchTerm = searchTermOptionGroup.searchTerm
			guard let adamID = try await Environment.current.searchForAppsMatchingSearchTerm(searchTerm).first?.adamID else {
				throw MASError.noCatalogAppsFound(for: searchTerm)
			}

			await AppStore.install.apps(withADAMIDs: [adamID], force: forceOptionGroup.force)
		}
```

### `mas.MAS.Lucky.run() async throws -> ()` at `0x10000c21c`

swiftdc:

```swift
mas.MAS.Lucky.run() async throws -> () {
    // async function: 2 resume funclet(s): resume #1 @0x10000c42c, resume #2 @0x10000c624
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Argument.wrappedValue.getter()
    (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(" ", type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x10060b0a0, 0x10060b098, 0x10054ff80, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
    mem64[x20 + 0x28] = x0; mem64[x20 + 0x30] = x1
    if (x8 != -1) {
        swift_once(0x10060c2f0, one-time initialization function for $current, ?)
    }
    let r0 = swift_task_localValueGet(?)
    if (!r0) {
        Swift.TaskLocal.get(self: ?)
    } else {
        outlined init with copy of mas.Environment(r0, ?)
    }
    await indirect_call(?)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Lucky param_1)
/* mas.MAS.Lucky.run() async throws -> () */

void __swift_stdcall mas::MAS::Lucky::_run(Lucky param_1)

{
  int iVar1;
  int *piVar2;
  undefined1 auVar3 [16];
  void *this;
  Environment EVar4;
  long lVar5;
  Argument AVar6;
  long lVar7;
  long *plVar8;
  ulong in_x1;
  void *in_x2;
  long unaff_x20;
  undefined8 uVar9;
  long unaff_x22;
  undefined8 uVar10;
  undefined8 uVar11;
  OptionGroup OVar12;
  String SVar13;
  
  *(ulong *)(unaff_x22 + 0x100) = in_x1;
  *(long *)(unaff_x22 + 0x108) = unaff_x20;
  *(undefined **)(unaff_x22 + 0xf8) = param_1.unknown;
  EVar4 = Environment::typeMetadataAccessor();
  lVar5 = _swift_task_alloc(*(long *)(*(long *)(EVar4.unknown + -8) + 0x40) + 0xfU &
                            0xfffffffffffffff0);
  *(long *)(unaff_x22 + 0x110) = lVar5;
  uVar9 = *(undefined8 *)(unaff_x20 + 0x28);
  uVar11 = *(undefined8 *)(unaff_x20 + 0x40);
  uVar10 = *(undefined8 *)(unaff_x20 + 0x38);
  *(undefined8 *)(unaff_x22 + 0x18) = *(undefined8 *)(unaff_x20 + 0x30);
  *(undefined8 *)(unaff_x22 + 0x10) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar11;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar10;
  *(undefined8 *)(unaff_x22 + 0x30) = *(undefined8 *)(unaff_x20 + 0x48);
  auVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_SearchTermOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_SearchTermOptionGroup>
                     );
  OVar12.title.bridgeObject = in_x2;
  OVar12._dummy = (bool)auVar3[0];
  OVar12._1_7_ = auVar3._1_7_;
  OVar12.title.str = (char *)auVar3._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar12);
  *(undefined8 *)(unaff_x22 + 0xa0) = *(undefined8 *)(unaff_x22 + 0x88);
  *(undefined8 *)(unaff_x22 + 0xa8) = *(undefined8 *)(unaff_x22 + 0x90);
  *(undefined1 *)(unaff_x22 + 0xb0) = *(undefined1 *)(unaff_x22 + 0x98);
  AVar6.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                 );
  ArgumentParser::Argument::get_wrappedValue(AVar6);
  uVar9 = *(undefined8 *)(unaff_x22 + 0xe8);
  *(undefined8 *)(unaff_x22 + 0xf0) = uVar9;
  ::___swift_instantiateConcreteTypeFromMangledNameV2
            (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
             &__mangled_name_ref_for_type_metadata_for__Swift_String_);
  ::Swift::Array<String>::_lazy_protocol_witness_table_accessor();
  SVar13.bridgeObject = (void *)0xe100000000000000;
  SVar13.str = (char *)0x20;
  SVar13 = (extension_Swift)::Swift::BidirectionalCollection::_joined(SVar13);
  *(String *)(unaff_x22 + 0x118) = SVar13;
  ::_outlined_consume();
  _swift_bridgeObjectRelease(uVar9);
  if (__one_time_initialization_token_for__current != -1) {
    _swift_once(&__one_time_initialization_token_for__current,
                Environment::one_time_init_for__current);
  }
  this = __s3mas11EnvironmentV8_currents9TaskLocalCyACGvpZ;
  lVar7 = _swift_task_localValueGet(__s3mas11EnvironmentV8_currents9TaskLocalCyACGvpZ);
  if (lVar7 == 0) {
    ::Swift::TaskLocal::get(this);
  }
  else {
    __outlined_init_with_copy_of_mas_Environment(lVar7,lVar5);
  }
  piVar2 = *(int **)(lVar5 + *(int *)(EVar4.unknown + 0x20));
  uVar9 = ((undefined8 *)(lVar5 + *(int *)(EVar4.unknown + 0x20)))[1];
  *(undefined8 *)(unaff_x22 + 0x128) = uVar9;
  _swift_retain(uVar9);
  __outlined_destroy_of_mas_Environment(lVar5);
  iVar1 = *piVar2;
  plVar8 = (long *)_swift_task_alloc(piVar2[1]);
  *(long **)(unaff_x22 + 0x130) = plVar8;
  *plVar8 = unaff_x22;
  plVar8[1] = (long)_run;
                    /* WARNING: Could not recover jumptable at 0x00010000c410. Too many branches */
                    /* WARNING: Treating indirect jump as call */
  (*(code *)((long)iVar1 + (long)piVar2))
            (param_1.unknown,in_x1 & 0xcfffffffffffffff,SVar13.str,SVar13.bridgeObject);
  return;
}
```

## `MAS.Open.run`

From `Sources/mas/Commands/MAS.Open.swift`.

```swift
		func run() async throws {
			guard let appIDString else {
				// If no App Store Page URL was given, open the App Store
				guard let macAppStoreSchemeURL = URL(string: "\(masScheme):") else {
					throw MASError.error("Failed to create URL from \(masScheme) scheme")
				}

				let workspace = NSWorkspace.shared
				guard let appURL = workspace.urlForApplication(toOpen: macAppStoreSchemeURL) else {
					throw MASError.error("Failed to find app to open \(masScheme) URLs")
				}

				try await workspace.openApplication(at: appURL, configuration: .init())
				return
			}

			let appStorePageURLString = try await Environment.current
				.lookupAppFromAppID(.init(from: appIDString, forceBundleID: forceBundleIDOptionGroup.forceBundleID))
				.appStorePageURLString
			guard var urlComponents = URLComponents(string: appStorePageURLString) else {
				throw MASError.invalidURL(appStorePageURLString)
			}

			urlComponents.scheme = masScheme
			guard let url = urlComponents.url else {
				throw MASError.invalidURL(.init(describing: urlComponents))
			}

			_ = try await url.open()
		}
```

### `mas.MAS.Open.run() async throws -> ()` at `0x10000d72c`

swiftdc:

```swift
mas.MAS.Open.run() async throws -> () {
    // async function: 5 resume funclet(s): resume #1 @0x10000de0c, resume #2 @0x10000e2b4, resume #3 @0x10000e10c, resume #4 @0x10000e414, resume #5 @0x10000e318
    mem128[x20] = self._appIDString[0..<16]
    ArgumentParser.Argument.wrappedValue.getter()
    if (x23 == 0) {
        Foundation.URL.init(string:)("macappstore:")
        if (getEnumTagSinglePayload value witness for Foundation.URL(?, 1) != 1) {
            initializeWithTake value witness for Foundation.URL(?, ?)
            let r2 = [NSWorkspace sharedWorkspace]
            let r3 = [r2 URLForApplicationToOpenURL:Foundation.URL._bridgeToObjectiveC(self: ?)]
            if (!r3) {
                let r6 = swift_allocError(0x1005e4420, lazy protocol witness table accessor for type mas.MASError and conformance mas.MASError : Swift.Error in mas(), 0, false)
                mem64[x1] = 0xd00000000000002b; mem64[x1 + 0x8] = "Failed to find app to open macappstore URLs"
                mem128[x1 + 0x10] = (0, 2618)
                mem64[x1 + 0x20] = 0xe200000000000000; mem64[x1 + 0x28] = 0
                mem64[x1 + 0x30] = 0xe000000000000000
                mem8[x1 + 0x38] = 0
                swift_willThrow(r6)
                destroy value witness for Foundation.URL(?)
                loc_10000dd68:
                /* unresolved indirect branch @ 0x10000ddf0 */ indirect_jump(?)
            } else {
                static Foundation.URL._unconditionallyBridgeFromObjectiveC(r3)
                initializeWithTake value witness for Foundation.URL(?, ?)
                let r4 = Foundation.URL._bridgeToObjectiveC(self: ?)
                let r5 = [[NSWorkspaceOpenConfiguration allocWithZone:nil] init]
                swift_continuation_init(?, 1)
                Swift.CheckedContinuation.init(continuation:function:)(?, ?)
                initializeWithTake value witness for Swift.CheckedContinuation<__C.NSRunningApplication, Swift.Error>(__swift_allocate_boxed_opaque_existential_0(?), ?)
                mem64[x4 + 0x8] = 0x42000000
                mem64[x4 + 0x10] = predefined @objc completion handler block implementation for @escaping @callee_unowned @convention(block) @Sendable (@unowned Swift.Optional<__C.NSRunningApplication>, @unowned Swift.Optional<__C.NSError>) -> () with result type __C.NSRunningApplication; mem64[x4 + 0x18] = 0x1005e1928
                [r2 openApplicationAtURL:r4 configuration:r5 completionHandler:?]
                destroy value witness for Swift.CheckedContinuation<__C.NSRunningApplication, Swift.Error>(__swift_allocate_boxed_opaque_existential_0(?))
                swift_continuation_await()
                // no fall-through
            }
        } else {
            merged outlined destroy of …(?, 0x10060b2a0, 0x100550530)
            let r1 = swift_allocError(0x1005e4420, lazy protocol witness table accessor for type mas.MASError and conformance mas.MASError : Swift.Error in mas(), 0, false)
            mem64[x1] = 0xd00000000000002c; mem64[x1 + 0x8] = "Failed to create URL from macappstore scheme"
            mem128[x1 + 0x10] = (0, 2618)
            mem64[x1 + 0x20] = 0xe200000000000000; mem64[x1 + 0x28] = 0
            mem64[x1 + 0x30] = 0xe000000000000000
            mem8[x1 + 0x38] = 0
            swift_willThrow(r1)
            goto loc_10000dd68
        }
    } else {
        if (x8 != -1) {
            swift_once(0x10060c2f0, one-time initialization function for $current, ?)
        }
        let r0 = swift_task_localValueGet(?)
        if (!r0) {
            Swift.TaskLocal.get(self: ?)
        } else {
            outlined init with copy of mas.Environment(r0, ?)
        }
        ArgumentParser.OptionGroup.wrappedValue.getter()
        ArgumentParser.Flag.wrappedValue.getter()
        function signature specialization <Arg[2] = Dead> of mas.AppID.init(from:forceBundleID:)(?, ?, ?)
        await indirect_call(?)
    }
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Open param_1)
/* WARNING: Function: _objc_opt_self replaced with injection: _objc_retain_fixup */
/* WARNING: Function: _objc_retainAutoreleasedReturnValue replaced with injection:
   _objc_retain_fixup */
/* WARNING: Function: _objc_release replaced with injection: _objc_release_fixup */
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* mas.MAS.Open.run() async throws -> () */

void __swift_stdcall mas::MAS::Open::_run(Open param_1)

{
  int *piVar1;
  undefined8 uVar2;
  undefined1 auVar3 [16];
  void *this;
  AppID AVar4;
  int iVar5;
  long lVar6;
  undefined8 uVar7;
  long lVar8;
  undefined8 uVar9;
  undefined8 uVar10;
  URL UVar11;
  undefined8 uVar12;
  undefined8 uVar13;
  undefined8 uVar14;
  URLComponents UVar15;
  Environment EVar16;
  Argument AVar17;
  Flag FVar18;
  long *plVar19;
  URL self;
  NSURL *pNVar20;
  URL UVar21;
  ID IVar22;
  UnsafeContinuation<undefined,undefined> continuation;
  ulong in_x1;
  undefined8 *extraout_x1;
  undefined8 *extraout_x1_00;
  void *in_x2;
  ulong uVar23;
  long lVar24;
  long lVar25;
  char *pcVar26;
  undefined8 *unaff_x20;
  undefined8 uVar27;
  long unaff_x22;
  void *pvVar28;
  code *pcVar29;
  undefined8 uVar30;
  OptionGroup OVar31;
  String from;
  String function;
  
  *(undefined **)(unaff_x22 + 0x178) = param_1.unknown;
  *(ulong *)(unaff_x22 + 0x180) = in_x1;
  lVar6 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift_CheckedContinuation<__C_NSRunningApplication,Swift_Error>
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Swift_CheckedContinuation<__C_NSRunningApplication,Swift_Error>
                    );
  lVar24 = *(long *)(lVar6 + -8);
  uVar7 = _swift_task_alloc(*(long *)(lVar24 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x188) = uVar7;
  lVar8 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                     &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
  uVar23 = *(long *)(*(long *)(lVar8 + -8) + 0x40) + 0xf;
  uVar9 = _swift_task_alloc(uVar23 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 400) = uVar9;
  uVar10 = _swift_task_alloc(uVar23 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x198) = uVar10;
  UVar11 = Foundation::URL::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x1a0) = UVar11.unknown;
  lVar25 = *(long *)(UVar11.unknown + -8);
  *(long *)(unaff_x22 + 0x1a8) = lVar25;
  uVar23 = *(long *)(lVar25 + 0x40) + 0xf;
  uVar10 = _swift_task_alloc(uVar23 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x1b0) = uVar10;
  uVar12 = _swift_task_alloc(uVar23 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x1b8) = uVar12;
  uVar13 = _swift_task_alloc(uVar23 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x1c0) = uVar13;
  uVar14 = _swift_task_alloc(uVar23 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x1c8) = uVar14;
  lVar8 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__demangling_cache_variable_for_type_metadata_for_Foundation_URLComponents_,
                     &__mangled_name_ref_for_type_metadata_for_Foundation_URLComponents_);
  uVar14 = _swift_task_alloc(*(long *)(*(long *)(lVar8 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x1d0) = uVar14;
  UVar15 = Foundation::URLComponents::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x1d8) = UVar15.unknown;
  lVar8 = *(long *)(UVar15.unknown + -8);
  *(long *)(unaff_x22 + 0x1e0) = lVar8;
  uVar14 = _swift_task_alloc(*(long *)(lVar8 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x1e8) = uVar14;
  EVar16 = Environment::typeMetadataAccessor();
  lVar8 = _swift_task_alloc(*(long *)(*(long *)(EVar16.unknown + -8) + 0x40) + 0xfU &
                            0xfffffffffffffff0);
  *(long *)(unaff_x22 + 0x1f0) = lVar8;
  uVar14 = unaff_x20[5];
  *(undefined8 *)(unaff_x22 + 0x120) = unaff_x20[6];
  *(undefined8 *)(unaff_x22 + 0x118) = uVar14;
  *(undefined1 *)(unaff_x22 + 0x128) = *(undefined1 *)(unaff_x20 + 7);
  AVar17.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<Swift_String_>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<Swift_String_>)
  ;
  ArgumentParser::Argument::get_wrappedValue(AVar17);
  pvVar28 = *(void **)(unaff_x22 + 0x168);
  if (pvVar28 != (void *)0x0) {
    pcVar26 = *(char **)(unaff_x22 + 0x160);
    if (__one_time_initialization_token_for__current != -1) {
      _swift_once(&__one_time_initialization_token_for__current,
                  Environment::one_time_init_for__current);
    }
    this = __s3mas11EnvironmentV8_currents9TaskLocalCyACGvpZ;
    lVar6 = _swift_task_localValueGet(__s3mas11EnvironmentV8_currents9TaskLocalCyACGvpZ);
    if (lVar6 == 0) {
      ::Swift::TaskLocal::get(this);
    }
    else {
      __outlined_init_with_copy_of_mas_Environment(lVar6,lVar8);
    }
    piVar1 = *(int **)(lVar8 + *(int *)(EVar16.unknown + 0x1c));
    uVar7 = ((undefined8 *)(lVar8 + *(int *)(EVar16.unknown + 0x1c)))[1];
    *(undefined8 *)(unaff_x22 + 0x1f8) = uVar7;
    _swift_retain(uVar7);
    __outlined_destroy_of_mas_Environment(lVar8);
    uVar7 = *unaff_x20;
    uVar10 = unaff_x20[3];
    uVar9 = unaff_x20[2];
    *(undefined8 *)(unaff_x22 + 0xf8) = unaff_x20[1];
    *(undefined8 *)(unaff_x22 + 0xf0) = uVar7;
    *(undefined8 *)(unaff_x22 + 0x108) = uVar10;
    *(undefined8 *)(unaff_x22 + 0x100) = uVar9;
    *(undefined8 *)(unaff_x22 + 0x110) = unaff_x20[4];
    auVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                       (&
                        __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceBundleIDOptionGroup>
                        ,&
                         __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceBundleIDOptionGroup>
                       );
    OVar31.title.bridgeObject = in_x2;
    OVar31._dummy = (bool)auVar3[0];
    OVar31._1_7_ = auVar3._1_7_;
    OVar31.title.str = (char *)auVar3._8_8_;
    ArgumentParser::OptionGroup::get_wrappedValue(OVar31);
    *(undefined8 *)(unaff_x22 + 0x148) = *(undefined8 *)(unaff_x22 + 0x130);
    *(undefined8 *)(unaff_x22 + 0x150) = *(undefined8 *)(unaff_x22 + 0x138);
    *(undefined1 *)(unaff_x22 + 0x158) = *(undefined1 *)(unaff_x22 + 0x140);
    FVar18.unknown =
         (undefined *)
         ::___swift_instantiateConcreteTypeFromMangledNameV2
                   (&
                    __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                    ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
    ArgumentParser::Flag::get_wrappedValue(FVar18);
    ::_outlined_consume();
    uVar23 = (ulong)*(bool *)(unaff_x22 + 0x129);
    from.bridgeObject = pvVar28;
    from.str = pcVar26;
    AVar4 = AppID::_init(from,*(bool *)(unaff_x22 + 0x129));
    *(ulong *)(unaff_x22 + 0x200) = CONCAT71(from.str._1_7_,AVar4.value);
    *(void **)(unaff_x22 + 0x208) = pvVar28;
    *(char *)(unaff_x22 + 0x12a) = (char)uVar23;
    iVar5 = *piVar1;
    plVar19 = (long *)_swift_task_alloc(piVar1[1]);
    *(long **)(unaff_x22 + 0x210) = plVar19;
    *plVar19 = unaff_x22;
    plVar19[1] = (long)_run;
                    /* WARNING: Could not recover jumptable at 0x00010000db10. Too many branches */
                    /* WARNING: Treating indirect jump as call */
    (*(code *)((long)iVar5 + (long)piVar1))
              (plVar19,unaff_x22 + 0x50,param_1.unknown,in_x1 & 0xcfffffffffffffff,
               CONCAT71(from.str._1_7_,AVar4.value),pvVar28,uVar23);
    return;
  }
  Foundation::URL::_init();
  iVar5 = (**(code **)(lVar25 + 0x30))(uVar9,1,UVar11.unknown);
  if (iVar5 == 1) {
    uVar7 = __merged_outlined_destroy_of_Foundation_URL_
                      (uVar9,&__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                       &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
    MASError::_lazy_protocol_witness_table_accessor();
    _swift_allocError(&__type_metadata_for_mas_MASError,uVar7,0,0);
    *extraout_x1 = 0xd00000000000002c;
    extraout_x1[1] = 0x800000010059b6a0;
    uVar7 = _DAT_100550d40;
    extraout_x1[3] = _UNK_100550d48;
    extraout_x1[2] = uVar7;
    extraout_x1[4] = 0xe200000000000000;
    extraout_x1[5] = 0;
    extraout_x1[6] = 0xe000000000000000;
    *(undefined1 *)(extraout_x1 + 7) = 0;
    _swift_willThrow();
  }
  else {
    pcVar29 = *(code **)(lVar25 + 0x20);
    (*pcVar29)(uVar13,uVar9,UVar11.unknown);
    self.unknown = (undefined *)
                   NSWorkspace::sharedWorkspace((ID)PTR__OBJC_CLASS___NSWorkspace_10060acc8);
    *(undefined **)(unaff_x22 + 0x228) = self.unknown;
    pNVar20 = Foundation::URL::_bridgeToObjectiveC(self);
    UVar21.unknown = (undefined *)NSWorkspace::URLForApplicationToOpenURL_((ID)self.unknown,pNVar20)
    ;
    uVar9 = 0;
    if (UVar21.unknown != (undefined *)0x0) {
      Foundation::URL::__unconditionallyBridgeFromObjectiveC(UVar21);
      UVar11.unknown = (undefined *)(*pcVar29)(uVar12,uVar10,UVar11.unknown);
      pNVar20 = Foundation::URL::_bridgeToObjectiveC(UVar11);
      *(NSURL **)(unaff_x22 + 0x230) = pNVar20;
      IVar22 = _objc_allocWithZone(PTR__OBJC_CLASS___NSWorkspaceOpenConfiguration_10060acc0);
      IVar22 = NSWorkspaceOpenConfiguration::init(IVar22);
      *(ID *)(unaff_x22 + 0x238) = IVar22;
      *(long *)(unaff_x22 + 0x38) = unaff_x22 + 0x170;
      *(long *)(unaff_x22 + 0x10) = unaff_x22;
      *(code **)(unaff_x22 + 0x18) = _run;
      continuation.unknown = (undefined *)_swift_continuation_init(unaff_x22 + 0x10,1);
      *(long *)(unaff_x22 + 0xe8) = lVar6;
      uVar9 = ___swift_allocate_boxed_opaque_existential_0(unaff_x22 + 0xd0);
      __C::NSRunningApplication::typeMetadataAccessor();
      ::___swift_instantiateConcreteTypeFromMangledNameV2
                (&__demangling_cache_variable_for_type_metadata_for_Swift_Error,
                 &__mangled_name_ref_for_type_metadata_for_Swift_Error);
      function.bridgeObject = (void *)0x800000010059b2f0;
      function.str = (char *)0xd000000000000026;
      ::Swift::CheckedContinuation::init(continuation,function);
      (**(code **)(lVar24 + 0x20))(uVar9,uVar7,lVar6);
      *(undefined **)(unaff_x22 + 0xb0) = PTR___NSConcreteStackBlock_1005fba70;
      *(undefined8 *)(unaff_x22 + 0xb8) = DAT_100550488;
      *(code **)(unaff_x22 + 0xc0) =
           __checked__objc_completion_handler_block_implementation_for__escaping__callee_unowned__convention_block___Sendable___unowned___C_NSRunningApplication___unowned___C_NSError____>____with_result_type___C_NSRunningApplication
      ;
      *(undefined **)(unaff_x22 + 200) = &_block_descriptor;
      NSWorkspace::openApplicationAtURL_configuration_completionHandler_
                ((ID)self.unknown,pNVar20,IVar22);
      (**(code **)(lVar24 + 8))(uVar9,lVar6);
      _swift_continuation_await(unaff_x22 + 0x10);
      return;
    }
    MASError::_lazy_protocol_witness_table_accessor();
    _swift_allocError(&__type_metadata_for_mas_MASError,uVar9,0,0);
    *extraout_x1_00 = 0xd00000000000002b;
    extraout_x1_00[1] = 0x800000010059b6d0;
    uVar7 = _DAT_100550d40;
    extraout_x1_00[3] = _UNK_100550d48;
    extraout_x1_00[2] = uVar7;
    extraout_x1_00[4] = 0xe200000000000000;
    extraout_x1_00[5] = 0;
    extraout_x1_00[6] = 0xe000000000000000;
    *(undefined1 *)(extraout_x1_00 + 7) = 0;
    _swift_willThrow();
    (**(code **)(lVar25 + 8))(uVar13,UVar11.unknown);
  }
  uVar7 = *(undefined8 *)(unaff_x22 + 0x1e8);
  uVar9 = *(undefined8 *)(unaff_x22 + 0x1c8);
  uVar13 = *(undefined8 *)(unaff_x22 + 0x1d0);
  uVar10 = *(undefined8 *)(unaff_x22 + 0x1b8);
  uVar14 = *(undefined8 *)(unaff_x22 + 0x1c0);
  uVar30 = *(undefined8 *)(unaff_x22 + 0x1b0);
  uVar12 = *(undefined8 *)(unaff_x22 + 400);
  uVar2 = *(undefined8 *)(unaff_x22 + 0x198);
  uVar27 = *(undefined8 *)(unaff_x22 + 0x188);
  _swift_task_dealloc(*(undefined8 *)(unaff_x22 + 0x1f0));
  _swift_task_dealloc(uVar7);
  _swift_task_dealloc(uVar13);
  _swift_task_dealloc(uVar9);
  _swift_task_dealloc(uVar14);
  _swift_task_dealloc(uVar10);
  _swift_task_dealloc(uVar30);
  _swift_task_dealloc(uVar2);
  _swift_task_dealloc(uVar12);
  _swift_task_dealloc(uVar27);
                    /* WARNING: Could not recover jumptable at 0x00010000ddf0. Too many branches */
                    /* WARNING: Treating indirect jump as call */
  (**(code **)(unaff_x22 + 8))();
  return;
}
```

## `MAS.Outdated.run`

From `Sources/mas/Commands/MAS.Outdated.swift`.

```swift
		func run() async {
			let outdatedApps =
				await outdatedAppsOptionGroup.outdatedApps(withFullJSON: outputFormatOptionGroup.shouldOutputJSON)
			if !outdatedApps.isEmpty {
				outputFormatOptionGroup.info(outdatedApps.map { .init(describing: $0) }.joined(separator: "\n"))
			}
		}
```

### `mas.MAS.Outdated.run() async -> ()` at `0x10000fc58`

swiftdc:

```swift
mas.MAS.Outdated.run() async -> () {
    // async function: 1 resume funclet(s): resume #1 @0x10000fdb0
    ArgumentParser.OptionGroup.wrappedValue.getter()
    mem128[x23] = self._outputFormatOptionGroup[0..<16]; mem128[x23 + 0x10] = self._outputFormatOptionGroup[16..<32]
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Flag.wrappedValue.getter()
    sub_10000f58c(?, ?, ?)
    let awaited1 = await mas.OutdatedAppsOptionGroup.outdatedApps(withFullJSON:)(self: (? + 192), ?)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Outdated param_1)
/* mas.MAS.Outdated.run() async -> () */

void __swift_stdcall mas::MAS::Outdated::_run(Outdated param_1)

{
  undefined1 uVar1;
  undefined1 auVar2 [16];
  Flag FVar3;
  long *plVar4;
  ulong in_x1;
  void *in_x2;
  undefined8 *unaff_x20;
  long unaff_x22;
  undefined8 uVar5;
  undefined8 uVar6;
  undefined8 uVar7;
  undefined8 uVar8;
  undefined8 uVar9;
  undefined8 uVar10;
  undefined8 uVar11;
  OptionGroup OVar12;
  OptionGroup OVar13;
  
  *(undefined8 **)(unaff_x22 + 0x238) = unaff_x20;
  uVar6 = unaff_x20[0x14];
  uVar5 = unaff_x20[0x13];
  uVar7 = unaff_x20[0x15];
  uVar9 = unaff_x20[0x18];
  uVar8 = unaff_x20[0x17];
  *(undefined8 *)(unaff_x22 + 0x98) = unaff_x20[0x16];
  *(undefined8 *)(unaff_x22 + 0x90) = uVar7;
  *(undefined8 *)(unaff_x22 + 0xa8) = uVar9;
  *(undefined8 *)(unaff_x22 + 0xa0) = uVar8;
  uVar7 = unaff_x20[0x19];
  *(undefined8 *)(unaff_x22 + 0xb8) = unaff_x20[0x1a];
  *(undefined8 *)(unaff_x22 + 0xb0) = uVar7;
  uVar8 = unaff_x20[0xc];
  uVar7 = unaff_x20[0xb];
  uVar9 = unaff_x20[0xd];
  uVar11 = unaff_x20[0x10];
  uVar10 = unaff_x20[0xf];
  *(undefined8 *)(unaff_x22 + 0x58) = unaff_x20[0xe];
  *(undefined8 *)(unaff_x22 + 0x50) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x68) = uVar11;
  *(undefined8 *)(unaff_x22 + 0x60) = uVar10;
  uVar9 = unaff_x20[0x11];
  *(undefined8 *)(unaff_x22 + 0x78) = unaff_x20[0x12];
  *(undefined8 *)(unaff_x22 + 0x70) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x88) = uVar6;
  *(undefined8 *)(unaff_x22 + 0x80) = uVar5;
  uVar5 = unaff_x20[5];
  uVar9 = unaff_x20[8];
  uVar6 = unaff_x20[7];
  *(undefined8 *)(unaff_x22 + 0x18) = unaff_x20[6];
  *(undefined8 *)(unaff_x22 + 0x10) = uVar5;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar6;
  uVar5 = unaff_x20[9];
  *(undefined8 *)(unaff_x22 + 0x38) = unaff_x20[10];
  *(undefined8 *)(unaff_x22 + 0x30) = uVar5;
  *(undefined8 *)(unaff_x22 + 0x48) = uVar8;
  *(undefined8 *)(unaff_x22 + 0x40) = uVar7;
  auVar2 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutdatedAppsOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutdatedAppsOptionGroup>
                     );
  OVar12.title.bridgeObject = in_x2;
  OVar12._dummy = (bool)auVar2[0];
  OVar12._1_7_ = auVar2._1_7_;
  OVar12.title.str = (char *)auVar2._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar12);
  uVar5 = *unaff_x20;
  uVar7 = unaff_x20[3];
  uVar6 = unaff_x20[2];
  *(undefined8 *)(unaff_x22 + 0x1a0) = unaff_x20[1];
  *(undefined8 *)(unaff_x22 + 0x198) = uVar5;
  *(undefined8 *)(unaff_x22 + 0x1b0) = uVar7;
  *(undefined8 *)(unaff_x22 + 0x1a8) = uVar6;
  *(undefined8 *)(unaff_x22 + 0x1b8) = unaff_x20[4];
  OVar13._0_16_ =
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                 );
  *(long *)(unaff_x22 + 0x240) = OVar13._0_8_;
  OVar13.title.bridgeObject = in_x2;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar13);
  uVar5 = *(undefined8 *)(unaff_x22 + 0x1e8);
  uVar6 = *(undefined8 *)(unaff_x22 + 0x1f0);
  *(undefined8 *)(unaff_x22 + 0x200) = uVar5;
  *(undefined8 *)(unaff_x22 + 0x208) = uVar6;
  uVar1 = *(undefined1 *)(unaff_x22 + 0x1f8);
  *(undefined1 *)(unaff_x22 + 0x210) = uVar1;
  FVar3.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar3);
  FUN_10000f58c(uVar5,uVar6,uVar1);
  plVar4 = (long *)_swift_task_alloc(DAT_1005521ec);
  *(long **)(unaff_x22 + 0x248) = plVar4;
  *plVar4 = unaff_x22;
  plVar4[1] = (long)_run;
  OutdatedAppsOptionGroup::_outdatedApps
            (SUB81(param_1.unknown,0),(undefined *)(in_x1 & 0xcfffffffffffffff));
  return;
}
```

## `MAS.Reset.run`

From `Sources/mas/Commands/MAS.Reset.swift`.

```swift
		func run() {
			for bundleID in ["com.apple.dock", "com.apple.storeuid"] {
				for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.terminate() {
					printer.warning("Failed to terminate app with bundle ID", bundleID)
					if !app.forceTerminate() {
						printer.error("Failed to force terminate app with bundle ID", bundleID)
					}
				}
			}

			let executablePathSet = Set(
				[
					"/System/Library/Frameworks/StoreKit.framework/Support/storekitagent",
					"/System/Library/PrivateFrameworks/AppStoreComponents.framework/Support/appstorecomponentsd",
					"/System/Library/PrivateFrameworks/AppStoreDaemon.framework/Support/appstoreagent",
					"/System/Library/PrivateFrameworks/CascadeSets.framework/Versions/A/XPCServices"
						+ "/SetStoreUpdateService.xpc/Contents/MacOS/SetStoreUpdateService",
					"/System/Library/PrivateFrameworks/CommerceKit.framework/Versions/A/Resources/storeaccountd",
					"/System/Library/PrivateFrameworks/CommerceKit.framework/Versions/A/Resources/storeassetd",
					"/System/Library/PrivateFrameworks/CommerceKit.framework/Versions/A/Resources/storedownloadd",
					"/System/Library/PrivateFrameworks/CommerceKit.framework/Versions/A/Resources/storeinstalld",
					"/System/Library/PrivateFrameworks/CommerceKit.framework/Versions/A/Resources/storelegacy",
				],
			)

			var processListMIB = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
			var length = 0
			guard unsafe sysctl(&processListMIB, u_int(processListMIB.count), nil, &length, nil, 0) == 0 else {
				printer.error("Failed to get process list length")
				return
			}

			var kinfoProcs = unsafe Array(repeating: unsafe kinfo_proc(), count: length / MemoryLayout<kinfo_proc>.stride)
			guard unsafe sysctl(&processListMIB, u_int(processListMIB.count), &kinfoProcs, &length, nil, 0) == 0 else {
				printer.error("Failed to get process list")
				return
			}

			unsafe withUnsafeTemporaryAllocation(of: CChar.self, capacity: .init(PATH_MAX)) { buffer in
				guard let baseAddress = buffer.baseAddress else {
					return
				}

				for unsafe pid in unsafe kinfoProcs.lazy.map(unsafe \.kp_proc.p_pid) {
					if
						unsafe proc_pidpath(pid, unsafe baseAddress, .init(buffer.count)) > 0,
						let executablePath = unsafe String(validatingCString: unsafe baseAddress),
						executablePathSet.contains(executablePath)
					{
						let exitStatus = kill(pid, SIGTERM)
						if exitStatus != 0 {
							printer.error("Failed to terminate", executablePath, "getting exit status", exitStatus, "for pid", pid)
						}
					}
				}
			}

			let folder = CKDownloadDirectory(nil)
			do {
				try FileManager.default.removeItem(atPath: folder)
			} catch {
				printer.error("Failed to delete download folder", folder, error: error)
			}
		}
```

The binary keeps it only as the specialization below, a copy the optimizer rewrote for its callers.

### `function signature specialization <Arg[0] = Dead> of mas.MAS.Reset.run() -> ()` at `0x1000124c4`

swiftdc:

```swift
function signature specialization <Arg[0] = Dead> of mas.MAS.Reset.run() -> () {
    NSRunningApplication
    while (true) {
        mem32[x19 + 0xc] = w8
        let r0 = [? runningApplicationsWithBundleIdentifier:(extension in Foundation):Swift.String._bridgeToObjectiveC()]
        let r1 = static (extension in Foundation):Swift.Array._unconditionallyBridgeFromObjectiveC(r0)
        if ((x20 >>ᵁ 62) != 0) {
            if (Swift._CocoaArrayWrapper.endIndex.getter(((r1 > -1) ? (r1 & 0xffffffffffffff8) : r1))) {
                loc_1000125e4:
                if (x25 < 1) {
                    trap()
                } else {
                    mem64[x19 + 0x30] = x25; mem64[x19 + 0x38] = x20
                    mem64[x19 + 0x20] = x26; mem64[x19 + 0x28] = x28
                    while (true) {
                        if (x28 != 0) {
                            generic specialization <__C.NSRunningApplication> of Swift._ArrayBuffer._getElementSlowPath(…)
                        }
                        if (bit 0 of [? terminate] clear) {
                            if (x8 != -1) {
                                swift_once(0x10060b908, one-time initialization function for printer, ?)
                            }
                            mem64[x19 + 0x48] = x8
                            let r2 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Any>, ?)
                            mem128[x0 + 0x10] = q0
                            mem64[x22 + 0x20] = 0xd000000000000026
                            mem64[x0 + 0x28] = x8
                            mem64[x0 + 0x58] = x27
                            mem64[x0 + 0x38] = x27; mem64[x0 + 0x40] = x26
                            mem64[x0 + 0x48] = x24
                            let r3 = NSFileHandle
                            mem64[x19 + 0x40] = x20
                            [r3 fileHandleWithStandardError]
                            function signature specialization <Arg[6] = Dead> of mas.Printer.(print in _13FF02662930BA0C33C74C7843D664F7)(_:prefix:format:separator:terminator:to:)(r2, "Warning:", "4;33", " ", 10)
                            swift_setDeallocating(?)
                            swift_arrayDestroy(?, ?, (type metadata for Any + 8))
                            if (bit 0 of [? forceTerminate] clear) {
                                let r4 = swift_initStackObject(?, ?)
                                mem128[x0 + 0x10] = q0
                                mem64[x28 + 0x20] = 0xd00000000000002c
                                mem64[x0 + 0x28] = x8
                                mem64[x0 + 0x58] = x20
                                mem64[x0 + 0x38] = x20; mem64[x0 + 0x40] = x26
                                mem64[x0 + 0x48] = x24
                                /* unresolved call @ 0x1000127c8 */ indirect_call(?, recovered_args: [?, …])
                                [? fileHandleWithStandardError]
                                function signature specialization <Arg[6] = Dead> of mas.Printer.(print in _13FF02662930BA0C33C74C7843D664F7)(_:prefix:format:separator:terminator:to:)(r4, "Error:", "4;31", " ", 10)
                                swift_setDeallocating(?)
                                swift_arrayDestroy(?, ?, (type metadata for Any + 8))
                            }
                        }
                        if (x25 == x21) {
                            break
                        } else {
                            continue
                        }
                        break
                    }
                    loc_100012554:
                    if (bit 0 of w10 set) {
                        break
                    } else {
                        continue
                    }
                    break
                }
            } else {
                goto loc_100012554
            }
        } else {
            if (x25 == 0) {
                goto loc_100012554
            } else {
                goto loc_1000125e4
            }
        }
    }
    swift_arrayDestroy(0x10060b590, 2)
    let r5 = swift_initStaticObject(type metadata for Swift._ContiguousArrayStorage<Swift.String>, 0x10060b5b8)
    let r6 = function signature specialization <Arg[0] = Owned To Guaranteed> of generic specialization <Swift.String, Swift.Array<Swift.String>> of Swift.Set.init<A where A == A1.Element, A1: Swift.Sequence>(r5)
    swift_arrayDestroy((r5 + 32), 9)
    let r7 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Swift.Int32>, ?)
    mem128[x0 + 0x10] = (3, 6)
    mem64[x0 + 0x20] = 0xe00000001
    mem32[x23 + 0x28] = 0
    mem64[x19 + 0x98] = 0
    if (!sysctl(?, 3, 0, ?, 0, 0)) {
        if (x8 < -0x287) {
            trap()
        } else {
            if (x8 >= 0x288) {
                static Swift.Array._allocateBufferUninitialized(minimumCapacity:)(?)
                mem64[x0 + 0x10] = x21
                while (true) {
                    bzero(?, 648)
                    if (x21 != 0) {
                        continue
                    } else {
                        break
                    }
                    break
                }
            }
            if (!isKnownUniquelyReferenced(r7)) {
                generic specialization <Swift.Int32> of Swift._ArrayBuffer._consumeAndCreateNew(bufferIsUnique:minimumCapacity:growForAppend:)(…)
            }
            mem64[x19 + 0x90] = x24
            let r9 = sysctl(?, 3, ?, ?, 0, 0)
            if (error == nil) {
                closure #1 (?, 1024, ?, r6)
                let r11 = CKDownloadDirectory(…)
                if (!r11) {
                    (extension in Foundation):Swift.String._bridgeToObjectiveC(static (extension in Foundation):Swift.String._unconditionallyBridgeFromObjectiveC(r11))
                }
                static (extension in Foundation):Swift.String._unconditionallyBridgeFromObjectiveC(r11)
                let r12 = [NSFileManager defaultManager]
                mem64[x19 + 0xa0] = 0
                let r13 = [r12 removeItemAtPath:? error:?]
                if (w25 == 0) {
                    let r14 = Foundation._convertNSErrorToError(?)
                    swift_willThrow(r14)
                    if (x8 != -1) {
                        swift_once(0x10060b908, one-time initialization function for printer, ?)
                    }
                    let r15 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 96, 7)
                    mem128[x0 + 0x10] = q0
                    mem64[x25 + 0x20] = 0xd000000000000020
                    mem64[x0 + 0x28] = "Failed to delete download folder"
                    mem64[x0 + 0x58] = type metadata for Swift.String
                    mem64[x0 + 0x38] = type metadata for Swift.String; mem64[x0 + 0x40] = x27
                    mem64[x0 + 0x48] = x26
                    /* unresolved call @ 0x100012da8 */ indirect_call(?, recovered_args: [r15, …])
                    swift_getErrorValue(r14, ?, ?)
                    /* unresolved call @ 0x100012e04 */ indirect_call(?, recovered_args: […])
                    let r16 = Swift.String.init<A>(describing:)(?)
                    mem64[x19 + 0xa0] = 0; mem64[x19 + 0xa8] = 0xe000000000000000
                    Swift.String.append(?)
                    Swift.String.append(r16)
                    Swift.String.append("\n")
                    [NSFileHandle fileHandleWithStandardError]
                    function signature specialization <Arg[6] = Dead> of mas.Printer.(print in _13FF02662930BA0C33C74C7843D664F7)(_:prefix:format:separator:terminator:to:)(r15, "Error:", "4;31", " ", ?)
                    swift_errorRelease(?)
                    swift_setDeallocating(?)
                    loc_100012f14:
                    swift_arrayDestroy(?, ?, ?)
                    swift_deallocClassInstance(?, 32, 7)
                }
            } else {
                if (x8 != -1) {
                    swift_once(0x10060b908, one-time initialization function for printer, ?)
                }
                let r10 = swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Any>, 64, 7)
                mem128[x0 + 0x10] = (1, 2)
                mem64[x0 + 0x38] = type metadata for Swift.String
                mem64[x26 + 0x20] = 0xd00000000000001a
                mem64[x0 + 0x28] = "Failed to get process list"
                /* unresolved call @ 0x100012bb0 */ indirect_call(?, recovered_args: [r10, …])
                [NSFileHandle fileHandleWithStandardError]
                function signature specialization <Arg[6] = Dead> of mas.Printer.(print in _13FF02662930BA0C33C74C7843D664F7)(_:prefix:format:separator:terminator:to:)(r10, "Error:", "4;31", " ", 10)
                swift_setDeallocating(?)
                goto loc_100012f14
            }
            loc_100012f38:
            if (x9 != x8) {
                __stack_chk_fail()
                // no fall-through
            } else {
                return
            }
        }
    } else {
        if (x8 != -1) {
            swift_once(0x10060b908, one-time initialization function for printer, ?)
        }
        let r8 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Any>, ?)
        mem128[x0 + 0x10] = (1, 2)
        mem64[x0 + 0x38] = type metadata for Swift.String
        mem64[x22 + 0x20] = 0xd000000000000021
        mem64[x0 + 0x28] = "Failed to get process list length"
        /* unresolved call @ 0x1000129d0 */ indirect_call(?, recovered_args: [r8, …])
        [NSFileHandle fileHandleWithStandardError]
        function signature specialization <Arg[6] = Dead> of mas.Printer.(print in _13FF02662930BA0C33C74C7843D664F7)(_:prefix:format:separator:terminator:to:)(r8, "Error:", "4;31", " ", 10)
        swift_setDeallocating(?)
        swift_arrayDestroy(?, ?, ?)
        goto loc_100012f38
    }
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Reset param_1)
/* WARNING: Function: _objc_opt_self replaced with injection: _objc_retain_fixup */
/* WARNING: Function: _objc_retainAutoreleasedReturnValue replaced with injection:
   _objc_retain_fixup */
/* WARNING: Function: _objc_release replaced with injection: _objc_release_fixup */
/* WARNING: Function: _objc_retain replaced with injection: _objc_retain_fixup */
/* WARNING: Heritage AFTER dead removal. Example location: x0 : 0x000100012aa8 */
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* WARNING: Restarted to delay deadcode elimination for space: register */
/* function signature specialization <Arg[0] = Dead> of mas.MAS.Reset.run() -> () */

void __swift_stdcall mas::MAS::Reset::_run(Reset param_1)

{
  _CocoaArrayWrapper _Var1;
  char *pcVar2;
  void *pvVar3;
  undefined *puVar4;
  undefined *puVar5;
  uint uVar6;
  code *pcVar7;
  int iVar8;
  NSString *pNVar9;
  _CocoaArrayWrapper _Var10;
  ID self;
  ID IVar11;
  undefined8 uVar12;
  undefined8 uVar13;
  Set<undefined> SVar14;
  _ArrayBuffer _Var15;
  long *plVar16;
  kinfo_proc kVar17;
  _ArrayBuffer<undefined> _Var18;
  long lVar19;
  undefined8 uVar20;
  _ArrayBuffer _Var21;
  void *pvVar22;
  char *pcVar23;
  undefined8 *puVar24;
  long extraout_x8;
  long lVar25;
  long extraout_x12;
  ID IVar26;
  ID IVar27;
  undefined8 *puVar28;
  ulong uVar29;
  String SVar30;
  String SVar31;
  String SVar32;
  String SVar33;
  String SVar34;
  undefined *local_640;
  uint local_634;
  undefined8 local_630;
  undefined8 local_628;
  undefined8 local_620;
  ulong local_618;
  ID local_610;
  _CocoaArrayWrapper _Stack_608;
  undefined *local_600;
  long *local_5f8;
  undefined8 local_5f0;
  undefined8 uStack_5e8;
  undefined8 local_5d8;
  char *pcStack_5d0;
  undefined1 auStack_5c0 [16];
  _ArrayBuffer<undefined> local_5b0;
  size_t local_5a8;
  undefined8 local_5a0;
  undefined8 uStack_598;
  undefined1 auStack_1a0 [64];
  undefined1 auStack_160 [48];
  undefined1 auStack_130 [96];
  undefined1 auStack_d0 [96];
  long local_70;
  
  puVar4 = PTR___type_metadata_for_Swift_String_1005fc368;
  local_70 = *(long *)PTR____stack_chk_guard_1005fbaa0;
  local_640 = PTR__OBJC_CLASS___NSRunningApplication_10060acb0;
  lVar25 = 0;
  local_630 = 0x800000010059b7c0;
  local_628 = 0x800000010059b790;
  uStack_5e8 = _UNK_1005510f8;
  local_5f0 = _DAT_1005510f0;
  uVar6 = 0;
  do {
    local_634 = uVar6;
    uVar13 = *(undefined8 *)(s_com_apple_dock_10060b590 + lVar25 * 0x10);
    uVar20 = *(undefined8 *)(s_com_apple_dock_10060b590 + lVar25 * 0x10 + 8);
    pNVar9 = (extension_Foundation)::Swift::String::_bridgeToObjectiveC();
    _Var10.unknown =
         (undefined *)objc_stub::runningApplicationsWithBundleIdentifier_((ID)local_640,pNVar9);
    __C::NSRunningApplication::typeMetadataAccessor();
    (extension_Foundation)::Swift::Array<undefined>::__unconditionallyBridgeFromObjectiveC();
    if ((ulong)_Var10.unknown >> 0x3e == 0) {
      IVar27 = *(ID *)(((ulong)_Var10.unknown & 0xffffffffffffff8) + 0x10);
    }
    else {
      _Var1.unknown = (undefined *)((ulong)_Var10.unknown & 0xffffffffffffff8);
      if ((undefined *)0x7fffffffffffffff < _Var10.unknown) {
        _Var1.unknown = _Var10.unknown;
      }
      IVar27 = ::Swift::_CocoaArrayWrapper::get_endIndex(_Var1);
    }
    if (IVar27 != 0) {
      if ((long)IVar27 < 1) {
                    /* WARNING: Does not return */
        pcVar7 = (code *)SoftwareBreakpoint(1,0x100012f74);
        (*pcVar7)();
      }
      IVar26 = 0;
      uVar29 = (ulong)_Var10.unknown & 0xc000000000000001;
      local_620 = uVar13;
      local_618 = uVar29;
      local_610 = IVar27;
      _Stack_608.unknown = _Var10.unknown;
      do {
        if (uVar29 == 0) {
          self = *(ID *)(_Var10.unknown + IVar26 * 8 + 0x20);
        }
        else {
          self = IVar26;
          ::Swift::_ArrayBuffer::__getElementSlowPath(IVar26,(_ArrayBuffer)_Var10.unknown);
        }
        IVar11 = objc_stub::terminate(self);
        if ((IVar11 & 1) == 0) {
          if (__one_time_initialization_token_for_printer != -1) {
            _swift_once(&__one_time_initialization_token_for_printer,one_time_init_for_printer);
          }
          local_5f8 = __s3mas3MASV7printerAA7PrinterVvpZ;
          uVar12 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                             (&
                              __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                              ,&
                               __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                             );
          lVar25 = _swift_initStackObject(uVar12,auStack_d0);
          *(undefined8 *)(lVar25 + 0x18) = uStack_5e8;
          *(undefined8 *)(lVar25 + 0x10) = local_5f0;
          *(undefined8 *)(lVar25 + 0x20) = 0xd000000000000026;
          *(undefined8 *)(lVar25 + 0x28) = local_628;
          *(undefined **)(lVar25 + 0x58) = puVar4;
          *(undefined **)(lVar25 + 0x38) = puVar4;
          *(undefined8 *)(lVar25 + 0x40) = uVar13;
          *(undefined8 *)(lVar25 + 0x48) = uVar20;
          puVar5 = PTR__OBJC_CLASS___NSFileHandle_10060acd0;
          _swift_bridgeObjectRetain(uVar20);
          local_600 = puVar5;
          NSFileHandle::fileHandleWithStandardError((ID)puVar5);
          __function_signature_specialization_<Arg[6]___Dead>_of_mas_Printer__print_in__13FF02662930BA0C33C74C7843D664F7______Any__prefix__Swift_String_format__Swift_String_separator__Swift_String_terminator__Swift_String_to____C_NSFileHandle___>___
                    (lVar25,0x3a676e696e726157,0xe800000000000000,0x33333b34,0xe400000000000000,0x20
                     ,0xe100000000000000,10);
          _swift_setDeallocating(lVar25);
          _swift_arrayDestroy((undefined8 *)(lVar25 + 0x20),*(undefined8 *)(lVar25 + 0x10),
                              PTR___type_metadata_for_Any_1005fda48 + 8);
          IVar27 = objc_stub::forceTerminate(self);
          if ((IVar27 & 1) == 0) {
            lVar19 = _swift_initStackObject(uVar12,auStack_130);
            uVar13 = local_620;
            *(undefined8 *)(lVar19 + 0x18) = uStack_5e8;
            *(undefined8 *)(lVar19 + 0x10) = local_5f0;
            *(undefined8 *)(lVar19 + 0x20) = 0xd00000000000002c;
            *(undefined8 *)(lVar19 + 0x28) = local_630;
            *(undefined **)(lVar19 + 0x58) = puVar4;
            *(undefined **)(lVar19 + 0x38) = puVar4;
            *(undefined8 *)(lVar19 + 0x40) = local_620;
            *(undefined8 *)(lVar19 + 0x48) = uVar20;
            pcVar7 = *(code **)(*local_5f8 + 0x88);
            _swift_bridgeObjectRetain(uVar20);
            plVar16 = (long *)(*pcVar7)();
            lVar25 = *plVar16;
            *plVar16 = lVar25 + 1;
            objc_stub::fileHandleWithStandardError((ID)local_600,lVar25);
            __function_signature_specialization_<Arg[6]___Dead>_of_mas_Printer__print_in__13FF02662930BA0C33C74C7843D664F7______Any__prefix__Swift_String_format__Swift_String_separator__Swift_String_terminator__Swift_String_to____C_NSFileHandle___>___
                      (lVar19,0x3a726f727245,0xe600000000000000,0x31333b34,0xe400000000000000,0x20,
                       0xe100000000000000,10);
            _swift_setDeallocating(lVar19);
            _swift_arrayDestroy((undefined8 *)(lVar19 + 0x20),*(undefined8 *)(lVar19 + 0x10),
                                PTR___type_metadata_for_Any_1005fda48 + 8);
          }
          else {
            uVar13 = local_620;
          }
          _Var10.unknown = _Stack_608.unknown;
          IVar27 = local_610;
          uVar29 = local_618;
        }
        IVar26 = IVar26 + 1;
      } while (IVar27 != IVar26);
    }
    _swift_bridgeObjectRelease(_Var10.unknown);
    puVar5 = PTR___type_metadata_for_Swift_String_1005fc368;
    lVar25 = 1;
    uVar6 = 1;
  } while ((local_634 & 1) == 0);
  _swift_arrayDestroy(s_com_apple_dock_10060b590,2,PTR___type_metadata_for_Swift_String_1005fc368);
  uVar13 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                     );
  lVar25 = _swift_initStaticObject(uVar13,&DAT_10060b5b8);
  SVar14 = ::Swift::Set::_init();
  _swift_arrayDestroy(lVar25 + 0x20,9,puVar5);
  uVar13 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_Int32>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_Int32>
                     );
  _Var15.unknown = (undefined *)_swift_initStackObject(uVar13,auStack_160);
  uVar13 = _DAT_100551100;
  *(undefined8 *)(_Var15.unknown + 0x18) = _UNK_100551108;
  *(undefined8 *)(_Var15.unknown + 0x10) = uVar13;
  *(undefined8 *)(_Var15.unknown + 0x20) = DAT_100551110;
  *(undefined4 *)(_Var15.unknown + 0x28) = 0;
  local_5a8 = 0;
  iVar8 = _sysctl((int *)(_Var15.unknown + 0x20),3,(void *)0x0,&local_5a8,(void *)0x0,0);
  puVar4 = PTR___type_metadata_for_Any_1005fda48;
  if (iVar8 != 0) {
    _swift_bridgeObjectRelease(SVar14.unknown);
    puVar4 = PTR___type_metadata_for_Any_1005fda48;
    if (__one_time_initialization_token_for_printer != -1) {
      _swift_once(&__one_time_initialization_token_for_printer,one_time_init_for_printer);
    }
    plVar16 = __s3mas3MASV7printerAA7PrinterVvpZ;
    uVar13 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                       (&
                        __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                        ,&
                         __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       );
    lVar25 = _swift_initStackObject(uVar13,auStack_1a0);
    uVar13 = _DAT_10054fde0;
    *(undefined8 *)(lVar25 + 0x18) = _UNK_10054fde8;
    *(undefined8 *)(lVar25 + 0x10) = uVar13;
    *(undefined **)(lVar25 + 0x38) = puVar5;
    *(undefined8 *)(lVar25 + 0x20) = 0xd000000000000021;
    *(undefined8 *)(lVar25 + 0x28) = 0x800000010059bb70;
    plVar16 = (long *)(**(code **)(*plVar16 + 0x88))();
    *plVar16 = *plVar16 + 1;
    NSFileHandle::fileHandleWithStandardError((ID)PTR__OBJC_CLASS___NSFileHandle_10060acd0);
    __function_signature_specialization_<Arg[6]___Dead>_of_mas_Printer__print_in__13FF02662930BA0C33C74C7843D664F7______Any__prefix__Swift_String_format__Swift_String_separator__Swift_String_terminator__Swift_String_to____C_NSFileHandle___>___
              (lVar25,0x3a726f727245,0xe600000000000000,0x31333b34,0xe400000000000000,0x20,
               0xe100000000000000,10);
    _swift_setDeallocating(lVar25);
    _swift_arrayDestroy((undefined8 *)(lVar25 + 0x20),*(undefined8 *)(lVar25 + 0x10),puVar4 + 8);
    _swift_release(_Var15.unknown);
    goto LAB_100012f38;
  }
  if ((long)local_5a8 < -0x287) {
                    /* WARNING: Does not return */
    pcVar7 = (code *)SoftwareBreakpoint(1,0x100012f90);
    (*pcVar7)();
  }
  if ((long)local_5a8 < 0x288) {
    _Var18.unknown = PTR___swiftEmptyArrayStorage_1005fda60;
  }
  else {
    lVar19 = (long)local_5a8 / 0x288;
    kVar17 = __C::kinfo_proc::typeMetadataAccessor();
    _Var18 = ::Swift::Array<undefined>::_allocateBufferUninitialized(kVar17.unknown,kVar17.unknown);
    *(long *)(_Var18.unknown + 0x10) = lVar19;
    lVar25 = 0x20;
    do {
      _bzero(_Var18.unknown + lVar25,0x288);
      lVar25 = lVar25 + 0x288;
      lVar19 = lVar19 + -1;
    } while (lVar19 != 0);
  }
  uVar29 = _swift_isUniquelyReferenced_nonNull_native(_Var15.unknown);
  if ((uVar29 & 1) == 0) {
    _Var15.unknown = (undefined *)::Swift::_ArrayBuffer::_consumeAndCreateNew(false,3,false,_Var15);
  }
  local_5b0.unknown = _Var18.unknown;
  _swift_bridgeObjectRetain(_Var15.unknown);
  iVar8 = _sysctl((int *)(_Var15.unknown + 0x20),3,_Var18.unknown + 0x20,&local_5a8,(void *)0x0,0);
  _swift_bridgeObjectRelease(_Var15.unknown);
  if (iVar8 == 0) {
    __closure__1__Swift_UnsafeMutableBufferPointer<Swift_Int8>___>____in_mas_MAS_Reset_run____>___
              (&local_5a0,0x400,&local_5b0,SVar14.unknown);
    _swift_bridgeObjectRelease(SVar14.unknown);
    pNVar9 = (NSString *)_CKDownloadDirectory(0);
    if (pNVar9 == (NSString *)0x0) {
      SVar30 = (extension_Foundation)::Swift::String::__unconditionallyBridgeFromObjectiveC();
      pNVar9 = (extension_Foundation)::Swift::String::_bridgeToObjectiveC();
      _swift_bridgeObjectRelease(SVar30.bridgeObject);
    }
    SVar30 = (extension_Foundation)::Swift::String::__unconditionallyBridgeFromObjectiveC();
    _Var21.unknown = SVar30.bridgeObject;
    IVar27 = NSFileManager::defaultManager((ID)PTR__OBJC_CLASS___NSFileManager_10060acd8);
    local_5a0 = 0;
    puVar24 = &local_5a0;
    IVar27 = NSFileManager::removeItemAtPath_error_(IVar27,pNVar9);
    if ((int)IVar27 == 0) {
      uVar13 = local_5a0;
      Foundation::__convertNSErrorToError();
      _swift_willThrow(0);
      if (__one_time_initialization_token_for_printer != -1) {
        _swift_once(&__one_time_initialization_token_for_printer,one_time_init_for_printer);
      }
      plVar16 = __s3mas3MASV7printerAA7PrinterVvpZ;
      uVar20 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                         (&
                          __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                          ,&
                           __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                         );
      lVar19 = _swift_allocObject(uVar20,0x60,7);
      *(undefined8 *)(lVar19 + 0x18) = uStack_5e8;
      *(undefined8 *)(lVar19 + 0x10) = local_5f0;
      puVar28 = (undefined8 *)(lVar19 + 0x20);
      *puVar28 = 0xd000000000000020;
      *(undefined8 *)(lVar19 + 0x28) = 0x800000010059bbc0;
      *(undefined **)(lVar19 + 0x58) = puVar5;
      *(undefined **)(lVar19 + 0x38) = puVar5;
      *(String *)(lVar19 + 0x40) = SVar30;
      plVar16 = (long *)(**(code **)(*plVar16 + 0x88))();
      lVar25 = *plVar16;
      *plVar16 = lVar25 + 1;
      uVar20 = _swift_getErrorValue(lVar25,uVar13,auStack_5c0,&local_5d8);
      (*(code *)PTR____chkstk_darwin_1005fba80)
                (*(undefined8 *)(*(long *)(pcStack_5d0 + -8) + 0x40),uVar20,local_5d8);
      pcVar23 = pcStack_5d0;
      (**(code **)(extraout_x12 + 0x10))
                (auStack_5c0 + (-0x80 - (extraout_x8 + 0xfU & 0xfffffffffffffff0)));
      SVar30 = ::Swift::String::_init
                         (auStack_5c0 + (-0x80 - (extraout_x8 + 0xfU & 0xfffffffffffffff0)),
                          pcStack_5d0);
      pvVar22 = SVar30.bridgeObject;
      local_5a0 = 0;
      uStack_598 = 0xe000000000000000;
      uVar29 = (ulong)SVar30.str & 0xffffffffffff;
      if (((ulong)pvVar22 & 0x2000000000000000) != 0) {
        uVar29 = (ulong)pvVar22 >> 0x38 & 0xf;
      }
      pcVar2 = (char *)0x0;
      if (uVar29 != 0) {
        pcVar2 = (char *)0xa;
      }
      pvVar3 = (void *)0xe000000000000000;
      if (uVar29 != 0) {
        pvVar3 = (void *)0xe100000000000000;
      }
      SVar31.bridgeObject = pvVar3;
      SVar31.str = pcVar2;
      SVar32.bridgeObject = puVar24;
      SVar32.str = pcVar23;
      ::Swift::String::append(SVar31,SVar32);
      _swift_bridgeObjectRelease(pvVar3);
      SVar33.bridgeObject = puVar24;
      SVar33.str = pcVar23;
      ::Swift::String::append(SVar30,SVar33);
      _swift_bridgeObjectRelease(pvVar22);
      SVar30.bridgeObject = (void *)0xe100000000000000;
      SVar30.str = (char *)0xa;
      SVar34.bridgeObject = puVar24;
      SVar34.str = pcVar23;
      ::Swift::String::append(SVar30,SVar34);
      uVar12 = uStack_598;
      uVar20 = local_5a0;
      NSFileHandle::fileHandleWithStandardError((ID)PTR__OBJC_CLASS___NSFileHandle_10060acd0);
      __function_signature_specialization_<Arg[6]___Dead>_of_mas_Printer__print_in__13FF02662930BA0C33C74C7843D664F7______Any__prefix__Swift_String_format__Swift_String_separator__Swift_String_terminator__Swift_String_to____C_NSFileHandle___>___
                (lVar19,0x3a726f727245,0xe600000000000000,0x31333b34,0xe400000000000000,0x20,
                 0xe100000000000000,uVar20);
      _swift_bridgeObjectRelease(uVar12);
      _swift_errorRelease(uVar13);
      _swift_setDeallocating(lVar19);
      uVar13 = *(undefined8 *)(lVar19 + 0x10);
      puVar4 = PTR___type_metadata_for_Any_1005fda48;
      goto LAB_100012f14;
    }
    _swift_bridgeObjectRelease(_Var18.unknown);
    _swift_bridgeObjectRelease(_Var15.unknown);
  }
  else {
    _swift_bridgeObjectRelease(SVar14.unknown);
    if (__one_time_initialization_token_for_printer != -1) {
      _swift_once(&__one_time_initialization_token_for_printer,one_time_init_for_printer);
    }
    plVar16 = __s3mas3MASV7printerAA7PrinterVvpZ;
    uVar13 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                       (&
                        __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                        ,&
                         __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       );
    lVar19 = _swift_allocObject(uVar13,0x40,7);
    uVar13 = _DAT_10054fde0;
    *(undefined8 *)(lVar19 + 0x18) = _UNK_10054fde8;
    *(undefined8 *)(lVar19 + 0x10) = uVar13;
    *(undefined **)(lVar19 + 0x38) = puVar5;
    puVar28 = (undefined8 *)(lVar19 + 0x20);
    *puVar28 = 0xd00000000000001a;
    *(undefined8 *)(lVar19 + 0x28) = 0x800000010059bba0;
    plVar16 = (long *)(**(code **)(*plVar16 + 0x88))();
    *plVar16 = *plVar16 + 1;
    NSFileHandle::fileHandleWithStandardError((ID)PTR__OBJC_CLASS___NSFileHandle_10060acd0);
    __function_signature_specialization_<Arg[6]___Dead>_of_mas_Printer__print_in__13FF02662930BA0C33C74C7843D664F7______Any__prefix__Swift_String_format__Swift_String_separator__Swift_String_terminator__Swift_String_to____C_NSFileHandle___>___
              (lVar19,0x3a726f727245,0xe600000000000000,0x31333b34,0xe400000000000000,0x20,
               0xe100000000000000,10);
    _swift_setDeallocating(lVar19);
    uVar13 = *(undefined8 *)(lVar19 + 0x10);
LAB_100012f14:
    _swift_arrayDestroy(puVar28,uVar13,puVar4 + 8);
    _swift_deallocClassInstance(lVar19,0x20,7);
    _swift_bridgeObjectRelease(_Var18.unknown);
    _Var21.unknown = _Var15.unknown;
  }
  _swift_bridgeObjectRelease(_Var21.unknown);
LAB_100012f38:
  if (*(long *)PTR____stack_chk_guard_1005fbaa0 != local_70) {
                    /* WARNING: Subroutine does not return */
    ___stack_chk_fail();
  }
  return;
}
```

## `MAS.Search.run`

From `Sources/mas/Commands/MAS.Search.swift`.

```swift
		func run() async throws {
			try run(
				catalogApps: try await Environment.current.searchForAppsMatchingSearchTerm(searchTermOptionGroup.searchTerm),
			)
		}
```

### `mas.MAS.Search.run() async throws -> ()` at `0x100013574`

swiftdc:

```swift
mas.MAS.Search.run() async throws -> () {
    // async function: 1 resume funclet(s): resume #1 @0x100013780
    if (x8 != -1) {
        swift_once(0x10060c2f0, one-time initialization function for $current, ?)
    }
    let r0 = swift_task_localValueGet(?)
    if (!r0) {
        Swift.TaskLocal.get(self: ?)
    } else {
        outlined init with copy of mas.Environment(r0, ?)
    }
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Argument.wrappedValue.getter()
    (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(" ", type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x10060b0a0, 0x10060b098, 0x10054ff80, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
    await indirect_call(?)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Search param_1)
/* mas.MAS.Search.run() async throws -> () */

void __swift_stdcall mas::MAS::Search::_run(Search param_1)

{
  int iVar1;
  int *piVar2;
  undefined1 auVar3 [16];
  void *this;
  Environment EVar4;
  long lVar5;
  long lVar6;
  Argument AVar7;
  long *plVar8;
  ulong in_x1;
  void *in_x2;
  long unaff_x20;
  long unaff_x22;
  undefined8 uVar9;
  undefined8 uVar10;
  undefined8 uVar11;
  OptionGroup OVar12;
  String SVar13;
  
  *(long *)(unaff_x22 + 0x78) = unaff_x20;
  EVar4 = Environment::typeMetadataAccessor();
  lVar5 = _swift_task_alloc(*(long *)(*(long *)(EVar4.unknown + -8) + 0x40) + 0xfU &
                            0xfffffffffffffff0);
  *(long *)(unaff_x22 + 0x80) = lVar5;
  if (__one_time_initialization_token_for__current != -1) {
    _swift_once(&__one_time_initialization_token_for__current,
                Environment::one_time_init_for__current);
  }
  this = __s3mas11EnvironmentV8_currents9TaskLocalCyACGvpZ;
  lVar6 = _swift_task_localValueGet(__s3mas11EnvironmentV8_currents9TaskLocalCyACGvpZ);
  if (lVar6 == 0) {
    ::Swift::TaskLocal::get(this);
  }
  else {
    __outlined_init_with_copy_of_mas_Environment(lVar6,lVar5);
  }
  piVar2 = *(int **)(lVar5 + *(int *)(EVar4.unknown + 0x20));
  *(undefined8 *)(unaff_x22 + 0x88) = ((undefined8 *)(lVar5 + *(int *)(EVar4.unknown + 0x20)))[1];
  _swift_retain();
  __outlined_destroy_of_mas_Environment(lVar5);
  uVar9 = *(undefined8 *)(unaff_x20 + 0x40);
  uVar11 = *(undefined8 *)(unaff_x20 + 0x58);
  uVar10 = *(undefined8 *)(unaff_x20 + 0x50);
  *(undefined8 *)(unaff_x22 + 0x18) = *(undefined8 *)(unaff_x20 + 0x48);
  *(undefined8 *)(unaff_x22 + 0x10) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar11;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar10;
  *(undefined8 *)(unaff_x22 + 0x30) = *(undefined8 *)(unaff_x20 + 0x60);
  auVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_SearchTermOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_SearchTermOptionGroup>
                     );
  OVar12.title.bridgeObject = in_x2;
  OVar12._dummy = (bool)auVar3[0];
  OVar12._1_7_ = auVar3._1_7_;
  OVar12.title.str = (char *)auVar3._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar12);
  *(undefined8 *)(unaff_x22 + 0x50) = *(undefined8 *)(unaff_x22 + 0x38);
  *(undefined8 *)(unaff_x22 + 0x58) = *(undefined8 *)(unaff_x22 + 0x40);
  *(undefined1 *)(unaff_x22 + 0x60) = *(undefined1 *)(unaff_x22 + 0x48);
  AVar7.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                 );
  ArgumentParser::Argument::get_wrappedValue(AVar7);
  uVar9 = *(undefined8 *)(unaff_x22 + 0x68);
  *(undefined8 *)(unaff_x22 + 0x70) = uVar9;
  ::___swift_instantiateConcreteTypeFromMangledNameV2
            (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
             &__mangled_name_ref_for_type_metadata_for__Swift_String_);
  ::Swift::Array<String>::_lazy_protocol_witness_table_accessor();
  SVar13.bridgeObject = (void *)0xe100000000000000;
  SVar13.str = (char *)0x20;
  SVar13 = (extension_Swift)::Swift::BidirectionalCollection::_joined(SVar13);
  *(void **)(unaff_x22 + 0x90) = SVar13.bridgeObject;
  ::_outlined_consume();
  _swift_bridgeObjectRelease(uVar9);
  iVar1 = *piVar2;
  plVar8 = (long *)_swift_task_alloc(piVar2[1]);
  *(long **)(unaff_x22 + 0x98) = plVar8;
  *plVar8 = unaff_x22;
  plVar8[1] = (long)_run;
                    /* WARNING: Could not recover jumptable at 0x000100013764. Too many branches */
                    /* WARNING: Treating indirect jump as call */
  (*(code *)((long)iVar1 + (long)piVar2))
            (param_1.unknown,in_x1 & 0xcfffffffffffffff,SVar13.str,SVar13.bridgeObject);
  return;
}
```

## `MAS.Search.run`

From `Sources/mas/Commands/MAS.Search.swift`.

```swift
		func run(catalogApps: [CatalogApp]) throws {
			guard !catalogApps.isEmpty else {
				throw MASError.noCatalogAppsFound(for: searchTermOptionGroup.searchTerm)
			}

			outputFormatOptionGroup.info(catalogApps.map(String.init).joined(separator: "\n"))
		}
```

### `mas.MAS.Search.run(catalogApps: [mas.CatalogApp]) throws -> ()` at `0x10001380c`

swiftdc:

```swift
mas.MAS.Search.run(catalogApps: Swift.Array<mas.CatalogApp>) throws -> () {
    if (x22 == 0) {
        ArgumentParser.OptionGroup.wrappedValue.getter()
        ArgumentParser.Argument.wrappedValue.getter()
        (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(self: local_90, " ", type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x10060b0a0, 0x10060b098, 0x10054ff80, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
        let r1 = swift_allocError(0x1005e4420, lazy protocol witness table accessor for type mas.MASError and conformance mas.MASError : Swift.Error in mas(), 0, false)
        mem64[x1] = x20; mem64[x1 + 0x8] = x25
        mem8[x1 + 0x38] = 3
        swift_willThrow(r1)
        throw ?
    } else {
        ArgumentParser.OptionGroup.wrappedValue.getter()
        let r0 = swift_initStackObject(type metadata for Swift._ContiguousArrayStorage<Any>, local_e8)
        mem128[x0 + 0x10] = (1, 2)
        generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_a8, …)
        while (true) {
            os_unfair_lock_lock(?)
            if (w27 != 1) {
                /* unresolved call @ 0x100013970 */ indirect_call(?, recovered_args: […])
                mem64[x19 + 0x10] = x27; mem64[x19 + 0x18] = x24
                mem8[x19 + 0x20] = 1
            }
            os_unfair_lock_unlock(?)
            if (x22 >=ᵁ (x8 >>ᵁ 1)) {
                generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_a8, …)
            }
            mem64[x25 + 0x10] = x19
            mem64[x8 + 0x20] = x27; mem64[x8 + 0x28] = x24
            if (x20 != 0) {
                continue
            } else {
                break
            }
            break
        }
        (extension in Swift):Swift.BidirectionalCollection< where A.Element == Swift.String>.joined(separator:)(self: local_90, 10, 0xe100000000000000, type metadata for Swift.Array<Swift.String>, merged lazy protocol witness table accessor for …(0x10060b0a0, 0x10060b098, 0x10054ff80, protocol conformance descriptor for Swift.Array<A> : Swift.BidirectionalCollection in Swift))
        mem64[x23 + 0x38] = type metadata for Swift.String
        mem64[x23 + 0x20] = x19; mem64[x23 + 0x28] = x20
        mas.OutputFormatOptionGroup.info(_:separator:terminator:)(self: ?, r0, " ", "\n")
    }
    machine_return() /* unresolved Swift success/error exit */
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Array<CatalogApp> catalogApps, Search param_2)
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* mas.MAS.Search.run(catalogApps: [mas.CatalogApp]) throws -> () */

void __swift_stdcall
mas::MAS::Search::_run(long param_1,undefined8 param_2,void *param_3,ContiguousArray param_4)

{
  ulong uVar1;
  long lVar2;
  undefined1 auVar3 [16];
  code *pcVar4;
  undefined8 uVar5;
  undefined8 uVar6;
  Argument AVar7;
  String *extraout_x1;
  long lVar8;
  undefined8 *unaff_x20;
  undefined8 uVar9;
  long minimumCapacity;
  undefined8 uVar10;
  undefined8 uVar11;
  undefined8 *puVar12;
  code *pcVar13;
  undefined8 uVar14;
  OptionGroup OVar15;
  OptionGroup OVar16;
  String SVar17;
  String separator;
  String SVar18;
  String separator_00;
  undefined1 auStack_e8 [64];
  code *local_a8;
  undefined8 uStack_a0;
  undefined1 local_98;
  code *local_90;
  undefined8 uStack_88;
  undefined8 local_80;
  undefined8 uStack_78;
  undefined8 local_70;
  
  minimumCapacity = *(long *)(param_1 + 0x10);
  if (minimumCapacity == 0) {
    uStack_88 = unaff_x20[9];
    local_90 = (code *)unaff_x20[8];
    uStack_78 = unaff_x20[0xb];
    local_80 = unaff_x20[10];
    local_70 = unaff_x20[0xc];
    auVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                       (&
                        __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_SearchTermOptionGroup>
                        ,&
                         __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_SearchTermOptionGroup>
                       );
    OVar16.title.bridgeObject = param_3;
    OVar16._dummy = (bool)auVar3[0];
    OVar16._1_7_ = auVar3._1_7_;
    OVar16.title.str = (char *)auVar3._8_8_;
    ArgumentParser::OptionGroup::get_wrappedValue(OVar16);
    local_90 = local_a8;
    uStack_88 = uStack_a0;
    local_80 = CONCAT71(local_80._1_7_,local_98);
    AVar7.unknown =
         (undefined *)
         ::___swift_instantiateConcreteTypeFromMangledNameV2
                   (&
                    __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                    ,&
                     __mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                   );
    ArgumentParser::Argument::get_wrappedValue(AVar7);
    local_90 = local_a8;
    ::___swift_instantiateConcreteTypeFromMangledNameV2
              (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
               &__mangled_name_ref_for_type_metadata_for__Swift_String_);
    ::Swift::Array<String>::_lazy_protocol_witness_table_accessor();
    SVar17.bridgeObject = (void *)0xe100000000000000;
    SVar17.str = (char *)0x20;
    SVar17 = (extension_Swift)::Swift::BidirectionalCollection::_joined(SVar17);
    ::_outlined_consume();
    uVar5 = _swift_bridgeObjectRelease(local_a8);
    MASError::_lazy_protocol_witness_table_accessor();
    _swift_allocError(&__type_metadata_for_mas_MASError,uVar5,0,0);
    *extraout_x1 = SVar17;
    *(undefined1 *)&extraout_x1[3].bridgeObject = 3;
    _swift_willThrow();
  }
  else {
    uStack_88 = unaff_x20[1];
    local_90 = (code *)*unaff_x20;
    uStack_78 = unaff_x20[3];
    local_80 = unaff_x20[2];
    local_70 = unaff_x20[4];
    auVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                       (&
                        __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                        ,&
                         __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutputFormatOptionGroup>
                       );
    OVar15.title.bridgeObject = param_3;
    OVar15._dummy = (bool)auVar3[0];
    OVar15._1_7_ = auVar3._1_7_;
    OVar15.title.str = (char *)auVar3._8_8_;
    ArgumentParser::OptionGroup::get_wrappedValue(OVar15);
    uVar5 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                      (&
                       __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                       ,&__mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Any>
                      );
    SVar18.str = (char *)_swift_initStackObject(uVar5,auStack_e8);
    uVar5 = _DAT_10054fde0;
    *(undefined8 *)(SVar18.str + 0x18) = _UNK_10054fde8;
    *(undefined8 *)(SVar18.str + 0x10) = uVar5;
    local_a8 = (code *)PTR___swiftEmptyArrayStorage_1005fda60;
    ::Swift::ContiguousArray::_createNewBuffer(false,minimumCapacity,false,param_4);
    puVar12 = (undefined8 *)(param_1 + 0x40);
    do {
      pcVar4 = local_a8;
      uVar14 = puVar12[-2];
      uVar10 = *puVar12;
      uVar9 = puVar12[2];
      uVar6 = puVar12[4];
      uVar5 = puVar12[6];
      lVar2 = puVar12[7];
      lVar8 = *(long *)(lVar2 + 0x10);
      _swift_bridgeObjectRetain();
      _swift_bridgeObjectRetain(uVar5);
      _swift_retain(lVar2);
      _swift_bridgeObjectRetain(uVar14);
      _swift_bridgeObjectRetain(uVar10);
      _swift_bridgeObjectRetain(uVar9);
      _os_unfair_lock_lock(lVar8 + 0x24);
      pcVar13 = *(code **)(lVar8 + 0x10);
      uVar11 = *(undefined8 *)(lVar8 + 0x18);
      if (*(char *)(lVar8 + 0x20) == '\x01') {
        ::_outlined_copy((State)(__int8)pcVar13);
      }
      else {
        (*pcVar13)(&local_90);
        ::_outlined_consume((State)(__int8)pcVar13);
        uVar11 = uStack_88;
        pcVar13 = local_90;
        *(code **)(lVar8 + 0x10) = local_90;
        *(undefined8 *)(lVar8 + 0x18) = uStack_88;
        *(undefined1 *)(lVar8 + 0x20) = 1;
        _swift_bridgeObjectRetain(uStack_88);
      }
      _os_unfair_lock_unlock(lVar8 + 0x24);
      _swift_release(lVar2);
      _swift_bridgeObjectRelease(uVar5);
      _swift_bridgeObjectRelease(uVar6);
      _swift_bridgeObjectRelease(uVar9);
      _swift_bridgeObjectRelease(uVar10);
      _swift_bridgeObjectRelease(uVar14);
      uVar1 = *(ulong *)(pcVar4 + 0x10);
      local_a8 = pcVar4;
      if (*(ulong *)(pcVar4 + 0x18) >> 1 <= uVar1) {
        ::Swift::ContiguousArray::_createNewBuffer
                  (1 < *(ulong *)(pcVar4 + 0x18),uVar1 + 1,true,param_4);
      }
      pcVar4 = local_a8;
      puVar12 = puVar12 + 0xc;
      *(ulong *)(local_a8 + 0x10) = uVar1 + 1;
      *(code **)(local_a8 + uVar1 * 0x10 + 0x20) = pcVar13;
      *(undefined8 *)(local_a8 + uVar1 * 0x10 + 0x28) = uVar11;
      minimumCapacity = minimumCapacity + -1;
    } while (minimumCapacity != 0);
    local_90 = local_a8;
    ::___swift_instantiateConcreteTypeFromMangledNameV2
              (&__demangling_cache_variable_for_type_metadata_for__Swift_String_,
               &__mangled_name_ref_for_type_metadata_for__Swift_String_);
    ::Swift::Array<String>::_lazy_protocol_witness_table_accessor();
    separator.bridgeObject = (void *)0xe100000000000000;
    separator.str = (char *)0xa;
    SVar17 = (extension_Swift)::Swift::BidirectionalCollection::_joined(separator);
    _swift_release(pcVar4);
    *(undefined **)(SVar18.str + 0x38) = PTR___type_metadata_for_Swift_String_1005fc368;
    *(String *)(SVar18.str + 0x20) = SVar17;
    SVar18.bridgeObject = (void *)0x20;
    separator_00.bridgeObject = (void *)0xa;
    separator_00.str = (char *)0xe100000000000000;
    OutputFormatOptionGroup::_info(SVar18,separator_00,(OutputFormatOptionGroup)0xe100000000000000);
    ::_outlined_consume();
    _swift_release(SVar18.str);
  }
  return;
}
```

## `MAS.Seller.run`

From `Sources/mas/Commands/MAS.Seller.swift`.

```swift
		func run() async {
			await run(catalogApps: await catalogAppsOptionGroup.appIDs.catalogApps)
		}
```

The optimizer inlined it into every caller, so the binary has no body of its own to decompile.

## `MAS.Seller.run`

From `Sources/mas/Commands/MAS.Seller.swift`.

```swift
		func run(catalogApps: [CatalogApp]) async {
			await catalogApps.forEach(attemptTo: "open") { catalogApp in
				guard let sellerURLString = catalogApp.sellerURLString else {
					printer.error("Failed to find seller app web page for ADAM ID", catalogApp.adamID)
					return
				}
				guard let url = URL(string: sellerURLString) else {
					throw MASError.invalidURL(sellerURLString)
				}

				_ = try await url.open()
			}
		}
```

The binary keeps it only as the specialization below, a copy the optimizer rewrote for its callers.

### `function signature specialization <Arg[2] = Dead> of mas.MAS.Seller.run(catalogApps: [mas.CatalogApp]) async -> ()` at `0x100015564`

swiftdc:

```swift
function signature specialization <Arg[2] = Dead> of mas.MAS.Seller.run(catalogApps: Swift.Array<mas.CatalogApp>) async -> () {
    // async function: 1 resume funclet(s): resume #1 @0x100016a70
    if (x25 == 0) {
        loc_100015d98:
        /* unresolved indirect branch @ 0x100015ddc */ indirect_jump(?)
    } else {
        while (true) {
            if (x20 != 0) {
                goto loc_100015c7c
            } else {
                outlined init with copy of mas.CatalogApp(?, ?)
                if (x8 != -1) {
                    swift_once(0x10060b908, one-time initialization function for printer, ?)
                }
                /* unresolved call @ 0x10001576c */ indirect_call(?, recovered_args: […])
                let r0 = [NSFileHandle fileHandleWithStandardError]
                storeEnumTagSinglePayload value witness for Foundation.Locale(?, 1, 1)
                (extension in Foundation):Swift.StringProtocol.range<A where A1: Swift.StringProtocol>(of:options:range:locale:)(self: (? + 592), ?, 4, 0, 0, 1, ?)
                merged outlined destroy of …(?, 0x10060b738, 0x100553200)
                if (w23 == 1) {
                    loc_100015874:
                    let r1 = Swift.String.count.getter(?, ?)
                    Swift.String.append(self: (? + 576), Swift.String.init(repeating:count:)(" ", (r1 + 1)))
                    if (isatty([r0 fileDescriptor])) {
                        Swift.String.append(self: (? + 688), "4;31")
                        Swift.String.append(self: (? + 688), "m")
                        Swift.String.append(self: (? + 688), "Error:")
                        Swift.String.append(self: (? + 688), "\u{1b}[")
                        Swift.String.append(self: (? + 688), "0m")
                    }
                    swift_allocObject(type metadata for Swift._ContiguousArrayStorage<Swift.String>, 48, 7)
                    mem128[x0 + 0x10] = (1, 2)
                    Swift.String.append(self: (? + 624), " ")
                    Swift.String.append(self: (? + 624), mas.(indent in _13FF02662930BA0C33C74C7843D664F7)(_:with:)(?, ?))
                    mem64[x27 + 0x20] = x8; mem64[x27 + 0x28] = x9
                    generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(…)
                    /* unresolved call @ 0x100015a2c */ indirect_call(?, recovered_args: [?, __swift_project_boxed_opaque_existential_0Tm(?, ?), …])
                    Swift.String.init<A>(describing:)(?)
                    if (x8 != -1) {
                        swift_once(0x10060c250, one-time initialization function for (nonEmptyLineStartRegex in _13FF02662930BA0C33C74C7843D664F7), ?)
                    }
                    /* unresolved call @ 0x100015a90 */ indirect_call(?, recovered_args: [?, __swift_project_value_buffer(?, 0x10060c258), …])
                    merged lazy protocol witness table accessor for …(0x10060b758, 0x10060b730, 0x1005513e8, protocol conformance descriptor for _StringProcessing.Regex<A> : _StringProcessing.RegexComponent in _StringProcessing)
                    (extension in _StringProcessing):Swift.RangeReplaceableCollection< where A.SubSequence == Swift.Substring>.replacing<A, B where A1: Swift.Collection, B1: _StringProcessing.RegexComponent, A1.Element == Swift.Character>(_:with:maxReplacements:)(self: (? + 672), ?, ?, 0x7fffffffffffffff, type metadata for Swift.String, type metadata for Swift.String, ?)
                    /* unresolved call @ 0x100015b08 */ indirect_call(?, recovered_args: […])
                    if (x28 >=ᵁ (x8 >>ᵁ 1)) {
                        generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(…)
                    }
                    mem64[x19 + 0x10] = x21
                    mem64[x8 + 0x20] = x24; mem64[x8 + 0x28] = x25
                    generic specialization <Swift.String, Swift.Array<Swift.String>> of Swift.Array.append<A where A == A1.Element, A1: Swift.Sequence>(contentsOf:)(self: local_68, …)
                    let r2 = mas.(indent in _13FF02662930BA0C33C74C7843D664F7)(_:with:)(?, ?)
                    function signature specialization <Arg[4] = Dead> of mas.Printer.(print in _13FF02662930BA0C33C74C7843D664F7)(_:separator:terminator:to:)(?, r2, ?, 10, 0xe100000000000000, r0)
                    swift_arrayDestroy(?, 2, (type metadata for Any + 8))
                    if (x28 == x23) {
                        goto loc_100015d84
                    } else {
                        if (x25 != 0) {
                            continue
                        } else {
                            goto loc_100015c28
                        }
                        goto loc_100015c28
                    }
                } else {
                    if ((x20 >>ᵁ 14) >ᵁ 0x18) {
                        trap()
                    } else {
                        Swift.String.subscript.getter(?)
                        static Swift.String._fromSubstring(?)
                        goto loc_100015874
                    }
                }
            }
        }
    }
    loc_100015c28:
    trap()
    loc_100015c7c:
    outlined init with copy of mas.CatalogApp(?, ?)
    outlined init with copy of Swift.Optional<Swift.String>(?, ?)
    Foundation.URL.init(string:)(?)
    /* unresolved call @ 0x100015cc4 */ indirect_call(?, recovered_args: [?, 1, …])
    if (w0 != 1) {
        merged outlined destroy of …(?, 0x10060b760, 0x1005513f0)
        /* unresolved call @ 0x100015e38 */ indirect_call(?, recovered_args: […])
        let r4 = [[NSWorkspaceOpenConfiguration allocWithZone:nil] init]
        let r5 = [NSWorkspace sharedWorkspace]
        let r6 = Foundation.URL._bridgeToObjectiveC()
        swift_continuation_init(?, 1)
        Swift.CheckedContinuation.init(continuation:function:)(?, ?)
        /* unresolved call @ 0x100015f0c */ indirect_call(?, recovered_args: [__swift_allocate_boxed_opaque_existential_0(?), …])
        [r5 openURL:r6 configuration:r4 completionHandler:?]
        /* unresolved call @ 0x100015f5c */ indirect_call(?, recovered_args: [__swift_allocate_boxed_opaque_existential_0(?), …])
        swift_continuation_await()
        // no fall-through
    } else {
        merged outlined destroy of …(?, 0x10060b2a0, 0x100550530)
        let r3 = swift_allocError(0x1005e4420, lazy protocol witness table accessor for type mas.MASError and conformance mas.MASError : Swift.Error in mas(), 0, false)
        mem64[x1] = x19; mem64[x1 + 0x8] = x20
        mem8[x1 + 0x38] = 2
        swift_willThrow(r3)
        await generic specialization <Swift.Array<mas.CatalogApp>, Swift.Error> of closure #1 nonisolated(nonsending) (…)
        // no fall-through
    }
    loc_100015d84:
    goto loc_100015d98
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Array<CatalogApp> catalogApps, Seller param_2)
/* WARNING: Function: _objc_opt_self replaced with injection: _objc_retain_fixup */
/* WARNING: Function: _objc_retainAutoreleasedReturnValue replaced with injection:
   _objc_retain_fixup */
/* WARNING: Function: _objc_release replaced with injection: _objc_release_fixup */
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* function signature specialization <Arg[2] = Dead> of mas.MAS.Seller.run(catalogApps:
   [mas.CatalogApp]) async -> () */

void __swift_stdcall mas::MAS::Seller::_run(undefined8 param_1,undefined8 param_2,long param_3)

{
  code *pcVar1;
  int iVar2;
  long lVar3;
  undefined8 uVar4;
  undefined8 uVar5;
  undefined8 uVar6;
  undefined8 uVar7;
  URL UVar8;
  undefined8 uVar9;
  long *plVar10;
  ID IVar11;
  Locale LVar12;
  __int64 _Var13;
  ID IVar14;
  undefined8 uVar15;
  undefined8 *puVar16;
  NSURL *pNVar17;
  UnsafeContinuation<undefined,undefined> continuation;
  Range<Index> RVar18;
  void *pvVar19;
  uint uVar20;
  char *pcVar21;
  ContiguousArray CVar22;
  ContiguousArray CVar23;
  long lVar24;
  long lVar25;
  long lVar26;
  ulong uVar27;
  char *pcVar28;
  long unaff_x22;
  undefined *puVar29;
  undefined8 uVar30;
  long lVar31;
  long lVar32;
  long lVar33;
  undefined8 uVar34;
  undefined8 uVar35;
  undefined8 uVar36;
  String SVar38;
  String SVar37;
  String SVar39;
  String repeating;
  String SVar40;
  String SVar41;
  String SVar42;
  String SVar43;
  String SVar44;
  String SVar45;
  undefined1 auVar46 [16];
  String SVar47;
  String SVar48;
  String SVar49;
  String SVar50;
  String SVar51;
  String SVar52;
  String SVar53;
  String SVar54;
  String SVar55;
  
  *(long *)(unaff_x22 + 0x2f0) = param_3;
  *(undefined8 *)(unaff_x22 + 0x2e8) = param_2;
  *(undefined8 *)(unaff_x22 + 0x2e0) = param_1;
  lVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for_Swift_CheckedContinuation<__C_NSRunningApplication,Swift_Error>
                     ,&
                      __mangled_name_ref_for_type_metadata_for_Swift_CheckedContinuation<__C_NSRunningApplication,Swift_Error>
                    );
  *(long *)(unaff_x22 + 0x2f8) = lVar3;
  lVar3 = *(long *)(lVar3 + -8);
  *(long *)(unaff_x22 + 0x300) = lVar3;
  uVar4 = _swift_task_alloc(*(long *)(lVar3 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x308) = uVar4;
  lVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&
                     __demangling_cache_variable_for_type_metadata_for__StringProcessing_Regex<Swift_Substring>
                     ,&
                      __mangled_name_ref_for_type_metadata_for__StringProcessing_Regex<Swift_Substring>
                    );
  *(long *)(unaff_x22 + 0x310) = lVar3;
  lVar3 = *(long *)(lVar3 + -8);
  *(long *)(unaff_x22 + 0x318) = lVar3;
  uVar5 = _swift_task_alloc(*(long *)(lVar3 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 800) = uVar5;
  lVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__demangling_cache_variable_for_type_metadata_for_Foundation_Locale_,
                     &__mangled_name_ref_for_type_metadata_for_Foundation_Locale_);
  uVar6 = _swift_task_alloc(*(long *)(*(long *)(lVar3 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x328) = uVar6;
  lVar3 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                    (&__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                     &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
  uVar7 = _swift_task_alloc(*(long *)(*(long *)(lVar3 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x330) = uVar7;
  UVar8 = Foundation::URL::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x338) = UVar8.unknown;
  lVar3 = *(long *)(UVar8.unknown + -8);
  *(long *)(unaff_x22 + 0x340) = lVar3;
  uVar9 = _swift_task_alloc(*(long *)(lVar3 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x348) = uVar9;
  lVar3 = *(long *)(param_3 + 0x10);
  *(long *)(unaff_x22 + 0x350) = lVar3;
  if (lVar3 != 0) {
    lVar31 = 0;
    *(undefined8 *)(unaff_x22 + 0x358) = 0;
    uVar5 = _UNK_10054fde8;
    uVar4 = _DAT_10054fde0;
    lVar33 = 1;
    puVar29 = PTR___type_metadata_for_Swift_String_1005fc368;
    while( true ) {
      uVar6 = 0x3a726f727245;
      lVar25 = *(long *)(unaff_x22 + 0x2f0) + lVar31;
      uVar15 = *(undefined8 *)(lVar25 + 0x20);
      uVar9 = *(undefined8 *)(lVar25 + 0x38);
      uVar7 = *(undefined8 *)(lVar25 + 0x30);
      *(undefined8 *)(unaff_x22 + 0x58) = *(undefined8 *)(lVar25 + 0x28);
      *(undefined8 *)(unaff_x22 + 0x50) = uVar15;
      *(undefined8 *)(unaff_x22 + 0x68) = uVar9;
      *(undefined8 *)(unaff_x22 + 0x60) = uVar7;
      uVar7 = *(undefined8 *)(lVar25 + 0x60);
      uVar15 = *(undefined8 *)(lVar25 + 0x78);
      uVar9 = *(undefined8 *)(lVar25 + 0x70);
      uVar36 = *(undefined8 *)(lVar25 + 0x48);
      uVar35 = *(undefined8 *)(lVar25 + 0x40);
      uVar34 = *(undefined8 *)(lVar25 + 0x58);
      uVar30 = *(undefined8 *)(lVar25 + 0x50);
      *(undefined8 *)(unaff_x22 + 0x98) = *(undefined8 *)(lVar25 + 0x68);
      *(undefined8 *)(unaff_x22 + 0x90) = uVar7;
      *(undefined8 *)(unaff_x22 + 0xa8) = uVar15;
      *(undefined8 *)(unaff_x22 + 0xa0) = uVar9;
      *(undefined8 *)(unaff_x22 + 0x78) = uVar36;
      *(undefined8 *)(unaff_x22 + 0x70) = uVar35;
      *(undefined8 *)(unaff_x22 + 0x88) = uVar34;
      *(undefined8 *)(unaff_x22 + 0x80) = uVar30;
      uVar7 = *(undefined8 *)(lVar25 + 0x58);
      *(undefined8 *)(unaff_x22 + 0x238) = *(undefined8 *)(lVar25 + 0x60);
      *(undefined8 *)(unaff_x22 + 0x230) = uVar7;
      lVar25 = *(long *)(unaff_x22 + 0x238);
      if (lVar25 != 0) {
        uVar4 = *(undefined8 *)(unaff_x22 + 0x230);
        lVar3 = *(long *)(unaff_x22 + 0x340);
        uVar5 = *(undefined8 *)(unaff_x22 + 0x338);
        uVar6 = *(undefined8 *)(unaff_x22 + 0x330);
        __outlined_init_with_copy_of_mas_CatalogApp(unaff_x22 + 0x50,unaff_x22 + 0x170);
        __outlined_init_with_copy_of_Swift_String_(unaff_x22 + 0x230,unaff_x22 + 0x2c0);
        Foundation::URL::_init();
        iVar2 = (**(code **)(lVar3 + 0x30))(uVar6,1,uVar5);
        if (iVar2 == 1) {
          uVar5 = __merged_outlined_destroy_of_ArgumentParser_Argument<[Swift_String]>
                            (*(undefined8 *)(unaff_x22 + 0x330),
                             &__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                             &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
          MASError::_lazy_protocol_witness_table_accessor();
          auVar46 = _swift_allocError(&__type_metadata_for_mas_MASError,uVar5,0,0);
          puVar16 = auVar46._8_8_;
          *puVar16 = uVar4;
          puVar16[1] = lVar25;
          *(undefined1 *)(puVar16 + 7) = 2;
          _swift_willThrow();
          *(long *)(unaff_x22 + 0x380) = auVar46._0_8_;
          uVar27 = *(ulong *)(unaff_x22 + 0x2e8);
          plVar10 = (long *)_swift_task_alloc(DAT_100552ce4);
          *(long **)(unaff_x22 + 0x388) = plVar10;
          *plVar10 = unaff_x22;
          plVar10[1] = (long)_run;
          __generic_specialization_<[mas_CatalogApp],Swift_Error>_of_closure__1_nonisolated_nonsending___A_Element_A1__async__>____in__extension_in_mas__Swift_Sequence_forEach<A_where_A1:_Swift_Error>_attemptTo__Swift_String____nonisolated_nonsending___A_Element__async_throws_A1___>_____async__>___
                    (*(undefined8 *)(unaff_x22 + 0x2e0),uVar27 & 0xcfffffffffffffff,unaff_x22 + 0x50
                     ,auVar46._0_8_,0x6e65706f,0xe400000000000000);
          return;
        }
        uVar4 = *(undefined8 *)(unaff_x22 + 0x348);
        lVar3 = *(long *)(unaff_x22 + 0x340);
        uVar7 = *(undefined8 *)(unaff_x22 + 0x338);
        uVar9 = *(undefined8 *)(unaff_x22 + 0x330);
        uVar6 = *(undefined8 *)(unaff_x22 + 0x308);
        lVar33 = *(long *)(unaff_x22 + 0x300);
        uVar5 = *(undefined8 *)(unaff_x22 + 0x2f8);
        __merged_outlined_destroy_of_ArgumentParser_Argument<[Swift_String]>
                  (unaff_x22 + 0x230,
                   &__demangling_cache_variable_for_type_metadata_for_Swift_String_,
                   &__mangled_name_ref_for_type_metadata_for_Swift_String_);
        (**(code **)(lVar3 + 0x20))(uVar4,uVar9,uVar7);
        IVar11 = _objc_allocWithZone(PTR__OBJC_CLASS___NSWorkspaceOpenConfiguration_10060acc0);
        IVar11 = NSWorkspaceOpenConfiguration::init(IVar11);
        *(ID *)(unaff_x22 + 0x360) = IVar11;
        UVar8.unknown =
             (undefined *)NSWorkspace::sharedWorkspace((ID)PTR__OBJC_CLASS___NSWorkspace_10060acc8);
        *(undefined **)(unaff_x22 + 0x368) = UVar8.unknown;
        pNVar17 = Foundation::URL::_bridgeToObjectiveC(UVar8);
        *(NSURL **)(unaff_x22 + 0x370) = pNVar17;
        *(long *)(unaff_x22 + 0x38) = unaff_x22 + 0x2d8;
        *(long *)(unaff_x22 + 0x10) = unaff_x22;
        *(code **)(unaff_x22 + 0x18) = _run;
        continuation.unknown = (undefined *)_swift_continuation_init(unaff_x22 + 0x10,1);
        *(undefined8 *)(unaff_x22 + 0x208) = uVar5;
        uVar4 = ___swift_allocate_boxed_opaque_existential_0(unaff_x22 + 0x1f0);
        __C::NSRunningApplication::typeMetadataAccessor();
        ::___swift_instantiateConcreteTypeFromMangledNameV2
                  (&__demangling_cache_variable_for_type_metadata_for_Swift_Error,
                   &__mangled_name_ref_for_type_metadata_for_Swift_Error);
        SVar39.bridgeObject = (void *)0x800000010059b2f0;
        SVar39.str = (char *)0xd000000000000026;
        ::Swift::CheckedContinuation::init(continuation,SVar39);
        (**(code **)(lVar33 + 0x20))(uVar4,uVar6,uVar5);
        *(undefined **)(unaff_x22 + 0x1d0) = PTR___NSConcreteStackBlock_1005fba70;
        *(undefined8 *)(unaff_x22 + 0x1d8) = DAT_100550488;
        *(code **)(unaff_x22 + 0x1e0) =
             __checked__objc_completion_handler_block_implementation_for__escaping__callee_unowned__convention_block___Sendable___unowned___C_NSRunningApplication___unowned___C_NSError____>____with_result_type___C_NSRunningApplication
        ;
        *(undefined **)(unaff_x22 + 0x1e8) = &_block_descriptor;
        NSWorkspace::openURL_configuration_completionHandler_
                  ((ID)UVar8.unknown,pNVar17,IVar11,unaff_x22 + 0x1d0);
        (**(code **)(lVar33 + 8))(uVar4,uVar5);
        _swift_continuation_await(unaff_x22 + 0x10);
        return;
      }
      uVar7 = *(undefined8 *)(unaff_x22 + 0x50);
      __outlined_init_with_copy_of_mas_CatalogApp(unaff_x22 + 0x50,unaff_x22 + 0xb0);
      if (__one_time_initialization_token_for_printer != -1) {
        _swift_once(&__one_time_initialization_token_for_printer,one_time_init_for_printer);
      }
      plVar10 = __s3mas3MASV7printerAA7PrinterVvpZ;
      uVar9 = *(undefined8 *)(unaff_x22 + 0x328);
      *(undefined8 *)(unaff_x22 + 0x130) = 0xd00000000000002e;
      *(undefined8 *)(unaff_x22 + 0x138) = 0x800000010059bd00;
      *(undefined **)(unaff_x22 + 0x168) = PTR___type_metadata_for_Swift_UInt64_1005fd890;
      *(undefined **)(unaff_x22 + 0x148) = puVar29;
      *(undefined8 *)(unaff_x22 + 0x150) = uVar7;
      plVar10 = (long *)(**(code **)(*plVar10 + 0x88))();
      *plVar10 = *plVar10 + 1;
      IVar11 = NSFileHandle::fileHandleWithStandardError
                         ((ID)PTR__OBJC_CLASS___NSFileHandle_10060acd0);
      *(undefined8 *)(unaff_x22 + 0x240) = 10;
      *(undefined8 *)(unaff_x22 + 0x248) = 0xe100000000000000;
      *(undefined8 *)(unaff_x22 + 0x250) = 0x3a726f727245;
      SVar37.bridgeObject = (void *)0xe600000000000000;
      SVar37.str = (char *)0x3a726f727245;
      *(undefined8 *)(unaff_x22 + 600) = 0xe600000000000000;
      *(undefined8 *)(unaff_x22 + 0x260) = 10;
      *(undefined8 *)(unaff_x22 + 0x268) = 0xe100000000000000;
      LVar12 = Foundation::Locale::typeMetadataAccessor();
      (**(code **)(*(long *)(LVar12.unknown + -8) + 0x38))(uVar9,1,1,LVar12.unknown);
      ::Swift::String::_lazy_protocol_witness_table_accessor();
      RVar18.unknown = (undefined *)0x4;
      uVar20 = 0;
      CVar22.unknown = (undefined *)0x0;
      (extension_Foundation)::Swift::StringProtocol::_range(unaff_x22 + 0x260);
      __merged_outlined_destroy_of_ArgumentParser_Argument<[Swift_String]>
                (uVar9,&__demangling_cache_variable_for_type_metadata_for_Foundation_Locale_,
                 &__mangled_name_ref_for_type_metadata_for_Foundation_Locale_);
      if ((uVar20 & 0xff) != 1) {
        if (0x18 < (ulong)RVar18.unknown >> 0xe) {
                    /* WARNING: Does not return */
          pcVar1 = (code *)SoftwareBreakpoint(1,0x100015f90);
          (*pcVar1)();
        }
        pvVar19 = (void *)0x60007;
        CVar23.unknown = (undefined *)0xe600000000000000;
        SVar55.bridgeObject = (void *)0x3a726f727245;
        SVar55.str = (char *)0x60007;
        SVar38.str = ::Swift::String::get_subscript(RVar18,SVar55);
        SVar38.bridgeObject = pvVar19;
        CVar22.unknown = CVar23.unknown;
        SVar37 = ::Swift::String::__fromSubstring(SVar38);
        _swift_bridgeObjectRelease(CVar23.unknown);
      }
      _Var13 = ::Swift::String::get_count(SVar37);
      _swift_bridgeObjectRelease(SVar37.bridgeObject);
      pcVar21 = (char *)(_Var13 + 1);
      if (SCARRY8(_Var13,1)) {
                    /* WARNING: Does not return */
        pcVar1 = (code *)SoftwareBreakpoint(1,0x100015f88);
        (*pcVar1)();
      }
      repeating.bridgeObject = (void *)0xe100000000000000;
      repeating.str = (char *)0x20;
      SVar39 = ::Swift::String::init(repeating,(__int64)pcVar21);
      SVar47.bridgeObject = CVar22.unknown;
      SVar47.str = pcVar21;
      ::Swift::String::append(SVar39,SVar47);
      _swift_bridgeObjectRelease(SVar39.bridgeObject);
      uVar7 = *(undefined8 *)(unaff_x22 + 0x240);
      pcVar28 = *(char **)(unaff_x22 + 0x248);
      IVar14 = NSFileHandle::fileDescriptor(IVar11);
      iVar2 = _isatty((int)IVar14);
      if (iVar2 == 0) {
        uVar9 = 0xe600000000000000;
      }
      else {
        *(undefined8 *)(unaff_x22 + 0x2b0) = 0x5b1b;
        *(undefined8 *)(unaff_x22 + 0x2b8) = 0xe200000000000000;
        SVar40.bridgeObject = (void *)0xe400000000000000;
        SVar40.str = (char *)0x31333b34;
        SVar48.bridgeObject = CVar22.unknown;
        SVar48.str = pcVar21;
        ::Swift::String::append(SVar40,SVar48);
        SVar41.bridgeObject = (void *)0xe100000000000000;
        SVar41.str = (char *)0x6d;
        SVar49.bridgeObject = CVar22.unknown;
        SVar49.str = pcVar21;
        ::Swift::String::append(SVar41,SVar49);
        SVar42.bridgeObject = (void *)0xe600000000000000;
        SVar42.str = (char *)0x3a726f727245;
        SVar50.bridgeObject = CVar22.unknown;
        SVar50.str = pcVar21;
        ::Swift::String::append(SVar42,SVar50);
        SVar43.bridgeObject = (void *)0xe200000000000000;
        SVar43.str = (char *)0x5b1b;
        SVar51.bridgeObject = CVar22.unknown;
        SVar51.str = pcVar21;
        ::Swift::String::append(SVar43,SVar51);
        SVar44.bridgeObject = (void *)0xe200000000000000;
        SVar44.str = (char *)0x6d30;
        SVar52.bridgeObject = CVar22.unknown;
        SVar52.str = pcVar21;
        ::Swift::String::append(SVar44,SVar52);
        uVar6 = *(undefined8 *)(unaff_x22 + 0x2b0);
        uVar9 = *(undefined8 *)(unaff_x22 + 0x2b8);
      }
      uVar15 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                         (&
                          __demangling_cache_variable_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                          ,&
                           __mangled_name_ref_for_type_metadata_for_Swift__ContiguousArrayStorage<Swift_String>
                         );
      pcVar21 = (char *)0x7;
      lVar25 = _swift_allocObject(uVar15,0x30);
      *(undefined8 *)(lVar25 + 0x18) = uVar5;
      *(undefined8 *)(lVar25 + 0x10) = uVar4;
      *(undefined8 *)(unaff_x22 + 0x270) = uVar6;
      *(undefined8 *)(unaff_x22 + 0x278) = uVar9;
      _swift_bridgeObjectRetain(uVar9);
      SVar45.bridgeObject = (void *)0xe100000000000000;
      SVar45.str = (char *)0x20;
      SVar53.bridgeObject = CVar22.unknown;
      SVar53.str = pcVar21;
      ::Swift::String::append(SVar45,SVar53);
      pcVar21 = pcVar28;
      SVar39 = (String)__mas__indent_in__13FF02662930BA0C33C74C7843D664F7_____Any_with__Swift_String___>_Swift_String
                                 (unaff_x22 + 0x130,uVar7);
      SVar54.bridgeObject = CVar22.unknown;
      SVar54.str = pcVar21;
      ::Swift::String::append(SVar39,SVar54);
      _swift_bridgeObjectRelease(SVar39.bridgeObject);
      uVar6 = *(undefined8 *)(unaff_x22 + 0x278);
      *(undefined8 *)(lVar25 + 0x20) = *(undefined8 *)(unaff_x22 + 0x270);
      *(undefined8 *)(lVar25 + 0x28) = uVar6;
      *(undefined **)(unaff_x22 + 0x2d0) = PTR___swiftEmptyArrayStorage_1005fda60;
      ::Swift::ContiguousArray::_createNewBuffer(false,1,false,CVar22);
      lVar24 = *(long *)(unaff_x22 + 0x2d0);
      *(undefined8 *)(unaff_x22 + 0x280) = uVar7;
      *(char **)(unaff_x22 + 0x288) = pcVar28;
      lVar26 = *(long *)(unaff_x22 + 0x168);
      uVar6 = ___swift_project_boxed_opaque_existential_0Tm(unaff_x22 + 0x150,lVar26);
      lVar32 = *(long *)(lVar26 + -8);
      uVar15 = _swift_task_alloc(*(long *)(lVar32 + 0x40) + 0xfU & 0xfffffffffffffff0);
      (**(code **)(lVar32 + 0x10))(uVar15,uVar6,lVar26);
      SVar39 = ::Swift::String::_init(uVar15,lVar26);
      _swift_task_dealloc(uVar15);
      *(String *)(unaff_x22 + 0x2a0) = SVar39;
      if (__one_time_initialization_token_for__nonEmptyLineStartRegex_in__13FF02662930BA0C33C74C7843D664F7_
          != -1) {
        _swift_once(&
                    __one_time_initialization_token_for__nonEmptyLineStartRegex_in__13FF02662930BA0C33C74C7843D664F7_
                    ,::_one_time_init);
      }
      uVar30 = *(undefined8 *)(unaff_x22 + 800);
      lVar26 = *(long *)(unaff_x22 + 0x318);
      uVar34 = *(undefined8 *)(unaff_x22 + 0x310);
      uVar6 = ___swift_project_value_buffer
                        (uVar34,&
                                __s3mas22nonEmptyLineStartRegex33_13FF02662930BA0C33C74C7843D664F7LL17_StringProcessing0F0VySsGvp
                        );
      uVar15 = (**(code **)(lVar26 + 0x10))(uVar30,uVar6,uVar34);
      ::Swift::String::_lazy_protocol_witness_table_accessor();
      uVar6 = uVar15;
      ::Swift::String::_lazy_protocol_witness_table_accessor();
      puVar16 = &
                __lazy_protocol_witness_table_cache_variable_for_type__StringProcessing_Regex<Swift_Substring>_and_conformance__StringProcessing_Regex<A>____StringProcessing_RegexComponent_in__StringProcessing
      ;
      _StringProcessing::Regex<Substring>::_lazy_protocol_witness_table_accessor();
      CVar22.unknown = PTR___type_metadata_for_Swift_String_1005fc368;
      (extension__StringProcessing)::Swift::RangeReplaceableCollection::_replacing
                (unaff_x22 + 0x290,uVar30,unaff_x22 + 0x280,0x7fffffffffffffff,
                 PTR___type_metadata_for_Swift_String_1005fc368,
                 PTR___type_metadata_for_Swift_String_1005fc368,uVar34,uVar15,uVar6,puVar16);
      (**(code **)(lVar26 + 8))(uVar30,uVar34);
      _swift_bridgeObjectRelease(SVar39.bridgeObject);
      uVar6 = *(undefined8 *)(unaff_x22 + 0x290);
      uVar15 = *(undefined8 *)(unaff_x22 + 0x298);
      uVar27 = *(ulong *)(lVar24 + 0x10);
      if (*(ulong *)(lVar24 + 0x18) >> 1 <= uVar27) {
        ::Swift::ContiguousArray::_createNewBuffer
                  (1 < *(ulong *)(lVar24 + 0x18),uVar27 + 1,true,CVar22);
        lVar24 = *(long *)(unaff_x22 + 0x2d0);
      }
      lVar32 = *(long *)(unaff_x22 + 0x350);
      *(ulong *)(lVar24 + 0x10) = uVar27 + 1;
      lVar26 = lVar24 + uVar27 * 0x10;
      *(undefined8 *)(lVar26 + 0x20) = uVar6;
      *(undefined8 *)(lVar26 + 0x28) = uVar15;
      ::Swift::Array<undefined>::_append(lVar24);
      _swift_bridgeObjectRelease(uVar9);
      puVar29 = PTR___type_metadata_for_Swift_String_1005fc368;
      *(undefined **)(unaff_x22 + 0x228) = PTR___type_metadata_for_Swift_String_1005fc368;
      *(undefined8 *)(unaff_x22 + 0x210) = 0x20;
      *(undefined8 *)(unaff_x22 + 0x218) = 0xe100000000000000;
      auVar46 = __mas__indent_in__13FF02662930BA0C33C74C7843D664F7_____Any_with__Swift_String___>_Swift_String
                          (unaff_x22 + 0x210,uVar7,pcVar28);
      _swift_bridgeObjectRelease(pcVar28);
      ___swift_destroy_boxed_opaque_existential_0Tm(unaff_x22 + 0x210);
      __function_signature_specialization_<Arg[4]___Dead>_of_mas_Printer__print_in__13FF02662930BA0C33C74C7843D664F7______Swift_String__separator__Swift_String_terminator__Swift_String_to____C_NSFileHandle___>___
                (lVar25,auVar46._0_8_,auVar46._8_8_,10,0xe100000000000000,IVar11);
      _swift_bridgeObjectRelease(auVar46._8_8_);
      _swift_bridgeObjectRelease(lVar25);
      _swift_arrayDestroy(unaff_x22 + 0x130,2,PTR___type_metadata_for_Any_1005fda48 + 8);
      __outlined_destroy_of_mas_CatalogApp(unaff_x22 + 0x50);
      if (lVar33 == lVar32) break;
      *(long *)(unaff_x22 + 0x358) = lVar33;
      lVar33 = lVar33 + 1;
      lVar31 = lVar31 + 0x60;
      lVar3 = lVar3 + -1;
      if (lVar3 == 0) {
                    /* WARNING: Does not return */
        pcVar1 = (code *)SoftwareBreakpoint(1,0x100015f8c);
        (*pcVar1)();
      }
    }
    uVar9 = *(undefined8 *)(unaff_x22 + 0x348);
    uVar7 = *(undefined8 *)(unaff_x22 + 0x330);
    uVar6 = *(undefined8 *)(unaff_x22 + 0x328);
    uVar5 = *(undefined8 *)(unaff_x22 + 800);
    uVar4 = *(undefined8 *)(unaff_x22 + 0x308);
  }
  _swift_task_dealloc(uVar9);
  _swift_task_dealloc(uVar7);
  _swift_task_dealloc(uVar6);
  _swift_task_dealloc(uVar5);
  _swift_task_dealloc(uVar4);
                    /* WARNING: Could not recover jumptable at 0x000100015ddc. Too many branches */
                    /* WARNING: Treating indirect jump as call */
  (**(code **)(unaff_x22 + 8))();
  return;
}
```

## `MAS.SignOut.run`

From `Sources/mas/Commands/MAS.SignOut.swift`.

```swift
		func run() {
			ISServiceProxy.genericShared().accountService.signOut()
		}
```

The optimizer inlined it into every caller, so the binary has no body of its own to decompile.

## `MAS.Uninstall.validate`

From `Sources/mas/Commands/MAS.Uninstall.swift`.

```swift
		func validate() throws(ValidationError) {
			if isUninstallingAll != installedAppsOptionGroup.appIDStrings.isEmpty {
				throw .init(
					isUninstallingAll
						? "Cannot specify both --all & app IDs"
						: "Must specify either --all or at least one app ID",
				)
			}
		}
```

### `mas.MAS.Uninstall.validate() throws(ArgumentParser.ValidationError) -> ()` at `0x1000182d8`

swiftdc:

```swift
mas.MAS.Uninstall.validate() throws(ArgumentParser.ValidationError) -> () {
    ArgumentParser.Flag.wrappedValue.getter()
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Argument.wrappedValue.getter()
    if (w9 != w8) {
        ArgumentParser.Flag.wrappedValue.getter()
        if (Swift._stdlib_isOSVersionAtLeastOrVariantVersionAtLeast(15, 0, 0, 18, 0, 0)) {
            swift_willThrowTypedImpl(local_c0, 0x1005e54b8)
        }
        throw ?
    }
    machine_return() /* unresolved Swift success/error exit */
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $validate(Uninstall param_1)
/* mas.MAS.Uninstall.validate() throws(ArgumentParser.ValidationError) -> () */

undefined1  [16] __swift_stdcall mas::MAS::Uninstall::_validate(Uninstall param_1)

{
  char *pcVar1;
  byte bVar2;
  Flag FVar3;
  Argument AVar4;
  ulong uVar5;
  void *in_x2;
  long lVar6;
  ulong unaff_x20;
  undefined8 ****ppppuVar7;
  OptionGroup OVar8;
  undefined1 auVar9 [16];
  char local_100;
  undefined7 uStack_ff;
  undefined8 local_e0;
  undefined8 ****local_c0;
  ulong uStack_b8;
  undefined8 local_b0;
  undefined8 uStack_a8;
  undefined8 local_a0;
  undefined8 uStack_98;
  undefined8 uStack_90;
  undefined8 uStack_88;
  undefined8 local_80;
  undefined8 uStack_78;
  
  uStack_b8 = *(undefined8 *)(unaff_x20 + 0x20);
  local_c0 = *(undefined8 *****)(unaff_x20 + 0x18);
  local_b0 = CONCAT71(local_b0._1_7_,*(undefined1 *)(unaff_x20 + 0x28));
  FVar3.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar3);
  uStack_98 = *(undefined8 *)(unaff_x20 + 0x58);
  local_a0 = *(undefined8 *)(unaff_x20 + 0x50);
  uStack_88 = *(undefined8 *)(unaff_x20 + 0x68);
  uStack_90 = *(undefined8 *)(unaff_x20 + 0x60);
  uStack_78 = *(undefined8 *)(unaff_x20 + 0x78);
  local_80 = *(undefined8 *)(unaff_x20 + 0x70);
  uStack_b8 = *(undefined8 *)(unaff_x20 + 0x38);
  local_c0 = *(undefined8 *****)(unaff_x20 + 0x30);
  uStack_a8 = *(undefined8 *)(unaff_x20 + 0x48);
  local_b0 = *(undefined8 *)(unaff_x20 + 0x40);
  auVar9 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_InstalledAppsOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_InstalledAppsOptionGroup>
                     );
  OVar8.title.bridgeObject = in_x2;
  OVar8._dummy = (bool)auVar9[0];
  OVar8._1_7_ = auVar9._1_7_;
  OVar8.title.str = (char *)auVar9._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar8);
  AVar4.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Argument<[Swift_String]>
                 );
  ppppuVar7 = &local_c0;
  ArgumentParser::Argument::get_wrappedValue(AVar4);
  ::_outlined_consume();
  _swift_bridgeObjectRelease(local_e0);
  ::_outlined_consume();
  lVar6 = *(long *)(CONCAT71(uStack_ff,local_100) + 0x10);
  _swift_bridgeObjectRelease();
  if ((bool)local_100 != (lVar6 == 0)) {
    uStack_b8 = *(undefined8 *)(unaff_x20 + 0x20);
    local_c0 = *(undefined8 *****)(unaff_x20 + 0x18);
    local_b0 = CONCAT71(local_b0._1_7_,*(undefined1 *)(unaff_x20 + 0x28));
    ArgumentParser::Flag::get_wrappedValue(FVar3);
    ppppuVar7 = (undefined8 ****)0xd000000000000023;
    pcVar1 = "least one app ID";
    if (local_100 == '\0') {
      ppppuVar7 = (undefined8 ****)0xd000000000000030;
      pcVar1 = "un would uninstall:\n";
    }
    unaff_x20 = (ulong)pcVar1 | 0x8000000000000000;
    local_c0 = ppppuVar7;
    uStack_b8 = unaff_x20;
    bVar2 = ::Swift::_stdlib_isOSVersionAtLeastOrVariantVersionAtLeast(0xf,0,0,0x12,0,0);
    uVar5 = (ulong)bVar2;
    if ((bVar2 & 1) != 0) {
      ArgumentParser::ValidationError::_lazy_protocol_witness_table_accessor();
      _swift_willThrowTypedImpl(&local_c0,&__type_metadata_for_ArgumentParser_ValidationError,uVar5)
      ;
    }
  }
  auVar9._8_8_ = unaff_x20;
  auVar9._0_8_ = ppppuVar7;
  return auVar9;
}
```

## `MAS.Uninstall.run`

From `Sources/mas/Commands/MAS.Uninstall.swift`.

```swift
		func run() async {
			let installedApps = await installedAppsOptionGroup.installedApps(withFullJSON: false)
			let uninstallingADAMIDByPathOrdered =
				(isUninstallingAll ? installedApps.map { .bundleID($0.bundleID) } : installedAppsOptionGroup.appIDs)
					.reduce(into: OrderedDictionary<String, String>()) { uninstallingADAMIDByPathOrdered, appID in
						uninstallingADAMIDByPathOrdered
							.merge(installedApps.compactMap { $0.matches(appID) ? ($0.path, .init($0.adamID)) : nil }) { $1 }
					}
			guard !uninstallingADAMIDByPathOrdered.isEmpty else {
				return
			}
			guard !isPerformingDryRun else {
				printer.notice("Dry run. A wet run would uninstall:\n")
				for appPath in uninstallingADAMIDByPathOrdered.keys {
					printer.info(appPath)
				}
				return
			}

			let fileManager = FileManager.default
			for appPath in uninstallingADAMIDByPathOrdered.keys {
				do {
					let appURL = URL(folderPath: appPath)
					let trashURL = try fileManager.url(
						for: .trashDirectory,
						in: .userDomainMask,
						appropriateFor: appURL,
						create: true,
					)
					let destinationPath = trashURL.appending(path: appURL.lastPathComponent, directoryHint: .isDirectory).filePath
					_ = try await mas::run(
						.path("/usr/bin/sudo"),
						"/bin/mv",
						appPath,
						fileManager.fileExists(atPath: destinationPath)
							? trashURL.appending(
								path: """
									\(appURL.deletingPathExtension().lastPathComponent) \
									\(Date().formatted(trashCollisionDateFormatStyle))\
									\(appURL.pathExtension.ifNotEmptyPrepend("."))
									""",
								directoryHint: .isDirectory,
							)
							.filePath
							: destinationPath,
						errorMessage: "Failed to trash \(appPath.quoted) to \(destinationPath.quoted)",
					)
					printer.info("Uninstalled", appPath.quoted, "to", destinationPath.quoted)
				} catch {
					printer.error("Failed to uninstall", appPath, error: error)
				}
			}
		}
```

### `mas.MAS.Uninstall.run() async -> ()` at `0x1000184cc`

swiftdc:

```swift
mas.MAS.Uninstall.run() async -> () {
    // async function: 2 resume funclet(s): resume #1 @0x10001878c, resume #2 @0x100019ec0
    ArgumentParser.OptionGroup.wrappedValue.getter()
    mas.InstalledAppsOptionGroup.appIDs.getter(self: (? + 304))
    mem64[x22 + 0x588] = x0
    mem64[x22 + 0x590] = x0
    mem64[x0] = x22; mem64[x0 + 0x8] = (1) await resume partial function for mas.MAS.Uninstall.run() async -> ()
    if (x9 != x8) {
        __stack_chk_fail()
        // no fall-through
    } else {
        await indirect_call(?)
    }
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Uninstall param_1)
/* mas.MAS.Uninstall.run() async -> () */

void __swift_stdcall mas::MAS::Uninstall::_run(Uninstall param_1)

{
  ulong uVar1;
  Configuration CVar2;
  DirectoryHint DVar3;
  CharacterSet CVar4;
  undefined8 uVar5;
  undefined7 extraout_var;
  VerbatimFormatStyle VVar6;
  Date DVar7;
  FilePath FVar8;
  Executable EVar9;
  undefined7 extraout_var_00;
  URL UVar10;
  InstalledAppsOptionGroup IVar11;
  long *plVar12;
  ulong in_x1;
  void *in_x2;
  long lVar13;
  long lVar14;
  long unaff_x20;
  long unaff_x22;
  undefined8 uVar15;
  undefined8 uVar16;
  OptionGroup OVar17;
  
  lVar13 = *(long *)PTR____stack_chk_guard_1005fbaa0;
  *(long *)(unaff_x22 + 0x490) = unaff_x20;
  *(ulong *)(unaff_x22 + 0x488) = in_x1;
  *(undefined **)(unaff_x22 + 0x480) = param_1.unknown;
  CVar4 = Foundation::CharacterSet::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x498) = CVar4.unknown;
  lVar14 = *(long *)(CVar4.unknown + -8);
  *(long *)(unaff_x22 + 0x4a0) = lVar14;
  uVar5 = _swift_task_alloc(*(long *)(lVar14 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x4a8) = uVar5;
  CVar2 = Subprocess::Configuration::typeMetadataAccessor();
  *(long *)(unaff_x22 + 0x4b0) = CONCAT71(extraout_var,CVar2.rawBytes);
  uVar5 = _swift_task_alloc(*(long *)(*(long *)(CONCAT71(extraout_var,CVar2.rawBytes) + -8) + 0x40)
                            + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x4b8) = uVar5;
  lVar14 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&__demangling_cache_variable_for_type_metadata_for_System_FilePath_,
                      &__mangled_name_ref_for_type_metadata_for_System_FilePath_);
  uVar5 = _swift_task_alloc(*(long *)(*(long *)(lVar14 + -8) + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x4c0) = uVar5;
  VVar6 = Foundation::Date::VerbatimFormatStyle::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x4c8) = VVar6.unknown;
  lVar14 = *(long *)(VVar6.unknown + -8);
  *(long *)(unaff_x22 + 0x4d0) = lVar14;
  uVar5 = _swift_task_alloc(*(long *)(lVar14 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x4d8) = uVar5;
  DVar7 = Foundation::Date::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x4e0) = DVar7.unknown;
  lVar14 = *(long *)(DVar7.unknown + -8);
  *(long *)(unaff_x22 + 0x4e8) = lVar14;
  uVar5 = _swift_task_alloc(*(long *)(lVar14 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x4f0) = uVar5;
  FVar8 = System::FilePath::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x4f8) = FVar8.unknown;
  lVar14 = *(long *)(FVar8.unknown + -8);
  *(long *)(unaff_x22 + 0x500) = lVar14;
  uVar5 = _swift_task_alloc(*(long *)(lVar14 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x508) = uVar5;
  EVar9 = Subprocess::Executable::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x510) = EVar9.unknown;
  lVar14 = *(long *)(EVar9.unknown + -8);
  *(long *)(unaff_x22 + 0x518) = lVar14;
  uVar5 = _swift_task_alloc(*(long *)(lVar14 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x520) = uVar5;
  DVar3 = Foundation::URL::DirectoryHint::typeMetadataAccessor();
  *(long *)(unaff_x22 + 0x528) = CONCAT71(extraout_var_00,DVar3.value);
  lVar14 = *(long *)(CONCAT71(extraout_var_00,DVar3.value) + -8);
  *(long *)(unaff_x22 + 0x530) = lVar14;
  uVar5 = _swift_task_alloc(*(long *)(lVar14 + 0x40) + 0xfU & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x538) = uVar5;
  lVar14 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&__demangling_cache_variable_for_type_metadata_for_Foundation_URL_,
                      &__mangled_name_ref_for_type_metadata_for_Foundation_URL_);
  uVar1 = *(long *)(*(long *)(lVar14 + -8) + 0x40) + 0xf;
  uVar5 = _swift_task_alloc(uVar1 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x540) = uVar5;
  uVar5 = _swift_task_alloc(uVar1 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x548) = uVar5;
  UVar10 = Foundation::URL::typeMetadataAccessor();
  *(undefined **)(unaff_x22 + 0x550) = UVar10.unknown;
  lVar14 = *(long *)(UVar10.unknown + -8);
  *(long *)(unaff_x22 + 0x558) = lVar14;
  uVar1 = *(long *)(lVar14 + 0x40) + 0xf;
  uVar5 = _swift_task_alloc(uVar1 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x560) = uVar5;
  uVar5 = _swift_task_alloc(uVar1 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x568) = uVar5;
  uVar5 = _swift_task_alloc(uVar1 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x570) = uVar5;
  uVar5 = _swift_task_alloc(uVar1 & 0xfffffffffffffff0);
  *(undefined8 *)(unaff_x22 + 0x578) = uVar5;
  uVar5 = *(undefined8 *)(unaff_x20 + 0x50);
  uVar16 = *(undefined8 *)(unaff_x20 + 0x68);
  uVar15 = *(undefined8 *)(unaff_x20 + 0x60);
  *(undefined8 *)(unaff_x22 + 0x38) = *(undefined8 *)(unaff_x20 + 0x58);
  *(undefined8 *)(unaff_x22 + 0x30) = uVar5;
  *(undefined8 *)(unaff_x22 + 0x48) = uVar16;
  *(undefined8 *)(unaff_x22 + 0x40) = uVar15;
  uVar5 = *(undefined8 *)(unaff_x20 + 0x70);
  *(undefined8 *)(unaff_x22 + 0x58) = *(undefined8 *)(unaff_x20 + 0x78);
  *(undefined8 *)(unaff_x22 + 0x50) = uVar5;
  uVar16 = *(undefined8 *)(unaff_x20 + 0x30);
  uVar15 = *(undefined8 *)(unaff_x20 + 0x48);
  uVar5 = *(undefined8 *)(unaff_x20 + 0x40);
  *(undefined8 *)(unaff_x22 + 0x18) = *(undefined8 *)(unaff_x20 + 0x38);
  *(undefined8 *)(unaff_x22 + 0x10) = uVar16;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar15;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar5;
  OVar17._0_16_ =
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&
                  __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_InstalledAppsOptionGroup>
                  ,&
                   __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_InstalledAppsOptionGroup>
                 );
  IVar11.unknown = OVar17._0_8_;
  *(undefined **)(unaff_x22 + 0x580) = IVar11.unknown;
  OVar17.title.bridgeObject = in_x2;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar17);
  InstalledAppsOptionGroup::get_appIDs(IVar11);
  *(undefined **)(unaff_x22 + 0x588) = IVar11.unknown;
  lVar14 = (long)
           __s3mas13installedApps10withAppIDs0D8FullJSON010unresolvedE9IDHandlerSayAA09InstalledE0VGSayAA0E2IDOG_SbyAJXEtYaF08_s3mas24kc31OptionGroupV09installedC012withg12JSONSayAA0B3e10VGSb_tYaFyS10J2IDOXEfU_Tf1nnnc_nTu
  ;
  plVar12 = (long *)_swift_task_alloc(DAT_10055303c);
  *(long **)(unaff_x22 + 0x590) = plVar12;
  *plVar12 = unaff_x22;
  plVar12[1] = (long)_run;
  if (*(long *)PTR____stack_chk_guard_1005fbaa0 != lVar13) {
                    /* WARNING: Subroutine does not return */
    ___stack_chk_fail();
  }
  (*(code *)((long)&
                   __s3mas13installedApps10withAppIDs0D8FullJSON010unresolvedE9IDHandlerSayAA09InstalledE0VGSayAA0E2IDOG_SbyAJXEtYaF08_s3mas24kc31OptionGroupV09installedC012withg12JSONSayAA0B3e10VGSb_tYaFyS10J2IDOXEfU_Tf1nnnc_nTu
            + lVar14))(param_1.unknown,in_x1 & 0xcfffffffffffffff,IVar11.unknown,0);
  return;
}
```

## `MAS.Update.run`

From `Sources/mas/Commands/MAS.Update.swift`.

```swift
		func run() async {
			await AppStore.update.apps(
				withADAMIDs: await outdatedAppsOptionGroup
					.outdatedApps(considerAllOutdated: forceOptionGroup.force, withFullJSON: false)
					.map(\.installedApp.adamID),
			)
		}
```

### `mas.MAS.Update.run() async -> ()` at `0x10001d208`

swiftdc:

```swift
mas.MAS.Update.run() async -> () {
    // async function: 2 resume funclet(s): resume #1 @0x10001d35c, resume #2 @0x10001d4a4
    ArgumentParser.OptionGroup.wrappedValue.getter()
    mem128[x23] = self._forceOptionGroup[0..<16]; mem128[x23 + 0x10] = self._forceOptionGroup[16..<32]
    ArgumentParser.OptionGroup.wrappedValue.getter()
    ArgumentParser.Flag.wrappedValue.getter()
    sub_10001cab0(?, ?, ?)
    let awaited1 = await mas.OutdatedAppsOptionGroup.outdatedApps(considerAllOutdated:withFullJSON:)(self: (? + 192), ?, ?)
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Update param_1)
/* mas.MAS.Update.run() async -> () */

void __swift_stdcall mas::MAS::Update::_run(Update param_1)

{
  undefined1 uVar1;
  undefined1 auVar2 [16];
  Flag FVar3;
  long *plVar4;
  undefined8 in_x1;
  void *in_x2;
  undefined8 *unaff_x20;
  long unaff_x22;
  OutdatedAppsOptionGroup OVar5;
  undefined8 uVar6;
  undefined8 uVar7;
  undefined8 uVar8;
  undefined8 uVar9;
  undefined8 uVar10;
  undefined8 uVar11;
  undefined8 uVar12;
  OptionGroup OVar13;
  OptionGroup OVar14;
  
  *(undefined **)(unaff_x22 + 0x1b0) = param_1.unknown;
  *(undefined8 *)(unaff_x22 + 0x1b8) = in_x1;
  uVar7 = unaff_x20[0x14];
  uVar6 = unaff_x20[0x13];
  uVar8 = unaff_x20[0x15];
  uVar10 = unaff_x20[0x18];
  uVar9 = unaff_x20[0x17];
  *(undefined8 *)(unaff_x22 + 0x98) = unaff_x20[0x16];
  *(undefined8 *)(unaff_x22 + 0x90) = uVar8;
  *(undefined8 *)(unaff_x22 + 0xa8) = uVar10;
  *(undefined8 *)(unaff_x22 + 0xa0) = uVar9;
  uVar8 = unaff_x20[0x19];
  *(undefined8 *)(unaff_x22 + 0xb8) = unaff_x20[0x1a];
  *(undefined8 *)(unaff_x22 + 0xb0) = uVar8;
  uVar9 = unaff_x20[0xc];
  uVar8 = unaff_x20[0xb];
  uVar10 = unaff_x20[0xd];
  uVar12 = unaff_x20[0x10];
  uVar11 = unaff_x20[0xf];
  *(undefined8 *)(unaff_x22 + 0x58) = unaff_x20[0xe];
  *(undefined8 *)(unaff_x22 + 0x50) = uVar10;
  *(undefined8 *)(unaff_x22 + 0x68) = uVar12;
  *(undefined8 *)(unaff_x22 + 0x60) = uVar11;
  uVar10 = unaff_x20[0x11];
  *(undefined8 *)(unaff_x22 + 0x78) = unaff_x20[0x12];
  *(undefined8 *)(unaff_x22 + 0x70) = uVar10;
  *(undefined8 *)(unaff_x22 + 0x88) = uVar7;
  *(undefined8 *)(unaff_x22 + 0x80) = uVar6;
  uVar6 = unaff_x20[5];
  uVar10 = unaff_x20[8];
  uVar7 = unaff_x20[7];
  *(undefined8 *)(unaff_x22 + 0x18) = unaff_x20[6];
  *(undefined8 *)(unaff_x22 + 0x10) = uVar6;
  *(undefined8 *)(unaff_x22 + 0x28) = uVar10;
  *(undefined8 *)(unaff_x22 + 0x20) = uVar7;
  uVar6 = unaff_x20[9];
  *(undefined8 *)(unaff_x22 + 0x38) = unaff_x20[10];
  *(undefined8 *)(unaff_x22 + 0x30) = uVar6;
  *(undefined8 *)(unaff_x22 + 0x48) = uVar9;
  *(undefined8 *)(unaff_x22 + 0x40) = uVar8;
  auVar2 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutdatedAppsOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_OutdatedAppsOptionGroup>
                     );
  OVar13.title.bridgeObject = in_x2;
  OVar13._dummy = (bool)auVar2[0];
  OVar13._1_7_ = auVar2._1_7_;
  OVar13.title.str = (char *)auVar2._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar13);
  uVar6 = *unaff_x20;
  uVar8 = unaff_x20[3];
  uVar7 = unaff_x20[2];
  *(undefined8 *)(unaff_x22 + 0x160) = unaff_x20[1];
  *(undefined8 *)(unaff_x22 + 0x158) = uVar6;
  *(undefined8 *)(unaff_x22 + 0x170) = uVar8;
  *(undefined8 *)(unaff_x22 + 0x168) = uVar7;
  *(undefined8 *)(unaff_x22 + 0x178) = unaff_x20[4];
  auVar2 = ::___swift_instantiateConcreteTypeFromMangledNameV2
                     (&
                      __demangling_cache_variable_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceOptionGroup>
                      ,&
                       __mangled_name_ref_for_type_metadata_for_ArgumentParser_OptionGroup<mas_ForceOptionGroup>
                     );
  OVar14.title.bridgeObject = in_x2;
  OVar14._dummy = (bool)auVar2[0];
  OVar14._1_7_ = auVar2._1_7_;
  OVar14.title.str = (char *)auVar2._8_8_;
  ArgumentParser::OptionGroup::get_wrappedValue(OVar14);
  uVar6 = *(undefined8 *)(unaff_x22 + 0x180);
  uVar7 = *(undefined8 *)(unaff_x22 + 0x188);
  *(undefined8 *)(unaff_x22 + 0x198) = uVar6;
  *(undefined8 *)(unaff_x22 + 0x1a0) = uVar7;
  uVar1 = *(undefined1 *)(unaff_x22 + 400);
  *(undefined1 *)(unaff_x22 + 0x1a8) = uVar1;
  FVar3.unknown =
       (undefined *)
       ::___swift_instantiateConcreteTypeFromMangledNameV2
                 (&__demangling_cache_variable_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>
                  ,&__mangled_name_ref_for_type_metadata_for_ArgumentParser_Flag<Swift_Bool>);
  ArgumentParser::Flag::get_wrappedValue(FVar3);
  FUN_10001cab0(uVar6,uVar7,uVar1);
  OVar5.unknown._1_7_ = 0;
  OVar5.unknown._0_1_ = *(byte *)(unaff_x22 + 0x191);
  plVar4 = (long *)_swift_task_alloc(DAT_1005521e4);
  *(long **)(unaff_x22 + 0x1c0) = plVar4;
  *plVar4 = unaff_x22;
  plVar4[1] = (long)_run;
  OutdatedAppsOptionGroup::_outdatedApps(SUB81(param_1.unknown,0),SUB81(in_x1,0),OVar5);
  return;
}
```

## `MAS.Version.run`

From `Sources/mas/Commands/MAS.Version.swift`.

```swift
		func run() {
			printer.info(version)
		}
```

The binary keeps it only as the specialization below, a copy the optimizer rewrote for its callers.

### `function signature specialization <Arg[0] = Dead> of mas.MAS.Version.run() -> ()` at `0x10001e418`

swiftdc:

```swift
function signature specialization <Arg[0] = Dead> of mas.MAS.Version.run() -> () {
    if (x8 != -1) {
        swift_once(0x10060b908, one-time initialization function for printer, ?)
    }
    let r0 = [NSFileHandle fileHandleWithStandardOutput]
    generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_98, …)
    outlined init with copy of Any(local_70, local_b8)
    Swift.String.init<A>(describing:)(local_b8)
    if (x23 >=ᵁ (x8 >>ᵁ 1)) {
        generic specialization <Swift.String> of Swift.ContiguousArray._createNewBuffer(bufferIsUnique:minimumCapacity:growForAppend:)(self: local_98, …)
    }
    mem64[x20 + 0x10] = x21
    mem64[x8 + 0x20] = x0; mem64[x8 + 0x28] = x1
    function signature specialization <Arg[4] = Dead> of mas.Printer.(print in _13FF02662930BA0C33C74C7843D664F7)(_:separator:terminator:to:)(?, " ", 10, 0xe100000000000000, r0)
    return
}
```

Ghidra:

```c
// tuple0 __swift_stdcall $run(Version param_1)
/* WARNING: Function: _objc_opt_self replaced with injection: _objc_retain_fixup */
/* WARNING: Function: _objc_retainAutoreleasedReturnValue replaced with injection:
   _objc_retain_fixup */
/* WARNING: Function: _objc_release replaced with injection: _objc_release_fixup */
/* function signature specialization <Arg[0] = Dead> of mas.MAS.Version.run() -> () */

void __swift_stdcall mas::MAS::Version::_run(Version param_1)

{
  ulong uVar1;
  ID IVar2;
  ContiguousArray in_x3;
  undefined *puVar3;
  String SVar4;
  undefined1 auStack_b8 [32];
  undefined *local_98;
  undefined8 local_70;
  undefined8 uStack_68;
  undefined *local_58;
  
  if (__one_time_initialization_token_for_printer != -1) {
    _swift_once(&__one_time_initialization_token_for_printer,one_time_init_for_printer);
  }
  local_58 = PTR___type_metadata_for_Swift_String_1005fc368;
  local_70 = 0x2b;
  uStack_68 = 0xe100000000000000;
  IVar2 = NSFileHandle::fileHandleWithStandardOutput((ID)PTR__OBJC_CLASS___NSFileHandle_10060acd0);
  local_98 = PTR___swiftEmptyArrayStorage_1005fda60;
  ::Swift::ContiguousArray::_createNewBuffer(false,1,false,in_x3);
  puVar3 = local_98;
  __outlined_init_with_copy_of_Any(&local_70,auStack_b8);
  SVar4 = ::Swift::String::_init(auStack_b8,PTR___type_metadata_for_Any_1005fda48 + 8);
  uVar1 = *(ulong *)(puVar3 + 0x10);
  if (*(ulong *)(puVar3 + 0x18) >> 1 <= uVar1) {
    ::Swift::ContiguousArray::_createNewBuffer(1 < *(ulong *)(puVar3 + 0x18),uVar1 + 1,true,in_x3);
    puVar3 = local_98;
  }
  *(ulong *)(puVar3 + 0x10) = uVar1 + 1;
  *(String *)(puVar3 + uVar1 * 0x10 + 0x20) = SVar4;
  __function_signature_specialization_<Arg[4]___Dead>_of_mas_Printer__print_in__13FF02662930BA0C33C74C7843D664F7______Swift_String__separator__Swift_String_terminator__Swift_String_to____C_NSFileHandle___>___
            (puVar3,0x20,0xe100000000000000,10,0xe100000000000000,IVar2);
  _swift_release(puVar3);
  ___swift_destroy_boxed_opaque_existential_0Tm(&local_70);
  return;
}
```
