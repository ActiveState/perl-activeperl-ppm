#!perl -w

use strict;
use Test qw(plan ok);
plan tests => 1;

use ActivePerl::PPM::Arch qw(arch short_arch pretty_arch);

print "# arch = ", arch(), "\n";
print "# short_arch = ", short_arch(), "\n";
print "# pretty_arch = ", pretty_arch(), "\n";

ok(length(arch()) > length(short_arch()));
