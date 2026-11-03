#include <assert.h>
#include <stdio.h>
#include "puf_v2.h"
struct mock { unsigned reads, starts, clears; int mode; };
static int status(void *ctx, struct puf_v2_status *s) {
    struct mock *m = ctx;
    ++m->reads;
    s->transaction_id = (m->reads < 4) ? 10 : 11;
    s->busy = (m->mode == 4);
    s->done = 1; s->key_ready = 1; s->error = 0;
    if (m->mode == 1 && m->reads >= 4) s->error = 0x84;
    if (m->mode == 2) s->transaction_id = 10; /* stale done */
    if (m->mode == 3 && m->reads >= 4) s->key_ready = 0;
    return 0;
}
static int start(void *ctx, int enroll) {
    struct mock *m = ctx; assert(enroll == 0 || enroll == 1); ++m->starts; return 0;
}
static int clear(void *ctx) { ++((struct mock *)ctx)->clears; return 0; }
int main(void) {
    struct mock m = {0,0,0,0};
    struct puf_v2_io io = {&m,status,start,clear};
    assert(puf_v2_generate(&io,0,8)==PUF_V2_OK);
    assert(m.reads==4 && m.starts==1 && m.clears==0);
    m=(struct mock){0,0,0,1}; assert(puf_v2_generate(&io,0,8)==PUF_V2_ERROR); assert(m.clears==1);
    m=(struct mock){0,0,0,2}; assert(puf_v2_generate(&io,0,3)==PUF_V2_TIMEOUT); assert(m.clears==1);
    m=(struct mock){0,0,0,3}; assert(puf_v2_generate(&io,1,8)==PUF_V2_ERROR); assert(m.clears==1);
    m=(struct mock){0,0,0,4}; assert(puf_v2_generate(&io,0,8)==PUF_V2_PROTOCOL); assert(m.starts==0);
    assert(puf_v2_generate(0,0,8)==PUF_V2_PROTOCOL);
    assert(puf_v2_generate(&io,2,8)==PUF_V2_PROTOCOL);
    puts("TEST_PASS test_firmware_v2"); return 0;
}
