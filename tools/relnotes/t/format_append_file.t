use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

use lib 'tools/relnotes/lib';
use Relnotes::Store;

# Temporary directory for test output
my $tmpdir = tempdir(CLEANUP => 1);
my $outfile = File::Spec->catfile($tmpdir, 'stage2.txt');

ok(!-e $outfile, 'Output file does not exist initially');

my @records = (
    {
        Commit  => 'deadbeef1111',
        Date    => '2025-04-01',
        Score   => 5,
        Status  => 'proposed',
        Sponsor => 'The FreeBSD Foundation',
        Subject => 'Test subject one',
        Body    => "Line one of body\nLine two of body",
    },
    {
        Commit  => 'deadbeef2222',
        Date    => '2025-04-02',
        Score   => 7,
        Status  => 'accepted',
        Subject => 'Test subject two',
        Body    => "Single line body",
    },
);

# Write records
ok(
    Relnotes::Store::append_file($outfile, \@records) // 1,
    'append_file() executed without dying'
);

ok(-f $outfile, 'Output file created');

# Re-read file
my @parsed = Relnotes::Store::read_file($outfile);

is(scalar @parsed, 2, 'Two records read back');

# First record
is($parsed[0]->{Commit},  'deadbeef1111', 'Commit parsed correctly (1)');
is($parsed[0]->{Date},    '2025-04-01',   'Date parsed correctly (1)');
is($parsed[0]->{Score},   5,              'Score parsed correctly (1)');
is($parsed[0]->{Status},  'proposed',     'Status parsed correctly (1)');
is($parsed[0]->{Sponsor}, 'The FreeBSD Foundation', 'Sponsor parsed correctly (1)');
is($parsed[0]->{Subject}, 'Test subject one', 'Subject parsed correctly (1)');
like(
    $parsed[0]->{Body},
    qr/Line one of body.*Line two of body/s,
    'Body parsed as multiline text (1)'
);

# Second record
is($parsed[1]->{Commit},  'deadbeef2222', 'Commit parsed correctly (2)');
is($parsed[1]->{Date},    '2025-04-02',   'Date parsed correctly (2)');
is($parsed[1]->{Score},   7,              'Score parsed correctly (2)');
is($parsed[1]->{Status},  'accepted',     'Status parsed correctly (2)');
is($parsed[1]->{Subject}, 'Test subject two', 'Subject parsed correctly (2)');
is($parsed[1]->{Body},    'Single line body', 'Body parsed correctly (2)');

done_testing;
