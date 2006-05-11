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

use Time::HiRes qw(time);

use base 'LWP::UserAgent';
use ActivePerl::PPM::Logger qw(ppm_log);

sub simple_request {
    my $self = shift;
    my $req = shift;
    my $before = time();

    my $res = $self->SUPER::simple_request($req, @_);

    my $used = time() - $before;
    my $bytes = "";
    my $speed = "";
    if (my $len = $res->content_length) {
	if ($req->method ne "HEAD") {
	    $bytes = "$len bytes ";
	    $speed = sprintf " - %.0f KB/s", ($len/1024) / $used;
	}
    }
    if ($used < 3) {
	$used = sprintf "%.2f sec", $used;
    }
    elsif ($used < 20) {
	$used = sprintf "%.1f sec", $used;
    }
    else {
	$used = sprintf "%.0f sec", $used;
    }
    ppm_log("INFO", sprintf("%s %s ==> %s (${bytes}in $used$speed)", $req->method, $req->uri, $res->status_line));
    return $res;
}

1;
