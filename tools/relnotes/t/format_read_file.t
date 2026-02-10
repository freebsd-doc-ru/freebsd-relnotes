use strict;
use warnings;
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Relnotes::Store;

my $file = "$FindBin::Bin/data/format_stage1_sample.txt";

ok(-f $file, 'Test data file exists');

my @records;
eval {
    @records = Relnotes::Store::read_file($file);
};
is($@, '', 'read_file() did not die');

is(scalar @records, 2, 'Two records parsed');

for my $rec (@records) {
    for my $field (qw(Commit Date Score Subject Body)) {
        ok(exists $rec->{$field}, "Field $field exists");
        ok(defined $rec->{$field}, "Field $field defined");
    }
}

is(
    $records[0]{Commit},
    'a2132d91739dc22b99e7da836c81962eed47b8f9',
    'First commit hash parsed correctly'
);

is(
    $records[0]{Date},
    '2025-04-01',
    'Date parsed correctly'
);

is(
    $records[0]{Score},
    5,
    'Score parsed correctly'
);

like(
    $records[0]{Body},
    qr/Line one of body.*Line two of body/s,
    'Body parsed as multiline text'
);

is(
    $records[1]{Score},
    7,
    'Second record score parsed correctly'
);

done_testing();

