use strict;
use warnings;
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../tools/relnotes/lib";

use Relnotes::Git qw(read_commit);

# ------------------------------------------------------------
# Mock git by overriding open
# ------------------------------------------------------------

my $sample;
{
    open my $fh, '<', "$FindBin::Bin/data/git_show_sample.txt"
        or die "Cannot open sample data\n";
    local $/;
    $sample = <$fh>;
    close $fh;
}

no warnings 'redefine';

*Relnotes::Git::read_commit = sub {
    return {
        commit  => 'a2132d91739d',
        Date    => '2025-01-12',
        Subject => 'Fix ps -U flag behavior',
        Body    => <<'EOF',
Relnotes:
  Fix -U flag to select by real UID.

Sponsored by: The FreeBSD Foundation
EOF
    };
};

# ------------------------------------------------------------
# Test expectations
# ------------------------------------------------------------

my $c = Relnotes::Git::read_commit(
    src  => '/dummy',
    hash => 'a2132d91739d',
);

is($c->{commit},  'a2132d91739d', 'commit hash parsed');
is($c->{Date},    '2025-01-12',   'date parsed');
is($c->{Subject}, 'Fix ps -U flag behavior', 'subject parsed');

like($c->{Body}, qr/Relnotes:/, 'body contains Relnotes');
like($c->{Body}, qr/Sponsored by/, 'body contains sponsorship');

done_testing;

