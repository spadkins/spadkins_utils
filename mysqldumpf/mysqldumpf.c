
#include <stdio.h>
#include "app_options.h"

#define KILO                          1024
#define MEGA                          KILO*KILO
#define BUFSIZE                       32*MEGA

#define MAX_COLUMNS                   255
#define MAX_COLUMN_LEN                32
#define MAX_UPDATE_CLAUSE_LEN         (MAX_COLUMNS*(MAX_COLUMN_LEN*2 + 13))
#define MAX_INSERT_COLUMNS_BUF_LEN    ((MAX_COLUMNS+1)*(MAX_COLUMN_LEN+1))

#define NO_IDX                        -1

static struct app_option app_options[] = {
    // { "tablename",      't', AO_STRING,  NULL, "name of table this data will be imported to instead of the original table" },
    // { "tabletype",      'y', AO_STRING,  NULL, "storage engine of the table this data will be imported to (MyISAM, InnoDB)" },
    { "columns-override",  'C', AO_STRING,  NULL, "the names of the columns to be used instead of the columns in the file" },
    { "columns-subset",    'S', AO_STRING,  NULL, "the list of columns to be retained in the output" },
    { "columns-removed",   'R', AO_STRING,  NULL, "the list of columns to be removed from the output (ignored if --columns_subset used)" },
    { "columns-added",     'A', AO_STRING,  NULL, "the list of columns to be added to the output (i.e. --columns-added=foo_id,bar" },
    { "column-values-added",'V',AO_STRING,  NULL, "the list of values for the columns to be added to the output (i.e. \"1,'baz'\")" },
    { "columns-updated",   'U', AO_STRING,  NULL, "the list of columns to be updated if the row already exists" },
    { "skip-update",       's', AO_BOOLEAN, NULL, "adds on 'on duplicate key update' clause, does nothing if collision (i.e. updates the last column to itself)" },
    { "update-keys",       'k', AO_STRING,  NULL, "adds on 'on duplicate key update' clause, excluding update on the named key columns (as comma-sep list)" },
    { "update-columns",    'c', AO_STRING,  NULL, "adds on 'on duplicate key update' clause, including update on only the named key columns (as comma-sep list)" },

    // These should not be in the final product. They are here for backward compatibility with earlier versions.
    { "update_mdttm",       0,  AO_BOOLEAN, NULL, "adds on 'on duplicate key update' clause setting modify_dttm column to itself (noop)" },
    { "update_rate",        0,  AO_BOOLEAN, NULL, "adds on 'on duplicate key update' clause for hotel_rate tables" },
    { "update_rate_ih",     0,  AO_BOOLEAN, NULL, "adds on 'on duplicate key update' clause for hotel_rate_ih tables" },
    { "update_mkt_rate",    0,  AO_BOOLEAN, NULL, "adds on 'on duplicate key update' clause for hotel_mkt_rate tables" },
    { "update_mkt_rate_ih", 0,  AO_BOOLEAN, NULL, "adds on 'on duplicate key update' clause for hotel_mkt_rate_ih tables" },

    { "skip-hints",         0,  AO_BOOLEAN, NULL, "removes all text containing hints from before or after the insert statements" },
    { "esc-ampersand",     'a', AO_BOOLEAN, NULL, "escapes ampersands (&) with a backslash (\\) in quotes" },
    // { "remove_id",      'r', AO_BOOLEAN, NULL, "remove the first column from the data" },
    { "silent",             0,  AO_BOOLEAN, NULL, "inhibit the printing of a count of the insert rows on stderr" },
    { "test",               0,  AO_BOOLEAN, NULL, "run tests instead of running the program" },
    { "debug",             'd', AO_BOOLEAN, NULL, "print lots of debug output about the chunks of input being processed" },
    // { "compress",       'z', AO_BOOLEAN, NULL, "compress the last field in the row when it is restored" }
};
static int num_app_options = sizeof(app_options)/sizeof(struct app_option);

// #################################################################
// # STATES:
// #################################################################
// # 0 - before the insert statement begins
// # 1 - inside the insert statement
// # 2 - after the insert statement finishes
// #################################################################

enum mdf_state {
    MDF_BEFORE_INSERTS = 0,
    MDF_INSIDE_INSERTS,
    MDF_AFTER_INSERTS
};

struct mdf_input {
    char  *buf;
    int   bufsize, bufchars, bufpos, bufinc, lastreadlen, debug;
};

struct mdf_output {
    char  *buf;
    int   bufsize, bufchars, debug;
};

static void  _input_init(struct mdf_input *input);
static int   _input_refill(struct mdf_input *input);
static int   _input_done(struct mdf_input *input);
static int   _skip_string_n(struct mdf_input *input, char *str, int n);
static int   _skip_n(struct mdf_input *input, int n);
static int   _skip_space(struct mdf_input *input);
static int   _skip_char(struct mdf_input *input, char skip_char);
static int   _read_n(struct mdf_input *input, int n, char **str_ptr);
static int   _read_word(struct mdf_input *input, char **str_ptr);
static int   _read_string_n(struct mdf_input *input, char *str, int n, char **str_ptr);
static int   _read_up_to_string_n(struct mdf_input *input, char *str, int n, char **str_ptr);
static int   _read_insert_values(struct mdf_input *input, char **str_ptr);
static int   _read_write_insert_values(struct mdf_input *input, struct mdf_output *output, char **str_ptr, short *subset_map, char *column_values_added);
static int   _nextchar(struct mdf_input *input, int offset);
static void  _output_init(struct mdf_output *output);
static int   _write(struct mdf_output *output, char *buf, int n);
static void  _flush(struct mdf_output *output);
static void  _die (struct mdf_output *output, char *msg);

static char **array_new(char *buf, int nchars, char *sep);
static int    array_size(char **array);
static char **array_copy(char **array);
static char **array_copy_deleting_some(char **array, char **delete_array);
static int    array_map(char **array, char **subset_array, short *subset_map);
static void   array_print(char **array);
static char  *array_join(char **array, char *sep);

static void   run_regression_tests (void);

static int    debug = 0;

int main(int argc, char **argv)
{
    struct mdf_input input;
    struct mdf_output output;
    int    ch, i, fieldnum;
    int    use_update_clause, state, chars_read, chars_written, skip_hints;
    int    update_mdttm, update_rate, update_rate_ih, update_mkt_rate, update_mkt_rate_ih;
    char  *buf, update_clause[MAX_UPDATE_CLAUSE_LEN], *p, insert_columns_buf[MAX_INSERT_COLUMNS_BUF_LEN];
    short  subset_map[MAX_COLUMNS+1];
    int    subset_used = 0;

    char  *tablename, *table;
    char  *tabletype;
    int    skip_update, remove_id, test, compress, silent;
    int    insert_record_count;

    ao_parse_options(argc, argv, num_app_options, app_options);

	// tablename          = ao_get_option("tablename")->value;
    // tabletype          = ao_get_option("tabletype")->value;
    skip_hints         = ao_get_option("skip-hints")->ivalue;
    skip_update        = ao_get_option("skip-update")->ivalue;

    update_mdttm       = ao_get_option("update_mdttm")->ivalue;
    update_rate        = ao_get_option("update_rate")->ivalue;
    update_rate_ih     = ao_get_option("update_rate_ih")->ivalue;
    update_mkt_rate    = ao_get_option("update_mkt_rate")->ivalue;
    update_mkt_rate_ih = ao_get_option("update_mkt_rate_ih")->ivalue;

    test               = ao_get_option("test")->ivalue;
    debug              = ao_get_option("debug")->ivalue;
    silent             = ao_get_option("silent")->ivalue;
    // remove_id          = ao_get_option("remove_id")->ivalue;
    // compress           = ao_get_option("compress")->ivalue;

    if (test) {
        run_regression_tests();
        exit(0);
    }

    char *update_keys      = ao_get_option("update-keys")->value;
    char *update_columns   = ao_get_option("update-columns")->value;
    char *columns_override = ao_get_option("columns-override")->value;
    char *columns_subset   = ao_get_option("columns-subset")->value;
    char *columns_removed  = ao_get_option("columns-removed")->value;
    char *columns_added    = ao_get_option("columns-added")->value;
    char *column_values_added = columns_added ? ao_get_option("column-values-added")->value : (char *) NULL;
    char *columns_updated  = ao_get_option("columns-updated")->value;

    char **columns_array          = (char **) NULL;
    char **columns_subset_array   = (char **) NULL;
    char **columns_removed_array  = (char **) NULL;
    char **retained_columns_array = (char **) NULL;
    char **update_columns_array   = (char **) NULL;
    char **keys_array             = (char **) NULL;

    char  *insert_columns = (char *) NULL;
    int    insert_columns_nchars = 0;
    int    retained_columns_size = 0;

    _input_init(&input);
    _output_init(&output);

    state             = MDF_BEFORE_INSERTS;
    use_update_clause = (skip_update || update_columns || update_keys || update_mdttm || update_rate || update_rate_ih || update_mkt_rate_ih || update_mkt_rate);
    update_clause[0]  = 0;  /* null terminate */

/*
INSERT INTO `hotel_chain` (`chain_id`, `chain_cd`, `chain_nm`, `data_source`, `prov_cd`, `segment_cd`, `modify_dttm`) VALUES (553,'AA','Americinns International','VAA',NULL,NULL,'0000-00-00 00:00:00'),(554,'AB','Abba','VAB',NULL,NULL,'0000-00-00 00:00:00'),(555,'AC','Atel',NULL,NULL,NULL,'0000-00-00 00:00:00'),(556,'AE','Amerihost Inn Hotels','VAE',NULL,NULL,'0000-00-00 00:00:00'),(557,'AH','Aston','VAH','AH',NULL,'0000-00-00 00:00:00'),(558,'AJ','Amerisui ... 'VI','Vista Inns','VVI',NULL,NULL,'2008-05-22 18:23:52');
/@!40000 ALTER TABLE `hotel_chain` ENABLE KEYS @/;
/@!40103 SET TIME_ZONE=@OLD_TIME_ZONE @/;

*/
    insert_record_count = 0;
    while (!_input_done(&input)) {  /* characters could remain or do remain */
        
        if (state == MDF_BEFORE_INSERTS) {
            if (debug) fprintf(stderr, "state 0: before INSERT\n");
            chars_read    = _read_up_to_string_n(&input, "INSERT INTO ", 12, &buf);
            if (!skip_hints)
                chars_written = _write(&output, buf, chars_read);

            state = MDF_INSIDE_INSERTS;
        }

        // INSERT INTO `hotel_chain` (`chain_id`, `chain_cd`, `chain_nm`, `data_source`, `prov_cd`, `segment_cd`, `modify_dttm`) VALUES (553,...
        if (state == MDF_INSIDE_INSERTS) {
            chars_read    = _read_string_n(&input, "INSERT INTO ", 12, &buf);
            chars_written = _write(&output, buf, chars_read);

            chars_read    = _read_string_n(&input, "`", 1, &buf);
            // chars_written = _write(&output, buf, chars_read);

            chars_read    = _read_word(&input, &buf);
            chars_written = _write(&output, buf, chars_read);

            chars_read    = _read_string_n(&input, "`", 1, &buf);
            // chars_written = _write(&output, buf, chars_read);
            
            chars_read    = _read_string_n(&input, " (", 2, &buf);    // The beginning of the column list
            if (chars_read > 0) {
                chars_written = _write(&output, buf, chars_read);

                chars_read    = _read_up_to_string_n(&input, ")", 1, &buf);
                if (! insert_columns) {  // if we've never seen it before, parse it and save it
                    if (columns_override) {
                        columns_array = array_new(columns_override, strlen(columns_override), ",` ");
                    }
                    else {
                        columns_array = array_new(buf, chars_read, ",` ");
                    }

                    if (columns_subset) {
                        columns_subset_array = array_new(columns_subset, 0, ", ");
                        _die(&output, "ERROR: --columns_subset not yet implemented.\n");
                    }
                    else if (columns_removed) {
                        columns_removed_array = array_new(columns_removed, 0, ", ");
                        retained_columns_array = array_copy_deleting_some(columns_array, columns_removed_array);
                        array_map(columns_array, retained_columns_array, subset_map);
                        subset_used = 1;
                    }
                    else {
                        retained_columns_array = columns_array;
                    }
                    retained_columns_size = array_size(retained_columns_array);

                    if (columns_added) {
                        if (column_values_added) {
                            strcpy(insert_columns_buf, columns_added);
                            strcat(insert_columns_buf, ",");
                            p = array_join(retained_columns_array, ", ");
                            strcat(insert_columns_buf, p);
                            insert_columns = insert_columns_buf;
                        }
                        else {
                            _die(&output, "ERROR: --columns-values-added must be supplied with --columns-added\n");
                        }
                    }
                    else {
                        insert_columns = array_join(retained_columns_array, ", ");
                    }
                    insert_columns_nchars = strlen(insert_columns);
                }
                chars_written = _write(&output, insert_columns, insert_columns_nchars);

                if (use_update_clause && !update_clause[0]) {

                    if (skip_update) {
                        if (retained_columns_size > 0) {
                            strcat(update_clause, "on duplicate key update ");
                            p = retained_columns_array[retained_columns_size-1];
                            strcat(update_clause, p);
                            strcat(update_clause, " = ");
                            strcat(update_clause, p);
                        }
                        else {
                            _die(&output, "ERROR: --skip_update option used but column list is unknown.\n");
                        }
                    }
                    else {
                        if (update_columns) {
                            update_columns_array = array_new(update_columns, 0, ", ");
                        }
                        else if (update_keys) {
                            keys_array = array_new(update_keys, 0, ", ");
                            update_columns_array = array_copy_deleting_some(retained_columns_array, keys_array);
                        }

                        if (update_columns_array) {
                            strcat(update_clause, "on duplicate key update ");
                            for (i = 0, p = update_columns_array[i]; p; i++, p = update_columns_array[i]) {
                                if (i > 0) strcat(update_clause, ", ");
                                strcat(update_clause, p);
                                strcat(update_clause, " = values(");
                                strcat(update_clause, p);
                                strcat(update_clause, ")");
                            }
                        }
                    }
                }

                chars_read    = _read_string_n(&input, ")", 1, &buf);
                chars_written = _write(&output, buf, chars_read);
            }
            else {
                _die(&output, "ERROR: override columns not yet supported. Insert statements must have the columns supplied currently.\n");
            }

            if (debug) fprintf(stderr, "BEGIN-OF-INSERT(1) update=[%d] update_rate=[%d] update_rate_ih=[%d] update_mkt=[%d] update_mkt_ih=[%d] update_clause=[%s]\n", use_update_clause, update_rate, update_rate_ih, update_mkt_rate, update_mkt_rate_ih, update_clause);
            if (use_update_clause && update_clause[0] == 0) {
                if (update_rate) {
                    strcat(update_clause, "on duplicate key update shop_request_id = values(shop_request_id), org_id = values(org_id), prop_id = values(prop_id), shop_data_source = values(shop_data_source), shop_currency_cd = values(shop_currency_cd), shop_pos_cd = values(shop_pos_cd), los = values(los), guests = values(guests), arv_dt = values(arv_dt), change_dttm = values(change_dttm), shop_status = values(shop_status), shop_dttm = values(shop_dttm), shop_msg = values(shop_msg), err_dttm = values(err_dttm), err_msg = values(err_msg), chain_cd = values(chain_cd), currency_cd = values(currency_cd), pos_cd = values(pos_cd), data = values(data), modify_dttm = values(modify_dttm)");
                }
                else if (update_rate_ih) {
                    strcat(update_clause, "on duplicate key update rate_id = values(rate_id), shop_request_id = values(shop_request_id), org_id = values(org_id), prop_id = values(prop_id), shop_data_source = values(shop_data_source), shop_currency_cd = values(shop_currency_cd), shop_pos_cd = values(shop_pos_cd), los = values(los), guests = values(guests), arv_dt = values(arv_dt), change_dttm = values(change_dttm), obsolete_dttm = values(obsolete_dttm), shop_status = values(shop_status), shop_dttm = values(shop_dttm), shop_msg = values(shop_msg), err_dttm = values(err_dttm), err_msg = values(err_msg), chain_cd = values(chain_cd), currency_cd = values(currency_cd), pos_cd = values(pos_cd), data = values(data), modify_dttm = values(modify_dttm)");
                }
                else if (update_mkt_rate) {
                    strcat(update_clause, "on duplicate key update shop_request_id = values(shop_request_id), org_id = values(org_id), mkt_keyword = values(mkt_keyword), shop_data_source = values(shop_data_source), shop_currency_cd = values(shop_currency_cd), qualifier = values(qualifier), los = values(los), guests = values(guests), arv_dt = values(arv_dt), shop_level = values(shop_level), change_dttm = values(change_dttm), shop_status = values(shop_status), shop_dttm = values(shop_dttm), shop_msg = values(shop_msg), err_dttm = values(err_dttm), err_msg = values(err_msg), data = values(data), modify_dttm = values(modify_dttm)");
                }
                else if (update_mkt_rate_ih) {
                    strcat(update_clause, "on duplicate key update shop_request_id = values(shop_request_id), org_id = values(org_id), mkt_keyword = values(mkt_keyword), shop_data_source = values(shop_data_source), shop_currency_cd = values(shop_currency_cd), qualifier = values(qualifier), los = values(los), guests = values(guests), arv_dt = values(arv_dt), shop_level = values(shop_level), change_dttm = values(change_dttm), obsolete_dttm = values(obsolete_dttm), shop_status = values(shop_status), shop_dttm = values(shop_dttm), shop_msg = values(shop_msg), err_dttm = values(err_dttm), err_msg = values(err_msg), data = values(data), modify_dttm = values(modify_dttm)");
                }
                else {
                    strcat(update_clause, "on duplicate key update modify_dttm = modify_dttm");
                    // s = buf2str(buf, n);
                }
            }
            if (debug) fprintf(stderr, "BEGIN-OF-INSERT(2) update=[%d] update_rate=[%d] update_rate_ih=[%d] update_mkt=[%d] update_mkt_ih=[%d] update_clause=[%s]\n", use_update_clause, update_rate, update_rate_ih, update_mkt_rate, update_mkt_rate_ih, update_clause);
            
            chars_read    = _read_up_to_string_n(&input, " VALUES ", 8, &buf);
            chars_written = _write(&output, buf, chars_read);

            chars_read    = _read_string_n(&input, " VALUES", 7, &buf);
            _skip_char(&input, ' ');
            chars_written = _write(&output, buf, chars_read);
            chars_written = _write(&output, "\n", 1);

            while (1) {
                if (subset_used) {
                    chars_read = _read_write_insert_values(&input, &output, &buf, subset_map, column_values_added);
                }
                else {
                    chars_read    = _read_insert_values(&input, &buf);
                    chars_written = _write(&output, buf, chars_read);
                }

                if (buf[chars_read-1] == ')') {
                    insert_record_count++;
                }

                if (chars_read = _read_string_n(&input, ";\n", 2, &buf)) {
                    if (debug) fprintf(stderr, "END-OF-INSERT update=[%d] update_rate=[%d] update_rate_ih=[%d] update_mkt=[%d] update_mkt_ih=[%d] update_clause=[%s]\n", use_update_clause, update_rate, update_rate_ih, update_mkt_rate, update_mkt_rate_ih, update_clause);
                    chars_written = _write(&output, "\n", -1);
                    if (use_update_clause) {
                        chars_written = _write(&output, update_clause, -1);
                    }
                    chars_written = _write(&output, ";\n", 2);
                    if (_nextchar(&input, 0) == '/')
                        state = MDF_AFTER_INSERTS;
                    break;
                }
                else if (chars_read = _read_string_n(&input, ",", 1, &buf)) {
                    chars_written = _write(&output, ",\n", 2);
                }
                else {
                    _die(&output, "ERROR: insert values not followed by comma or semi-colon\n");
                }
                if (chars_read == 0) {
                    _die(&output, "ERROR: weird state while reading inserts. exiting...\n");
                }
            }
        }
        if (state == MDF_AFTER_INSERTS) {
            chars_read    = _read_n(&input, BUFSIZE, &buf);
            if (!skip_hints)
                chars_written = _write(&output, buf, chars_read);
        }
    }
    _flush(&output);
    if (!silent) fprintf(stderr, "%d\n", insert_record_count);
}

static void _input_init(struct mdf_input *input) {
    input->buf      = (char *) malloc(BUFSIZE);
    input->bufpos   = 0;
    input->bufchars = 0;
    input->bufsize  = BUFSIZE;
    input->lastreadlen = 1;
    input->debug    = ao_get_option("debug")->ivalue;
}

static int _input_done(struct mdf_input *input) {
    int done;
    _input_refill(input);
    done = (input->bufpos >= input->bufchars);
    return(done);
}

static int _input_refill(struct mdf_input *input) {
    int chars_refilled = 0;
    int chars_read;

    /* if we have never started, we need to read some data in */
    /* if we are half way through and we read the full amount last time, we need to read some more data in */
    if ((input->bufchars < input->bufsize || (input->bufchars == input->bufsize && input->bufpos >= input->bufsize/2)) && input->lastreadlen) {
        if (input->bufpos > 0) {
            memmove(input->buf, input->buf + input->bufpos, input->bufchars - input->bufpos);
            input->bufchars -= input->bufpos;
            input->bufpos    = 0;
        }
        input->lastreadlen = 0;
        while (1) {
            chars_read = read(0, input->buf + input->bufchars, input->bufsize - input->bufchars);
            if (input->debug) fprintf(stderr, "_refill(): read(0, buf, %d) = %d\n", input->bufsize - input->bufchars, chars_read);
            input->bufchars += chars_read;
            chars_refilled += chars_read;
            input->lastreadlen += chars_read;
            if (input->bufsize == input->bufchars || chars_read == 0) break;
        }
    }

    return(chars_refilled);
}

static int   _skip_string_n(struct mdf_input *input, char *str, int n) {
    int chars_skipped;
    if (input->bufpos + n > input->bufchars) {
        chars_skipped = 0;
    }
    else if (memcmp(input->buf + input->bufpos, str, n) == 0) {
        chars_skipped = n;
        input->bufpos += chars_skipped;
    }
    else {
        chars_skipped = 0;
    }
    return(chars_skipped);
}

static int   _skip_n(struct mdf_input *input, int n) {
    int chars_skipped;
    if (input->bufpos + n > input->bufchars) _input_refill(input);
    if (input->bufpos + n > input->bufchars) {
        chars_skipped = input->bufchars - input->bufpos;
        input->bufpos = input->bufchars;
    }
    else {
        chars_skipped = n;
        input->bufpos += n;
    }
    if (input->debug) fprintf(stderr, "input: _skip_n(%d) = %d\n", n, chars_skipped);
    return(chars_skipped);
}

static int   _skip_space(struct mdf_input *input) {
    int chars_skipped = 0;
    while (input->bufpos <= input->bufchars) {
        if (input->bufpos == input->bufchars) {
            if (input->lastreadlen > 0) {
                _input_refill(input);
            }
            else {
                break;
            }
        }
        else if (input->buf[input->bufpos] == ' ') {
            chars_skipped++;
            input->bufpos++;
        }
        else {
            break;
        }
    }
    return(chars_skipped);
}

static int   _skip_char(struct mdf_input *input, char skip_char) {
    int chars_skipped = 0;
    char *p = input->buf + input->bufpos;
    while (input->bufpos + chars_skipped <= input->bufchars) {
        if (*p == skip_char) {
            p++;
            chars_skipped++;
            input->bufpos++;
        }
        else {
            break;
        }
    }
    if (input->debug) fprintf(stderr, "_skip_char(%c) = %d\n", skip_char, chars_skipped);
    return(chars_skipped);
}

static int   _read_n(struct mdf_input *input, int n, char **str_ptr) {
    int chars_read;
    int ch;
    *str_ptr = input->buf + input->bufpos;
    chars_read = n;
    if (input->bufpos + n > input->bufchars) chars_read = input->bufchars - input->bufpos;
    input->bufpos += chars_read;
    if (input->debug) fprintf(stderr, "_read_n(%d, %lx) = %d\n", n, *str_ptr, chars_read);
    return(chars_read);
}

static int _read_word(struct mdf_input *input, char **str_ptr) {
    int chars_read = 0;
    char ch, *p;
    *str_ptr = input->buf + input->bufpos;
    p = input->buf + input->bufpos;
    // if (input->debug) fprintf(stderr, "_read_word() : bufpos=%d bufchars=%d\n", input->bufpos, input->bufchars);
    while (input->bufpos < input->bufchars) {
        ch = *p;
        // if (input->debug) fprintf(stderr, "_read_word() : ch=%c checked...\n", ch);
        if ((ch >= 'A' && ch <= 'Z') ||
            (ch >= 'a' && ch <= 'z') ||
            (ch >= '0' && ch <= '9') ||
            (ch == '_')) {
            chars_read++;
            input->bufpos++;
            p++;
        }
        else {
            break;
        }
    }
    if (input->debug) fprintf(stderr, "_read_word() = %d\n", chars_read);
    return(chars_read);
}

static int _read_string_n(struct mdf_input *input, char *str, int n, char **str_ptr) {
    int chars_read = 0;
    *str_ptr = input->buf + input->bufpos;
    if (memcmp(input->buf + input->bufpos, str, n) == 0) {
        chars_read = n;
        input->bufpos += chars_read;
    }
    if (input->debug) fprintf(stderr, "_read_string_n(%s, %d, %lx) = %d\n", str, n, *str_ptr, chars_read);
    return(chars_read);
}

static int _read_up_to_string_n(struct mdf_input *input, char *str, int n, char **str_ptr) {
    int chars_read = 0;
    char *p;
    p = *str_ptr = input->buf + input->bufpos;
    while (input->bufpos + chars_read < input->bufchars) {
        // if (input->debug) fprintf(stderr, "_read_up_to_string_n() buf[n]=[%c] str[0]=[%c] cmp=%d\n", *p, *str, memcmp(p, str, n));
        if (*p == *str && memcmp(p, str, n) == 0) {
            break;
        }
        else {
            chars_read++;
            p++;
        }
    }
    input->bufpos += chars_read;
    if (input->debug) fprintf(stderr, "_read_up_to_string_n(%s, %d, %lx) = %d\n", str, n, *str_ptr, chars_read);
    return(chars_read);
}

static int _read_insert_values(struct mdf_input *input, char **str_ptr) {
    int chars_read = 0;
    int in_quote = 0;
    int field;
    char *p;
    p = *str_ptr = input->buf + input->bufpos;
    field = 0;
    if (*p == '(') {
        chars_read++;
        p++;
        field++;
    }
    while (input->bufpos + chars_read < input->bufchars) {
        if (in_quote) {
            if (*p == '\\') {
                chars_read += 2;
                p += 2;
            }
            else {
                if (*p == '\'') in_quote = 0;
                chars_read++;
                p++;
            }
        }
        else if (*p == '\'') {
            in_quote = 1;
            chars_read++;
            p++;
        }
        else if (*p == ',') {
            field++;
            chars_read++;
            p++;
        }
        else if (*p == ')') {
            chars_read++;
            p++;
            break;
        }
        else {
            chars_read++;
            p++;
        }
    }
    input->bufpos += chars_read;
    if (input->debug) fprintf(stderr, "_read_insert_values(%lx) = %d lastchar=[%c,%x] nextchar=[%c,%x] bufpos=%d bufchars=%d\n",
        *str_ptr, chars_read, *(p-1), *(p-1), *p, *p, input->bufpos, input->bufchars);
    return(chars_read);
}

static int _read_write_insert_values(struct mdf_input *input, struct mdf_output *output, char **str_ptr, short *subset_map, char *column_values_added) {
    int chars_read = 0;
    int field_chars_read = 0;
    int in_quote = 0;
    int field_num, first_field, chars_written;
    char *p, *field;
    p = *str_ptr = input->buf + input->bufpos;
    field_num = 0;
    if (*p == '(') {
        chars_written = _write(output, "(", 1);
        chars_read++;
        p++;
        if (column_values_added) {
            chars_written = _write(output, column_values_added, strlen(column_values_added));
            chars_written = _write(output, ",", 1);
        }
    }
    field = p;
    first_field = 1;
    while (input->bufpos + chars_read < input->bufchars) {
        if (in_quote) {
            if (*p == '\\') {
                chars_read += 2;
                field_chars_read += 2;
                p += 2;
            }
            else {
                if (*p == '\'') in_quote = 0;
                chars_read++;
                field_chars_read ++;
                p++;
            }
        }
        else if (*p == '\'') {
            in_quote = 1;
            chars_read++;
            field_chars_read ++;
            p++;
        }
        else if (*p == ',') {
            if (subset_map[field_num] != NO_IDX) {
                if (first_field) {
                    first_field = 0;
                }
                else {
                    chars_written = _write(output, ",", 1);
                }
                chars_written = _write(output, field, field_chars_read);
            }
            if (input->debug) fprintf(stderr, "_read_write_insert_values() [found ,] : field_num=%d map=[%d]\n", field_num, subset_map[field_num]);
            field_num++;
            chars_read++;
            p++;
            field = p;
            field_chars_read = 0;
        }
        else if (*p == ')') {
            if (subset_map[field_num] != NO_IDX) {
                if (first_field) {
                    first_field = 0;
                }
                else {
                    chars_written = _write(output, ",", 1);
                }
                chars_written = _write(output, field, field_chars_read);
            }
            if (input->debug) fprintf(stderr, "_read_write_insert_values() [found )] : field_num=%d map=[%d]\n", field_num, subset_map[field_num]);
            chars_written = _write(output, ")", 1);
            chars_read++;
            field_chars_read ++;
            p++;
            break;
        }
        else {
            chars_read++;
            field_chars_read ++;
            p++;
        }
    }
    input->bufpos += chars_read;
    if (input->debug) fprintf(stderr, "_read_write_insert_values(%lx) = %d lastchar=[%c,%x] nextchar=[%c,%x] bufpos=%d bufchars=%d\n",
        *str_ptr, chars_read, *(p-1), *(p-1), *p, *p, input->bufpos, input->bufchars);
    return(chars_read);
}

static int _nextchar(struct mdf_input *input, int offset) {
    char *p = input->buf + input->bufpos;
    return(*p);
}

static char **array_new(char *buf, int nchars, char *sep) {
    if (debug) fprintf(stderr,"array_new()\n");
    if (debug) fprintf(stderr,"array_new([%s], %d, [%s])\n", buf, nchars, sep);
    int newsize, bufpos, isep, numsep, char_skipped, newarraylen;
    char *p, *newbuf, *newarray[MAX_COLUMNS+1], **newarray_copy;
    if (!nchars) nchars = strlen(buf);
    newbuf = (char *) malloc(nchars + 1);
    if (debug) fprintf(stderr,"array_new(): allocated newbuf=0x%08x\n", newbuf);
    strncpy(newbuf, buf, nchars);
    newbuf[nchars] = 0;
    newsize = 0;
    numsep = strlen(sep);
    for (bufpos = 0; bufpos < nchars; bufpos++) {
        // skip any leading separators
        char_skipped = 1;
        while (char_skipped && bufpos < nchars) {
            char_skipped = 0;
            for (isep = 0; isep < numsep; isep++) {
                if (newbuf[bufpos] == sep[isep]) {
                    char_skipped = 1;
                    if (debug) fprintf(stderr,"array_new(): skipping a [%c]\n", sep[isep]);
                    bufpos++;
                    break;
                }
            }
        }
        // skip to the end of the field and null terminate it
        if (newbuf[bufpos]) {
            newarray[newsize] = newbuf + bufpos;
            if (debug) fprintf(stderr,"array_new(): found field %d at position %d\n", newsize, bufpos);
            if (debug) fprintf(stderr,"array_new(): found field in newbuf=0x%08x field=0x%08x\n", newbuf, newarray[newsize]);
            newsize++;
            char_skipped = 1;
            while (char_skipped && bufpos < nchars) {
                char_skipped = 1;
                for (isep = 0; isep < numsep; isep++) {
                    if (newbuf[bufpos] == sep[isep]) {
                        char_skipped = 0;
                        break;
                    }
                }
                if (char_skipped) {
                    bufpos++;
                }
                else {
                    newbuf[bufpos] = 0;  // null terminate the string
                }
            }
            if (debug) fprintf(stderr,"array_new(): found field %d value is [%s]\n", newsize-1, newarray[newsize-1]);
        }
        newarray[newsize] = (char *) NULL;
    }
    newarraylen = (newsize+1) * sizeof(p);
    newarray_copy = (char **) malloc(newarraylen);
    if (debug) fprintf(stderr,"array_new(): newarray\n");
    if (debug) array_print(newarray);
    memcpy(newarray_copy, newarray, newarraylen);
    if (debug) fprintf(stderr,"array_new(): newarray_copy\n");
    if (debug) array_print(newarray_copy);
    return(newarray_copy);
}

static int array_size(char **array) {
    int i;
    char *p;
    if (debug) fprintf(stderr,"array_size(): array=0x%08x\n", array);
    for (i = 0, p = array[i]; p; i++, p = array[i]) {
        if (debug) fprintf(stderr,"array_size(): p=0x%08x size=%d\n", p, i);
    }
    return(i);  // the size
}

static char **array_copy(char **array) {
    char **newarray, *newbuf, *field;
    int buflen, fieldlen, newarraylen, size, i, pos;
    size = array_size(array);
    newarraylen = (size+1) * sizeof(newbuf);
    newarray    = (char **) malloc(newarraylen);
    memcpy(newarray, array, newarraylen);
    if (size > 0) {
        buflen = size;  // number of null terminators
        for (i = 0; i < size; i++) {
            fieldlen = strlen(array[i]);
            buflen += fieldlen;
        }
        newbuf = (char *) malloc(buflen);
        pos = 0;
        for (i = 0; i < size; i++) {
            field    = array[i];
            fieldlen = strlen(field);
            newarray[i] = newbuf + pos;
            memcpy(newbuf + pos, field, fieldlen);
            pos += fieldlen;
            newbuf[pos] = 0; // null terminate
            pos ++;
        }
    }
    return(newarray);
}

static char **array_copy_deleting_some(char **array, char **delete_array) {
    char **newarray, *newbuf, *field, *delete_field;
    int buflen, fieldlen, newarraylen, size, newsize, i, pos, newidx[MAX_COLUMNS+1], new_idx, delete_idx, delete_size, deleted;

    size = array_size(array);
    delete_size = array_size(delete_array);

    newsize = 0;
    if (size > 0) {
        new_idx = 0;
        for (i = 0; i < size; i++) {
            field    = array[i];
            deleted = 0;
            for (delete_idx = 0; delete_idx < delete_size; delete_idx++) {
                if (strcmp(field, delete_array[delete_idx]) == 0) {
                    deleted = 1;
                    break;
                }
            }
            if (deleted) {
                if (debug) fprintf(stderr,"array_copy_deleting_some() : deleted [%d] [%s]\n", i, field);
                newidx[i] = -1;
            }
            else {
                if (debug) fprintf(stderr,"array_copy_deleting_some() : keeping [%d] [%s] new_idx=%d\n", i, field, new_idx);
                newidx[i] = new_idx;
                new_idx ++;
                newsize ++;
            }
        }
    }
    if (debug) fprintf(stderr,"array_copy_deleting_some() : kept [%d] entries\n", newsize);

    newarraylen = (newsize+1) * sizeof(newbuf);
    newarray    = (char **) malloc(newarraylen);
    memcpy(newarray, array, newarraylen);
    if (size > 0) {
        buflen = size;  // number of null terminators
        for (i = 0; i < size; i++) {
            if (newidx[i] != -1) {
                fieldlen = strlen(array[i]);
                buflen += fieldlen;
            }
        }
        newbuf = (char *) malloc(buflen);
        pos = 0;
        for (i = 0; i < size; i++) {
            if (newidx[i] != -1) {
                field    = array[i];
                fieldlen = strlen(field);
                newarray[newidx[i]] = newbuf + pos;
                memcpy(newbuf + pos, field, fieldlen);
                pos += fieldlen;
                newbuf[pos] = 0; // null terminate
                pos ++;
            }
        }
    }
    newarray[newsize] = (char *) NULL;
    return(newarray);
}

static int array_map(char **array, char **subset_array, short *subset_map) {
    char *field, *subset_field;
    int buflen, fieldlen, size, i, pos, new_idx, subset_idx, subset_size, found;
    int columns_mapped;

    size = array_size(array);
    subset_size = array_size(subset_array);

    columns_mapped = 0;
    if (size > 0) {
        for (i = 0; i < size; i++) {
            field    = array[i];
            found = 0;
            for (subset_idx = 0; subset_idx < subset_size; subset_idx++) {
                if (strcmp(field, subset_array[subset_idx]) == 0) {
                    found = 1;
                    break;
                }
            }
            if (found) {
                subset_map[i] = subset_idx;
                columns_mapped ++;
                if (debug) fprintf(stderr,"array_map() : i=[%d] f=[%s] => map=[%2d] found (mapped=%d)\n", i, field, subset_map[i], columns_mapped);
            }
            else {
                subset_map[i] = NO_IDX;
                if (debug) fprintf(stderr,"array_map() : i=[%d] f=[%s] => map=[%2d] not found\n", i, field, subset_map[i]);
            }
        }
    }
    if (debug) fprintf(stderr,"array_map() : mapped [%d] entries\n", columns_mapped);

    return(columns_mapped);
}

static void array_print (char **array) {
    int size = array_size(array);
    int i;
    for (i = 0; i < size; i++) {
        fprintf(stderr,"   %4d : [%s]\n", i, array[i]);
    }
}

static char  *array_join (char **array, char *sep) {
    char *p = "", *field;
    int len, seplen, fieldlen, size, i, pos;
    size = array_size(array);
    seplen = strlen(sep);
    if (size > 0) {
        len = seplen * (size-1);
        for (i = 0; i < size; i++) {
            fieldlen = strlen(array[i]);
            len += fieldlen;
        }
        p = (char *) malloc(len + 1);
        p[len] = 0;   // null terminate it in advance
        pos = 0;
        for (i = 0; i < size; i++) {
            field    = array[i];
            fieldlen = strlen(field);
            memcpy(p + pos, field, fieldlen);
            pos += fieldlen;
            if (i < size - 1) {
                memcpy(p + pos, sep, seplen);
                pos += seplen;
            }
        }
    }
    return(p);
}

static void _output_init(struct mdf_output *output) {
    output->buf      = (char *) malloc(BUFSIZE);
    output->bufchars = 0;
    output->bufsize  = BUFSIZE;
    output->debug    = ao_get_option("debug")->ivalue;
}

static int   _write(struct mdf_output *output, char *buf, int n) {
    int highwater_size;
    int chars_written = 0;
    if (n == -1) n = strlen(buf);
    highwater_size = BUFSIZE/2;
    if (output->bufchars + n >= highwater_size) {
        if (output->bufchars > 0) {
            write(1, output->buf, output->bufchars);
            output->bufchars = 0;
        }
        chars_written = write(1, buf, n);
    }
    else {
        memcpy(output->buf + output->bufchars, buf, n);
        output->bufchars += n;
        chars_written = n;
    }
    if (output->debug) {
        fprintf(stderr, "_write(output, buf, %d) = %d [", n, chars_written);
        fflush(stderr);
        write(2, buf, chars_written);
        fprintf(stderr, "]\n");
    }
    return(chars_written);
}

static void  _flush(struct mdf_output *output) {
    if (output->bufchars > 0) {
        write(1, output->buf, output->bufchars);
        output->bufchars = 0;
    }
}

static void _die (struct mdf_output *output, char *msg) {
    _flush(output);
    fprintf(stderr, msg);
    exit(-1);
}

static void run_regression_tests (void) {
    char *columns, **array, **array2, **array3;
    int array1_size, i;
    short map[16];
    columns = " `alph.a`,`br-avo`,`cha_rlie`,` 4delta`, `echo5` ";
    fprintf(stderr,"====================================\n");
    fprintf(stderr,"array_new()\n");
    fprintf(stderr,"%-20s = [%s]\n", "columns", columns);
    array = array_new(columns, 0, ",` ");
    array_print(array);
    fprintf(stderr,"rejoined = [%s]\n", array_join(array, ","));
    fprintf(stderr,"====================================\n");
    fprintf(stderr,"array_copy()\n");
    array2 = array_copy(array);
    array_print(array2);
    fprintf(stderr,"rejoined = [%s]\n", array_join(array2, ","));
    fprintf(stderr,"====================================\n");
    fprintf(stderr,"array_copy_deleting_some() (alpha, delta)\n");
    array3 = array_new("alph.a,4delta", 0, ",");
    array_print(array3);
    fprintf(stderr,"array_copy_deleting_some() producing (bravo, charlie, echo)\n");
    array2 = array_copy_deleting_some(array, array3);
    array_print(array2);
    fprintf(stderr,"rejoined = [%s]\n", array_join(array2, ","));
    fprintf(stderr,"====================================\n");
    array_map(array, array2, map);
    array1_size = array_size(array);
    for (i = 0; i < array1_size; i++) {
        fprintf(stderr,"  map [%2d] => [%2d]\n", i, map[i]);
    }
}

