require 5.008;
use ExtUtils::MakeMaker;

WriteMakefile(
   NAME         => "ActivePerl::PPM",
   VERSION_FROM => "lib/ActivePerl/PPM.pm",
   EXE_FILES    => ["bin/ppm", "bin/ppm-shell"],
   PREREQ_PM    => {
		       'DBI' => 1.50,
		       'DBD::SQLite' => 1.12,
                       'XML::Simple' => 2.14,
                       'LWP' => 5.805,
                       'Archive::Tar' => 1.26,
                       'ActiveState::Handy' => 1.01,
                   },
   dist         => { COMPRESS => 'gzip -9f', SUFFIX => 'gz'},
);

sub MY::postamble {
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
