#!/usr/bin/env perl
#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

use strict;
use warnings;

use Getopt::Long;
use File::Spec;
use FindBin;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');

use Relnotes::Store;
use Relnotes::Sections;

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

my $release_dir;
my $dry_run = 0;
my $write   = 0;
my $help    = 0;


GetOptions(
    'release-dir=s' => \$release_dir,
    'dry-run'       => \$dry_run,
    'write'         => \$write,
    'help'          => \$help,
) or usage();

usage() if $help;
usage("Missing --release-dir") unless $release_dir;
usage("Specify --dry-run or --write") unless $dry_run || $write;
usage("Choose only one: --dry-run or --write") if $dry_run && $write;

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

my $stage2_file = File::Spec->catfile(
    $release_dir,
    'relnotes_stage2.txt'
);

die "Stage2 file not found: $stage2_file\n"
    unless -f $stage2_file;

my $adoc_file = File::Spec->catfile(
    $release_dir,
    'relnotes.adoc'
);

my $already_included = extract_gitrefs_from_adoc($adoc_file);

# ------------------------------------------------------------
# Load data
# ------------------------------------------------------------

my @records = Relnotes::Store::read_file($stage2_file);

# Only accepted, with meaningful Section
@records = grep {
       ($_->{Status}  // '') eq 'accepted'
    && ($_->{Section} // '') ne ''
    && ($_->{Section} // '') ne 'undecided'
} @records;

@records = grep {
    my($retvalue)=(1);
    my $h = $_->{Commit};
    for my $seen (keys %$already_included) {
        if (hash_matches($h, $seen)) {
            print "Skipping already documented commit $h (matches $seen)\n";
            $retvalue = 0;
            last;
        }
    }

    $retvalue;
} @records;

# ------------------------------------------------------------
# Load sections mapping
# ------------------------------------------------------------

my $sections = Relnotes::Sections::load_sections($release_dir);

# ------------------------------------------------------------
# Validate sections
# ------------------------------------------------------------

for my $r (@records) {
    my $sec = $r->{Section};
    unless (exists $sections->{$sec}) {
        warn "Unknown section '$sec' for commit $r->{Commit}\n";
    }
}

# ------------------------------------------------------------
# Group by Section
# ------------------------------------------------------------

my %by_section;

for my $r (@records) {
    push @{ $by_section{ $r->{Section} } }, $r;
}

# ------------------------------------------------------------
# Sort inside each section
#   Score desc, Date desc
# ------------------------------------------------------------

for my $sec (keys %by_section) {
    my @sorted = sort {
           ($b->{Score} // 5) <=> ($a->{Score} // 5)
        || ($b->{Date}  // '') cmp ($a->{Date}  // '')
    } @{ $by_section{$sec} };

    $by_section{$sec} = \@sorted;
}

# ------------------------------------------------------------
# DRY-RUN OUTPUT
# ------------------------------------------------------------

if(0)
{
print "=== DRY RUN: relnotes_stage2_to_adoc ===\n";
print "Release dir: $release_dir\n";
print "Stage2 file: $stage2_file\n";

for my $sec (sort keys %by_section) {
    my $meta = $sections->{$sec};

    my $anchor = $meta->{anchor} // '';
    my $title  = $meta->{title}  // '';

    print "\n== $sec ($anchor)\n";
    print "   $title\n\n";

    for my $r (@{ $by_section{$sec} }) {
        printf "  + %s | score=%s | %s\n",
            $r->{Commit} // '',
            $r->{Score}  // 5,
            $r->{Date}   // '';

        print "    $r->{Subject}\n\n";
    }
}
}

# ------------------------------------------------------------
# DRY-RUN asciidoc output (by section, by anchor)
# ------------------------------------------------------------

my ($adoc_sections, $adoc_lines)
    = parse_adoc_sections($adoc_file);

my $by_anchor = index_sections_by_anchor($adoc_sections);

if ($dry_run)
{
    print "=== DRY RUN: asciidoc insertion preview ===\n";
    print "File: $adoc_file\n";

    for my $sec (sort keys %by_section) {
        my $meta = $sections->{$sec};
        my $anchor = $meta->{anchor};

        unless ($anchor && exists $by_anchor->{$anchor}) {
            warn "Anchor not found in relnotes.adoc for section '$sec'\n";
            next;
        }

        my $adoc_sec = $by_anchor->{$anchor};

        print "\n--- Section: $sec\n";
        print "    Anchor: [[${anchor}]]\n";
        print "    Insert after line $adoc_sec->{end}\n\n";

        my @rendered = render_records_as_adoc(
            @{ $by_section{$sec} }
        );

        for my $l (@rendered) {
            print "$l\n";
        }
    }
}

# ------------------------------------------------------------
# WRITE MODE: insert into adoc_lines
# ------------------------------------------------------------

if ($write) {

    print "=== WRITE MODE: updating relnotes.adoc ===\n";

    # Чтобы индексы не поехали — идём СНИЗУ ВВЕРХ
    for my $sec (sort {
    $by_anchor->{ $sections->{$b}{anchor} }->{end}
    <=>
    $by_anchor->{ $sections->{$a}{anchor} }->{end}
} keys %by_section) {

        my $meta   = $sections->{$sec};
        my $anchor = $meta->{anchor};

        next unless $anchor && exists $by_anchor->{$anchor};

        my $adoc_sec = $by_anchor->{$anchor};
        my $insert_at = $adoc_sec->{end};

        my @rendered = render_records_as_adoc(
            @{ $by_section{$sec} }
        );

        print "Inserting ", scalar(@rendered),
              " lines into section '$sec'\n";

        splice(
            @$adoc_lines,
            $insert_at + 1,
            0,
            @rendered
        );
    }

    open my $out, '>', $adoc_file
        or die "Cannot write $adoc_file: $!";

    print $out join("\n", @$adoc_lines), "\n";
    close $out;

    print "relnotes.adoc updated successfully\n";
}

exit 0;

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

sub usage {
    my ($msg) = @_;

    print STDERR "ERROR: $msg\n\n" if $msg;

    print STDERR <<"USAGE";
Usage:
  relnotes_stage2_to_adoc.pl --release-dir <dir> --dry-run

Options:
  --release-dir   Path to release directory
  --dry-run       Do not write files, only show planned output
  --write         Write changes to relnotes.adoc
  --help          Show this help
USAGE

    exit 1;
}

sub extract_gitrefs_from_adoc {
    my ($path) = @_;

    return {} unless -f $path;

    open my $fh, '<', $path
        or die "Cannot open $path: $!";

    my %seen;

    while (my $line = <$fh>) {
        while ($line =~ /gitref:([0-9a-f]{7,40})\[/g) {
            $seen{$1} = 1;
        }
    }

    close $fh;
    return \%seen;
}

sub hash_matches {
    my ($a, $b) = @_;

    return 0 unless $a && $b;

    my $len = length($a) < length($b) ? length($a) : length($b);
    return substr($a, 0, $len) eq substr($b, 0, $len);
}

sub parse_adoc_sections {
    my ($path) = @_;

    open my $fh, '<', $path
        or die "Cannot open $path: $!";

    my @lines = <$fh>;
    close $fh;

    chomp @lines;

    my @sections;
    my $cur;

    for my $i (0 .. $#lines) {
        if ($lines[$i] =~ /^\[\[([^\]]+)\]\]/) {
            push @sections, $cur if $cur;
            $cur = {
                anchor => $1,
                start  => $i,
            };
        }
    }

    push @sections, $cur if $cur;

    for my $i (0 .. $#sections) {
        my $next = $sections[$i + 1];
        $sections[$i]->{end}
            = $next ? $next->{start} - 1 : $#lines;
    }

    return (\@sections, \@lines);
}

sub index_sections_by_anchor {
    my ($sections) = @_;

    my %by_anchor;
    for my $s (@$sections) {
        $by_anchor{ $s->{anchor} } = $s;
    }

    return \%by_anchor;
}

sub render_records_as_adoc {
    my (@records) = @_;

    my @out;

    for my $r (@records) {
        push @out, "* $r->{Subject}";

        if ($r->{Body}) {
            push @out,
                map { "  $_" } split /\n/, $r->{Body};
        }

        push @out,
            "  gitref:$r->{Commit}\[repository=src\]";

        if ($r->{Sponsor}) {
            push @out, "  (Sponsored by $r->{Sponsor})";
        }

        push @out, "";
    }

    return @out;
}

