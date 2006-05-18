#!perl -w

use strict;
use Test;
use ActiveState::Run qw(shell_quote);

plan tests => 10;

my $prefix = "xx$$.d";
if (-e $prefix) {
    $prefix = undef;
    die;  # prevent accidental clobber
}

mkdir($prefix, 0755);

END {
    if ($prefix && -d $prefix) {
	system("sqlite3", "$prefix/ppm.db", ".dump");
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



