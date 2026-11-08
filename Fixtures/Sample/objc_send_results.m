__attribute__((noinline)) long consumeLong(long value) { return value + 1; }
struct SDRange { long location; long length; };
struct SDOne { long value; };
__attribute__((objc_root_class)) @interface SDStructResultProbe
- (struct SDRange)range:(long)value;
- (struct SDOne)one:(long)value;
- (long)scalar:(long)value;
- (long)location:(long)value;
- (long)length:(long)value;
- (long)oneField:(long)value;
- (long)scalarForward:(long)value;
- (long)consumeLocation:(long)value;
@end
@implementation SDStructResultProbe
- (struct SDRange)range:(long)value { return (struct SDRange){value, 42}; }
- (struct SDOne)one:(long)value { return (struct SDOne){value}; }
- (long)scalar:(long)value { return value; }
- (long)location:(long)value { return [self range:value].location; }
- (long)length:(long)value { return [self range:value].length; }
- (long)oneField:(long)value { return [self one:value].value; }
- (long)scalarForward:(long)value { return [self scalar:value]; }
- (long)consumeLocation:(long)value { return consumeLong([self range:value].location); }
@end
