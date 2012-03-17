
#include <stdio.h>
#include "app_options.h"

#define BUFLEN          1024
#define SHORT_CHARS_PER_LINE  16
#define LONG_CHARS_PER_LINE   100

/*
      char *fgets(char *s, int size, FILE *stream);
      fgets() reads in at most one less than size characters from stream  and
      stores  them  into  the buffer pointed to by s.  Reading stops after an
      EOF or a newline.  If a newline is read, it is stored into the  buffer.
      A '\0' is stored after the last character in the buffer.

       ssize_t read(int fd, void *buf, size_t count);
       read()  attempts to read up to count bytes from file descriptor fd into
       the buffer starting at buf.
       If count is zero, read() returns zero and has  no  other  results.   If
       count is greater than SSIZE_MAX, the result is unspecified.
*/

static struct app_option app_options[] = {
    { "width", 'w', AO_INT, "16", "the number of bytes per line" },
    { "text",  't', AO_BOOLEAN, NULL, "text only (not hex)" }
};
static int num_app_options = sizeof(app_options)/sizeof(struct app_option);

int main(int argc, char **argv)
{
    char buf[BUFLEN];
    int len, filepos, linepos, charpos, pos;
    int ch, i, no_hex, chars_per_line;

    ao_parse_options(argc, argv, num_app_options, app_options);

    chars_per_line = ao_get_option("width")->ivalue;
    no_hex         = ao_get_option("text")->ivalue;

    filepos = 0;
    while (len = read(0, buf, BUFLEN)) {
        for (linepos = 0; linepos < len; linepos += chars_per_line) {
            printf("%08X> ", filepos + linepos);
            if (!no_hex) {
                for (charpos = 0; charpos < chars_per_line; charpos++) {
                    pos = linepos + charpos;
                    if (pos >= len) {
                        printf("  ");
                    }
                    else  {
                        ch = buf[pos] & 0xff;
                        printf("%02X", ch);
                    }
                    if (charpos % 2 == 1) {
                        printf(" ");
                    }
                }
                printf("  ");
            }
            for (charpos = 0; charpos < chars_per_line; charpos++) {
                pos = linepos + charpos;
                if (pos >= len) {
                    printf(" ");
                }
                else  {
                    ch = buf[pos] & 0xff;
                    if (ch < 0x20 || ch >= 0x7f) {
                        printf(".");
                    }
                    else {
                        printf("%c", ch);
                    }
                }
                if (charpos % 8 == 7) {
                    printf(" ");
                }
            }
            printf("\n");
        }
        filepos += len;
    }
}

