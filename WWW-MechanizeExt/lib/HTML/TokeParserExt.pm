
############################################################################
# HTML::TokeParserExt
############################################################################
package HTML::TokeParserExt;
use HTML::TokeParser;
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

