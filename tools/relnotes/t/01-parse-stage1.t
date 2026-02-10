use strict;
use warnings;
use Test::More;

use lib 'lib';
use Relnotes::Workflow;

my $entries = Relnotes::Workflow->parse_file(
    't/data/stage1_sample.txt'
);

is(scalar @$entries, 1, 'one commit parsed');
is($entries->[0]{Score}, 5, 'default score is 5');
is($entries->[0]{Date}, '2026-01-28', 'date parsed');

done_testing;

