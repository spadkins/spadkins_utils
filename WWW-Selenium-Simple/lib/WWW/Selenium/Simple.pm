
######################################################################
## File: $Id: Simple.pm 48157 2010-09-13 09:09:43Z ashishku $
######################################################################

use strict;

package WWW::Selenium::Simple;

use URI;
use Test::More qw(no_plan);
use Data::Dumper;

sub new {
    my ($this) = @_;
    my $self = {};
    bless $self, (ref($this) || $this);
    return($self);
}

sub user_agent {
    my ($self, %args) = @_;
    #if (! $args{autocheck}) {
    #    $args{autocheck} = 1;
    #}
    my $ua = WWW::Selenium::Simple::UserAgent->new(%args);

    if ($App::options{agent}) {
        if ($App::options{agent} =~ /[A-Za-z0-9 ]/) {
            $ua->agent_alias($App::options{agent});
        }
        else {
            $ua->agent($App::options{agent});
        }
    }
    return($ua);
}

# $ua->run_test_file($file, \%App::options);
sub run_test_file {
    my ($self, $ua, $file, $options) = @_;
    my ($cmds);
    if ($file =~ /\.html$/) {
        $cmds = $self->read_html_test_file($file);
    }
    elsif ($file =~ /\.sel$/) {
        $cmds = $self->read_sel_test_file($file);
    }
    else {
        die "Error: I don't know how to read a file of Selenium commands unless the file ends in .html or .sel ($file)\n";
    }
    $self->run_cmds($ua, $options, $cmds);
}

sub read_html_test_file {
    my ($self, $file) = @_;
    my $cmds = [];
    my $cmd = [];
    open(my $fh, "<", $file) || die "Unable to open file for reading [$file]: $!\n";
    while (<$fh>) {
        chomp;
        if (m!^\s*<td>([^<]*)</td>\s*$!) {
            push(@$cmd, $1);
        }
        elsif (m!^\s*</tr>\s*$!) {
            if ($#$cmd > -1) {
                push(@$cmds, $cmd);
                $cmd = [];
            }
        }
    }
    close($fh);
    return($cmds);
}

sub read_sel_test_file {
    my ($self, $file) = @_;
    my $cmds = [];
    my ($cmd);
    open(my $fh, "<", $file) || die "Unable to open file for reading [$file]: $!\n";
    while (<$fh>) {
        chomp;
        next if (/^ *#/ || /^\s*$/);
        $cmd = [ split(/ *\| */) ];
        push(@$cmds, $cmd);
    }
    close($fh);
    return($cmds);
}

# open                  | /                                                          | 
# assertTitle           | OpenDNS - Cloud Internet Security and DNS                  | 
# click                 | link=Sign In                                               | 
# clickAndWait          | link=Sign In                                               | 
# assertTitle           | OpenDNS &gt; Sign in to your OpenDNS Dashboard             | 
# click                 | id=dont_expire                                             | 
# click                 | id=dont_expire                                             | 
# clickAndWait          | id=sign-in                                                 | 
# assertTitle           | OpenDNS Dashboard                                          | 
# click                 | link=Settings                                              | 
# clickAndWait          | link=Settings                                              | 
# assertTitle           | OpenDNS Dashboard &gt; Settings                            | 
# click                 | css=#cb1810630 &gt; strong                                 | 
# clickAndWait          | css=#cb1810630 &gt; strong                                 | 
# assertTitle           | OpenDNS Dashboard &gt; Settings &gt; Web Content Filtering | 
# click                 | id=moderate                                                | 
# click                 | id=save-categories                                         | 
# click                 | link=Stats                                                 | 
# clickAndWait          | link=Stats                                                 | 
# assertTitle           | OpenDNS Dashboard &gt; Stats                               | 
# click                 | link=Domains                                               | 
# clickAndWait          | link=Domains                                               | 
# assertTitle           | OpenDNS Dashboard &gt; Stats &gt; Domains                  | 
# click                 | xpath=(//a[contains(text(),'Next')])[2]                    | 
# clickAndWait          | xpath=(//a[contains(text(),'Next')])[2]                    | 
# assertTitle           | OpenDNS Dashboard &gt; Stats &gt; Domains                  | 
# select                | id=view                                                    | label=Blocked Domains
# clickAndWait          | css=input.ajaxbutton.nav-submit-button                     | 
# assertTitle           | OpenDNS Dashboard &gt; Stats &gt; Domains                  | 

sub run_cmds {
    my ($self, $ua, $options, $cmds) = @_;

    my $verbose = $options->{verbose};
    local $URI::ABS_REMOTE_LEADING_DOTS = 1;
    my ($cmd, $op, $arg1, $arg2, @extra_args);
    my ($url, $success, $status, $link, $link_text, $title, $expected_title);

    for (my $i = 0; $i <= $#$cmds; $i++) {
        $cmd = $cmds->[$i];
        ($op, $arg1, $arg2, @extra_args) = @$cmd;
        if ($op eq "open") {
            $url = $arg1;
            if ($url !~ /^[a-z]+:/) {   # if it doesn't start with the protocol (http/https/ftp), it's not an absolute URL
                die "You must supply a --base=<url> option because relative URL's exist in the test file\n" if (!$options->{base});
                $url = URI->new_abs($arg1, $options->{base})->as_string();
                print "$url = URI->new_abs($arg1, $options->{base})->as_string();\n" if ($verbose >= 9);
            }
            $ua->get($url);
            if ($verbose == 1) {
                $success = $ua->success();
                $status  = $ua->response()->status_line();
                ok($success, "GET $url ($status)");
            }
        }
        elsif ($op eq "assertTitle") {
            $title = $ua->title();
            $expected_title = $self->html_decode($arg1);
            if ($verbose == 1) {
                is($title, $expected_title, "Title: [$expected_title]");
            }
        }
        elsif ($op eq "click" || $op eq "clickAndWait") {
            next if ($i > 0 && $op eq "clickAndWait" && $cmds->[$i-1][0] eq "click" && $cmds->[$i-1][1] eq $arg1);

            # click                 | link=Sign In                                               | 
            # clickAndWait          | id=sign-in                                                 | 
            # click                 | css=#cb1810630 &gt; strong                                 | 
            # clickAndWait          | css=input.ajaxbutton.nav-submit-button                     | 
            # click                 | id=moderate                                                | 
            # click                 | xpath=(//a[contains(text(),'Next')])[2]                    | 

            if ($arg1 =~ /^link=(.*)/) {
                $link_text = $1;

                # text    => 'string' and text_regex    => qr/regex/, text matches the text of the link against string, which must be an exact match.
                # url     => 'string' and url_regex     => qr/regex/, Matches the URL of the link against string or regex, as appropriate.
                # url_abs => 'string' and url_abs_regex => regex Matches the absolute URL of the link against string or regex, as appropriate.
                # name    => 'string' and name_regex    => regex Matches the name of the link against string or regex, as appropriate.
                # id      => 'string' and id_regex      => regex Matches the attribute 'id' of the link against string or regex, as appropriate.
                # class   => 'string' and class_regex   => regex Matches the attribute 'class' of the link against string or regex, as appropriate.
                # tag     => 'string' and tag_regex     => regex Matches the tag that the link came from against string or regex, as appropriate.

                $link = $ua->find_link( text => $link_text );
                if ($link) {
                    $url  = $link->url();
                    $ua->get($url);

                    # $ua->follow_link( text => $link_text );

                    if ($verbose == 1) {
                        $success = $ua->success();
                        $status  = $ua->response()->status_line();
                        $url     = $ua->uri();
                        ok($success, "follow_link($link_text) $url ($status)");
                    }
                }
                else {
                    ok(0, "follow_link($link_text) : link not found in page");
                }
            }
        }
        elsif ($op eq "select") {
        }
        else {
            die "Unknown Selenium Command: $op [$arg1] [$arg2] (@extra_args)\n";
        }
    }
}

my %html_entity_subst = (
    "lsquo"  => "'",     # left single quote
    "rsquo"  => "'",     # right single quote
    "sbquo"  => "'",     # single low-9 quote
    "ldquo"  => "\"",    # left double quote
    "rdquo"  => "\"",    # right double quote
    "bdquo"  => "'",     # double low-9 quote
    "dagger" => "",      # dagger
    "Dagger" => "",      # double dagger
    "permil" => "",      # per mill sign
    "lsaquo" => "'",     # single left-pointing angle quote
    "rsaquo" => "'",     # single right-pointing angle quote
    "spades" => "",      # black spade suit
    "clubs"  => "",      # black club suit
    "hearts" => "",      # black heart suit
    "diams"  => "",      # black diamond suit
    "oline"  => "_",     # overline, = spacing overscore
    "larr"   => "",      # leftward arrow
    "uarr"   => "",      # upward arrow
    "rarr"   => "",      # rightward arrow
    "darr"   => "",      # downward arrow
    "trade"  => "(tm)",  # trademark sign
    "quot"   => "\"",    # double quotation mark
    "amp"    => "&",     # ampersand
    "frasl"  => "/",     # slash
    "lt"     => "<",     # less-than sign
    "gt"     => ">",     # greater-than sign
    "ndash"  => "-",     # en dash
    "mdash"  => "-",     # em dash
    "nbsp"   => "",      # nonbreaking space
    "iexcl"  => "!",     # inverted exclamation
    "cent"   => "",      # cent sign
    "pound"  => "",      # pound sterling
    "curren" => "",      # general currency sign
    "yen"    => "Y",     # yen sign
    "sect"   => "",      # section sign
    "uml"    => "",      # umlaut
    "die"    => "",      # umlaut
    "copy"   => "(c)",   # copyright
    "ordf"   => "a",     # feminine ordinal
    "laquo"  => "<<",    # left angle quote
    "not"    => "!",     # not sign
    "shy"    => "-",     # soft hyphen
    "reg"    => "(R)",   # registered trademark
    "macr"   => "",      # macron accent
    "hibar"  => "",      # macron accent
    "deg"    => "",      # degree sign
    "plusmn" => "",      # plus or minus
    "sup2"   => "",      # superscript two
    "sup3"   => "",      # superscript three
    "acute"  => "'",     # acute accent
    "micro"  => "u",     # micro sign
    "para"   => "",      # paragraph sign
    "middot" => ".",     # middle dot
    "cedil"  => "",      # cedilla
    "sup1"   => "",      # superscript one
    "ordm"   => "",      # masculine ordinal
    "raquo"  => ">>",    # right angle quote
    "frac14" => " 1/4",  # one-fourth
    "frac12" => " 1/2",  # one-half
    "frac34" => " 3/4",  # three-fourths
    "iquest" => "?",     # inverted question mark
    "Agrave" => "A",     # uppercase A, grave accent
    "Aacute" => "A",     # uppercase A, acute accent
    "Acirc"  => "A",     # uppercase A, circumflex accent
    "Atilde" => "A",     # uppercase A, tilde
    "Auml"   => "A",     # uppercase A, umlaut
    "Aring"  => "A",     # uppercase A, ring
    "AElig"  => "Ae",    # uppercase AE
    "Ccedil" => "C",     # uppercase C, cedilla
    "Egrave" => "E",     # uppercase E, grave accent
    "Eacute" => "E",     # uppercase E, acute accent
    "Ecirc"  => "E",     # uppercase E, circumflex accent
    "Euml"   => "E",     # uppercase E, umlaut
    "Igrave" => "I",     # uppercase I, grave accent
    "Iacute" => "I",     # uppercase I, acute accent
    "Icirc"  => "I",     # uppercase I, circumflex accent
    "Iuml"   => "I",     # uppercase I, umlaut
    "ETH"    => "D",     # uppercase Eth, Icelandic
    "Ntilde" => "N",     # uppercase N, tilde
    "Ograve" => "O",     # uppercase O, grave accent
    "Oacute" => "O",     # uppercase O, acute accent
    "Ocirc"  => "O",     # uppercase O, circumflex accent
    "Otilde" => "O",     # uppercase O, tilde
    "Ouml"   => "O",     # uppercase O, umlaut
    "times"  => "x",     # multiplication sign
    "Oslash" => "O",     # uppercase O, slash
    "Ugrave" => "U",     # uppercase U, grave accent
    "Uacute" => "U",     # uppercase U, acute accent
    "Ucirc"  => "U",     # uppercase U, circumflex accent
    "Uuml"   => "U",     # uppercase U, umlaut
    "Yacute" => "Y",     # uppercase Y, acute accent
    "THORN"  => "P",     # uppercase THORN, Icelandic
    "szlig"  => "ss",    # lowercase sharps, German
    "agrave" => "a",     # lowercase a, grave accent
    "aacute" => "a",     # lowercase a, acute accent
    "acirc"  => "a",     # lowercase a, circumflex accent
    "atilde" => "a",     # lowercase a, tilde
    "auml"   => "a",     # lowercase a, umlaut
    "aring"  => "a",     # lowercase a, ring
    "aelig"  => "ae",    # lowercase ae
    "ccedil" => "c",     # lowercase c, cedilla
    "egrave" => "e",     # lowercase e, grave accent
    "eacute" => "e",     # lowercase e, acute accent
    "ecirc"  => "e",     # lowercase e, circumflex accent
    "euml"   => "e",     # lowercase e, umlaut
    "igrave" => "i",     # lowercase i, grave accent
    "iacute" => "i",     # lowercase i, acute accent
    "icirc"  => "i",
    "iuml"   => "i",
    "eth"    => "e",
    "ntilde" => "n",
    "ograve" => "o",
    "oacute" => "o",
    "ocirc"  => "o",
    "otilde" => "o",
    "ouml"   => "o",
    "divide" => "o",
    "oslash" => "o",
    "ugrave" => "u",
    "uacute" => "u",
    "ucirc"  => "u",
    "uuml"   => "u",
    "yacute" => "y",
    "thorn"  => "p",
    "yuml"   => "y",

    "32"     => " ",
    "33"     => "!",
    "34"     => "\"",
    "35"     => "#",
    "36"     => "\$",
    "37"     => "\%",
    "38"     => "&",
    "39"     => "'",
    "40"     => "(",
    "41"     => ")",
    "42"     => "*",
    "43"     => "+",
    "44"     => ",",
    "45"     => "-",
    "46"     => ".",
    "47"     => "/",
    "48"     => "0",
    "49"     => "1",
    "50"     => "2",
    "51"     => "3",
    "52"     => "4",
    "53"     => "5",
    "54"     => "6",
    "55"     => "7",
    "56"     => "8",
    "57"     => "9",
    "58"     => ":",
    "59"     => ";",
    "60"     => "<",
    "61"     => "=",
    "62"     => ">",
    "63"     => "?",
    "64"     => "\@",
    "65"     => "A",
    "66"     => "B",
    "67"     => "C",
    "68"     => "D",
    "69"     => "E",
    "70"     => "F",
    "71"     => "G",
    "72"     => "H",
    "73"     => "I",
    "74"     => "J",
    "75"     => "K",
    "76"     => "L",
    "77"     => "M",
    "78"     => "N",
    "79"     => "O",
    "80"     => "P",
    "81"     => "Q",
    "82"     => "R",
    "83"     => "S",
    "84"     => "T",
    "85"     => "U",
    "86"     => "V",
    "87"     => "W",
    "88"     => "X",
    "89"     => "Y",
    "90"     => "Z",
    "91"     => "[",
    "92"     => "\\",
    "93"     => "]",
    "94"     => "^",
    "95"     => "_",
    "96"     => "`",
    "97"     => "a",
    "98"     => "b",
    "99"     => "c",
    "100"    => "d",
    "101"    => "e",
    "102"    => "f",
    "103"    => "g",
    "104"    => "h",
    "105"    => "i",
    "106"    => "j",
    "107"    => "k",
    "108"    => "l",
    "109"    => "m",
    "110"    => "n",
    "111"    => "o",
    "112"    => "p",
    "113"    => "q",
    "114"    => "r",
    "115"    => "s",
    "116"    => "t",
    "117"    => "u",
    "118"    => "v",
    "119"    => "w",
    "120"    => "x",
    "121"    => "y",
    "122"    => "z",
    "123"    => "{",
    "124"    => "|",
    "125"    => "}",
    "126"    => "~",

    "149"    => "",      # unused
    "150"    => "-",     # en dash
    "151"    => "-",     # em dash
    "159"    => "",      # unused
    "160"    => " ",     # nonbreaking space
    "161"    => "!",     # inverted exclamation
    "162"    => "",      # cent sign
    "163"    => "",      # pound sterling
    "164"    => "",      # general currency sign
    "165"    => "",      # yen sign
    "166"    => "|",     # broken vertical bar
    "167"    => "",      # section sign
    "168"    => "",      # umlaut
    "169"    => "(c)",   # copyright
    "170"    => "a",     # feminine ordinal
    "171"    => "<<",    # left angle quote
    "172"    => "",      # not sign
    "173"    => "-",     # soft hyphen
    "174"    => "(R)",   # registered trademark
    "175"    => "_",     # macron accent
    "176"    => "o",     # degree sign
    "177"    => "",      # plus or minus
    "178"    => "",      # superscript two
    "179"    => "",      # superscript three
    "180"    => "",      # acute accent
    "181"    => "",      # micro sign
    "182"    => "",      # paragraph sign
    "183"    => ".",     # middle dot
    "184"    => "",      # cedilla
    "185"    => "",      # superscript one
    "186"    => "",      # masculine ordinal
    "187"    => ">>",    # right angle quote
    "188"    => " 1/4",  # one-fourth
    "189"    => " 1/2",  # one-half
    "190"    => " 3/4",  # three-fourths
    "191"    => "?",     # inverted question mark
    "192"    => "A",     # uppercase A, grave accent
    "193"    => "A",     # uppercase A, acute accent
    "194"    => "A",     # uppercase A, circumflex accent
    "195"    => "A",     # uppercase A, tilde
    "196"    => "A",     # uppercase A, umlaut
    "197"    => "A",     # uppercase A, ring
    "198"    => "Ae",    # uppercase AE
    "199"    => "C",     # uppercase C, cedilla
    "200"    => "E",     # uppercase E, grave accent
    "201"    => "E",     # uppercase E, acute accent
    "202"    => "E",     # uppercase E, circumflex accent
    "203"    => "E",     # uppercase E, umlaut
    "204"    => "I",     # uppercase I, grave accent
    "205"    => "I",     # uppercase I, acute accent
    "206"    => "I",     # uppercase I, circumflex accent
    "207"    => "I",     # uppercase I, umlaut
    "208"    => "D",     # uppercase Eth, Icelandic
    "209"    => "N",     # uppercase N, tilde
    "210"    => "O",     # uppercase O, grave accent
    "211"    => "O",     # uppercase O, acute accent
    "212"    => "O",     # uppercase O, circumflex accent
    "213"    => "O",     # uppercase O, tilde
    "214"    => "O",     # uppercase O, umlaut
    "215"    => "x",     # multiplication sign
    "216"    => "O",     # uppercase O, slash
    "217"    => "U",     # uppercase U, grave accent
    "218"    => "U",     # uppercase U, acute accent
    "219"    => "U",     # uppercase U, circumflex accent
    "220"    => "U",     # uppercase U, umlaut
    "221"    => "Y",     # uppercase Y, acute accent
    "222"    => "P",     # uppercase THORN, Icelandic
    "223"    => "ss",    # lowercase sharps, German
    "224"    => "a",     # lowercase a, grave accent
    "225"    => "a",     # lowercase a, acute accent
    "226"    => "a",     # lowercase a, circumflex accent
    "227"    => "a",     # lowercase a, tilde
    "228"    => "a",     # lowercase a, umlaut
    "229"    => "a",     # lowercase a, ring
    "230"    => "ae",    # lowercase ae
    "231"    => "c",     # lowercase c, cedilla
    "232"    => "e",     # lowercase e, grave accent
    "233"    => "e",     # lowercase e, acute accent
    "234"    => "e",     # lowercase e, circumflex accent
    "235"    => "e",     # lowercase e, umlaut
    "236"    => "i",     # lowercase i, grave accent
    "237"    => "i",     # lowercase i, grave accent
    "238"    => "i",     # icirc
    "239"    => "i",     # iuml
    "240"    => "i",     # eth
    "241"    => "e",     # ntilde
    "242"    => "n",     # ograve
    "243"    => "o",     # oacute
    "244"    => "o",     # ocirc
    "245"    => "o",     # otilde
    "246"    => "o",     # ouml
    "247"    => "o",     # divide
    "248"    => "o",     # oslash
    "249"    => "u",     # ugrave
    "250"    => "u",     # uacute
    "251"    => "u",     # ucirc
    "252"    => "u",     # uuml
    "253"    => "y",     # yacute
    "254"    => "p",     # thorn
    "255"    => "y",     # yuml
    "8217"   => "'",     # Italian e.g d'Elsa
);

sub html_decode {
    my ($self, $html_fragment) = @_;
    $html_fragment =~ s/&([A-Za-z][A-Za-z0-9]*);/(defined $html_entity_subst{$1} ? $html_entity_subst{$1} : "")/eg;
    $html_fragment =~ s/&#([0-9]+);?/(defined $html_entity_subst{$1 + 0} ? $html_entity_subst{$1 + 0} : "")/eg;
    return($html_fragment);
}

sub url_decode {
    my ($self, $url) = @_;
    $url =~ tr/+/ /;
    $url =~ s/%([a-fA-F0-9]{2,2})/chr(hex($1))/eg;
    $url =~ s/<!--(.|\n)*-->//g;
    return($url);
}

sub url_encode {
    my ($self, $url) = @_;
    $url =~ s/([\W])/"%" . uc(sprintf("%2.2x",ord($1)))/eg;
    return($url);
}

package WWW::Selenium::Simple::UserAgent;
use vars qw(@ISA);
use WWW::Mechanize;
@ISA = qw(WWW::Mechanize);

sub new {
    my ($this, @args) = @_;
    my $self = $this->SUPER::new(@args);
    if ($App::options{logdir} && ! exists $self->{logdir}) {
        my $logdir = $App::options{logdir};
        $logdir = "log" if ($logdir eq "1");
        $self->{logdir} = $logdir;
        if (! -d $logdir) {
            mkdir($logdir);
        }
        else {
            foreach my $file (<$logdir/*>) {
                unlink($file);
            }
        }
    }
    if (! exists $self->{maxtries}) {
        $self->{maxtries} = $App::options{maxtries} || 1;  # assume we are not trying for error-tolerance
    }
    return($self);
}

############################################################################
# WWW::Mechanize 0.40 (how it used to work)
############################################################################
# get() call sequence
#   WWW::Mechanize->get() (or click()/follow())
#     WWW::Mechanize->_do_request()  [submits request, extracts forms/links]
#      *LWP::UserAgent->request() [follow redirects, satisfy authentication]
#     LWP::UserAgent->simple_request()              [prepare/send a request]
#       LWP::UserAgent->prepare_request()           [add useragent, cookies]
#      *LWP::UserAgent->send_request()        [send 1 request, get response]
#       WWW::Mechanize->extract_links()          [find all <a>/<frame> tags]
# * So we override send_request() so that we can log exactly the requests
#   that go out and the responses that come back.
############################################################################

############################################################################
# WWW::Mechanize 0.70 (how it works now)
############################################################################
# get() call sequence
#   WWW::Mechanize->get()         [fix URL to absolute wrt <base> if needed]
#     LWP::UserAgent->get()                             [colonic headers!?!]
#      *WWW::Mechanize->request()            [manage page stack and Referer]
#     WWW::Mechanize->_make_request()     [enable LWP::UA::request override]
#       LWP::UserAgent->request()      [follow redirects, do authentication]
#         LWP::UserAgent->simple_request()          [prepare/send a request]
#           LWP::UserAgent->prepare_request()       [add useragent, cookies]
#          *LWP::UserAgent->send_request()     [send 1 request/get response]
#     WWW::Mechanize->_reset_page()                  [clear links and forms]
#     WWW::Mechanize->_parse_html()                [extract links and forms]
#       HTML::Form->parse()                                  [extract forms]
#       WWW::Mechanize->_extract_links()     [find a/area/frame/iframe tags]
#
# * We override send_request() so that we can log exactly the requests
#   that go out and the responses that come back (for debug/development).
# * We override both request() and send_request() to implement autoproxying.
#
# WWW::Selenium::Simple::UserAgent->request()  [allocate proxy, manage retry/reallocation]
# WWW::Selenium::Simple::UserAgent->send_request()   [accum success/fail stats, debug log]
############################################################################
# follow_link()/follow() call get()
############################################################################
# click() call sequence
#   WWW::Mechanize->click()                        [supply x=1/y=1 defaults]
#      HTML::Form->click()              [create a request from a form click]
#     *WWW::Mechanize->request()                        [submit the request]
############################################################################
# submit() call sequence
#   WWW::Mechanize->submit()
#      HTML::Form->make_request()    [create a request from a SUBMIT button]
#     *WWW::Mechanize->request()                        [submit the request]
############################################################################

my $seq = 0;

sub send_request {
    my($self, $request, $arg, $size) = @_;
    $seq++;
    my $logdir = $self->{logdir};
    my ($tag, $req_begin_time, $req_end_time, $req_time);

    if ($logdir) {
        $tag = sprintf("%04d",$seq);
        mkdir($logdir) if (! -d $logdir);
        $self->dump($request, "request", "$logdir/$tag.req");
    }

    my $request_stats = $self->{request_stats};

    $req_begin_time = time();

    my $response = $self->SUPER::send_request($request, $arg, $size);

    $req_end_time = time();
    $req_time = $req_end_time - $req_begin_time;

    if ($response->code() < 400) {
        $request_stats->{req_sent}++;
        $request_stats->{req_time} += $req_time;
        $request_stats->{req_time_sq} += $req_time*$req_time;
        $request_stats->{req_content_length} += ($response->content_length() || length($response->content()));
        if ( my $encoding = $response->header( 'content-encoding' ) ) {
            my $content = "";
            $content = $response->content();
            $self->{content} = $content;
      
            if ($encoding =~ /gzip/i) {
                $content = Compress::Zlib::memGunzip($content);
                $self->{content} = $content;
                $response->content($content);
            }
            elsif ($encoding =~ /deflate/i) {
                $content = Compress::Zlib::uncompress($content);
                $self->{content} = $content;
                $response->content($content);
            }
        }
    }
    else {
        $request_stats->{req_errors}++;
        $request_stats->{req_err_time} += $req_time;
        $request_stats->{last_error} = $response->status_line();
        $request_stats->{req_content_length} += ($response->content_length() || length($response->content()));
    }

    if ($logdir) {
        $self->dump($response, "response", "$logdir/$tag.res");
    }

    return($response);
}

sub request {
    my($self, $request, $arg, $size, $previous) = @_;
    my ($response, $tries, @args, $proxy);

    #&LWP::Debug::level("+trace", "+debug");
    my $autoproxy   = $self->{autoproxy};
    my $request_stats = $self->{request_stats};
    if (!$request_stats) {
        $request_stats = {
            proxy              => "direct",
            begin_time         => time(),
            req_sent           => 0,
            req_time           => 0,
            req_time_sq        => 0,
            req_errors         => 0,
            req_err_time       => 0,
            req_content_length => 0,
            last_error         => undef,
        };
        $self->{request_stats} = $request_stats;
    }
    my $maxtries = $self->{maxtries} || (($autoproxy || $self->{proxy}{http}) ? 8 : 3);
    my ($response_code, $status_line);
    for ($tries = 0; $tries < $maxtries; $tries++) {

        if ($autoproxy && !$self->{proxy}{http}) {
            @args = $autoproxy->{getproxy_args} ? @{$autoproxy->{getproxy_args}} : ();
            $proxy = &{$autoproxy->{getproxy_sub}}(@args);
            if ($proxy =~ /^http/) {
                #$self->{proxy}{http} = $proxy;
                $self->proxy('http', $proxy);      # We now have to set the proxy this way. ASH,FAS,MMT,VPF,BDE,BSE and BFR would fail.
                #$self->{proxy}{https} = $proxy;   # method 1 for SSL proxying (doesn't work)
                $ENV{HTTPS_PROXY} = $proxy;        # method 2 for SSL proxying (does work!)
            }
            else {
                delete $self->{proxy}{http};
                #delete $self->{proxy}{https};
                delete $ENV{HTTPS_PROXY};
            }
            if ($proxy ne $request_stats->{proxy}) {
                $request_stats->{proxy}              = $proxy;
                $request_stats->{begin_time}         = time();
                $request_stats->{req_sent}           = 0;
                $request_stats->{req_time}           = 0;
                $request_stats->{req_time_sq}        = 0;
                $request_stats->{req_errors}         = 0;
                $request_stats->{req_err_time}       = 0;
                $request_stats->{req_content_length} = 0;
                $request_stats->{last_error}         = undef;
            }
        }

        eval {
            $self->{response} = $self->SUPER::request($request, $arg, $size, $previous);
            $response_code = $self->{response}->code();
            $status_line = $self->{response}->status_line();
        };
        if ($@) {
            $response_code = 500;
            $status_line = $@;
            chomp $status_line;
        }

        if ($autoproxy && $self->{proxy}{http}) {
            if ($response_code >= 400 ||
                ($request_stats->{req_time}/($request_stats->{req_sent} + 3) > 10.0)) {
                @args = $autoproxy->{finishproxy_args} ? @{$autoproxy->{finishproxy_args}} : ();
                delete $self->{proxy}{http};
                #delete $self->{proxy}{https};  # method 1 for SSL proxying (doesn't work)
                delete $ENV{HTTPS_PROXY};       # method 2 for SSL proxying (does work!)
                &{$autoproxy->{finishproxy_sub}}(@args);
            }
        }
        if ($response_code < 300 && $self->{html}) {
            ### TODO: maybe do some testing here, which of the following is better
            ### $self->uri() or $self->base for setting html base tag
            #push(@{$self->{html}}, [$self->uri(), $self->content()]);

            #if capture type is 'record', store html of all pages
            my $capture_type = $self->{html_capture_type} || "record";
            if ($capture_type !~ /snapshot/is){
                $self->html_capture();
            } 
        }
        last if ($response_code < 400);
    }

    if ($tries == $maxtries) {
        if ($self->{comment}) {
            die "$status_line (after $tries tries) " . $self->{comment};
        }
        else {
            die "$status_line (after $tries tries)";
        }
    }
    #&LWP::Debug::level("-trace", "-debug");
    return($self->{response});
}

sub html_capture {
    my ($self) = @_;
    push(@{$self->{html}}, [$self->{response}->base, $self->content()]);
}

#Subroutine to return the page number
sub html_capture_page {

    my ($self) = @_;
    return ($#{$self->{html}} + 1);
}    

sub get_request_stats {
    my ($self) = @_;
    return($self->{request_stats} || {});
}

sub clear_request_stats {
    my ($self, $proxy) = @_;
    my $request_stats = $self->{request_stats};
    if (!$request_stats) {
        $request_stats = {};
        $self->{request_stats} = $request_stats;
    }
    $request_stats->{proxy}              = $proxy if ($proxy);
    $request_stats->{begin_time}         = time();
    $request_stats->{req_sent}           = 0;
    $request_stats->{req_time}           = 0;
    $request_stats->{req_time_sq}        = 0;
    $request_stats->{req_errors}         = 0;
    $request_stats->{req_err_time}       = 0;
    $request_stats->{req_content_length} = 0;
    $request_stats->{last_error}         = undef;
}

# turn on and off autoproxying
sub autoproxy {
    my ($self, $getproxy_sub, $getproxy_args, $finishproxy_sub, $finishproxy_args, $maxtries) = @_;
    $self->{autoproxy} = {
        on                 => 1,
        getproxy_sub       => $getproxy_sub,
        getproxy_args      => $getproxy_args,
        finishproxy_sub    => $finishproxy_sub,
        finishproxy_args   => $finishproxy_args,
        maxtries           => $maxtries,
    };
}

sub autoproxy_off {
    my ($self) = @_;
    $self->{autoproxy}{on} = 0;
    delete $self->{autoproxy};
    delete $self->{proxy}{http};
    #delete $self->{proxy}{https};
    delete $ENV{HTTPS_PROXY};
}

sub autoproxy_release {
    my ($self, $last_error) = @_;
    my $autoproxy = $self->{autoproxy};
    if (defined $autoproxy && $autoproxy->{on} && $self->{proxy}{http}) {
        delete $self->{proxy}{http};
        #delete $self->{proxy}{https};
        delete $ENV{HTTPS_PROXY};
    }
}

sub DESTROY {
    my ($self) = @_;
    if (defined $self->{autoproxy} && $self->{autoproxy}{on}) {
        $self->autoproxy_release();
        $self->{autoproxy}{on} = 0;
    }
}

### This is grabbed straight from WWW::Mechanize version 1.20
### It has since been deprecated, so we copied it.
sub form {
    my $self = shift;
    my $arg = shift;

    return $arg =~ /^\d+$/ ? $self->form_number($arg) : $self->form_name($arg);
}

sub get {
    my ($self, $url) = @_;
    if ($self->{logdir} && !$self->{comment}) {
        my $oldtitle = $self->title();
        $self->{comment} = "From [$oldtitle] via get($url)";
    }
    $self->set_host_header($url);
    my $response = $self->SUPER::get($url);
    $self->dump_page_info() if ($self->{logdir});
    delete $self->{comment};
    return($response);
}

sub set_host_header {
    my ($self, $url) = @_;
    my ($host);
    if ($url =~ m!^[a-z]+//:([^/?&]+)!) {
        $host = $1;
        $self->add_header("Host", $host);
    }
    #$self->add_header("Accept", "*/*");
    #$self->add_header("Accept-Language", "en-us");
    #$self->add_header("Accept-Encoding", "gzip, deflate");
    #$self->add_header("If-Modified-Since", "Mon, 16 Jun 2003 18:45:10 GMT; length=9857");
    #$self->add_header("Proxy-Connection", "Keep-Alive");
    #$self->add_header("Pragma", "no-cache");
    #delete $WWW::Mechanize::headers{TE};
    #delete $WWW::Mechanize::headers{Connection};
}

sub set_referer_header {
    my ($self) = @_;
    my $uri = $self->uri();
    $self->add_header("Referer", $uri);
}

# NOTE: WWW::Mechanize->follow() calls WWW::Mechanize->get()
sub follow {
    my ($self, $string_num) = @_;
    if ($self->{logdir} && !$self->{comment}) {
        my $oldtitle = $self->title();
        $self->{comment} = "From [$oldtitle] via follow($string_num)";
    }
    $self->set_referer_header();
    $self->follow_deprecated_044($string_num);
    # follow() calls get(), so get() will dump_page_info(). not needed here.
    # $self->dump_page_info() if ($self->{logdir});
    delete $self->{comment};
}

sub follow_deprecated_044 {
    my ($self, $link) = @_;
    my @links = @{$self->{links}};
    my $thislink;
    if ( $link =~ /^\d+$/ ) { # is a number?
        if ($link <= $#links) {
            $thislink = $links[$link];
        } else {
            warn "Link number $link is greater than maximum link $#links ",
             "on this page ($self->{uri})\n" unless $self->quiet;
            return;
        }
    } else {            # user provided a regexp
        LINK: foreach my $l (@links) {
            if ($l->[1] =~ /$link/) {
            $thislink = $l;     # grab first match
            last LINK;
            }
        }
        unless ($thislink) {
            warn "Can't find any link matching $link on this page ",
             "($self->{uri})\n" unless $self->quiet;
            return;
        }
    }

    $thislink = $thislink->[0];     # we just want the URL, not the text

    $self->_push_page_stack();
    $self->get( $thislink );

    return 1;
}

sub click {
    my ($self, $button, $x, $y) = @_;
    if ($self->{logdir} && !$self->{comment}) {
        my $oldtitle = $self->title();
        $self->{comment} = "From [$oldtitle] via click($button,$x,$y)";
    }
    $self->set_referer_header();
    $self->set_host_header($self->current_form()->uri()->as_string());
    $self->SUPER::click($button, $x, $y);
    $self->dump_page_info() if ($self->{logdir});
    delete $self->{comment};
}

sub submit {
    my ($self) = @_;
    if ($self->{logdir} && !$self->{comment}) {
        my $oldtitle = $self->title();
        $self->{comment} = "From [$oldtitle] via submit()";
    }
    $self->set_referer_header();
    $self->set_host_header($self->current_form()->uri()->as_string());
    $self->SUPER::submit();
    $self->dump_page_info() if ($self->{logdir});
    delete $self->{comment};
}

sub post_content {
    my ($self, $url, $content_type, $content) = @_;

    my $request = HTTP::Request->new("POST");
    $request->url($url);
    $request->header('Content-Type', $content_type);
    $request->header('Content-Length', length $content);  # Not really needed
    $request->header( Accept_Encoding => 'gzip; deflate' );
    $request->content($content);
    my $response = $self->request($request);

    my $response_content = "";
    $response_content = $response->content();
    $self->{content} = $response_content;

    return($response_content);
}

sub is_followable {
    my ($self, $string_num) = @_;
    my ($links, $i, $link, $url, $text, $name);
    $links = $self->links();
    if ($string_num =~ /^\d+$/) {
        return(($string_num <= $#$links) ? 1 : 0);
    }
    for ($i = 0; $i <= $#$links; $i++) {
        $link = $links->[$i];
        ($url, $text, $name) = @$link;
        return(1) if ($text eq $string_num);
    }
    return(0);
}

sub is_clickable {
    my ($self, $button) = @_;
    my ($form, $input, $name);
    $form = $self->current_form();
    foreach $input (@{$form->{'inputs'}}) {
        next unless $input->can("click");
        $name = $input->name;
        return(1) if ($button eq $name);
    }
    return(0);
}

# title() was rewritten because it fails in some cases.
# i.e. pages returned from sites like www.expedia.com.

sub title {
    my ($self) = @_;
    my $content = $self->content();
    return("") if (!$content);
    my $parser = WWW::Selenium::Simple::TokeParser->new(\$content) || die "Cannot create parser: $!\n";
    my $result = $parser->get_tag("title");
    return("") if (!$result);
    return($parser->get_trimmed_text());
}

sub check_title {
    my ($self, $goodtitle_regexp, $comment, $verbose) = @_;
    my ($title);
    $comment = $comment ? " ($comment)" : "";
    my $response = $self->res();
    if ($response->is_error()) {
        die "HTTP Error${comment}: " . $response->status_line() . " expected [$goodtitle_regexp]\n";
    }
    else {
        $title = $self->title();
        print ">>> title [$title]\n" if ($verbose);
        if (defined $goodtitle_regexp) {
            if ($goodtitle_regexp eq "") {
                die "Unexpected page title${comment}: title=[$title] expected [$goodtitle_regexp]\n"
                    if ($title ne "");
            }
            else {
                die "Unexpected page title${comment}: title=[$title] expected [$goodtitle_regexp]\n"
                    if ($title !~ /$goodtitle_regexp/);
            }
        }
    }
}

# overrides LWP::UserAgent->clone() in order to ensure that the cookie jar
# is maintained (not discarded) across clone()s.  (This was causing
# the WWW::Mechanize->back() method to restore a "page" that had no
# memory of cookies accumulated.)

sub clone {
    my $self = shift;
    my $copy = bless { %$self }, ref $self;  # copy most fields

    # We want these as references!!!
    # So we overrode the LWP::UserAgent->clone() method to do this.
    # Keep the comments.

    # elements that are references must be handled in a special way
    #$copy->{'proxy'} = { %{$self->{'proxy'}} };
    #$copy->{'no_proxy'} = [ @{$self->{'no_proxy'}} ];  # copy array

    # remove reference to objects for now
    #delete $copy->{cookie_jar};
    #delete $copy->{conn_cache};

    $copy;
}

sub comment {
    my ($self, $comment) = @_;
    $self->{comment} = $comment if (defined $comment);
    return($self->{comment});
}

sub linknums {
    my ($self, $linktext) = @_;
    
    my ($links, $linknum, $link, @linknums);
    my ($url, $text, $name);

    $links = $self->links();
    @linknums = ();
    for ($linknum = 0; $linknum <= $#$links; $linknum++) {
        $link = $links->[$linknum];
        ($url, $text, $name) = @$link;
        push(@linknums, $linknum) if ($text eq $linktext);
    }

    if (wantarray) {
        return(@linknums);
    }
    elsif ($#linknums > -1) {
        return($linknums[0]);
    }
    else {
        return(undef);
    }
}

sub get_tables {
    my ($self, $attrib, $value_set) = @_;
    my $content = $self->content();
    my $parser = WWW::Selenium::Simple::TokeParser->new(\$content) || die "Cannot create parser: $!\n";
    return($parser->get_tables($attrib, $value_set));
}

sub dump {
    my ($self, $obj, $var, $file) = @_;
    local(*FILE);
    open(FILE,"> $file") || die "Unable to open $file: $!\n";
    print FILE "# COMMENT: $self->{comment}\n" if ($self->{comment});
    my $d = Data::Dumper->new([ $obj ], [ $var ]);
    $d->Indent(1);
    print FILE $d->Dump();
    close(FILE);
}

sub dump_page_info {
    my ($self, $comment) = @_;

    my $logdir = $self->{logdir};
    return if (!$logdir);

    my $file = sprintf("$logdir/%04d.rpi",$seq);
    local(*FILE);
    open(FILE,"> $file") || die "Unable to open $file: $!\n";

    print FILE "# TITLE:    ", $self->title, "\n";
    print FILE "# COMMENT:  $self->{comment}\n" if ($self->{comment});
    print FILE "# COMMENT2: $comment\n" if ($comment);

    my ($links, $i, $link, $url, $text, $name, $tag, $base, $attrs);
    $links = $self->links();
    printf FILE "lnum [text]         [name]         [url]\n";
    for ($i = 0; $i <= $#$links; $i++) {
        $link = $links->[$i];
        # ($url, $text, $name) = @$link;
        $url   = $link->url()   || "";
        $text  = $link->text()  || "";
        $name  = $link->name()  || "";
        $tag   = $link->tag()   || "";
        $base  = $link->base()  || "";
        $attrs = $link->attrs() || "";
        printf FILE "%4d %-18s %-18s [%s]\n", $i, "[$text]", "[$name]", $url;
    }
    print FILE "\n";

    my ($forms, $form, $formnum, $input, $buttonnum);
    $forms = $self->forms();
    if ($forms && (ref($forms) eq "ARRAY") && $#$forms > -1) {
        $formnum = 0;
        foreach $form (@$forms) {
            $formnum++;
            print FILE "Form #$formnum - forms may be selected by number\n";
            print FILE "bnum [name]: buttons must be clicked by name. i.e. \$agent->click(\$name);\n";
            $buttonnum = 0;
            foreach $input (@{$form->{'inputs'}}) {
                next unless $input->can("click");
                $name = $input->name || "";
                printf FILE "%4d [$name]\n", $buttonnum;
                $buttonnum++;
            }
            print FILE "\n";
        }
        $formnum = 0;
        foreach $form (@$forms) {
            my %inputnum = ();
            $formnum++;
            print FILE "Form #$formnum - forms may be selected by number\n";
            print FILE "fnum [name] [value] [num]: fields set by name. \$agent->field(\$name,\$value,\$num);\n";
            foreach $input (@{$form->{'inputs'}}) {
                next if $input->can("click");  # don't worry about buttons
                $name = $input->name;
                if ($inputnum{$name}) {
                    $inputnum{$name}++;
                }
                else {
                    $inputnum{$name} = 1;
                }
                printf FILE "   field(%-26s, %-26s, $inputnum{$name}) [%s]\n",
                    "\"$name\"", ('"' . ($input->value()||"") . '"'), ($input->type()||"");
            }
            print FILE "\n";
        }
    }
    else {
        print FILE "No forms in this page\n\n";
    }

    close(FILE);
}

sub get_cookie_hash {
   my ($self) = @_;
   my %cookie_hash;
   $self->cookie_jar()->scan( sub { &putInHash(\%cookie_hash, @_) } );
   return \%cookie_hash;
}

sub putInHash {
   my ($cookie_hash,$version,$key,$val,$path,$domain,$port,$path_spec,$secure,$expires,$discard,$hash) = @_;
   $cookie_hash->{$key} = $val;
}

# added from mech 0.70 by MFP on 12/8/03 to handle HolidayAutosDE/UK

sub tick {
    my $self = shift;
    my $name = shift;
    my $value = shift;
    my $set = @_ ? shift : 1;  # default to 1 if not passed

    # loop though all the inputs
    my $index = 0;
    while ( my $input = $self->current_form->find_input( $name, "checkbox", $index ) ) {
    # Can't guarantee that the first element will be undef and the second
    # element will be the right name
    foreach my $val ($input->possible_values()) {
        next unless defined $val;
        if ($val eq $value) {
        $input->value($set ? $value : undef);
        return;
        }
    }

    # move onto the next input
    $index++;
    } # while

    # got self far?  Didn't find anything
    $self->warn( qq{No checkbox "$name" for value "$value" in form} );
} # tick()

# Here are some URL's describing character set specification in HTML
#    http://www.w3.org/TR/REC-html40/charset.html#h-5.2.2
#    http://www.htmlhelp.com/tools/validator/charset.html
# Here are some lists of some valid charset values. (Note: "Shift_JIS" requires an underscore! Others require dots and colons.)
#    http://www.htmlhelp.com/tools/validator/supported-encodings.html.en
#    http://www.iana.org/assignments/character-sets
sub charset {
    my ($self) = @_;
    my ($charset);
    my $response = $self->response();
    if ($response) {
        # the preferred way is for the server to send it in the "Content-Type" header
        my $content_type = $response->header("Content-type");
        if ($content_type && $content_type =~ /charset=([A-Za-z0-9\.:_-]+)/i) {
            $charset = $1;
        }
    }
    if (!$charset) {
        # a second way is for a document to include a <meta http-equiv> tag
        my $content = $self->content();
        if ($content =~ /<META\s+HTTP-EQUIV="?Content-Type"?[^<>]*charset=([A-Za-z0-9\.:_-]+)/i) {
            $charset = $1;
        }
    }
    return($charset);
}

############################################################################
# WWW::Selenium::Simple::TokeParser
############################################################################
package WWW::Selenium::Simple::TokeParser;
use HTML::TokeParser;
use vars qw(@ISA);
@ISA = qw(HTML::TokeParser);

use strict;

sub get_named_tag {
    my ($self, $tag, $name) = @_;
    my ($result, $tag2, $attr, $attrseq, $text);
    $result = [];
    while ($result) {
        $result = $self->get_tag($tag);
        #print "get_named_tag(): $tag => $result\n";
        return(undef) if (!defined $result);
        #print "get_named_tag(): $tag result => [", join(",",@$result), "]\n";
        ($tag2, $attr, $attrseq, $text) = @$result;
        #print "get_named_tag(): $tag2 attrs => [", join(",",(keys %$attr)), "]\n";
        last if ($attr->{name} && $attr->{name} eq $name);
    }
    return($result);
}

sub get_attributed_tag {
    my ($self, $tag, $attrib, $value) = @_;
    my ($result, $tag2, $attr, $attrseq, $text);
    $result = [];
    while ($result) {
        $result = $self->get_tag($tag);
        return(undef) if (!defined $result);
        ($tag2, $attr, $attrseq, $text) = @$result;
        last if ($attr->{$attrib} && $attr->{$attrib} eq $value);
    }
    return($result);
}

sub get_nth_tag {
    my ($self, @ops) = @_;
    my ($result, $opcount, $tagcount, $returntype);
    my ($numtags, $tag);
    $result = [];

    $returntype = "";
    if ($#ops % 2 == 0) {
        $returntype = pop(@ops);
    }

    for ($opcount = 0; $opcount < $#ops; $opcount += 2) {
        $tag = $ops[$opcount];
        $numtags = $ops[$opcount+1];
        for ($tagcount = 0; $tagcount < $numtags; $tagcount++) {
            $result = $self->get_tag($tag);
            return(undef) if (!defined $result);
        }
    }

    if (!$returntype) {
        return($result);
    }
    else {
        my ($tag2, $attr, $attrseq, $text);
        ($tag2, $attr, $attrseq, $text) = @$result;
        if ($returntype eq "text") {
            $text = $self->get_trimmed_text("/$tag");
            $text =~ s/\&nbsp;/ /gi; # this will never happen because ...
            $text =~ s/\xa0/ /g;     # ... &nbsp; gets transformed to \xA0 by get_trimmed_text()
            $text =~ s/\n/ /g;
            $text =~ s/<[^<>]*>/ /g;
            $text =~ s/\s+$//;
            $text =~ s/^\s+//;
            $text =~ s/\s+/ /g;
            return($text);
        }
        else {
            return($attr->{$returntype});
        }
    }
}

sub get_list {
    my ($self) = @_;

    my ($result, $tag, $attr, $attrseq, $text, $value, @values);
    while ($result = $self->get_tag("li", "/ol", "/ul")) {
        ($tag, $attr, $attrseq, $text) = @$result;
        if ($tag eq "li") {
            $value = $self->get_trimmed_text();
            push(@values, $value);
        }
        else {
            last;
        }
    }
    return(\@values);
}

sub get_list_element {
    my ($self, $regexp) = @_;

    my ($result, $tag, $attr, $attrseq, $text, $value);
    while ($result = $self->get_tag("li")) {
        ($tag, $attr, $attrseq, $text) = @$result;
        $value = $self->get_trimmed_text();
        return($value) if ($value =~ /$regexp/);
    }
    return(undef);
}

sub get_select {
    my ($self, $name, $values_list, $labels_hash, $values_hash, $labels_list) = @_;

    @$values_list = () if ($values_list);
    %$labels_hash = () if ($labels_hash);
    %$values_hash = () if ($values_hash);
    @$labels_list = () if ($labels_list);

    my ($result, $tag, $attr, $attrseq, $text, $value, $label);
    $result = $self->get_named_tag("select", $name);
    return(undef) if (!defined $result);
    while ($result = $self->get_tag("/select", "option")) {
        ($tag, $attr, $attrseq, $text) = @$result;
        #print "get_select(): ($tag, $attr, $attrseq, $text)\n";
        if ($tag eq "option") {
            $value = $attr->{value};
            $label = $self->get_trimmed_text();
            #print "          >>> value=[$value] label=[$label]\n";
            push(@$values_list, $value)     if ($values_list);
            $labels_hash->{$value} = $label if ($labels_hash);
            $values_hash->{$label} = $value if ($values_hash);
            push(@$labels_list, $label)     if ($labels_list);
        }
        else {
            last;
        }
    }
}

sub get_input_values {
    my ($self, $name) = @_;

    my ($result, $tag, $attr, $attrseq, $text, @values);
    while ($result = $self->get_named_tag("input", $name)) {
        ($tag, $attr, $attrseq, $text) = @$result;
        push(@values, $attr->{value});
    }
    return(@values);
}

sub get_radio_values {
    my ($self, $name) = @_;
    my ($result, $tag, $attr, $attrseq, $text, @values);
    while ($result = $self->get_tag("input")) {
        ($tag, $attr, $attrseq, $text) = @$result;
		if ( ($attr->{type} eq "radio") && ($attr->{name} eq $name) ) {
        	push(@values, $attr->{value});
		}
    }
    return(@values);
}

sub get_tables {
    my ($self, $attrib, $value_set) = @_;
    # print "get_tables($attrib, $value_set)\n";
    my ($table, @tables);
    @tables = ();
    while (1) {
        $table = $self->get_table($attrib, $value_set);
        # print "get_tables(): got [$table]\n";
        last if (!defined $table);
        # $self->print_array($table);
        push(@tables, $table);
    }
    return(\@tables);
}

# returns an array of 2-D tables
# i.e. $tables = $parser->get_table("name","hotel_info");
# i.e. $tables = $parser->get_table("name","hotel_info,hotel_grid");
#      $tables = $parser->get_table("name",{hotel_info=>1,hotel_grid=>1});
#      $tables = $parser->get_table("name",["hotel_info","hotel_grid"]);
#      $tables = $parser->get_table();   # get next table
sub get_table {
    my ($self, $attrib, $value_set) = @_;
    # print "get_table($attrib, $value_set)\n";

    # first, turn "value_set" into a hashref "set"
    if (!$value_set) {
        $attrib = "";
        $value_set = {};
    }
    elsif (ref($value_set) eq "") {
        if ($value_set =~ /,/) {
            my @values = split(/,/,$value_set);
            $value_set = {};
            foreach (@values) {
                $value_set->{$_} = 1;
            }
        }
        else {
            $value_set = { $value_set => 1 };
        }
    }
    elsif (ref($value_set) eq "ARRAY") {
        my @values = @$value_set;
        $value_set = {};
        foreach (@values) {
            $value_set->{$_} = 1;
        }
    }
    # print "value_set={", join(",", %$value_set), "}\n";

    my $tagresult = [];
    my $table = [];
    my $rowidx = -1;
    my $colidx = -1;

    my $table_tag_seen = 0;
    my $table_found = 0;
    my $capture_text = 0;
    my $inside_table_row = 0;

    my ($tag, $attr, $attrseq, $text, $plaintext, $subtable, $plaintextfragment, $value);

    while ($tagresult) {
        $tagresult = $self->get_tag();
        last if (!defined $tagresult);
        ($tag, $attr, $attrseq, $text) = @$tagresult;
        if ($tag eq "table") {
            $table_tag_seen = 1;
            # print "tag=$tag attr={", join(",",%$attr), "} (searching on $attrib)\n";
            if ($table_found) {
                $subtable = $self->get_table();
                # print ">get_table(): got [$subtable]\n";
                $capture_text = 0;
                $self->_save_cell($table,$rowidx,$colidx,$plaintext,$subtable);
            }
            else {
                if (!$attrib) {
                    $table_found = 1;
                    $capture_text = 0;
                    $rowidx = -1;
                    $colidx = -1;
                }
                else {
                    $value = $attr->{$attrib} || "";
                    if ($value && defined $value_set->{$value}) {
                        $table_found = 1;
                        $capture_text = 0;
                        $rowidx = -1;
                        $colidx = -1;
                    }
                }
            }
            # print " >>> found=$table_found rowidx=$rowidx colidx=$colidx\n";
        }
        elsif ($tag eq "tr") {
            if (!$table_found && !$table_tag_seen) {
                $table_found = 1;
            }
            if ($table_found) {
                $capture_text = 0;
                $rowidx++;
                $colidx = -1;
                $inside_table_row = 1;
                # print "<tr>: capture_text=$capture_text [$rowidx][$colidx] plaintext=$plaintext\n";
            }
        }
        elsif ($tag eq "td") {
            if ($table_found) {
                $subtable = undef;
                $plaintext = "";
                $colidx++;
                $capture_text = 1;
                # print "<td>: capture_text=$capture_text [$rowidx][$colidx] plaintext=$plaintext\n";
            }
        }
        elsif ($tag eq "/td") {
            if ($table_found) {
                $capture_text = 1;
                # print "</td>: capture_text=$capture_text plaintext=$plaintext\n";
            }
        }
        elsif ($tag eq "/tr") {
            if ($table_found) {
                $capture_text = 1;
                $inside_table_row = 0;
                # print "</tr>: capture_text=$capture_text\n";
            }
        }
        elsif ($tag eq "/table") {
            if ($table_found) {
                $capture_text = 0;
                $inside_table_row = 0;
                # print "</table>: capture_text=$capture_text\n";
                # print "returning [$table] (via </table> tag)...\n";
                # $self->print_array($table);
                return($table);
            }
        }
        if ($capture_text) {
            $plaintextfragment = $self->get_text();
            if ($plaintextfragment ne "" && $plaintextfragment !~ /^\s+$/) {
                $plaintext .= " " if ($plaintext ne "");
                $plaintext .= $plaintextfragment;
            }
            # a </table name=xyz> tag shows up as text rather than as a </table> tag
            if (!$inside_table_row) {
                if ($plaintext =~ m!</table!i) {
                    $capture_text = 0;
                    $inside_table_row = 0;
                    # print "returning [$table] (via </table> disguised as text)...\n";
                    # $self->print_array($table);
                    return($table);
                }
            }
            elsif ($plaintext ne "") {
                $self->_save_cell($table,$rowidx,$colidx,$plaintext,$subtable);
            }
        }
    }
    return(undef);
}

sub _save_cell {
    my ($self, $table, $rowidx, $colidx, $plaintext, $subtable) = @_;
    if ($rowidx >= 0 && $colidx >= 0) {
        if ($subtable) {
            # print "Saving: ${table}->[$rowidx][$colidx] = $subtable\n";
            if (! defined $table->[$rowidx][$colidx]) {
                $table->[$rowidx][$colidx] = [ $subtable ];
            }
            elsif (ref($table->[$rowidx][$colidx]) eq "ARRAY") {
                push(@{$table->[$rowidx][$colidx]}, $subtable);
            }
            else {
                #warn "Warning: saving subtable on top of text\n" if (defined $table->[$rowidx][$colidx]);
                $table->[$rowidx][$colidx] = [ $subtable ];
            }
        }
        elsif ($plaintext ne "") {
            $plaintext =~ s/\&nbsp;/ /gi; # this will sometimes not happen because ...
            $plaintext =~ s/\xa0/ /g;     # ... &nbsp; gets transformed to \xA0 (\240) sometimes
            $plaintext =~ s/\n/ /g;
            $plaintext =~ s/<[^<>]*>/ /g;
            $plaintext =~ s/\s+$//;
            $plaintext =~ s/^\s+//;
            $plaintext =~ s/\s+/ /g;
            if ($plaintext ne "") {
                # print "Saving: ${table}->[$rowidx][$colidx] = $plaintext\n";
                if (defined $table->[$rowidx][$colidx]) {
                    $table->[$rowidx][$colidx] .= " " . $plaintext;
                }
                else {
                    $table->[$rowidx][$colidx] = $plaintext;
                }
            }
        }
        else {
            if (! defined $table->[$rowidx][$colidx]) {
                $table->[$rowidx][$colidx] = undef;
            }
        }
    }
    else {
        # no big deal
        # die "Tried to save text [$plaintext] or table [$subtable] for [$rowidx][$colidx]\n";
    }
    $_[4] = "" if ($#_ >= 4);     # reach up and clear $plaintext in the *caller* scope
    $_[5] = undef if ($#_ >= 5);  # reach up and clear $subtable in the *caller* scope
}

sub print_array {
    my ($self, $array, $indent) = @_;
    $indent ||= 0;
    my $all_scalars = 1;
    foreach my $elem (@$array) {
        if (defined $elem && ref($elem) eq "ARRAY") {
            $all_scalars = 0;
            last;
        }
    }
    if ($all_scalars) {
        print "  " x $indent if ($indent);
        print "[ ";
        foreach my $elem (@$array) {
            if (!defined $elem) {
                print "undef, ";
            }
            elsif (ref($elem) eq "ARRAY") {
                print "\n";
                $self->print_table($elem, $indent+1);
                print(("    " x $indent), "  ");
            }
            elsif ($elem =~ /^-?[0-9\.]+$/) {
                print "$elem, ";
            }
            else {
                print "\"$elem\", ";
            }
        }
        print "],\n";
    }
    else {
        print "  " x $indent if ($indent);
        print "[\n";
        foreach my $elem (@$array) {
            if (!defined $elem) {
                print "  " x $indent if ($indent);
                print "  undef,\n";
            }
            elsif (ref($elem) eq "ARRAY") {
                $self->print_array($elem, $indent+1);
            }
            elsif ($elem =~ /^-?[0-9\.]+$/) {
                print "  " x $indent if ($indent);
                print "  $elem,\n";
            }
            else {
                print "  " x $indent if ($indent);
                print "  \"$elem\",\n";
            }
        }
        print "  " x $indent if ($indent);
        print $indent ? "],\n" : "];\n";
    }
}

sub print_parsed {
    my ($self) = @_;

    my $tagresult = [];
    my ($tag, $attr, $attrseq, $text);
    while ($tagresult) {
        $tagresult = $self->get_tag();
        last if (!defined $tagresult);
        ($tag, $attr, $attrseq, $text) = @$tagresult;
        printf("%-8s {$attr} [$attrseq] %s\n", $tag, $text);
        $text = $self->get_text();
        printf("%-8s %s\n", "[text]", $text) if ($text !~ /^\s*$/);
    }
}

sub print_binary {
    my ($data) = @_;
    my ($len, $pos, $byte, $hexdata, $textdata);
    my ($linechars, $linepos, $linelen, $linedatalen);
    $len = length($data);
    $linelen = 16;
    $pos = 0;
    while ($pos < $len) {
        $linepos = $pos;
        $hexdata = "";
        $textdata = "";
        $linedatalen = ($pos <= $len - $linelen) ? $linelen : ($len - $pos);
        for (; $pos < $linepos + $linedatalen; $pos++) {
            $byte = ord(substr($data,$pos,1));
            #$textdata .= " " if ($pos % 8 == 0);
            $textdata .= ($byte >= 32 && $byte < 127) ? chr($byte) : ".";
            $hexdata  .= " " if ($pos % 2 == 0);
            $hexdata  .= sprintf("%02X", $byte);
        }
        for (; $pos < $linepos + $linelen; $pos++) {
            $byte = ord(substr($data,$pos,1));
            #$textdata .= " " if ($pos % 8 == 0);
            $textdata .= " ";
            $hexdata  .= " " if ($pos % 2 == 0);
            $hexdata  .= "  ";
        }
        printf "%06X> [%6d] $hexdata   $textdata\n", $linepos, $linepos;
    }
}

1;

__END__

open                  | /                                                          | 
assertTitle           | OpenDNS - Cloud Internet Security and DNS                  | 
click                 | link=Sign In                                               | 
clickAndWait          | link=Sign In                                               | 
assertTitle           | OpenDNS &gt; Sign in to your OpenDNS Dashboard             | 
click                 | id=dont_expire                                             | 
click                 | id=dont_expire                                             | 
clickAndWait          | id=sign-in                                                 | 
assertTitle           | OpenDNS Dashboard                                          | 
click                 | link=Settings                                              | 
clickAndWait          | link=Settings                                              | 
assertTitle           | OpenDNS Dashboard &gt; Settings                            | 
click                 | css=#cb1810630 &gt; strong                                 | 
clickAndWait          | css=#cb1810630 &gt; strong                                 | 
assertTitle           | OpenDNS Dashboard &gt; Settings &gt; Web Content Filtering | 
click                 | id=moderate                                                | 
click                 | id=save-categories                                         | 
click                 | link=Stats                                                 | 
clickAndWait          | link=Stats                                                 | 
assertTitle           | OpenDNS Dashboard &gt; Stats                               | 
click                 | link=Domains                                               | 
clickAndWait          | link=Domains                                               | 
assertTitle           | OpenDNS Dashboard &gt; Stats &gt; Domains                  | 
click                 | xpath=(//a[contains(text(),'Next')])[2]                    | 
clickAndWait          | xpath=(//a[contains(text(),'Next')])[2]                    | 
assertTitle           | OpenDNS Dashboard &gt; Stats &gt; Domains                  | 
select                | id=view                                                    | label=Blocked Domains
clickAndWait          | css=input.ajaxbutton.nav-submit-button                     | 
assertTitle           | OpenDNS Dashboard &gt; Stats &gt; Domains                  | 

