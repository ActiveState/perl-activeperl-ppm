#!perl -w

use Test qw(plan ok);
plan tests => 4;

use ActivePerl::PPM::Repo;

my $repo = ActivePerl::PPM::Repo->new("t/repo/test1");

ok($repo);
ok($repo->name, "Test Repo One");
ok($repo->prio, 1);
ok($repo->url =~ /^file:/);
