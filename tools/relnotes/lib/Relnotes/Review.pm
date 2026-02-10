#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

package Relnotes::Review;
use strict;
use warnings;

sub manual_check_stub {
    my ($text) = @_;

    my @lines = split /\n/, $text;
    splice @lines, 3 if @lines > 3;

    @lines = map { "  DEBUG>> $_" } @lines;

    return {
        result => 'proposed',
        text   => join("\n", @lines),
        section => 'undecided',
    };
}

1;
