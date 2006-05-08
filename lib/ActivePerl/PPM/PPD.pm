package ActivePerl::PPM::PPD;

use strict;
use ActivePerl::PPM::ParsePPD ();
use ActivePerl::PPM::Package ();
use ActivePerl::PPM::Logger qw(ppm_log);

sub ActivePerl::PPM::Package::new_ppd {
    my($class, $data, $arch) = @_;
    $arch ||= do {
	require Config;
	my $tmp = $Config::Config{archname};
	$tmp .= sprintf "-%vd", substr($^V, 0, 2) if $] >= 5.008;
	$tmp;
    };

    my $pkg;
    my $p = ActivePerl::PPM::ParsePPD->new(sub {
	$pkg = shift;
    });
    eval {
	$p->parse_more($data);
	$p->parse_done;
    };
    if ($@) {
	# malformed XML
	ppm_log("ERR", $@);
	return undef;
    }

    # Move relevant attributes for the matching implementation up
    for my $impl (@{$pkg->{implementation} || []}) {
	my $impl_arch = $impl->{architecture} || "noarch";
	if ($arch eq $impl_arch || $impl_arch eq "noarch") {
	    for my $k (keys %$impl) {
		if (ref($impl->{$k}) eq "HASH") {
		    for my $k2 (keys %{$impl->{$k}}) {
			$pkg->{$k}{$k2} = $impl->{$k}{$k2};
		    }
		}
		else {
		    $pkg->{$k} = $impl->{$k};
		}
	    }
	}
    }
    delete $pkg->{implementation};  # not used any more

    # convert legacy OSD version number
    for my $version ($pkg->{version}) {
	if ($version =~ /^\d+(?:,\d+){3}/) {
	    $version =~ s/,/./g;
	    1 while $version =~ s/(\d\.\d+)\.0+$/$1/;  # drop trailing '.0's
	}
    }

    $pkg->{arch} = $arch;

    return $class->new($pkg);
}

1;

__END__

=head1 NAME

ActivePerl::PPM::PPD - Parser for PPD files

=head1 SYNOPSIS

  my $ppd = ActivePerl::PPM::Package->new_ppd('<SOFTPKG NAME="Foo">...</SOFTPKG>');

=head1 DESCRIPTION

This module adds the C<new_ppd> constructor to the
C<ActivePerl::PPM::Package> class.  This constructor parses PPD
files and allow package objects to be initialized from these
files. PPD is an XML based format that is used to describe PPM
packages.

The following methods are added:

=over

=item $ppd = ActivePerl::PPM::Package->new_ppd( $ppd_document, $archname )

The constructor take a literal document as
argument and will return and object representing the PPD.  The method
return C<undef> if $ppd_document does not contain the expected XML.

The $archname should be specified to select attributes for a specific
architecture where the PPD describes multiple implementations.  The
$archname argument defaults to the value $Config{arch} with the major
version number appended.  Use the value C<noarch> to only select
implementation sections without any ARCHITECTURE restriction.

=back

=head1 PPD XML FORMAT

The PPM PPD is an XML based format that normally use the F<.ppd>
extension.  The format is based on the now defunct OSD specification
(L<http://www.w3.org/TR/NOTE-OSD>).  This shows an example of a
minimal PPD document:

  <SOFTPKG NAME="Acme-Buffy" VERSION="1.3" DATE="2002-03-27">
    <AUTHOR>Leon Brocard (leon@astray.com)</AUTHOR>
    <ABSTRACT>
      An encoding scheme for Buffy the Vampire Slayer fans
    </ABSTRACT>
    <PROVIDE NAME="Acme::Buffy" VERSION="1.3"/>
    <IMPLEMENTATION>
      <CODEBASE HREF="i686-linux-thread-multi-5.8/Acme-Buffy.tar.gz" />
      <ARCHITECTURE NAME="i686-linux-thread-multi-5.8" />
    </IMPLEMENTATION>
  </SOFTPKG>

=head2 Changes since PPM3

The PPD format changed in PPM4.  This section lists what's different:

=over

=item *

The format of the SOFTPKG/VERSION attribute has been relaxed.  This
attribute should now contain the version identifier as used for the
original package.  PPM will not be able to order packages based on
this label.

=item *

The SOFTPKG/DATE attribute has been introduced.  This should be the
release date of the package.  For CPAN packages this should be the
date when the package was uploaded to CPAN.

=item *

Added REQUIRE and PROVIDE elements that are used to describe
features that this package depends on and provides.  The NAME
attribute is required for both.  The VERSION attribute is optional and
should be a floating number.  Features are assumed to be backwards
compatible and a feature with a higher version number is regarded
better.

=item *

The DEPENDENCY elements are deprecated.  Use REQUIRE instead.  If
present they are mapped to REQUIRE but their VERSION attribute is
ignored.

=item *

The OS, OSVERSION, PROCESSOR, PERLCORE elements are deprecated and
always ignored.  Implementations are matched using the ARCHITECTURE
element and nothing more.

=item *

The TITLE element is deprecated and ignored.  The SOFTPKG/NAME
attribute is the title.

=back

=head1 SEE ALSO

L<ActivePerl::PPM::Package>, L<http://www.w3.org/TR/NOTE-OSD>

