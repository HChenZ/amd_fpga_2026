#include "puf_v2.h"
int puf_v2_generate(const struct puf_v2_io *io, int enroll, uint32_t polls) {
    struct puf_v2_status s;
    uint32_t id;
    if (!io || !io->status || !io->start || !io->clear || !polls ||
        (enroll != 0 && enroll != 1)) return PUF_V2_PROTOCOL;
    if (io->status(io->context, &s) || s.busy) return PUF_V2_PROTOCOL;
    id = s.transaction_id + 1u;
    if (io->start(io->context, enroll)) return PUF_V2_PROTOCOL;
    while (polls--) {
        if (io->status(io->context, &s)) break;
        if (s.transaction_id != id) continue;
        if (s.error) { io->clear(io->context); return PUF_V2_ERROR; }
        if (s.done && !s.busy) {
            if (s.key_ready) return PUF_V2_OK;
            io->clear(io->context); return PUF_V2_ERROR;
        }
    }
    io->clear(io->context);
    return PUF_V2_TIMEOUT;
}
