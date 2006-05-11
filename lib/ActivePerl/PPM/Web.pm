package ActivePerl::PPM::Web;

use strict;
use base qw(Exporter);
our @EXPORT_OK = qw(web_ua);

use ActivePerl::PPM ();

my $ua;

sub web_ua {
    unless ($ua) {
	$ua = ActivePerl::PPM::Web::UA->new(
	    agent => "PPM/$ActivePerl::PPM::VERSION ($^O) ",
	    env_proxy => 1,
	    keep_alive => 1,
        );
	$ua->default_header("Accept-Encoding" => "gzip, deflate");
    }
    return $ua;
}

package ActivePerl::PPM::Web::UA;

use base 'LWP::UserAgent';
use ActivePerl::PPM::Logger qw(ppm_log);

sub simple_request {
    my $self = shift;
    my $req = shift;
    my $res = $self->SUPER::simple_request($req, @_);
    ppm_log("INFO", sprintf("%s %s ==> %s", $req->method, $req->uri, $res->status_line));
    return $res;
}

1;
