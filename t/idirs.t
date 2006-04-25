#!perl -w

use strict;
use Test qw(plan ok);

plan tests => 16;

my $prefix = "xx$$.d";
if (-e $prefix) {
    $prefix = undef;
    die;  # prevent accidental clobber
}

sub j { join("|", @_) }

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
$dir->init_db;

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
    files => {
        "t/idirs.t" => "lib:idirs.t",
        "t/repo.t" => "archlib:repo.t",
    },
}));

ok($dir->install({
    name => "Foo2",
    files => {
        "t/repo.t" => "lib:idirs.t",
	"t/repo" => "bin:",
    },
}));

ok($dir->verify);

END {
    #system("echo .dump | sqlite3 $prefix/etc/ppm.db");
    if ($prefix && -d $prefix) {
	require File::Path;
	File::Path::rmtree($prefix, 1);
    }
}
