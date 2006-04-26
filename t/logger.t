#!perl -w

use strict;

use Test;
plan tests => 1;

use ActivePerl::PPM::Logger;

ppm_log("WARN", "hi there");
ppm_debug("Running low");
ppm_logger()->log(LOG_WARNING, "hi there");

ok(1);  # not a real test
