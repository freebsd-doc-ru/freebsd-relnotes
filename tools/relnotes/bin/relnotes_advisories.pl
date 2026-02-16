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
use Cwd 'abs_path';

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

my ($repo, $branch, $advisories_dir, $release_dir, $dry_run, $help, $format_list, $format_relnotes);

GetOptions(
    'repo=s'           => \$repo,
    'branch=s'         => \$branch,
    'advisories-dir=s' => \$advisories_dir,
    'release-dir=s'    => \$release_dir,
    'dry-run'          => \$dry_run,
    'help|h'          => \$help,
    'format-list'      => \$format_list,
    'format-relnotes'  => \$format_relnotes,
) or die "Invalid parameters\n";

if ($help) {
    print <<"USAGE";
Usage: $0 --repo <path> --branch releng/X.Y \\
          --advisories-dir <path> --release-dir <path> [--dry-run]

Options:
  --repo             Path to FreeBSD git repository
  --branch           Target release branch (e.g. releng/14.4)
  --advisories-dir   Directory with SA/EN .asc files
  --release-dir      Output directory
  --dry-run          Do not write file, print to stdout
  -h, --help         Show this help

Stage1 logic:
  Advisory is applicable iff:
    commit ∈ target branch
    AND
    commit ∉ previous release tag

USAGE
    exit 0;
}
$format_list = 1 unless $format_relnotes;   # default is format_list
die "--repo required\n"           unless $repo;
die "--branch required\n"         unless $branch;
die "--advisories-dir required\n" unless $advisories_dir;
die "--release-dir required\n"    unless $release_dir;

$repo           = abs_path($repo);
$advisories_dir = abs_path($advisories_dir);
$release_dir    = abs_path($release_dir);

# ------------------------------------------------------------
# Parse releng/X.Y
# ------------------------------------------------------------

$branch =~ m{^releng/(\d+)\.(\d+)$}
    or die "--branch must be releng/X.Y\n";

my ($major, $minor) = ($1, $2);

my $target_branch = $branch;
my $stable_branch = "stable/$major";

my ($prev_tag);
if ($minor > 0) {
    $prev_tag = sprintf("refs/tags/release/%d.%d.0", $major, $minor - 1); # exactly tag
}
else
{
    $prev_tag = sprintf("refs/tags/release/%d.0.0", $major - 1); # exactly tag
}

# verify branches exist
run_git_die("rev-parse $target_branch");

if ($prev_tag) {
    my $rc = run_git("rev-parse $prev_tag");
    if ($rc != 0) {
        warn "Previous tag $prev_tag not found — skipping previous check\n";
        $prev_tag = undef;
    }
}

# ------------------------------------------------------------
# Collect advisories
# ------------------------------------------------------------

opendir my $dh, $advisories_dir or die "Cannot open $advisories_dir: $!\n";

my @files = grep {
    /^FreeBSD-(SA|EN)-\d+:\d+\..+\.asc$/
} readdir $dh;

closedir $dh;

# ------------------------------------------------------------
# Process advisories
# ------------------------------------------------------------

my @results;

for my $file (sort @files) {

    my $path = File::Spec->catfile($advisories_dir, $file);

    my ($type, $id) = parse_filename($file);

    my $info = parse_correction_details($path);

    my $branches  = $info->{branches};
    my $topic     = $info->{topic};
    my $announced = $info->{announced};

    my ($chosen_branch, $hash) =
        choose_commit($branches, $target_branch, $stable_branch);

    my $applicable = 0;

    if ($hash) {

        my $in_target = is_ancestor($hash, $target_branch);

        if ($in_target) {

            if ($prev_tag) {
                my $in_prev = is_ancestor($hash, $prev_tag);
                $applicable = $in_prev ? 0 : 1;
            }
            else {
                # no previous branch (X.0)
                $applicable = 1;
            }
        }
    }

   push @results, {
        id            => $id,
        type          => $type,
        source_branch => $chosen_branch // '',
        hash          => $hash // '',
        applicable    => $applicable ? 'true' : 'false',
        topic         => $topic,
        announced     => $announced,
    };
}

# ------------------------------------------------------------
# Output
# ------------------------------------------------------------

my $out_fh;
my $out;

if ($dry_run) {
    $out_fh = *STDOUT;
}
else {
    $out = File::Spec->catfile($release_dir, "stage1_advisories.txt");
    open $out_fh, '>', $out or die "Cannot write $out: $!\n";
}

for my $r (@results) {
        my $announced = $r->{announced} // '';
        my $topic     = $r->{topic} // '';
        my $formatted_date = format_announced_date($announced);

    # --------------------------------------------------------
    # FORMAT: RELNOTES
    # --------------------------------------------------------
    if ($format_relnotes) {

        next unless $r->{applicable} eq 'true';

        my $filename = $r->{id} . ".asc";
        my $noext    = $r->{id};
        # convert command(1) to man:command(1) format
        $topic =~ s/\b([A-Za-z][A-Za-z-_]*)\(([1-9])\)/man:$1\[$2\]/g;

        print $out_fh "\n";
        print $out_fh '| link:https://www.FreeBSD.org/security/advisories/'.$filename.'['.$noext."]\n";
        print $out_fh "| $formatted_date\n";
        print $out_fh "| $topic\n";
    }

    # --------------------------------------------------------
    # FORMAT: LIST (старый формат)
    # --------------------------------------------------------
    else {
        if ($dry_run) {
            print join(" | ",
                $r->{id},
                $r->{type},
                $r->{source_branch} || '-',
                $r->{hash} || '-',
                $r->{applicable}, $announced, $topic
            ), "\n";

        }
        else {
            print $out_fh "[advisory $r->{id}]\n";
            print $out_fh "Type: $r->{type}\n";
            print $out_fh "Source-Branch: $r->{source_branch}\n";
            print $out_fh "Commit: $r->{hash}\n";
            print $out_fh "Applicable: $r->{applicable}\n";
            print $out_fh "Announced: $announced\n";
            print $out_fh "Topic: $topic\n";
            print $out_fh "\n";
    }
    }
}

if (!$dry_run) {
    close $out_fh;
    print "Processed ", scalar(@results), " advisories\n";
    print "Results written to $out\n";
}
# ============================================================
# Functions
# ============================================================

sub parse_filename {
    my ($file) = @_;
    $file =~ /^FreeBSD-(SA|EN)-(\d+:\d+)\./
        or die "Bad filename format: $file\n";
    return ($1, "FreeBSD-$1-$2");
}

sub parse_correction_details {
    my ($path) = @_;

    open my $fh, '<', $path
        or die "Cannot open $path: $!\n";

    my %branches;
    my $in_section = 0;

    my $topic      = '';
    my $announced  = '';

    while (my $line = <$fh>) {

        chomp $line;

        # --------------------------------------------
        # Capture Topic
        # --------------------------------------------
        if (!$topic && $line =~ /^Topic:\s*(.+)$/i) {
            $topic = $1;
            next;
        }

        # --------------------------------------------
        # Capture Announced
        # --------------------------------------------
        if (!$announced && $line =~ /^Announced:\s*(\d{4}-\d{2}-\d{2})/i) {
            $announced = $1;
            next;
        }

        # --------------------------------------------
        # Correction details section
        # --------------------------------------------
        if ($line =~ /^VI\.\s+Correction details/i) {
            $in_section = 1;
            next;
        }

        next unless $in_section;

        last if $line =~ /^[IVX]+\.\s+/;

        if ($line =~ m{^\s*(\S+?)\s+([0-9a-f]{7,40})\b}) {
            my ($branch, $hash) = ($1, $2);
            $branch =~ s{/$}{};
            $branches{$branch} = $hash;
        }
    }

    close $fh;

    return {
        branches  => \%branches,
        topic     => $topic,
        announced => $announced,
    };
}

sub choose_commit {
    my ($branches, $target_branch, $stable_branch) = @_;

    return ($target_branch, $branches->{$target_branch})
        if exists $branches->{$target_branch};

    return ($stable_branch, $branches->{$stable_branch})
        if exists $branches->{$stable_branch};

    return (undef, undef);
}

sub is_ancestor {
    my ($hash, $branch) = @_;
    my $rc = run_git("merge-base --is-ancestor $hash $branch");
    return $rc == 0 ? 1 : 0;
}

sub run_git {
    my ($args) = @_;
    my $cmd = "git -C $repo $args > /dev/null 2>&1";
    system($cmd);
    return $? >> 8;
}

sub run_git_die {
    my ($args) = @_;
    my $rc = run_git($args);
    die "git $args failed\n" if $rc != 0;
}

sub format_announced_date {
    my ($date) = @_;

    # ожидаем формат типа: 2024-01-17
    if ($date =~ /^(\d{4})-(\d{2})-(\d{2})/) {
        my ($y, $m, $d) = ($1, $2, $3);

        my @months = qw(
            January February March April May June
            July August September October November December
        );

        return sprintf("%d %s %d", $d, $months[$m-1], $y);
    }

    return $date;   # fallback
}
