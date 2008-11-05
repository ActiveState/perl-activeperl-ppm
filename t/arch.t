#!perl -w

use strict;
use Test qw(plan ok);
plan tests => 1;

use ActivePerl::PPM::Arch qw(arch short_arch pretty_arch @archs);

print "# arch = ", arch(), "\n";
print "# short_arch = ", short_arch(), "\n";
print "# pretty_arch = ", pretty_arch(), "\n";

ok(length(arch()) > length(short_arch()));

for (@archs, "noarch", "noarch-5.8") {
    printf "# %-22s %s\n", $_, pretty_arch($_);
}
