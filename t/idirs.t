#!perl -w

use strict;
use Test qw(plan ok);

plan tests => 44;

my $prefix = "xx$$.d";
if (-e $prefix) {
    $prefix = undef;
    die;  # prevent accidental clobber
}

sub j { join("|", @_) }
sub file_eq { require File::Compare; File::Compare::compare(@_) == 0 };

use ActivePerl::PPM::IDirs;

my $dir = ActivePerl::PPM::IDirs->new(prefix => $prefix);
ok($dir->name, "");
ok($dir->prefix, $prefix);
ok($dir->lib, "$prefix/lib");
ok($dir->etc, "$prefix/etc");
ok(j($dir->inc), "$prefix/lib");
ok($dir->packages, 0);
ok(j($dir->packlists), "");
ok($dir->verify);

$dir = ActivePerl::PPM::IDirs->new(prefix => $prefix);

eval { $dir->install(); };    ok($@, qr/^No packages to install/);
eval { $dir->install({}); };  ok($@, qr/^Missing package name/);

ok($dir->install({
    name => "Foo",
    version => "1.0a",
    author => "Foo <foo\@example.com>",
    abstract => "To foo or not to foo",
}));
ok($dir->packages, 1);
ok(j($dir->packages), "Foo");

ok($dir->install({
    name => "Foo2",
    abstract => "Abs",
    files => {
        "t/idirs.t" => "lib:idirs.t",
        "t/logger.t" => "archlib:logger.t",
    },
}));
ok($dir->packages, 2);
ok(j($dir->packages), "Foo|Foo2");

my @pkg = $dir->packages("name", "version", "abstract");
ok(@pkg, 2);
ok($pkg[0][0], "Foo");
ok($pkg[0][1], "1.0a");
ok($pkg[1][2], "Abs");

ok(-f "$prefix/lib/idirs.t");
ok(file_eq("t/idirs.t", "$prefix/lib/idirs.t"));
ok(-f "$prefix/lib/logger.t");
ok(file_eq("t/logger.t", "$prefix/lib/logger.t"));
ok(j($dir->package_files("Foo2")), "$prefix/lib/auto/Foo2/.packlist|$prefix/lib/idirs.t|$prefix/lib/logger.t");
ok($dir->verify);

ok($dir->install({
    name => "Foo2",
    files => {
        "t/logger.t" => "lib:idirs.t",
	"t/repo" => "bin:",
    },
}));
ok($dir->packages, 2);
ok(j($dir->packages), "Foo|Foo2");
ok(-f "$prefix/lib/idirs.t");
ok(file_eq("t/logger.t", "$prefix/lib/idirs.t"));
ok(!-f "$prefix/lib/logger.t");
ok(-f "$prefix/bin/test1/Acme-Buffy.ppd");
ok(file_eq("t/repo/test1/Acme-Buffy.ppd", "$prefix/bin/test1/Acme-Buffy.ppd"));
ok($dir->verify);

$dir->uninstall("Foo2");
ok($dir->packages, 1);
ok(j($dir->packages), "Foo");
ok(!-f "$prefix/lib/idirs.t");
ok(!-f "$prefix/bin/test1/Acme-Buffy.ppd");
ok($dir->verify);

eval { $dir->uninstall("Foo2") };
ok($@, qr/^Package Foo2 isn't installed/);

$dir->uninstall("Foo");
ok($dir->packages, 0);
ok(j($dir->packages), "");
ok($dir->verify);

END {
    #system("echo .dump | sqlite3 $prefix/etc/ppm.db");
    if ($prefix && -d $prefix) {
	require File::Path;
	File::Path::rmtree($prefix, 1);
    }
}
