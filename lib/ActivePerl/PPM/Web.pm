package ActivePerl::PPM::Web;

use strict;
use base qw(Exporter);
our @EXPORT_OK = qw(web_ua);

use ActivePerl::PPM ();

my $ua;

sub web_ua {
    return $ua ||= do {
        require LWP::UserAgent;
	LWP::UserAgent->new(
	    agent => "PPM/$ActivePerl::PPM::VERSION ($^O) ",
	    env_proxy => 1,
	    keep_alive => 1,
        );
    };
}

1;
