#!perl -w

use strict;
use Test;
plan tests => 4;

use ActivePerl::PPM::ParsePPD;

my $p = ActivePerl::PPM::ParsePPD->new(sub {
    my $ppd = shift;
    print "$ppd->{name}\n";
    ok($ppd->{name}, qr/^A/);
});

open(my $fh, "<", "t/repo/test2/package.lst");
my $buf;
while (read($fh, $buf, 12)) {
    print "# --\n";
    $p->parse_more($buf);
}
$p->parse_done;
