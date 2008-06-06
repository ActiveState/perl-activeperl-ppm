package ActivePerl::PPM::Arch;

use strict;
use base 'Exporter';

our @EXPORT_OK = qw(arch short_arch pretty_arch);

use Config qw(%Config);

sub arch {
    my $arch = $Config{archname};
    if ($] >= 5.008) {
        my $vstring = sprintf "%vd", $^V;
        $vstring =~ s/\.\d+$//;
        $arch .= "-$vstring";
    }
    return $arch;
}

sub short_arch {
    my $arch = arch();
    1 while $arch =~ s/-(thread|multi|2level)//;
    return $arch;
}

sub pretty_arch {
    my $arch = shift || arch();
    1 while $arch =~ s/-(thread|multi|2level)//;
    my $perl = "5.6";
    $perl = $1 if $arch =~ s/-(5\.\d\d?)$//;
    if ($arch eq "darwin") {
        $arch = "Mac OS X";
    }
    elsif ($arch eq "aix") {
        $arch = "AIX";
    }
    elsif ($arch =~ /^MSWin32-x86(_64)?$/) {
        $arch = "Windows";
        $arch .= " 64" if $1;
    }
    else {
        $arch = ucfirst($arch);  # lame
    }
    return "ActivePerl $perl on $arch";
}

1;

__END__

=head1 NAME

ActivePerl::PPM::Arch - Get current architecture identification

=head1 DESCRIPTION

The following functions are provided:

=over

=item arch()

Returns the string that PPM use to identify the architecture of the
current perl.  This is what goes into the NAME attribute of the
ARCHITECTURE element of the PPD files; see L<ActivePerl::PPM::PPD>.

This is L<$Config{archname}> with the perl major version number
appended.

=item short_arch()

This is the shorteded architecture string; dropping the segments for
features that will always be enabled for ActivePerl ("thread",
"multi", "2level").

Used to form the URL for the PPM CPAN repositories provided by
ActiveState.

=item pretty_arch()

=item pretty_arch( $arch )

Returns a more human readable form of arch().  Will be a string on the form:

   "ActivePerl 5.10 for Windows 64"

=back

=head1 SEE ALSO

L<ppm>, L<ActivePerl::PPM::PPD>, L<Config>
