#!perl -w

use strict;

use Test;
plan tests => 1;

use ActivePerl::PPM::Logger;

ppm_log("WARN", "testing WARN");
ppm_debug("testing DEBUG");
ppm_logger()->log(LOG_WARNING, "testing WARNING");

ok(1);  # not a real test
