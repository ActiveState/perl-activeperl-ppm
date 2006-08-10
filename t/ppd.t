#!perl -w

use Test qw(plan ok);
plan tests => 30;

use ActivePerl::PPM::PPD;

my $ppd = ActivePerl::PPM::Package->new_ppd(<<'EOT', arch => "MSWin32-x86-multi-thread");
  <SOFTPKG NAME="Date-Calc" VERSION="5,4,0,0">
    <ABSTRACT>Gregorian calendar date calculations</ABSTRACT>
    <AUTHOR>Steffen Beyer (sb@engelschall.com)</AUTHOR>
    <IMPLEMENTATION>
      <ARCHITECTURE NAME="MSWin32-x86-multi-thread-5.8" />
      <CODEBASE HREF="http://ppm.activestate.com/PPMPackages/5.8-windows/MSWin32-x86-multi-thread-5.8/Date-Calc-5.4.tar.gz" />
      <DEPENDENCY NAME="Bit-Vector" VERSION="6,4,0,0" />
      <DEPENDENCY NAME="Carp-Clan" VERSION="5,3,0,0" />
      <OS NAME="MSWin32" />
    </IMPLEMENTATION>
    <IMPLEMENTATION>
      <ARCHITECTURE NAME="MSWin32-x86-multi-thread" />
      <CODEBASE HREF="http://ppm.activestate.com/PPMPackages/5.6-windows/MSWin32-x86-multi-thread-5.6/Date-Calc-5.4.tar.gz" />
      <DEPENDENCY NAME="Bit-Vector" VERSION="6,4,0,0" />
      <DEPENDENCY NAME="Carp-Clan" VERSION="5,3,0,0" />
      <INSTALL EXEC="PPM_PERL" HREF="sorry.pl">ignored</INSTALL>
      <UNINSTALL>false</UNINSTALL>
      <OS NAME="MSWin32" />
    </IMPLEMENTATION>
    <PROVIDE NAME="Date::Calc" VERSION="5.4"/>
    <TITLE>Date-Calc</TITLE>
  </SOFTPKG>
EOT

# use Data::Dump; Data::Dump::dump($ppd);

ok($ppd->name, "Date-Calc");
ok($ppd->version, "5.4");
ok($ppd->author, "Steffen Beyer (sb\@engelschall.com)");
ok($ppd->abstract, "Gregorian calendar date calculations");
ok($ppd->codebase, "http://ppm.activestate.com/PPMPackages/5.6-windows/MSWin32-x86-multi-thread-5.6/Date-Calc-5.4.tar.gz");

my %features;

%features = $ppd->provides;
ok(keys %features, 2);
ok(exists $features{"Date-Calc"});
ok(exists $features{"Date::Calc"});

%features = $ppd->requires;
ok(exists $features{"Bit-Vector"});
ok(exists $features{"Carp-Clan"});

ok($ppd->{script}{install}{exec}, "PPM_PERL");
ok($ppd->{script}{install}{uri}, "sorry.pl");
ok($ppd->{script}{install}{text}, undef);
ok($ppd->{script}{uninstall}{exec}, undef);
ok($ppd->{script}{uninstall}{uri}, undef);
ok($ppd->{script}{uninstall}{text}, "false");

# Try some to parse some bad stuff
ok(ActivePerl::PPM::Package->new_ppd("<foo>"), undef);
ok(ActivePerl::PPM::Package->new_ppd("<foo></foo><bar>"), undef);
ok(ActivePerl::PPM::Package->new_ppd(__FILE__), undef);
ok(ActivePerl::PPM::Package->new_ppd("t/repo/test1/Acme-Buffy.ppd"), undef);
ok(ActivePerl::PPM::Package->new_ppd("<HARDPKG/>"), undef);
ok(ActivePerl::PPM::Package->new_ppd("<SOFTPKG/>"), undef);
ok(ActivePerl::PPM::Package->new_ppd("<SOFTPKG NAME='Foo'/>"), undef);
ok(ActivePerl::PPM::Package->new_ppd("<SOFTPKG NAME='Foo' VERSION='0.1'/>"));  # works

# Another exampe
$ppd = ActivePerl::PPM::Package->new_ppd(<<'EOT', arch => "foo-bar");
  <SOFTPKG NAME="Foo" VERSION="a">
    <ARCHITECTURE NAME="bar"/>
    <CODEBASE HREF="xxx.tar.gz"/>
  </SOFTPKG>
EOT
ok($ppd->{name}, "Foo");
ok(!exists $ppd->{codebase});

$ppd = ActivePerl::PPM::Package->new_ppd(<<'EOT', arch => "foo-bar");
  <SOFTPKG NAME="Foo" VERSION="a">
    <ARCHITECTURE NAME="foo-bar"/>
    <CODEBASE HREF="xxx.tar.gz"/>
  </SOFTPKG>
EOT
ok($ppd->{name}, "Foo");
ok($ppd->{codebase}, "xxx.tar.gz");

$ppd = ActivePerl::PPM::Package->new_ppd(<<'EOT', arch => "foo-bar");
  <SOFTPKG NAME="Foo" VERSION="a">
    <ARCHITECTURE NAME="bar"/>
    <CODEBASE HREF="xxx.tar.gz"/>
    <IMPLEMENTATION>
       <ARCHITECTURE NAME="foo-bar"/>
       <CODEBASE HREF="yyy.tar.gz"/>
    </IMPLEMENTATION>
  </SOFTPKG>
EOT
ok($ppd->{name}, "Foo");
ok($ppd->{codebase}, "yyy.tar.gz");
