#ifndef PUF_V2_H
#define PUF_V2_H
#include <stdint.h>
/* Transport-neutral HAL. No MMIO address is allocated by this prototype.
 * Platform adapters must expose atomic status/id snapshots and trusted helper
 * provisioning. No API reads the internal key. */
enum { PUF_V2_ABI = 2, PUF_V2_OK = 0, PUF_V2_ERROR = -1,
       PUF_V2_TIMEOUT = -2, PUF_V2_PROTOCOL = -3 };
struct puf_v2_status {
    uint32_t transaction_id;
    uint8_t busy, done, key_ready, error;
};
struct puf_v2_io {
    void *context;
    int (*status)(void *, struct puf_v2_status *);
    int (*start)(void *, int enroll);
    int (*clear)(void *);
};
/* Bounded polls, never silent reenrollment or DNA-only fallback. On failure,
 * clear revokes readiness and resets sampling; it retains diagnostic helper. */
int puf_v2_generate(const struct puf_v2_io *io, int enroll, uint32_t polls);
#endif
