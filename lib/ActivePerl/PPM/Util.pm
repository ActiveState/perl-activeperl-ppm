package ActivePerl::PPM::Util;

use strict;
use base 'Exporter';

our @EXPORT_OK = qw(is_cpan_package);

sub is_cpan_package {
    my $pkg_name = shift;
    return "" if $pkg_name =~ /^Active(State|Perl)-/;
    return "libwww-perl" if $pkg_name eq "LWP";
    return "TermReadKey" if $pkg_name eq "Term-ReadKey";
    return $pkg_name;  # assume everything else is
}

1;
