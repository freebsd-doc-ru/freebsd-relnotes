#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long;
use File::Spec;
use FindBin;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

my $release_dir;
my $repo_dir = '.';
my $help;

GetOptions(
    'release-dir=s' => \$release_dir,
    'repo-dir=s'    => \$repo_dir,
    'help'          => \$help,
) or usage();

usage() if $help;
usage("Missing --release-dir") unless $release_dir;

my $adoc_file = File::Spec->catfile(
    $release_dir,
    'relnotes.adoc'
);

die "relnotes.adoc not found: $adoc_file\n"
    unless -f $adoc_file;

# ------------------------------------------------------------
# Extract commit hashes from adoc
# ------------------------------------------------------------

my $commits = extract_gitrefs_with_section($adoc_file);

die "No commits found in relnotes.adoc\n"
    unless %$commits;

# ------------------------------------------------------------
# Collect info from git
# ------------------------------------------------------------

my @rows;

for my $hash (sort keys %$commits) {

    my ($email, $subject) = get_commit_info($repo_dir, $hash);

    next unless $email;

    push @rows, {
        email   => $email,
        commit  => $hash,
        subject => $subject,
        section => $commits->{$hash},
    };
}

# ------------------------------------------------------------
# Sort by email
# ------------------------------------------------------------

@rows = sort {
    lc($a->{email}) cmp lc($b->{email})
} @rows;

# ------------------------------------------------------------
# Output
# ------------------------------------------------------------
my $report_file = File::Spec->catfile(
    $release_dir,
    #'relnotes_committers_report.txt'
    'relnotes_authors_report.txt'
);

open my $out, '>', $report_file
    or die "Cannot write $report_file: $!";

printf $out "%-30s  %-20s  %-12s  %s\n",
    "Committer", "Section", "Commit", "Subject";

printf $out "%s\n", "-" x 90;

for my $r (@rows) {
    printf $out "%-30s  %-20s  %-12s  %s\n",
        $r->{email},
        substr($r->{section} // '',0,20),
        substr($r->{commit}, 0, 12),
        $r->{subject};
}

close $out;

print "Report written to $report_file\n";

exit 0;

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

sub usage {
    my ($msg) = @_;

    print STDERR "ERROR: $msg\n\n" if $msg;

    print STDERR <<"USAGE";
Usage:
  relnotes_committers_report.pl --release-dir <dir> [--repo-dir <git repo>]

Options:
  --release-dir   Path to release directory (contains relnotes.adoc)
  --repo-dir      Path to git repository (default: current dir)
  --help          Show this help
USAGE

    exit 1;
}

sub extract_gitrefs_with_section {
    my ($path) = @_;

    open my $fh, '<', $path
        or die "Cannot open $path: $!";

    my %seen;
    my $current_section = '';

    while (my $line = <$fh>) {

        # Заголовок секции (например: == Core)
        if ($line =~ /^==+\s+(.*)$/) {
            $current_section = $1;
            next;
        }

        while ($line =~ /gitref:([0-9a-f]{7,40})\[/g) {
            $seen{$1} = $current_section;
        }
    }

    close $fh;
    return \%seen;
}

sub get_commit_info {
    my ($repo_dir, $hash) = @_;

    my $cmd = sprintf(
        #"git -C %s show -s --format='%%ce%%n%%s' %s 2>/dev/null", #committer email
        "git -C %s show -s --format='%%ae%%n%%s' %s 2>/dev/null", # author email
        $repo_dir,
        $hash
    );

    my @out = `$cmd`;

    return unless @out >= 2;

    chomp @out;

    my $email   = $out[0];
    my $subject = $out[1];

    return ($email, $subject);
}
