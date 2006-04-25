require 5.008;
use ExtUtils::MakeMaker;

WriteMakefile(
   NAME         => "ActivePerl::PPM",
   VERSION_FROM => "lib/ActivePerl/PPM.pm",
   EXE_FILES    => ["bin/ppm4"],
   PREREQ_PM    => {
		       'DBI' => 1.50,
		       'DBD::SQLite' => 1.12,
                       'XML::Simple' => 2.14,
                       'LWP' => 5.805,
                       'Archive::Tar' => 1.26,
                   },
   dist         => { COMPRESS => 'gzip -9f', SUFFIX => 'gz'},
);
