#!perl -w

use strict;
use Test qw(plan ok);

plan tests => 20;

use ActivePerl::PPM::Package;

*vcmp = \&ActivePerl::PPM::Package::_vcmp;

ok(vcmp(0, 0), 0);
ok(vcmp(1, 0), 1);
ok(vcmp(0, 1), -1);

ok(vcmp("1.0", "1.0"), 0);
ok(vcmp("1.0", "1.1"), -1);
ok(vcmp("1.2", "1.0"), 1);
ok(vcmp("1.01", "1.10"), -1);

ok(vcmp("1.1", "1.10"), 0);  # XXX really

ok(vcmp("1.1", "1.1.1"), -1);
ok(vcmp("1.1.1", "1.1.2"), -1);

ok(vcmp("1.1", "1.1a"), -1);
ok(vcmp("1.1a", "1.1b"), -1);
ok(vcmp("1.1b", "1.1b"), 0);
ok(vcmp("1.1c", "1.1b"), 1);

ok(vcmp("1_1beta", "1_1"), -1);

ok(vcmp("foo", "foo"), 0);
ok(vcmp("foo", "bar"), undef);
ok(vcmp(1, undef), undef);
ok(vcmp(undef, 1), undef);
ok(vcmp(undef, undef), undef);

