#
# Copyright (c) 2026 Vladlen Popolitov
#
# SPDX-License-Identifier: BSD-2-Clause
#

package Relnotes::Git;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(read_commit);

sub read_commit {
    my (%args) = @_;

    my $src  = $args{src}  or die "read_commit: src is required";
    my $hash = $args{hash} or die "read_commit: hash is required";

    my $cmd = qq(git -C $src show -s  --date=short --format=%H%x00%ad%x00%B  $hash);

    open my $fh, '-|', $cmd
        or die "Cannot run git show for $hash\n";

    local $/;
    my $raw = <$fh>;
    close $fh;

    die "Empty git show output for $hash\n"
        unless defined $raw && length $raw;

    chomp $raw;

    my ($h, $date, $msg) = split /\x00/, $raw, 3;
    die "Malformed git show output for $hash\n"
        unless defined $msg;

    my ($subject, @body) = split /\n/, $msg;
    my $body = join "\n", @body;

    return {
        commit  => $h,
        Date    => $date,
        Subject => $subject,
        Body    => $body,
    };
}

1;
