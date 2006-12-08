#!perl -w

use strict;
use Test qw(plan ok);
plan tests => 8;

use ActivePerl::PPM::Util qw(is_cpan_package clean_err join_with);

ok(is_cpan_package("Foo"), "Foo");
ok(is_cpan_package("ActivePerl-Foo"), "");

ok(clean_err("foo at x.pl line 32"), "foo");
ok(clean_err("foo _at bar"), "foo at bar");

ok(join_with("and", "foo"), "foo");
ok(join_with("and", "foo", "bar"), "foo and bar");
ok(join_with("and", "foo", "bar", "baz"), "foo, bar and baz");
ok(join_with("or", 1..10), "1, 2, 3, 4, 5, 6, 7, 8, 9 or 10");
