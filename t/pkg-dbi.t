#!perl -w

use strict;
use Test qw(plan ok);

plan tests => 23;

use ActivePerl::PPM::Package ();
use DBI;

my $db = "xx-pkg-dbi-$$.db";
if (-d $db) {
    my $msg = "$db is in the way, aborting";
    undef($db);
    die $msg;
}

END {
    return unless $db;
    #system("sqlite3 $db .dump");
    unlink($db);
}

my $dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", {
    AutoCommit => 0,
    PrintError => 0,
});
#$dbh->trace(1);

print "# Using SQLite v$dbh->{sqlite_version} with DBI v$DBI::VERSION\n";

for my $create (ActivePerl::PPM::Package->sql_create_tables()) {
    #print "$create\n";
    $dbh->do($create);
}
$dbh->commit;

ok(ActivePerl::PPM::Package->new_dbi($dbh, 1), undef);

my $pkg = ActivePerl::PPM::Package->new(name => "Foo");
my $id = $pkg->dbi_store($dbh);
$dbh->commit;
ok($id);
ok($pkg = ActivePerl::PPM::Package->new_dbi($dbh, $id));
ok($pkg->{id}, $id);

$pkg->version("1.1");
$pkg->abstract("Foo is better than bar");

ok($pkg->dbi_store($dbh), $id);
$dbh->commit;

ok($pkg = ActivePerl::PPM::Package->new_dbi($dbh, $id));
ok($pkg->name_version, "Foo-1.1");
ok($pkg->abstract, "Foo is better than bar");

$pkg = $pkg->clone;
$pkg->name("Bar");
$id = $pkg->dbi_store($dbh);
$dbh->commit;

ok($pkg = ActivePerl::PPM::Package->new_dbi($dbh, $id));
ok($pkg->name_version, "Bar-1.1");
ok($pkg->abstract, "Foo is better than bar");

$pkg = ActivePerl::PPM::Package->new(name => "Foo", version => "1.1");
ok($pkg->dbi_store($dbh));

$pkg->version("1.2");
ok($pkg->dbi_store($dbh));

# start over again with a new database
$dbh->disconnect;
unlink($db) || die "Can't unlink $db: $!";

$dbh = DBI->connect("dbi:SQLite:dbname=$db", "", "", {
    AutoCommit => 0,
    PrintError => 0,
});
#$dbh->trace(1);

for my $create (ActivePerl::PPM::Package->sql_create_tables(name_unique => 1)) {
    #print "$create\n";
    $dbh->do($create);
}
$dbh->commit;

$pkg = ActivePerl::PPM::Package->new(name => "Foo", version => "1.1");
ok($pkg->dbi_store($dbh), 1);

$pkg = ActivePerl::PPM::Package->new(name => "Foo", version => "1.2");
ok($pkg->dbi_store($dbh), undef);  # fails because (name) not unique

$dbh->commit;

# test storing package with lots of features
$pkg = ActivePerl::PPM::Package->new(name => "Bar", version => "1.0");
$pkg->{require}{'Foo::Bar'} = 1.1;
$pkg->{provide}{'Bar::'} = 1.0;
$pkg->{provide}{'Good feeling'} = 0;

$pkg->{script}{install}   = { exec => "PPM_PERL", text => q(print "Hello, world!\n"), };
$pkg->{script}{uninstall} = { exec => "PPM_PERL", uri => "http://www.example.com/goodbye.pl", };

ok($pkg->dbi_store($dbh), 2);
undef($pkg);
$dbh->commit;

$pkg = ActivePerl::PPM::Package->new_dbi($dbh, 2);
ok($pkg->name_version, "Bar-1.0");
ok($pkg->{id}, 2);
ok($pkg->{provide}{"Good feeling"}, 0);
ok($pkg->{require}{"Foo::Bar"}, 1.1);
ok($pkg->{script}{install}{exec}, "PPM_PERL");
ok($pkg->{script}{install}{uri}, undef);
ok($pkg->{script}{install}{text}, q(print "Hello, world!\n"));

$dbh->disconnect;
