#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

package Relnotes::Review;
use strict;
use warnings;

sub manual_check_stub {
    my ($text, $included) = @_;
# ------------------------------------------------------------
# Try to load external automatic reviewer
# ------------------------------------------------------------
    my $has_auto;

    {
        local $@;
        eval {
            require Relnotes::ReviewAuto;
            Relnotes::ReviewAuto->import();
            $has_auto = 1;
        };
    }

    if ($has_auto && Relnotes::ReviewAuto->can('manual_check_stub')) {
        return Relnotes::ReviewAuto::manual_check_stub($text, $included);
    }

# ------------------------------------------------------------
# Fallback: local stub implementation
# ------------------------------------------------------------
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
