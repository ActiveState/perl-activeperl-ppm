#!perl -w

require 5.008;
use strict;
use ExtUtils::MakeMaker;

use constant DARWIN => $^O eq 'darwin';

my @exe = qw(
    bin/ppm
    bin/ppm-shell
);

push @exe, 'bin/PPM.app' if DARWIN;

WriteMakefile(
   NAME         => "ActivePerl::PPM",
   VERSION_FROM => "lib/ActivePerl/PPM.pm",
   EXE_FILES    => [@exe],
   PREREQ_PM    => {
		       'DBI' => 1.50,
		       'DBD::SQLite' => 1.12,
                       'XML::Simple' => 2.14,
                       'LWP' => 5.805,
                       'Archive::Tar' => 1.26,
                       'ActiveState::Handy' => 1.01,
                       'ActiveState::Version' => 0,
                   },
   dist         => { COMPRESS => 'gzip -9f', SUFFIX => 'gz'},
);

package MY;

sub postamble {
    return '' unless -f "ppm.yml";
    return q(

ppm-$(INSTALLDIRS)-area.db: ppm.yml
	$(PERL) mk-area-db $(INSTALLDIRS)

install :: db_$(INSTALLDIRS)_install
	$(NOECHO) $(NOOP)

db_perl_install : ppm-perl-area.db
	$(MKPATH) $(PERLPREFIX)/etc
	$(CP) ppm-perl-area.db $(PERLPREFIX)/etc

db_site_install : ppm-site-area.db
	$(MKPATH) $(SITEPREFIX)/etc
	$(CP) ppm-site-area.db $(SITEPREFIX)/etc

);
}

sub installbin {
    my $inherited = shift->SUPER::installbin(@_);

    if (main::DARWIN) {
        my $fixin = q[$(PERLRUN) -Mblib -MConfig -MActivePerl::PPM -pi -e's/<perl-bin>/$$Config{bin}/g; s/<ppm-ver>/0+$$ActivePerl::PPM::VERSION/eg;' $(INST_SCRIPT)/PPM.app/Contents/Info.plist];

        $inherited =~ s[\$\(FIXIN\)(.*PPM\.app)][$fixin$1/Contents/MacOS/PPM]g;
        $inherited =~ s/\$\(RM_F\)/\$(RM_RF)/g;
        $inherited =~ s/\$\(CP\)(.*PPM\.app)/\$(CP) -r$1/g;
    }

    return $inherited;
}
