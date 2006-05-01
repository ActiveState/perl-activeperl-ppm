package ActivePerl::PPM::PPD;

use strict;
use XML::Simple ();
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

    my $xml = eval { XML::Simple::XMLin($data,
	KeepRoot => 1,  # so that we can verify root
        ForceArray => [qw(IMPLEMENTATION DEPENDENCY PROVIDES REQUIRES)],
    ) };
    if ($@) {
	# malformed XML
	ppm_log("ERR", $@);
	return undef;
    }

    if (!exists $xml->{SOFTPKG}) {
	ppm_log("Root element isn't <SOFTPKG>");
	return undef;
    }
    $xml = $xml->{SOFTPKG};  # discard root

    if (!(exists $xml->{NAME} && exists $xml->{VERSION})) {
	ppm_log("Required SOFTPKG attribute NAME and VERSION missing");
	return undef;
    }

    # Move relevant attributes for the matching implementation up
    for my $impl (@{$xml->{IMPLEMENTATION} || []}) {
	my $impl_arch = $impl->{ARCHITECTURE}{NAME} || "noarch";
	if ($arch eq $impl_arch || $impl_arch eq "noarch") {
	    $xml->{CODEBASE} = $impl->{CODEBASE};
	    for (qw(DEPENDENCY PROVIDES REQUIRES)) {
		next unless exists $impl->{$_};
		push(@{$xml->{$_}}, @{$impl->{$_}});
	    }
	}
    }
    delete $xml->{IMPLEMENTATION};  # not used any more

    # convert legacy OSD version number
    for my $version ($xml->{VERSION}) {
	if ($version =~ /^\d+(?:,\d+){3}/) {
	    $version =~ s/,/./g;
	    1 while $version =~ s/(\d\.\d+)\.0+$/$1/;  # drop trailing '.0's
	}
    }

    # convert legacy DEPENDENCY into REQUIRES.  This loose the version info.
    if (my $dep = delete $xml->{DEPENDENCY}) {
	push(@{$xml->{REQUIRES}}, map { NAME => $_->{NAME}, VERSION => 0 }, @$dep);
    }

    my %self;
    $self{arch} = $arch;

    for my $role (qw(require provide)) {
	my $tmp = delete $xml->{uc($role) . "S"} || next;
	for (@$tmp) {
	    $self{$role}{$_->{NAME}} = $_->{VERSION};
	}
    }

    if (my $codebase = delete $xml->{CODEBASE}) {
	$self{codebase} = $codebase->{HREF};
    }

    # move the remaining elements into %self
    for my $attr (keys %$xml) {
	$self{lc($attr)} = $xml->{$attr};
    }

    return $class->new(\%self);
}

1;

__END__

=head1 NAME

ActivePerl::PPM::PPD - Parser for PPD files

=head1 SYNOPSIS

  my $ppd = ActivePerl::PPM::Package->new_ppd('foo.ppd');
  # or
  my $ppd = ActivePerl::PPM::Package->new_ppd('<SOFTPKG NAME="Foo">...</SOFTPKG>');

=head1 DESCRIPTION

This module adds the C<new_ppd> constructor to the
C<ActivePerl::PPM::Package> class.  This constructor parses PPD
files and allow package objects to be initialized from these
files. PPD is an XML based format that is used to describe PPM
packages.

The following methods are added:

=over

=item $ppd = ActivePerl::PPM::Package->new_ppd( $filename, $archname )

=item $ppd = ActivePerl::PPM::Package->new_ppd( $ppd_document, $archname )

The constructor take either a filename or a literal document as
argument and will return and object representing the PPD.  The method
return C<undef> if the specified file can't be read, or if the file or
the $ppd_document does not contain the expected XML.

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
    <PROVIDES NAME="Acme::Buffy" VERSION="1.3"/>
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

Added REQUIRES and PROVIDES elements that are used to describe
features that this package depends on and provides.  The NAME
attribute is required for both.  The VERSION attribute is optional and
should be a floating number.  Features are assumed to be backwards
compatible and a feature with a higher version number is regarded
better.

=item *

The DEPENDENCY elements are deprecated.  Use REQUIRES instead.  If
present they are mapped to REQUIRES but their VERSION attribute is
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

