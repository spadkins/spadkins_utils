
#include <stdio.h>     /* printf() */
#include <stdlib.h>    /* exit(), malloc(), atoi(), atof() */
#include <string.h>    /* strcmp() */
#include <getopt.h>    /* getopt_long() */

#include "app_options.h"

/*******************************************************************************/
/* STATIC VARIABLES                                                            */
/*******************************************************************************/
static int gs_argc;
static char **gs_argv;
static int gs_num_app_options;
static struct app_option *gs_app_options;
static int gs_exit_with_usage = 0;

/*******************************************************************************/
/* STATIC FUNCTIONS                                                            */
/*******************************************************************************/

static int _build_options(
    int    num_app_options,
    struct app_option *app_options,
    struct option **long_options_ptr,
    char **short_options_ptr
)
{
    int num_long_options, len_short_options, aoi, soi, loi;
    char *short_options;
    struct option *long_options;

    num_long_options  = num_app_options + 1;      /* every app_option + "help" */
    len_short_options = 2 * num_app_options + 2;  /* every option can have a letter and an arg + '?' + terminator */

    short_options = (char *) malloc(len_short_options);
    long_options  = (struct option *) malloc(num_long_options * sizeof(struct option));

    soi = 0;
    loi = 0;

    for (aoi = 0; aoi < num_app_options; aoi++) {

        loi = aoi;
        long_options[loi].name    = app_options[aoi].name;
        long_options[loi].flag    = 0;
        long_options[loi].val     = 0;
        long_options[loi].has_arg = 1;
        if (app_options[aoi].type == AO_BOOLEAN)
            long_options[loi].has_arg = 0;

        if (app_options[aoi].letter) {
            if (app_options[aoi].type == AO_BOOLEAN) {
                short_options[soi]   = app_options[aoi].letter;
                short_options[soi+1] = 0;    /* null terminate the string */
                soi++;
            }
            else {
                short_options[soi]   = app_options[aoi].letter;
                short_options[soi+1] = ':';
                short_options[soi+2] = 0;    /* null terminate the string */
                soi += 2;
            }
        }
    }

    loi = num_app_options;
    long_options[loi].name    = "help";  /* we always support --help */
    long_options[loi].has_arg = 0;
    long_options[loi].flag    = 0;
    long_options[loi].val     = 0;
    short_options[soi]        = '?';  /* we always support -? */
    short_options[soi+1]      = 0;    /* null terminate the string */
    soi++;
    
    *short_options_ptr = short_options;
    *long_options_ptr  = long_options;

    return(num_long_options);
}

static void _parse_option_arg(struct app_option *app_option, char *optarg)
{
    app_option->value = optarg;
    app_option->ivalue = 0;
    app_option->fvalue = 0.0;

    if (app_option->type == AO_STRING) {
    }
    else if (app_option->type == AO_BOOLEAN) {
        if (optarg == NULL) {
            app_option->value = "1";
            app_option->ivalue = 1;
            app_option->fvalue = 1;
        }
        else {
            app_option->ivalue = atoi(optarg);
            app_option->fvalue = app_option->ivalue;
        }
    }
    else if (app_option->type == AO_INT) {
        if (optarg == NULL) {
            app_option->ivalue = 0;
            app_option->fvalue = 0.0;
        }
        else {
            app_option->ivalue = atoi(optarg);
            app_option->fvalue = app_option->ivalue;
        }
    }
    else if (app_option->type == AO_FLOAT) {
        if (optarg == NULL) {
            app_option->ivalue = 0;
            app_option->fvalue = 0.0;
        }
        else {
            app_option->fvalue = atof(optarg);
            app_option->ivalue = app_option->fvalue;
        }
    }
    else if (app_option->type == AO_DATE) {
    }
    else if (app_option->type == AO_DATETIME) {
    }
}

static void _process_long_option(
    struct option *long_option,
    char  *optarg
)
{
    int aoi;
    for (aoi = 0; aoi < gs_num_app_options; aoi++) {
        if (strcmp(gs_app_options[aoi].name, long_option->name) == 0) {
            _parse_option_arg(&gs_app_options[aoi], optarg);
        }
    }

    /*
    printf ("process long option %s", long_option->name);
    if (optarg)
        printf (" with arg %s", optarg);
    printf ("\n");
    */

    if (strcmp(long_option->name, "help") == 0) {
        gs_exit_with_usage = 1;
    }
}

static void _process_short_option(
    char   option_letter,
    char  *optarg
)
{
    int aoi;
    for (aoi = 0; aoi < gs_num_app_options; aoi++) {
        if (gs_app_options[aoi].letter == option_letter) {
            _parse_option_arg(&gs_app_options[aoi], optarg);
        }
    }

    /*
    printf ("process short option %c", option_letter);
    if (optarg)
        printf (" with arg %s", optarg);
    printf ("\n");
    */

    if (option_letter == '?') {
        gs_exit_with_usage = 1;
    }
}

/*******************************************************************************/
/* EXTERNAL FUNCTIONS                                                          */
/*******************************************************************************/

extern int ao_parse_options(
    int    argc,
    char **argv,
    int    num_app_options,
    struct app_option *app_options
)
{
    int c;
    int next_argv_index, num_long_options, aoi;
    char *short_options, *value;
    struct option *long_options;

    gs_argc            = argc;
    gs_argv            = argv;
    gs_num_app_options = num_app_options;
    gs_app_options     = app_options;

    num_long_options = _build_options(num_app_options, app_options, &long_options, &short_options);

    next_argv_index = 1;  /* skip over the command */
    while (1) {
        int option_index = 0;

        c = getopt_long(argc, argv, short_options, long_options, &option_index);
        next_argv_index = optind;

        if (c == -1) {
            break;  /* end of option parsing */
        }
        else if (c == 0) {
            _process_long_option(&long_options[option_index], optarg);
        }
        else {
            _process_short_option(c, optarg);
        }
    }

    /* handle defaults */
    for (aoi = 0; aoi < gs_num_app_options; aoi++) {
        value = gs_app_options[aoi].value;
        if (value == NULL) {
            if (gs_app_options[aoi].default_value == NULL && gs_app_options[aoi].type == AO_BOOLEAN) {
                _parse_option_arg(&gs_app_options[aoi], "0");
            }
            else {
                _parse_option_arg(&gs_app_options[aoi], gs_app_options[aoi].default_value);
            }
        }
    }

    if (gs_exit_with_usage) {
        ao_print_usage();
        exit(0);
    }

    return(next_argv_index);
}

void ao_print_usage(void)
{
    int aoi;
    char *value;
    char opt[256];
    printf("Usage: %s [options] [args]\n", gs_argv[0]);
    for (aoi = 0; aoi < gs_num_app_options; aoi++) {
        value = gs_app_options[aoi].value;
        if (value == NULL) value = "NULL";

        if (gs_app_options[aoi].type == AO_BOOLEAN) sprintf(opt, "%s", gs_app_options[aoi].name);
        else                                        sprintf(opt, "%s=<arg>", gs_app_options[aoi].name);
        printf("   --%-20s   [%s]", opt, value);

        if (gs_app_options[aoi].type == AO_STRING) printf(" (string)");
        else if (gs_app_options[aoi].type == AO_BOOLEAN) printf(" (boolean)");
        else if (gs_app_options[aoi].type == AO_INT) printf(" (int)");
        else if (gs_app_options[aoi].type == AO_FLOAT) printf(" (float)");
        else if (gs_app_options[aoi].type == AO_DATE) printf(" (date)");
        else if (gs_app_options[aoi].type == AO_DATETIME) printf(" (datetime)");

        if (gs_app_options[aoi].letter) printf(" (synonym for -%c)", gs_app_options[aoi].letter);
        printf(" %s\n", gs_app_options[aoi].description);
    }
}

struct app_option *ao_get_option(char  *name)
{
    int aoi;
    struct app_option *app_option_ptr;

    app_option_ptr = (struct app_option *) NULL;
    for (aoi = 0; aoi < gs_num_app_options; aoi++) {
        if (strcmp(name, gs_app_options[aoi].name) == 0) {
            app_option_ptr = &gs_app_options[aoi];
            break;
        }
    }
    return(app_option_ptr);
}

