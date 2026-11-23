// In-image functions that share the Swift runtime's access-marker names
// and nothing else. Each writes the object's first stored field, at
// offset 16 of a Swift class instance. See accesstwin.swift.
void swift_beginAccess(long *object, void *buffer, long flags, void *pc) { object[2] = 19; }
void swift_endAccess(long *object) { object[2] = 23; }
