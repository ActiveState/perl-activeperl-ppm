#!perl -w

use strict;
use Test;
use ActiveState::Run qw(shell_quote);

plan tests => 20;

my $prefix = "xx$$.d";
if (-e $prefix) {
    $prefix = undef;
    die;  # prevent accidental clobber
}

mkdir("$prefix",     0755) || die;
mkdir("$prefix/lib", 0755) || die;

END {
    if ($prefix && -d $prefix) {
	#system("sqlite3", "$prefix/ppm.db", ".dump");
	require File::Path;
	File::Path::rmtree($prefix, 1);
    }
}

$ENV{ACTIVEPERL_PPM_HOME} = $prefix;

my @PPM = ($^X, (-d "blib" ? "-Mblib" : "-Ilib"), "bin/ppm");

my $ppm_out;
my $ppm_err;

sub ppm {
    print "\n# \$ ppm @_\n";
    $ppm_out = readpipe shell_quote(@PPM, @_) . " 2>$prefix/error";
    for (split(/^/, $ppm_out)) {
	print "# $_";
    }
    $ppm_err = "";
    open(my $fh, "<", "$prefix/error") || die "Can't read back error";
    while (<$fh>) {
	print "#ERR $_";
	$ppm_err .= $_;
    }
    close($fh);

    return $ppm_out;
}

ppm("version");
ok($ppm_out, qr/^ppm \d+/);
ok($ppm_err, "");
ok($ppm_out, ppm("--version"));
ok($ppm_err, "");

ppm("foo");
ok($ppm_out, "");
ok($ppm_err, qr/^Usage:\s+ppm\b/m);

ok(ppm("help"), qr/^SYNOPSIS\b/m);
ok(ppm("help", "help"), qr/this file/);
ok(ppm("help", "foo"), "Sorry, no help for 'foo'\n");
ok($ppm_err, "");

ppm("area");
ok($ppm_out, qr/^\s+home\s+0\s+/m);
ok($ppm_out, qr/^\s*->\s+site\s+(\d+)/m);
ok($ppm_out, qr/^\s+perl\s+(\d+)/m);
ok(ppm("area", "--current"), "site\n");

ppm("area", "--current", "home");
ok($?, 0);
ok(ppm("area", "--current"), "home\n");
die unless $ppm_out eq "home\n";  # don't want installs anywhere else

# try installing from our live repo
ppm("install", "Tie-Log");
ok($?, 0);
ppm("verify", "Tie-Log");
ok($?, 0);
ok(ppm("files", "Tie-Log"), qr,^\Q$prefix\E/lib/Tie/Log.pm$,m);
ok(ppm("remove", "Tie-Log"), "Tie-Log: uninstalled\n");
