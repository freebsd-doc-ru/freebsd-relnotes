#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long;
use File::Spec;
use FindBin;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use Relnotes::Store;

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

my $release_dir;
my $from_file;
my $into_file;
my $insert_into;
my $select;
my $orderby;
my $expr;
my $help;

GetOptions(
    'release-dir=s' => \$release_dir,
    'from=s'        => \$from_file,
    'into=s'        => \$into_file,
    "insert-into=s" => \$insert_into,
    "select=s"      => \$select,
    'orderby=s'     => \$orderby,
    'where=s'       => \$expr,
    'help'          => \$help,
) or usage();

usage() if $help;

my $outputs = 0;
$outputs++ if defined $into_file;
$outputs++ if defined $insert_into;
$outputs++ if defined $select;

die "One of --into, --insert-into or --select is required\n"
    if $outputs == 0;

die "--into, --insert-into and --select are mutually exclusive\n"
    if $outputs > 1;


usage("Missing --release-dir") unless $release_dir;
usage("Missing --from")        unless $from_file;
###usage("Missing --into")        unless $into_file;
usage("Missing --where")       unless $expr;

my $src = File::Spec->catfile($release_dir, $from_file);
die "Source file not found: $src\n" unless -f $src;

my $dst;
if (defined $into_file) {
    $dst = File::Spec->catfile($release_dir, $into_file);
    die "Target file already exists: $dst\n" if -e $dst;
}
elsif (defined $insert_into) {
    $dst = File::Spec->catfile($release_dir, $insert_into);
}





# ------------------------------------------------------------
# Read source
# ------------------------------------------------------------

my @records = Relnotes::Store::read_file($src);
enrich_status_fields(\@records);

# ------------------------------------------------------------
# Prepare expression
# ------------------------------------------------------------

my @fields = detect_fields(\@records);

print @fields;

my $compiled_expr = compile_expression($expr, \@fields);

# ------------------------------------------------------------
# Filter
# ------------------------------------------------------------

my @selected;

for my $r (@records) {

    #my ($include, $score) = parse_status($r->{Status});
    #my $result = eval $compiled_expr;
    #if ($@) {
    #    die "Error evaluating expression: $@\n";
    #}

    #push @selected, $r if $result;

    {
        local $SIG{__WARN__} = sub {
            print STDERR "\nWARNING during eval:\n";
            print STDERR "  Expression: $compiled_expr\n";
            print STDERR "Commit: " . ($r->{Commit} // 'undef') . "\n";
            print STDERR "  Record: ", dump_record($r), "\n";
            print STDERR "  Message: $_[0]\n";
        };

        my $result = eval $compiled_expr;

        if ($@) {
            print STDERR "\nFATAL EVAL ERROR\n";
            print STDERR "Expression: $compiled_expr\n";
            print STDERR "Commit: " . ($r->{Commit} // 'undef') . "\n";
            print STDERR "Record: " . dump_record($r) . "\n";
            print STDERR "Error: $@\n";
            die "Aborting due to eval error\n";
        }
        push @selected, $r if $result;
    }


}

# ------------------------------------------------------------
# Sort if requested
# ------------------------------------------------------------

if ($orderby) {

    my @keys = split /\s*,\s*/, $orderby;
    print "In order by ";
    print @keys;
    print "\n";
    @selected = sort {
        my $cmp = 0;

        for my $k (@keys) {
                my ($k, $dir) = $k =~ /^\s*(\w+)(?:\s+(ASC|DESC))?\s*$/i;
                $dir = uc($dir // 'ASC');

            if ($k =~ /Score$/) {
                if ($dir eq 'DESC'){
                    $cmp ||= (($b->{$k} // 0) <=> ($a->{$k} // 0));
                }
                else
                {
                    $cmp ||= (($a->{$k} // 0) <=> ($b->{$k} // 0));
                }
            } else {
                if ($dir eq 'DESC') {
                    $cmp ||= (($b->{$k} // '') cmp ($a->{$k} // ''));
                }
                else
                {
                    $cmp ||= (($a->{$k} // '') cmp ($b->{$k} // ''));
                }
            }
        }

        $cmp;
    } @selected;
}

# ------------------------------------------------------------
# Write result
# ------------------------------------------------------------

###Relnotes::Store::write_file($dst, \@selected);

###print "Copied ", scalar(@selected), " records to $dst\n";

if (defined $into_file) {

    Relnotes::Store::write_file($dst, \@selected);
    print "Copied ", scalar(@selected), " records to $dst\n";

}
elsif (defined $insert_into) {

    Relnotes::Store::append_file($dst, \@selected);
    print "Appended ", scalar(@selected), " records to $dst\n";

}
elsif (defined $select) {

    my @fields = split(/\s*,\s*/, $select);

    for my $rec (@selected) {
        my @values = map { defined $rec->{$_} ? $rec->{$_} : '' } @fields;
        print join(" | ", @values), "\n";
    }

    print "Selected ", scalar(@selected), " records\n";
}

exit 0;

# ============================================================
# Helpers
# ============================================================

sub usage {
    my ($msg) = @_;
    print STDERR "ERROR: $msg\n\n" if $msg;
    print STDERR <<"USAGE";
Usage:
  relnotes_stage_copy.pl
    --release-dir <dir>
    --from <stage file>
    --into <target file>
    --where '<perl expression>'
    [--orderby Field1,Field2]

Example:
  --where 'Subject =~ /ZFS/ && score >= 50'
USAGE
    exit 1;
}

sub detect_fields {
    my ($records) = @_;
    return keys %{ $records->[$#$records] || {} };
}

sub compile_expression {
    my ($expr, $fields) = @_;

    my $compiled = $expr;

    # заменить имена полей на $r->{Field}
    for my $f (@$fields) {
        $compiled =~ s/\b$f\b/\$r->{$f}/g;
    }

    # дополнительные переменные
    # include -> $include
    # score   -> $score

    return $compiled;
}

sub parse_status {
    my ($status) = @_;

    my $include;
    my $score;

    if ($status && $status =~ /\((.*?)\)/) {
        my $inside = $1;
        my %kv = map {
            my ($k,$v) = split /=/, $_, 2;
            $k => $v;
        } split /,/, $inside;

        $include = $kv{include};
        $score   = $kv{score};
    }

    return ($include, $score);
}

sub enrich_status_fields {
    my ($records) = @_;

    for my $r (@$records) {

        my $status = $r->{Status} // '';

        # Разделить текст и скобки
        my ($text, $inside);

        if ($status =~ /^([^(]+)\((.*?)\)\s*$/) {
            $text   = $1;
            $inside = $2;
        } else {
            $text = $status;
        }

        $text =~ s/\s+$// if defined $text;

        $r->{StatusText} = $text;

        my %kv;

        if ($inside) {
            %kv = map {
                my ($k,$v) = split /=/, $_, 2;
                $k => $v;
            } split /,/, $inside;
        }

        $r->{StatusInclude} = $kv{include};
        $r->{StatusScore}   = defined $kv{score}
                              ? $kv{score} + 0
                              : undef;
    }
}

sub dump_record {
    my ($r) = @_;
    return join ", ",
        map { "$_=" . (defined $r->{$_} ? $r->{$_} : 'undef') }
        sort keys %$r;
}