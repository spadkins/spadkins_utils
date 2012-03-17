
######################################################################
## File: $Id: MechanizeExt.pm 48157 2010-09-13 09:09:43Z ashishku $
######################################################################

############################################################################
# HTML::Form::TextInput
############################################################################
# When using WWW::Mechanize, we need to be able to override <input type=hidden>
# fields with the field() method (which calls HTML::Form::TextInput->value()).
# However, the standard HTML::Form::TextInput->value() method complains if
# the field is "readonly" or "type=hidden".
# So we redefine this method to accept "type=hidden".
############################################################################
use HTML::Form;
#use LWP::Debug qw(+ -conns);
package HTML::Form::TextInput;
no warnings;  # don't complain that we're redefining a method

sub value
{
    my $self = shift;
    my $old = $self->{value};
    $old = "" unless defined $old;
    if (@_) {
    if (exists($self->{readonly})) {
        Carp::carp("Input '$self->{name}' is readonly") if $^W;
    }
    $self->{value} = shift;
    }
    $old;
}

package HTML::Form;
use HTML::TokeParser;
use HTML::TokeParserExt;

sub parse
{
    my($class, $html, $base_uri) = @_;
    ####################################################
    # very weird error where the word 'part' is foo-barred
    # for some reason.  Expedia has it in an action and is 
    # failing.  Change it in the HTML before you parse it
    # and then change it back in the action.
    ####################################################
    #$html =~ s/(<[Ff][Oo][Rr][Mm][^>]*[Aa][Cc][Tt][Ii][Oo][Nn][^>]*)part/$1alexbugfix/g;
    #$html =~ /(<FORM.*?ACTION.*?)part.*?"/i;

    if ( $html =~ /(<FORM.*?ACTION=[^ ]*)part(.*?)\"/i ) {
       my $result = $1;
       my $resultb = $2;
    }

    if ($result) {
        $html =~ s/${result}part/${result}alexbugfix/;
        #$html =~ s/(<[Ff][Oo][Rr][Mm][^>]*[Aa][Cc][Tt][Ii][Oo][Nn][^>]*[^enctype]+[^>]*)part/$1alexbugfix/g;
    }
    my $parser = HTML::TokeParser->new(\$html);
    eval {
        # optimization
        $parser->report_tags(qw(form input textarea select optgroup option));
    };

    my @forms;
    my $f;  # current form
    while (my $t = $parser->get_tag) {
        my($tag,$attr) = @$t;
        if ($tag eq "form") {
            my $action = delete $attr->{'action'};
            $action =~ s/alexbugfix/part/g;

            $action = "" unless defined $action;
            $action = URI->new_abs($action, $base_uri);
            $f = $class->new($attr->{'method'},
                     $action,
                     $attr->{'enctype'});
            $f->{attr} = $attr;
            push(@forms, $f);
            while (my $t = $parser->get_tag) {
                my($tag, $attr) = @$t;
                last if $tag eq "/form";
                if ($tag eq "input") {
                    my $type = delete $attr->{type} || "text";
                    $f->push_input($type, $attr);
                } elsif ($tag eq "textarea") {
                    $attr->{textarea_value} = $attr->{value}
                    if exists $attr->{value};
                    my $text = $parser->get_text("/textarea");
                    $attr->{value} = $text;
                    $f->push_input("textarea", $attr);
                } elsif ($tag eq "select") {
                    $attr->{select_value} = $attr->{value}
                    if exists $attr->{value};
                    while ($t = $parser->get_tag) {
                        my $tag = shift @$t;
                        last if $tag eq "/select";
                        next if $tag =~ m,/?optgroup,;
                        next if $tag eq "/option";
                        if ($tag eq "option") {
                            my %a = (%$attr, %{$t->[0]});
                            $a{value} = $parser->get_trimmed_text
                            unless defined $a{value};
                            $f->push_input("option", \%a);
                        } else {
                            print "Bad <select> tag '$tag'\n";
                            Carp::carp("Bad <select> tag '$tag'") if $^W;
                        }
                    }
                }
            }
        } elsif ($form_tags{$tag}) {
            print "<$tag> outside <form>\n";
            Carp::carp("<$tag> outside <form>") if $^W;
        }
    }
    for (@forms) {
        $_->fixup;
    }

    wantarray ? @forms : $forms[0];
}


############################################################################
# WWW::MechanizeExt
############################################################################

use vars qw($HAS_ZLIB );
BEGIN {
    $HAS_ZLIB = 1 if defined eval "require Compress::Zlib;";
}

package WWW::MechanizeExt;
use WWW::Mechanize;
use Data::Dumper;
@ISA = qw(WWW::Mechanize);

use strict;

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
    return($self);
}

############################################################################
# WWW::Mechanize 0.40 (how it used to work)
############################################################################
# get() call sequence
#   WWW::Mechanize->get() (or click()/follow())
#     WWW::Mechanize->_do_request()  [submits request, extracts forms/links]
#      *LWP::UserAgent->request() [follow redirects, satisfy authentication]
#     LWP::UserAgent->simple_request()      [prepare/send a request]
#       LWP::UserAgent->prepare_request()       [add useragent, cookies]
#      *LWP::UserAgent->send_request()    [send 1 request, get response]
#       WWW::Mechanize->extract_links()      [find all <a>/<frame> tags]
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
# WWW::MechanizeExt->request()  [allocate proxy, manage retry/reallocation]
# WWW::MechanizeExt->send_request()   [accum success/fail stats, debug log]
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

    my $profiler = $App::options{"app.Context.profiler"};
    my ($context);
    if ($profiler) {
        $context = App->context();
        $context->profile_start("net");
    }

    my $response = $self->SUPER::send_request($request, $arg, $size);

    if ($profiler) {
        $context->profile_stop("net");
    }

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

sub html_capture{
    my ($self) = @_;
    push(@{$self->{html}}, [$self->{response}->base, $self->content()]);
}

#Subroutine to return the page number
sub html_capture_page{

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

    my $content = "";
    $content = $response->content();
    $self->{content} = $content;

    return($content);
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
    my $parser = HTML::TokeParserExt->new(\$content) || die "Cannot create parser: $!\n";
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
    my $parser = HTML::TokeParserExt->new(\$content) || die "Cannot create parser: $!\n";
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

    my ($links, $i, $link, $url, $text, $name);
    $links = $self->links();
    printf FILE "lnum [text]         [name]         [url]\n";
    for ($i = 0; $i <= $#$links; $i++) {
    $link = $links->[$i];
    ($url, $text, $name) = @$link;
    printf FILE "%4d %-18s %-18s [%.64s]\n", $i, "[$text]", "[$name]", ((length($url) > 24) ? "$url..." : $url);
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
                $name = $input->name;
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
                    "\"$name\"", ('"' . $input->value() . '"'), $input->type();
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

1;

__END__

This is some code from
   http://www.mail-archive.com/libwww@perl.org/msg04693.html
to patch WWW::Mechanize to do compression automatically.
We need to consider integrating something like this.

package WWW::Mechanize::Compress;

use strict;
use warnings FATAL => 'all';
use vars qw( $VERSION $HAS_ZLIB );
$VERSION = '0.01';

use base qw( WWW::Mechanize );
use Carp qw( carp croak );

BEGIN {
    $HAS_ZLIB = 1 if defined eval "require Compress::Zlib;";
}

sub _make_request {
    my $self    = shift;
    my $request = shift;

    $request->header( Accept_encoding => 'gzip; deflate' ) if $HAS_ZLIB;
    my $response = $self->SUPER::_make_request( $request, @_ );

    if ( my $encoding = $response->header( 'Content-Encoding' ) ) {
        croak 'Compress::Zlib not found. Cannot uncompress content.' unless $HAS_ZLIB;
        $self->{ uncompressed_content } = Compress::Zlib::memGunzip($response->content)
            if $encoding =~ /gzip/i;
        $self->{ uncompressed_content } = Compress::Zlib::uncompress($response->content)
            if $encoding =~ /deflate/i;
    }
    return $response;
}

sub content {
    my $self = shift;
    return $self->{ uncompressed_content } || $self->{ content };
}

1;

