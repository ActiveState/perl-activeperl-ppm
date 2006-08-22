package ActivePerl::PPM::PPD;

use strict;
use ActivePerl::PPM::ParsePPD ();
use ActivePerl::PPM::Package ();
use ActivePerl::PPM::Logger qw(ppm_log);
use URI ();

sub ActivePerl::PPM::Package::new_ppd {
    my($class, $pkg, %opt) = @_;
    my $arch = delete $opt{arch} || "noarch";
    my $base = delete $opt{base};
    my $rel_base = delete $opt{rel_base};

    unless (ref $pkg) {
	my $data = $pkg;
	$pkg = undef;
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
	unless ($pkg) {
	    ppm_log("ERR", "No SOFTPKG found in parsed PPD document");
	    return undef;
	}
    }

    if (exists $pkg->{codebase}) {
	my $pkg_arch = $pkg->{architecture} || "noarch";
	unless ($arch eq $pkg_arch || $pkg_arch eq "noarch") {
	    delete $pkg->{codebase};
	    delete $pkg->{script};
	}
    }

    if (!exists $pkg->{codebase}) {
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
    }
    delete $pkg->{implementation};  # not used any more

    # rebase URIs
    $base = "dummy:/" unless $base;
    if ($pkg->{base}) {
	$base = URI->new_abs($pkg->{base}, $base);
	$pkg->{base} = $base->as_string;
	$pkg->{base} =~ s,^dummy:/,,;
    }
    if ($base ne "dummy:/" || $rel_base) {
	my @uri_ref;
	if (exists $pkg->{codebase}) {
	    push(@uri_ref, \$pkg->{codebase});
	}
	if (exists $pkg->{script}) {
	    for my $kind (keys %{$pkg->{script}}) {
		next unless exists $pkg->{script}{$kind}{uri};
		push(@uri_ref, \$pkg->{script}{$kind}{uri});
	    }
	}
	for my $uri_ref (@uri_ref) {
	    my $uri = URI->new_abs($$uri_ref, $base);
	    $uri = $uri->rel($rel_base) if $rel_base;
	    $uri = $uri->as_string;
	    $uri =~ s,^dummy:/,,;
	    $$uri_ref = $uri;
	}
    }

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

=item $ppd = ActivePerl::PPM::Package->new_ppd( $ppd_document, %opt )

=item $ppd = ActivePerl::PPM::Package->new_ppd( $parsed_ppd_hashref, %opt )

The constructor take a literal document as argument and will return
and object representing the PPD.  The method return C<undef> if
$ppd_document does not contain the expected XML.

The following options are supported:

=over

=item arch => $archname

The $archname should be specified to select attributes for a specific
architecture where the PPD describes multiple implementations.  The
value C<noarch> is the default and will only select
implementation sections without any ARCHITECTURE restriction.

=item base => $base_uri

All URIs in the PPD will be made absolute with $base_uri as base.

=item rel_base => $base_uri

All URIs in the PPD will be made relative if they can be resolved from
$base_uri.  Only safe to use together with C<base> which is applied
first.  If both C<base> and C<rel_base> are the same, they cancel
eachother out and the effect will be the same as if none of them where
specified.

=back

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
      <CODEBASE HREF="i686-linux-thread-multi-5.8/Acme-Buffy.tar.gz"/>
      <ARCHITECTURE NAME="i686-linux-thread-multi-5.8"/>
    </IMPLEMENTATION>
  </SOFTPKG>

The following elements are used:

=over

=item ABSTRACT

Content is a short text describing the purpose of this
package. No attributes.  Parent must be a SOFTPKG element.

=item ARCHITECTURE

Required attribute is NAME which should match
C<$Config{archname}-$major_vers> for the perl this package was
compiled for.  If this element is missing then it's the same as
specifying <ARCHITECTURE NAME="noarch"/>. No content.  Parent must be
either SOFTPKG or IMPLEMENTATION.

=item AUTHOR

Content is a text naming the author (with email address) of this
package. No attributes.  Parent must be a SOFTPKG element.

=item CODEBASE

Required attribute is HREF providing a URI where the binary package
(the tared up C<blib> tree) of the package can be obtained.  The URI
can be relative and is then resolved based on the URI of the PPD
document itself.  No content.  Parent must be SOFTPKG or
IMPLEMENTATION.

=item DEPENDENCY

Deprecated.  Required attribute is NAME.  Optional attribute is
VERSION.  No content.

=item IMPLEMENTATION

No attributes.  Optional container for ARCHITECTURE, DEPENDENCY,
INSTALL, PROVIDE, REQUIRE, UNINSTALL elements.  Parent must be
SOFTPKG.  There can be multiple instances of IMPLEMENTATION but they
should each contain an ARCHITECTURE element that differ from each
other.

=item INSTALL

Optional attributes EXEC and HREF.  Textual content might be provided.
Used to denote script to run after the blib files of the package has
been installed, a so called post-install script.  The script to run
can either be provided as content or externally via HREF.  If both are
provided then only HREF is used.

If EXEC is provided it give the name of the interpreter to run the
script.  For historical reason if the script was not obtained via HREF
then any occurences of double semicolon ";;" is replaced by newline
before it is saved in a temporary file and passed as first argument to
EXEC.  The special value "PPM_PERL" ensures that the script runs with
the same perl interpreter that runs PPM.  The special value "SELF"
make the script run self contained.

If EXEC is not provided then the commands of the script are passed to
the system command interpreter (via system(3)) one by one.  If the
script was obtained via HREF then each line is considered a command.
If the script was obtained from the content, then double semicolon
";;" is used to separate commands.

When the script/command runs it will have the unpacked package tarball
(obtained by downloading the CODEREF) as their working directory, and
the following environment variable will be set:

=over

=item PPM_ACTION

One of "install", "upgrade" or "uninstall".

=item PPM_INSTARCHLIB

The archlib directory of the current install area.

=item PPM_INSTLIB

The lib directory of the current install area.

=item PPM_INSTPACKLIST

The name of the installed F<.packlist> file of the package.

=item PPM_INSTROOT

The prefix directory of the current install area.

=item PPM_NEW_VERSION

The version label of the package just installed.

=item PPM_PERL

The path to the perl that runs PPM.

=item PPM_PREV_VERSION

The version label that the package had before the upgrade started.
This variable is only present when PPM_ACTION is "upgrade".

=item PPM_VERSION

What version of PPM is running.

=back

=item PROVIDE

Required attribute is NAME.  Optional attribute is VERSION.  No content.

The NAME represent a feature that this package provide if installed.
Any label goes.  The VERSION is a floating point number.

=item REPOSITORY

Element must be root if present.  Container for a set of SOFTPKG
elements.  Optional attributes are ARCHITECTURE and BASE.  If
ARCHITECTECTURE is present it provide default for all contained
SOFTPKG elements that do not have an explicit ARCHITECTECTURE
element.  If BASE is provided it provide the base URI that relative
URIs of CODEBASE, INSTALL and UNINSTALL are resolved from.

The file name F<package.xml> is commonly used for documents
containing a REPOSITORY root.

=item REPOSITORYSUMMARY

Treated the same as REPOSITORY.  Supported for backwards compatibility
with old style F<package.lst> files.

=item REQUIRE

Required attribute is NAME.  Optional attribute is VERSION.  No content.

=item SOFTPKG

Represent a package available for PPM to install.  Container for all
the other elements defined here (except REPOSITORY and
REPOSITORYSUMMARY).

Required attributes are NAME and VERSION.  Optional attribute is DATE.

The NAME and VERSION value can be any label.  Older versions of this
specification had a more strict definition of VERSION as a sequence of
exactly 4 numbers in the range 0 to 65535 separated by comma.  If such
values are encountered then they are converted to "standard" format by
replacing the commas with dots and trimming off ".0.0" or ".0".

The DATE attribute should use ISO 8601 formatted date (or datetime)
stamps.  That is "YYYY-MM-DD" or "YYYY-MM-DDThh:mm:ssZ" format.  See
L<http://en.wikipedia.org/wiki/ISO_8601> for more information.

Parent must be REPOSITORY or REPOSITORYSUMMARY, or the SOFTPKG can be
the document root.  The order of content elements are of no
significance.

=item UNINSTALL

Used for scripts that run just before the package is uninstalled.  The
attributes and content are the same as for INSTALL.

=back

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

