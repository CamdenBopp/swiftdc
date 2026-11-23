#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdalign.h>
extern void *__swift_project_boxed_opaque_existential_0(void *, void *);
extern void *__swift_project_boxed_opaque_existential_1(void *, void *);
int main(void) {
    void *(*helpers[])(void *, void *) = {__swift_project_boxed_opaque_existential_0, __swift_project_boxed_opaque_existential_1};
    const unsigned masks[] = {0,1,3,7,15,31,63,127,255};
    unsigned observations = 0;
    for (unsigned f=0; f<2; ++f) for (unsigned boxed=0; boxed<2; ++boxed)
    for (unsigned i=0; i<sizeof(masks)/sizeof(*masks); ++i) {
        alignas(256) unsigned char heap[1024], oldheap[1024];
        uintptr_t witness[16], oldwitness[16], metadata[2], oldmetadata[2];
        uintptr_t container[4], oldcontainer[4];
        memset(heap, 0x5a, sizeof heap);
        for (unsigned j=0; j<16; ++j) witness[j]=0xabc000+j;
        witness[10] = (boxed ? (1u<<17) : 0) | masks[i];
        metadata[0] = (uintptr_t)witness; metadata[1]=0x1234;
        container[0]=(uintptr_t)heap; container[1]=23;container[2]=29;container[3]=31;
        memcpy(oldheap,heap,sizeof heap); memcpy(oldwitness,witness,sizeof witness);
        memcpy(oldmetadata,metadata,sizeof metadata); memcpy(oldcontainer,container,sizeof container);
        void *actual=helpers[f](container,&metadata[1]);
        void *expected=boxed ? (void *)(heap+((16u+masks[i])&~masks[i])) : (void *)container;
        if (actual!=expected || memcmp(oldcontainer,container,sizeof container)
            || memcmp(oldwitness,witness,sizeof witness) || memcmp(oldmetadata,metadata,sizeof metadata)
            || memcmp(oldheap,heap,sizeof heap)) {
            fprintf(stderr,"FAIL shape=%u boxed=%u mask=%u\n",f,boxed,masks[i]);return 1;
        }
        ++observations;
    }
    printf("PASS %u projection pointer and no-write observations\n", observations);
    return 0;
}
