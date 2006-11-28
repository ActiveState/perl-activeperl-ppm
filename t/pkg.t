#!perl -w

use strict;
use Test qw(plan ok);

plan tests => 28;

use ActivePerl::PPM::Package ();

my($p1, $p2, $p3);

$p1 = ActivePerl::PPM::Package->new(name => "Foo");
$p2 = ActivePerl::PPM::Package->new({name => "Bar", version => "1.2"});
$p3 = $p2->clone;
$p3->{version} = "1.3";

ok($p1->name, "Foo");
ok($p2->name, "Bar");
ok($p1->name_version, "Foo");
ok($p2->name_version, "Bar-1.2");
ok($p3->name_version, "Bar-1.3");

ok($p1->compare($p2), undef);
ok(eval { $p1->better_than($p2)}, undef);
ok($@, qr/^No ordering between package Foo and Bar-1.2/);

ok(eval { ActivePerl::PPM::Package::best($p1, $p2) }, undef);
ok($@);

$p1 = ActivePerl::PPM::Package->new(
    name => "Foo",
    version => "beta1",
    provide => {
        "Foo::" => 1,
        "Foo::Bar" => 1.01,
    },
);

$p2 = ActivePerl::PPM::Package->new(
    name => "Foo",
    version => "beta2",
    provide => {
        "Foo::" => 1,
        "Foo::Bar" => 1.02,
    },
);

ok($p1->name_version, "Foo-beta1");
ok($p1->compare($p1), 0);
ok($p1->compare($p2), -1);
ok($p2->compare($p1), 1);

ok(!$p1->better_than($p2));
ok($p2->better_than($p1));

ok(ActivePerl::PPM::Package::best($p1, $p2)->name_version, "Foo-beta2");
ok(ActivePerl::PPM::Package::best($p2, $p1)->name_version, "Foo-beta2");

$p3 = $p2->clone;
$p3->{version} = "beta1";

ok($p2->compare($p3), 1);

$p3->{version} = "beta2";
ok($p2->compare($p3), 0);

$p3->{version} = "beta3";
ok($p2->compare($p3), -1);

$p3->{provide}{"Foo::Baz"} = 1;
ok($p2->compare($p3), -1);
ok($p3->compare($p2), 1);

ok(!$p2->better_than($p3));
ok($p3->better_than($p2));

ok(ActivePerl::PPM::Package::best($p1, $p2, $p3)->name_version, "Foo-beta3");
ok(ActivePerl::PPM::Package::best($p2, $p1, $p3)->name_version, "Foo-beta3");
ok(ActivePerl::PPM::Package::best($p3, $p2, $p1)->name_version, "Foo-beta3");
