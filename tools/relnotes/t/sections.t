use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Spec;
use FindBin;

use lib "$FindBin::Bin/../lib";

use Relnotes::Sections;

# ------------------------------------------------------------
# Prepare temporary release directory

my $tmp_release = tempdir(CLEANUP => 1);

print STDERR $FindBin::Bin;


my $src_csv = File::Spec->catfile(
    $FindBin::Bin, '../..', 'sections.csv'
);

ok(-f $src_csv, 'Test sections.csv exists');

my $dst_csv = File::Spec->catfile(
    $tmp_release, 'sections.csv'
);

copy($src_csv, $dst_csv)
    or die "Cannot copy sections.csv: $!";

ok(-f $dst_csv, 'sections.csv copied into release dir');

# ------------------------------------------------------------
# Load sections

my $sections = Relnotes::Sections::load_sections($tmp_release);

ok($sections, 'Sections loaded');
is(ref $sections, 'HASH', 'Returned value is a hashref');

# ------------------------------------------------------------
# Check parsed co

done_testing();