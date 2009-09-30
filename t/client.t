#!perl -w

BEGIN {
    return unless ActivePerl::PRODUCT() =~ /enterprise/i;
    print "1..0 # skipped: APED doesn't setup the default repo\n";
    exit 0;
}

use strict;
use Test qw(plan ok skip);
use URI::file;

plan tests => 33;

my $prefix = "xx$$.d";
if (-e $prefix) {
    $prefix = undef;  # prevent accidental clobber
    die;
}

sub j { join("|", map {defined($_) ? $_ : "<undef>"} @_) }
sub file_eq { require File::Compare; File::Compare::compare(@_) == 0 };

use ActivePerl::PPM::Client;

my $client = ActivePerl::PPM::Client->new($prefix, inc => []);
ok(j($client->areas), "site|perl");
undef($client);

$client = ActivePerl::PPM::Client->new($prefix, inc => []);
ok(j($client->areas), "site|perl");
ok($client->area("site")->name, "site");

my $repo = $client->repo(1);
if (!$repo) {
    if ($^O ne "linux" && $^O ne "MSWin32") {
	skip("No ActiveState Package Repository for $^O") for 1..8;
    }
    else {
	die "No ActiveState Package Repository set up";
    }
}
else {
    ok($repo->{enabled});
    ok($repo->{id}, 1);
    ok($repo->{name}, "ActiveState Package Repository");
    ok($repo->{prio}, 1);
    ok($repo->{packlist_uri}, qr,^http://ppm4.ActiveState.com/,i);
    ok($repo->{packlist_last_status_code}, undef);
    $client->repo_enable(1, 0);
    ok($client->repo(1)->{enabled}, 0);
    $client->repo_delete(1);
    ok(j($client->repos), "");
}

undef($client);

$client = ActivePerl::PPM::Client->new($prefix);
ok(j($client->repos), "");
$client->repo_add(name => "Test repo", packlist_uri => URI::file->new_abs("t/repo/test1/"));
ok(j($client->repos), "1");

$repo = $client->repo(1);
ok($repo->{enabled});
ok($repo->{id}, 1);
ok($repo->{name}, "Test repo");
ok($repo->{prio}, 0);
ok($repo->{packlist_uri}, qr,^file:///.*t/repo/test1/$,);

ok(j($client->search("*Buffy")), "Acme-Buffy");

$client->repo_enable(1, 0);  # disable it
$repo = $client->repo(1);
ok(!$repo->{enabled});
ok(j($client->search("*Buffy")), "");

$client->repo_add(name => "Test repo", packlist_uri => URI::file->new_abs("t/repo/test2/"));
$repo = $client->repo(2);
ok($repo->{enabled});
ok($repo->{id}, 2);
ok($repo->{name}, "Test repo");
ok($repo->{prio}, 0);
ok($repo->{packlist_uri}, qr,^file:///.*t/repo/test2/package.lst$,);

ok(j($client->search("*Buffy")), "Acme-Buffy");

$client->config_save(foo => 42, bar => 33);
ok($client->config_get("foo"), 42);
ok(j($client->config_get("bar", "foo")), "33|42");
ok(j($client->config_get("not-there", "bar")), "<undef>|33");
undef($client);

$client = ActivePerl::PPM::Client->new($prefix);
ok($client->config_get("foo"), 42);
ok($client->config_get("not-there"), undef);
$client->config_save(bar => "*");
ok($client->config_get("bar"), "*");


END {
    undef($client);  # close any database handles
    if ($prefix && -d $prefix) {
	#system("sqlite3", "$prefix/ppm.db", ".dump");
	require File::Path;
	File::Path::rmtree($prefix, 1);
    }
}
