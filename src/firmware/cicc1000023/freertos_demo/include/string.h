#ifndef FREERTOS_MINIMAL_STRING_H
#define FREERTOS_MINIMAL_STRING_H

#include <stddef.h>

void *memset(void *dst, int value, size_t len);
void *memcpy(void *dst, const void *src, size_t len);
int memcmp(const void *lhs, const void *rhs, size_t len);
size_t strlen(const char *s);

#endif
