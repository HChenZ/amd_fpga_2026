#include <stdarg.h>
#include <stddef.h>

#include "uart.h"

void *memset(void *dst, int value, size_t len)
{
    unsigned char *d = (unsigned char *) dst;

    for (size_t i = 0; i < len; i++)
    {
        d[i] = (unsigned char) value;
    }

    return dst;
}

void *memcpy(void *dst, const void *src, size_t len)
{
    unsigned char *d = (unsigned char *) dst;
    const unsigned char *s = (const unsigned char *) src;

    for (size_t i = 0; i < len; i++)
    {
        d[i] = s[i];
    }

    return dst;
}

int memcmp(const void *lhs, const void *rhs, size_t len)
{
    const unsigned char *l = (const unsigned char *) lhs;
    const unsigned char *r = (const unsigned char *) rhs;

    for (size_t i = 0; i < len; i++)
    {
        if (l[i] != r[i])
        {
            return (int) l[i] - (int) r[i];
        }
    }

    return 0;
}

size_t strlen(const char *s)
{
    const char *p = s;

    while (*p != '\0')
    {
        p++;
    }

    return (size_t) (p - s);
}

static void append_char(char *buffer, size_t length, size_t *used, char ch)
{
    if (*used + 1U < length)
    {
        buffer[*used] = ch;
    }

    (*used)++;
}

static void append_string(char *buffer, size_t length, size_t *used, const char *s)
{
    while (*s != '\0')
    {
        append_char(buffer, length, used, *s++);
    }
}

static void append_unsigned(char *buffer, size_t length, size_t *used, unsigned long value)
{
    char tmp[10];
    int pos = 0;

    do
    {
        tmp[pos++] = (char) ('0' + (value % 10UL));
        value /= 10UL;
    } while (value != 0UL);

    while (pos > 0)
    {
        append_char(buffer, length, used, tmp[--pos]);
    }
}

int snprintf(char *buffer, size_t length, const char *format, ...)
{
    va_list args;
    size_t used = 0;

    va_start(args, format);

    while (*format != '\0')
    {
        if (*format != '%')
        {
            append_char(buffer, length, &used, *format++);
            continue;
        }

        format++;
        if (*format == 's')
        {
            const char *s = va_arg(args, const char *);
            append_string(buffer, length, &used, s ? s : "(null)");
        }
        else if ((*format == 'u') || (*format == 'd'))
        {
            append_unsigned(buffer, length, &used, va_arg(args, unsigned int));
        }
        else if (*format == '%')
        {
            append_char(buffer, length, &used, '%');
        }
        else
        {
            append_char(buffer, length, &used, '%');
            append_char(buffer, length, &used, *format);
        }

        if (*format != '\0')
        {
            format++;
        }
    }

    va_end(args);

    if (length != 0U)
    {
        size_t term = (used < length) ? used : (length - 1U);
        buffer[term] = '\0';
    }

    return (int) used;
}

void _exit(int status)
{
    (void) status;
    uart_puts("_exit\n");
    for (;;)
    {
    }
}
