use strict;
use warnings;
use Test::More;

use lib 'lib';
use Relnotes::Workflow;

my $entries = [
    {
        commit => 'abc1234',
        Date   => '2026-01-28',
        Score  => 5,
        Status => 'accepted',
    },
    {
        commit => 'deadbeef',
        Date   => '28-01-2026',
        Score  => 42,
        Status => 'unknown',
    },
    {
        commit => 'feedface',
        Score  => 3,
    },
];

my $res = Relnotes::Workflow->validate_entries($entries);

is(scalar @{ $res->{errors} }, 3, 'three validation errors');
is(scalar @{ $res->{warnings} }, 1, 'one warning (missing Date)');

like($res->{errors}[0], qr/invalid Date/,   'date error detected');
like($res->{errors}[1], qr/invalid Score/,  'score error detected');
like($res->{errors}[2], qr/invalid Status/, 'status error detected');

done_testing;

