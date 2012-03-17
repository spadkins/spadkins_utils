
enum app_option_type {
    AO_STRING = 0,
    AO_BOOLEAN,
    AO_INT,
    AO_FLOAT,
    AO_DATE,
    AO_DATETIME
};

struct app_option {
    char *name;
    char  letter;
    enum app_option_type type;
    char *default_value;
    char *description;
    int   found;
    char *value;
    void *pvalue;
    int   ivalue;
    float fvalue;
};

/* returns next_arg_index */
extern int ao_parse_options(
    int    argc,
    char **argv,
    int    num_app_options,
    struct app_option *app_options
);

extern void ao_print_usage(void);
extern struct app_option *ao_get_option(char  *name);

