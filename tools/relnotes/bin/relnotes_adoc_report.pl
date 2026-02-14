#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long;
use File::Spec;
use FindBin;
use File::Path qw(make_path);

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');

use Relnotes::Sections;
use Relnotes::Git qw(read_commit);

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

my $release_dir;
my $src;
my $help;

GetOptions(
    'release-dir=s' => \$release_dir,
    'src=s'         => \$src,
    'help'          => \$help,
) or usage();

usage() if $help;
usage("Missing --release-dir") unless $release_dir;
usage("Missing --src (path to src repo)") unless $src;

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

my $adoc_file = File::Spec->catfile(
    $release_dir,
    'relnotes.adoc'
);

die "relnotes.adoc not found in $release_dir\n"
    unless -f $adoc_file;

# ------------------------------------------------------------
# Load sections mapping
# ------------------------------------------------------------

my $sections = Relnotes::Sections::load_sections($release_dir);

# Build anchor → section reverse index
my %anchor_to_section;

for my $sec (keys %$sections) {
    my $anchor = $sections->{$sec}{anchor};
    $anchor_to_section{$anchor} = $sec if $anchor;
}

# ------------------------------------------------------------
# Parse relnotes.adoc
# ------------------------------------------------------------

my ($sections_in_adoc, $lines) = parse_adoc_sections($adoc_file);

# anchor → list of hashes
my %commits_by_section;

for my $sec (@$sections_in_adoc) {

    my $anchor = $sec->{anchor};
    my $section_name = $anchor_to_section{$anchor};

    next unless $section_name;

    for my $i ($sec->{start} .. $sec->{end}) {
        my $line = $lines->[$i];

    # Ignore commented lines (// comment)
    next if $line =~ m{^// };

        while ($line =~ /gitref:([0-9a-f]{7,40})\[/g) {
            push @{ $commits_by_section{$section_name} }, $1;
        }
    }
}

# ------------------------------------------------------------
# Remove duplicates per section
# ------------------------------------------------------------

for my $sec (keys %commits_by_section) {
    my %seen;
    $commits_by_section{$sec} = [
        grep { !$seen{$_}++ } @{ $commits_by_section{$sec} }
    ];
}

# ------------------------------------------------------------
# Collect git info and write reports
# ------------------------------------------------------------

for my $sec (sort keys %commits_by_section) {

    my $outfile = File::Spec->catfile(
        $release_dir,
        "$sec.txt"
    );

    open my $out, '>', $outfile
        or die "Cannot write $outfile: $!";

    print "Generating $outfile\n";

    for my $hash (@{ $commits_by_section{$sec} }) {

        my $c = read_commit(
            src  => $src,
            hash => $hash,
        );

        print $out "============================================================\n";
        print $out "Commit: $hash\n";
        print $out "Date:   $c->{Date}\n";
        print $out "Subject:\n  $c->{Subject}\n\n";

        if ($c->{Body}) {
            print $out "Body:\n";
            for my $l (split /\n/, $c->{Body}) {
                print $out "  $l\n";
            }
            print $out "\n";
        }

        if ($c->{Files} && @{ $c->{Files} }) {
            print $out "Files:\n";
            for my $f (@{ $c->{Files} }) {
                print $out "  $f\n";
            }
            print $out "\n";
        }

        print $out "\n";
    }

    close $out;
}

print "Done.\n";
exit 0;

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

sub usage {
    my ($msg) = @_;
    print STDERR "ERROR: $msg\n\n" if $msg;

    print STDERR <<"USAGE";
Usage:
  relnotes_adoc_report.pl
      --release-dir <dir>
      --src <path-to-src-repo>

Description:
  Reads relnotes.adoc, extracts gitref hashes grouped by section,
  retrieves full git commit info, and writes per-section reports.
USAGE

    exit 1;
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
