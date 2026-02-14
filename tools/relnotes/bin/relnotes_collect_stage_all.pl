#!/usr/bin/env perl
#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

use strict;
use warnings;
use Getopt::Long;
use FindBin;
use POSIX qw(strftime);


# ------------------------------------------------------------
# Locate our own library regardless of cwd
# ------------------------------------------------------------
use lib "$FindBin::Bin/../lib";
use Relnotes::Workflow;
use Relnotes::Git qw(read_commit);

# ------------------------------------------------------------
# CLI arguments
# ------------------------------------------------------------

my ($src, $branch, $from, $to, $release_dir);

GetOptions(
    'src=s'         => \$src,
    'branch=s'      => \$branch,
    'from=s'        => \$from,
    'to=s'          => \$to,
    'release-dir=s' => \$release_dir,
) or die "Invalid arguments\n";

die "--src, --from, --to, --release-dir are required\n"
    unless $src  && $from && $to && $release_dir;

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

my $stage1 = "$release_dir/relnotes_stage_all.txt";

# ------------------------------------------------------------
# Load existing entries (if any)
# ------------------------------------------------------------

my %known;
if (-f $stage1) {
    my $existing = Relnotes::Workflow->parse_file($stage1);
    %known = map { $_->{commit} => 1 } @$existing;
}

# ------------------------------------------------------------
# Git log
# ------------------------------------------------------------

my $range = "$from..$to";

my $cmd = qq(
    git -C $src log --format=%H $range
);

#print $cmd;

open my $lst, '-|', $cmd
    or die "Cannot run git log in $src\n";
my @hashes = map { chomp; $_ } <$lst>;
close $lst;

my @new;

for my $hash (@hashes) {
    next if $known{$hash};

    my $c = read_commit(
        src  => $src,
        hash => $hash,
    );

    $c->{Score} = 5;   # default
    push @new, $c;
}

exit 0 unless @new;

# ------------------------------------------------------------
# Ensure release dir exists
# ------------------------------------------------------------

if (!-d $release_dir) {
    die "Release directory does not exist: $release_dir\n";
}

# ------------------------------------------------------------
# Append to stage1 file
# ------------------------------------------------------------

open my $fh, '>>', $stage1
    or die "Cannot open $stage1 for append: $!";

for my $e (@new) {
    print $fh "\n[commit $e->{commit}]\n";
    print $fh "Commit: $e->{commit}\n";
    print $fh "Date: $e->{Date}\n";
    print $fh "Score: $e->{Score}\n";
    print $fh "Sponsor: $e->{Sponsor}\n";
    print $fh "Subject: $e->{Subject}\n";

    if ($e->{Body}) {
        print $fh "Body:\n";
        for my $l (split /\n/, $e->{Body}) {
            print $fh "  $l\n";
        }
    }
}

close $fh;

print scalar(@new) . " new relnotes candidates added\n";

