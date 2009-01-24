#!perl -w

use strict;
use Test::More tests => 14;

use ActivePerl::PPM::Profile ();

my $profile = ActivePerl::PPM::Profile->new(<<EOT);
<PPMPROFILE>
  <ACTIVEPERL VERSION="1004" PERL_VERSION="5.10.0" PPM_VERSION="4.04"/>
  <REPOSITORY NAME="ActiveState Package Repository" HREF="http://ppm4.activestate.com/darwin/5.10/1004/package.xml"/>
  <REPOSITORY NAME="log4perl" HREF="http://log4perl.sourceforge.net/ppm" ENABLED="0"/>
  <SOFTPKG NAME="BSD-Resource" VERSION="1.28"/>
  <SOFTPKG NAME="File-Next" VERSION="1.02"/>
  <SOFTPKG NAME="mylib" VERSION="0.02"/>
</PPMPROFILE>
EOT

ok($profile);

is($profile->activeperl_version, "1004");
ok(!utf8::is_utf8($profile->activeperl_version));
is($profile->perl_version, "5.10.0");
is($profile->ppm_version, "4.04");

is($profile->repositories, 2);
is($profile->packages, 3);

my @repos = $profile->repositories;
is($repos[0]->{name}, "ActiveState Package Repository");
is($repos[0]->{href}, "http://ppm4.activestate.com/darwin/5.10/1004/package.xml");
ok($repos[0]->{enabled});
is($repos[1]->{href}, "http://log4perl.sourceforge.net/ppm");
ok(!$repos[1]->{enabled});

my @pkgs = $profile->packages;
is($pkgs[0]->{name}, "BSD-Resource");
is($pkgs[0]->{version}, "1.28");

