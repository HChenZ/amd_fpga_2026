/* Test-only exports of the selected upstream/local permutation helpers.
 * No permutation or AEAD algorithm is reimplemented here. */
#include <stdint.h>
#include "permutations.h"

void golden_permute(uint64_t *out, const uint64_t *in, int rounds,
                    uint8_t constant) {
  ascon_state_t s;
  int i;
  for (i = 0; i < 5; ++i) s.x[i] = in[i];
  if (rounds == 1) ROUND(&s, constant);
  else if (rounds == 8) P8(&s);
  else if (rounds == 12) P12(&s);
  for (i = 0; i < 5; ++i) out[i] = s.x[i];
}
