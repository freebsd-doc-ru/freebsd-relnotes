#!/usr/bin/env perl
#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use FindBin;
use File::Spec;

use lib "$FindBin::Bin/../lib";

use Relnotes::Store;
use Relnotes::Util   qw(extract_sponsor_from_subject);
use Relnotes::Review qw(manual_check_stub);

# ------------------------------------------------------------

my $release_dir;

GetOptions(
    'release-dir=s' => \$release_dir,
) or die usage();

die usage() unless $release_dir;

# ------------------------------------------------------------
# Resolve paths

my $stage1_file = File::Spec->catfile(
    $release_dir, 'relnotes_stage1.txt'
);

my $stage2_file = File::Spec->catfile(
    $release_dir, 'relnotes_stage2.txt'
);

die "Stage1 file not found: $stage1_file\n"
    unless -f $stage1_file;

# ------------------------------------------------------------
# Read data

my @stage1 = Relnotes::Store::read_file($stage1_file);
my @stage2 = -f $stage2_file
           ? Relnotes::Store::read_file($stage2_file)
           : ();

my %stage2_commits = map { $_->{Commit} => 1 } @stage2;

# ------------------------------------------------------------
# Transfer logic

my @new_entries;

for my $e (@stage1) {

    my $hash = $e->{Commit};
    next if $stage2_commits{$hash};

    my ($sponsor, $clean_subject)
        = extract_sponsor_from_subject($e->{Subject});

    my $full_text = join "\n",
        $clean_subject,
        ($e->{Body} // '');

    my $review = Relnotes::Review::manual_check_stub($full_text);

    my %out = %$e;

    $out{Subject} = $clean_subject;
    $out{Sponsor} = $sponsor;
    $out{Status}  = $review->{result};   # proposed
    $out{Section} = $review->{section};   # e.g. Userland / Kernel / undecided
    $out{Body}    = $review->{text};

    push @new_entries, \%out;
}

# ------------------------------------------------------------
# Write result


if (@new_entries) {
    Relnotes::Store::append_file($stage2_file, \@new_entries);
    print "Transferred ", scalar(@new_entries),
          " commits to $stage2_file\n";
} else {
    print "No new commits to transfer\n";
}

exit 0;

# ------------------------------------------------------------

sub usage {
    return <<"USAGE";
Usage:
  relnotes_stage1_to_stage2.pl --release-dir releases/14.3R

Description:
  Transfers new commit entries from relnotes_stage1.txt
  to relnotes_stage2.txt inside the given release directory.

USAGE
}
