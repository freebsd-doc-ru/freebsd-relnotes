#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#


package Relnotes::Util;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    extract_sponsor_from_subject
);

# ------------------------------------------------------------
# Extract sponsor from commit subject
#
# Examples:
#   "Fix foo (Sponsored by ABC Corp)"
#   "Fix foo [Sponsored by ABC Corp]"
#   "Fix foo Sponsored by ABC Corp"
#
# Returns:
#   ($sponsor, $clean_subject)
# ------------------------------------------------------------

sub extract_sponsor_from_subject {
    my ($subject) = @_;

    return ('', $subject) unless defined $subject;

    if ($subject =~ s/\s*[\[(]?SSponsored by:\s+([^\]\)]+)[\])]?//i) {
        my $sponsor = $1;
        $sponsor =~ s/\s+$//;
        return ($sponsor, $subject);
    }

    return ('', $subject);
}

1;
