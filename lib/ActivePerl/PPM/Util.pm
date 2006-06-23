package ActivePerl::PPM::Util;

use strict;
use base 'Exporter';

our @EXPORT_OK = qw(is_cpan_package);

sub is_cpan_package {
    my $pkg_name = shift;
    return 0 if $pkg_name =~ /^Active(State|Perl)-/;
    return 1;  # assume everything else is
}

1;
