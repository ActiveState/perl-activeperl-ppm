#!perl -w

use strict;
use Test;
use ActiveState::Run qw(shell_quote);
use ActiveState::Path qw(abs_path);
use Config qw(%Config);

plan tests => 18;

my $prefix_base = "xx$$.d";
(my $prefix = abs_path($prefix_base)) =~ s,\\,/,g;

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
$ENV{PERL5LIB} = "$prefix/lib";

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

ppm("area", "list", "--csv= ");
ok($ppm_out, qr/^\(\Q$prefix_base\E\)\s+n\/a\s+/m);
ppm("area", "init", $prefix_base);
ppm("area", "list", "--csv= ");
ok($ppm_out, qr/^\Q$prefix_base\E\*?\s+0\s+/m);
ok($ppm_out, qr/^site\*?\s+(\d+)/m);
ok($ppm_out, qr/^perl\s+(\d+)/m);

# try installing from our live repo
my $live_repo = 1;
$live_repo = 0 if $^O eq "aix";
$live_repo = 0 if $Config{archname} =~ /\b(ia|x|x86_)64\b/;
$live_repo = 0 if $Config{archname} =~ /\bsolaris(-\w+)*-64\b/;
$live_repo = 0 if $Config{archname} =~ /\bx86-solaris\b/;
if ($live_repo) {
    ppm("install", "File-Slurp", "--area", $prefix_base, "--force");
    ok($?, 0);
    ppm("verify", "File-Slurp");
    ok($?, 0);
    ok(ppm("files", "File-Slurp") =~ m,^\Q$prefix\E/lib/File/Slurp\.pm$,m);
    ok(ppm("remove", "File-Slurp"), "File-Slurp: uninstalled\n");
}
else {
    skip("No live repo for $Config{archname}") for 1..4;
}
