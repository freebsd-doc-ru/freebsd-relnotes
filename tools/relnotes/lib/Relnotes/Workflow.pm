#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

package Relnotes::Workflow;

use strict;
use warnings;

use Relnotes::Store;

my %VALID_STATUS = map { $_ => 1 } qw(
    pending
    accepted
    rejected
    merged
);

sub parse_lines {
    my ($class, $lines) = @_;
    my @entries;
    my $cur;

    for my $line (@$lines) {
        chomp $line;

        if ($line =~ /^\[commit\s+([0-9a-f]{7,40})\]/) {
            push @entries, $cur if $cur;
            $cur = { commit => $1 };
            next;
        }

        next unless $cur;

        if ($line =~ /^(\w+):\s*(.*)$/) {
            $cur->{$1} = $2;
        }
        elsif ($line =~ /^\s+(.*)$/) {
            push @{ $cur->{_multiline} }, $1;
        }
    }

    push @entries, $cur if $cur;

    for my $e (@entries) {
        if ($e->{_multiline}) {
            $e->{Summary} = join "\n", @{ $e->{_multiline} };
            delete $e->{_multiline};
        }
        $e->{Score} //= 5;
    }

    return \@entries;
}

sub parse_file {
    my ($class, $path) = @_;

    my @lines = Relnotes::Store::read_lines($path);
    return $class->parse_lines(\@lines);
}


sub parse_file_delme {
    my ($class, $path) = @_;
    open my $fh, '<', $path or die "Cannot open $path: $!";

    my @entries;
    my $cur;

    while (my $line = <$fh>) {
        chomp $line;

        if ($line =~ /^\[commit\s+([0-9a-f]{7,40})\]/) {
            push @entries, $cur if $cur;
            $cur = { commit => $1 };
            next;
        }

        next unless $cur;

        if ($line =~ /^(\w+):\s*(.*)$/) {
            $cur->{$1} = $2;
        }
        elsif ($line =~ /^\s+(.*)$/) {
            push @{ $cur->{_multiline} }, $1;
        }
    }

    push @entries, $cur if $cur;
    close $fh;

    for my $e (@entries) {
        if ($e->{_multiline}) {
            $e->{Summary} = join "\n", @{ $e->{_multiline} };
            delete $e->{_multiline};
        }
        $e->{Score} //= 5;
    }

    return \@entries;
}

sub validate_entries {
    my ($class, $entries) = @_;

    my @errors;
    my @warnings;

    for my $e (@$entries) {
        my $id = $e->{commit} // '<unknown>';

        # Date
        if (exists $e->{Date}) {
            if ($e->{Date} !~ /^\d{4}-\d{2}-\d{2}$/) {
                push @errors, "commit $id: invalid Date format '$e->{Date}'";
            }
        } else {
            push @warnings, "commit $id: missing Date";
        }

        # Score
        if (!defined $e->{Score}) {
            $e->{Score} = 5;
        }
        elsif ($e->{Score} !~ /^\d+$/ || $e->{Score} < 1 || $e->{Score} > 10) {
            push @errors, "commit $id: invalid Score '$e->{Score}' (must be 1..10)";
        }

        # Status
        if (exists $e->{Status}) {
            if (!$VALID_STATUS{ $e->{Status} }) {
                push @errors, "commit $id: invalid Status '$e->{Status}'";
            }
        }
    }

    return {
        errors   => \@errors,
        warnings => \@warnings,
    };
}

sub sort_for_adoc {
    my ($class, $entries) = @_;

    return [
        sort {
            ($b->{Score} <=> $a->{Score})
                ||
            ($b->{Date} cmp $a->{Date})
        } @$entries
    ];
}

1;
