#!perl -w

use strict;
use Test qw(plan ok);
use Config qw(%Config);
use File::Path qw(rmtree mkpath);

plan tests => 107, todo => [72];

my $prefix = "xx$$.d";
if (-e $prefix) {
    $prefix = undef;
    die;  # prevent accidental clobber
}

delete $ENV{ACTIVEPERL_PPM_HOME};  # avoid overrides

sub j { join("|", @_) }
sub file_eq { require File::Compare; File::Compare::compare(@_) == 0 };

use ActivePerl::PPM::InstallArea;

my $dir = ActivePerl::PPM::InstallArea->new(prefix => $prefix);
ok($dir->name, "");
ok($dir->prefix, $prefix);
ok($dir->lib, "$prefix/lib");
ok($dir->archlib, "$prefix/lib");
ok($dir->etc, "$prefix/etc");
ok($dir->bin, "$prefix/bin");
ok($dir->html, "$prefix/html");
ok($dir->script, "$prefix/bin");
ok(j($dir->inc), "$prefix/lib");
ok($dir->packages, 0);
ok(j($dir->packlists), "");
ok($dir->verify);

$dir = ActivePerl::PPM::InstallArea->new("site");
ok($dir->name, "site");
ok($dir->lib, $Config{sitelib});
$dir = undef;
# avoid hitting methods that needs to create a database, since
# we don't really want to update stuff the perl that runs this
# test

$dir = ActivePerl::PPM::InstallArea->new(prefix => $prefix);

ok($dir->packages, 0);
ok(j($dir->packages), "");
ok($dir->package(0), undef);
ok($dir->package(1), undef);
ok($dir->package_id("Foo"), undef);

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
        "t/install-area.t" => "lib:install-area.t",
        "t/logger.t" => "archlib:logger.t",
    },
}));
ok($dir->packages, 2);
ok(j($dir->packages), "Foo|Foo2");

my @pkg = $dir->packages("name", "version", "abstract", "id");
ok(@pkg, 2);
ok($pkg[0][0], "Foo");
ok($pkg[0][1], "1.0a");
ok($pkg[1][2], "Abs");

ok(-f "$prefix/lib/install-area.t");
ok(file_eq("t/install-area.t", "$prefix/lib/install-area.t"));
ok(-f "$prefix/lib/logger.t");
ok(file_eq("t/logger.t", "$prefix/lib/logger.t"));
ok(j($dir->package_files($pkg[1][3])), "$prefix/lib/auto/Foo2/.packlist|$prefix/lib/install-area.t|$prefix/lib/logger.t");
ok($dir->verify);

ok($dir->install({
    name => "Foo2",
    files => {
        "t/logger.t" => "lib:install-area.t",
	"t/repo" => "bin:",
    },
}));
ok($dir->packages, 2);
ok(j($dir->packages), "Foo|Foo2");
ok(-f "$prefix/lib/install-area.t");
ok(file_eq("t/logger.t", "$prefix/lib/install-area.t"));
ok(!-f "$prefix/lib/logger.t");
ok(-f "$prefix/bin/test1/Acme-Buffy.ppd");
ok(file_eq("t/repo/test1/Acme-Buffy.ppd", "$prefix/bin/test1/Acme-Buffy.ppd"));
ok($dir->verify);

$dir->uninstall("Foo2");
ok($dir->packages, 1);
ok(j($dir->packages), "Foo");
ok(!-f "$prefix/lib/install-area.t");
ok(!-f "$prefix/bin/test1/Acme-Buffy.ppd");
ok($dir->verify);

eval { $dir->uninstall("Foo2") };
ok($@, qr/^Package Foo2 isn't installed/);

$dir->uninstall("Foo");
ok($dir->packages, 0);
ok(j($dir->packages), "");
ok($dir->verify);

# Another install attempt
{
    my $status = $dir->install({
        name => "PPM",
        version => "4.0",
        abstract => "Abs",
        blib => ".",
    });
    ok($status);
    ok($status->{count}{installed} > 40);
    ok($status->{pkg}{PPM}{new_version}, "4.0");
    ok($status->{pkg}{PPM}{packlist}, "$prefix/lib/auto/PPM/.packlist");
    ok(-f "$prefix/bin/ppm");
    ok(-f "$prefix/lib/ActivePerl/PPM/InstallArea.pm");

    $dir->uninstall("PPM");
    ok($dir->packages, 0);
    ok(!-f "$prefix/bin/ppm");
    ok(!-d "$prefix/lib/ActivePerl");

    # Let's try the same install, but this time force failure that
    # triggers roolbak
    local $ActivePerl::PPM::InstallArea::FAIL_AT_END_OF_INSTALL = 1;
    $status = eval { $dir->install({
        name => "PPM",
        version => "4.0",
        abstract => "Abs",
        blib => ".",
    })};
    ok(!$status);
    ok($dir->packages, 0);
    ok(!-f "$prefix/bin/ppm");
    ok(!-d "$prefix/lib/ActivePerl");

    # Try rollback with an install that has changed a few files
    $ActivePerl::PPM::InstallArea::FAIL_AT_END_OF_INSTALL = 0;
    $status = $dir->install({
        name => "PPM",
        version => "4.0",
        abstract => "Abs",
        blib => ".",
    });
    ok($dir->packages, 1);

    $ActivePerl::PPM::InstallArea::FAIL_AT_END_OF_INSTALL = 1;
    $status = eval { $dir->install({
	name => "PPM",
        version => "4.0001",
        abstract => "Don't care",
	files => {
            lib => "lib:",
        }
    })};
    ok($dir->packages, 1);
    ok(-f "$prefix/bin/ppm");
    ok($dir->verify);  # XXX currently fails
}

# test readonliness
my $db_file = "$prefix/etc/ppm-area.db";
chmod(0400, $db_file) || warn "Can't make $db_file readonly: $!";
$dir = ActivePerl::PPM::InstallArea->new(prefix => $prefix);
ok($dir->readonly);
chmod(0600, $db_file) || warn "Can't make $db_file writable: $!";
$dir = ActivePerl::PPM::InstallArea->new(prefix => $prefix);
ok(!$dir->readonly);
$dir = undef;

rmtree($prefix, 1);
mkdir($prefix, 0555);  # non-writable directory
$dir = ActivePerl::PPM::InstallArea->new(prefix => $prefix);
ok($dir->lib, "$prefix/lib");
ok($dir->readonly);
ok($dir->packages, 0);
ok(j($dir->packages), "");

chmod(0755, $prefix) || warn "Can't make $prefix writable: $!";
$dir = ActivePerl::PPM::InstallArea->new(prefix => $prefix, name => "foo");
ok($dir->name, "foo");
ok($dir->lib, "$prefix/lib");
ok(!$dir->readonly);
ok($dir->packages, 0);
$dir->sync_db;
ok($dir->packages, 0);

# simulate manual install
my $fh;
mkpath("$prefix/lib/auto/Dummy", 1, 0755);
open($fh, ">$prefix/lib/auto/Dummy/.packlist")|| die;
close($fh);
mkpath("$prefix/lib/auto/Foo/Bar", 1, 0755);
open($fh, ">$prefix/lib/auto/Foo/Bar/.packlist")|| die;
print $fh "$prefix/lib/Foo/Bar.pm\n";
close($fh);
mkpath("$prefix/lib/Foo", 1, 0755);
open($fh, ">$prefix/lib/Foo/Bar.pm") || die;
print $fh "package Foo::Bar;
use strict;
our \$VERSION = q(1.00);
1;
";
close($fh) || die;

# see if sync_db notice them
$dir->sync_db;
ok($dir->packages, 2);
my $pkg;

ok($pkg = $dir->package("Dummy"));
ok($pkg->{name}, "Dummy");
ok($pkg->{version}, undef);
ok(j($dir->package_files($pkg->{id})), "$prefix/lib/auto/Dummy/.packlist");
ok($dir->package_packlist($pkg->{id}), "$prefix/lib/auto/Dummy/.packlist");

ok($pkg = $dir->package("Foo-Bar"));
ok($pkg->{name}, "Foo-Bar");
ok($pkg->{version}, "1.00");
ok(j($dir->package_files($pkg->{id})), "$prefix/lib/Foo/Bar.pm|$prefix/lib/auto/Foo/Bar/.packlist");
ok($dir->package_packlist($pkg->{id}), "$prefix/lib/auto/Foo/Bar/.packlist");

ok(!$dir->package("foo-bar"));
ok($pkg = $dir->package("foo-bar", sloppy => 1));
ok($pkg->{name}, "Foo-Bar");

ok($pkg = $dir->package("foo::bar", sloppy => 1));
ok($pkg->{name}, "Foo-Bar");

$dir->sync_db;
ok($dir->packages, 2);

# simulate manual removal of Dummy
unlink("$prefix/lib/auto/Dummy/.packlist") || warn;
$dir->sync_db;
ok($dir->packages, 1);

# simulate update of Foo::Bar
open($fh, ">$prefix/lib/Foo/Bar.pm") || die;
print $fh "package Foo::Bar;
use strict;
our \$VERSION = q(1.01);
1;
";
close($fh) || die;
$dir->sync_db;
ok($dir->packages, 1);
ok($pkg = $dir->package("Foo-Bar"));
ok($pkg->{version}, "1.01");

# feature_have
ok($dir->feature_have("foo-bar"), undef);
ok($dir->feature_have("Foo-Bar"), "0E0");
ok($dir->feature_have("Foo::Bar"), "1.01");

END {
    if ($prefix && -d $prefix) {
	#system("sqlite3", $db_file, ".dump");
	rmtree($prefix, 1);
    }
}
