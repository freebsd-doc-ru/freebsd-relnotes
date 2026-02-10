use strict;
use warnings;
use Test::More;

use lib 'lib';
use Relnotes::Workflow;

my $data = [
    { commit => 'a', Score => 5, Date => '2026-01-10' },
    { commit => 'b', Score => 9, Date => '2026-01-01' },
    { commit => 'c', Score => 9, Date => '2026-02-01' },
];

my $sorted = Relnotes::Workflow->sort_for_adoc($data);

is($sorted->[0]{commit}, 'c', 'score desc, date desc');
is($sorted->[1]{commit}, 'b', 'same score, earlier date');
is($sorted->[2]{commit}, 'a', 'lower score last');

done_testing;

