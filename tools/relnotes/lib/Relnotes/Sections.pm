#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#


# load_sections($release_dir) → \%sections
#
# {
#   'Userland.programs' => {
#       anchor => 'userland-programs',
#       title  => 'Userland Application Changes',
#   },
#   ...
# }
package Relnotes::Sections;

use strict;
use warnings;
use FindBin;
use File::Spec;

sub load_sections {
    my ($release_dir) = @_;

    my @candidates;

    if ($release_dir) {
        push @candidates,
            File::Spec->catfile($release_dir, 'sections.csv');
    }

    push @candidates,
        File::Spec->catfile($FindBin::Bin, '..', 'sections.csv');

    my $path;
    for my $p (@candidates) {
        if (-f $p) {
            $path = $p;
            last;
        }
    }

    die "sections.csv not found\n" unless $path;

    open my $fh, '<', $path
        or die "Cannot open $path: $!";

    my %sections;

    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;
        next if $line =~ /^Section\s*,/;

        my ($section, $anchor, $title) = split /\s*,\s*/, $line, 3;

        next unless $section && $anchor;

        $sections{$section} = {
            anchor => $anchor,
            title  => $title // '',
        };
    }

    close $fh;

    return \%sections;
}

1;
