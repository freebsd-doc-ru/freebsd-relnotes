#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

package Relnotes::Store;

use strict;
use warnings;
use Carp qw(croak);

sub read_file {
    my ($file) = @_;
    open my $fh, '<', $file or croak "Can't open $file: $!";

    my @records;
    my $current;
    my $in_body = 0;

    while (my $line = <$fh>) {
        chomp $line;

        # New commit block
        if ($line =~ /^\[commit\s+([0-9a-f]{7,40})\]/) {
            push @records, $current if $current;
            $current = {
                Commit => $1,
                Body   => '',
            };
            $in_body = 0;
            next;
        }

        next unless $current;   # ignore garbage before first commit

        if ($line =~ /^Commit:\s*(.+)$/) {
            $current->{Commit} = $1;
            next;
        }

        if ($line =~ /^Date:\s*(.+)$/) {
            $current->{Date} = $1;
            next;
        }

        if ($line =~ /^Score:\s*(\d+)/) {
            $current->{Score} = int($1);
            next;
        }

        if ($line =~ /^Subject:\s*(.*)$/) {
            $current->{Subject} = $1;
            next;
        }

        if ($line =~ /^Status:\s*(.*)$/) {
            $current->{Status} = $1;
            next;
        }

        if ($line =~ /^Sponsor:\s*(.*)$/) {
            my $s = $1;

            if (exists $current->{Sponsor} && defined $current->{Sponsor} && $current->{Sponsor} ne '') {
                $current->{Sponsor} .= " | $s";
            } else {
                $current->{Sponsor} = $s;
            }

            next;
        }

        if ($line =~ /^Section:\s*(.*)$/) {
            $current->{Section} = $1;
            next;
        }

        if ($line =~ /^Review:\s*(.*)$/) {
            $current->{Review} = $1;
            next;
        }

        if ($line =~ /^Body:\s*$/) {
            $in_body = 1;
            next;
        }

        if ($in_body) {
            $current->{Body} .= $line . "\n";
            next;
        }
    }
    if (defined $current->{Body}) {
        $current->{Body} =~ s/\s+\z//;
    }
    push @records, $current if $current;

    close $fh;
    return @records;
}

sub read_lines {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot open $path: $!";
    my @lines = <$fh>;
    close $fh;
    return @lines;
}

sub append_file {
    my ($file, $records) = @_;

    open my $fh, '>>', $file
        or die "Can't open $file for append: $!";

    for my $h (@$records) {


        print $fh "[commit $h->{Commit}]\n";
        print $fh "Date: $h->{Date}\n"     if defined $h->{Date};
        print $fh "Score: $h->{Score}\n"   if defined $h->{Score};
        print $fh "Status: $h->{Status}\n" if defined $h->{Status};
        print $fh "Sponsor: $h->{Sponsor}\n" if defined $h->{Sponsor};
        print $fh "Section: $h->{Section}\n" if defined $h->{Section};
        print $fh "Subject: $h->{Subject}\n" if defined $h->{Subject};
        print $fh "Review: $h->{Review}\n" if defined $h->{Review};

        print $fh "Body:\n";
        if (defined $h->{Body}) {
            my $body = $h->{Body};
            $body =~ s/\s+\z//;   # убрать лишние хвостовые переводы строк
            print $fh "$body\n";
        }

        print $fh "\n";
    }

    close $fh;
}

sub write_file {
    my ($path, $records) = @_;

    die "write_file(): records must be ARRAY ref"
        unless ref $records eq 'ARRAY';

    open my $fh, '>', $path
        or die "Cannot write $path: $!";

    for my $r (@$records) {

        print $fh "[commit $r->{Commit}]\n";

        # фиксированный порядок полей — ВАЖНО
        for my $field (qw(
            Date
            Score
            Status
            Sponsor
            Section
            Subject
            Review
        )) {
            next unless exists $r->{$field};
            next unless defined $r->{$field};

            print $fh "$field: $r->{$field}\n";
        }

        if (defined $r->{Body} && $r->{Body} ne '') {
            for my $line (split /\n/, $r->{Body}) {
                print $fh "$line\n";
            }
        }

        print $fh "\n";
    }

    close $fh;
    return 1;
}

1;
