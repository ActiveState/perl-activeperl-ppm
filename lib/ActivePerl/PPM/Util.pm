package ActivePerl::PPM::Util;

use strict;
use base 'Exporter';

our @EXPORT_OK = qw(is_cpan_package clean_err);

sub is_cpan_package {
    my $pkg_name = shift;
    return "" if $pkg_name =~ /^Active(State|Perl)-/;
    return "libwww-perl" if $pkg_name eq "LWP";
    return "TermReadKey" if $pkg_name eq "Term-ReadKey";
    return $pkg_name;  # assume everything else is
}

sub clean_err {
    my $err = shift;
    $err =~ s/ at .*//s unless $ENV{ACTIVEPERL_PPM_DEBUG};
    $err =~ s/ _at / at /g; # escape for when you really want "at" in the message
    $err =~ s/\n*\z//;
    return $err;
}

1;
