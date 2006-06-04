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
    local $| = 1;  # so that progress output shows

    my $res = $self->SUPER::simple_request($req, @_);

    my $used = (time() - $before) || 1e-6;
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

my @animation = ("/", "-", "\\", "|");
my $animation_index = 0;
my $last_p;
my $last_t;

sub progress {
    my($self, $status, $response) = @_;
    if ($status eq "begin") {
	$animation_index = 0;
	$last_p = "";
	$last_t = time;
    }
    elsif ($status eq "end") {
	print "     \b\b\b\b\b";
    }
    elsif ($status eq "tick") {
	my $c = $animation[$animation_index];
	$animation_index = ($animation_index + 1) % @animation;
	print $c . ("\b" x length($c));
    }
    elsif ($status =~ /^\d/) {
	$status = 1 if $status > 1;
	my $p = sprintf "%3.0f%%", $status * 100;
	if ($last_p ne $p) {
	    my $t = time;
	    my $d = $t - $last_t;
	    if ($status == 1 || $d > 0.5) {
		print $p . ("\b" x length($p));
		$last_p = $p;
		$last_t = $t;
	    }
	}
    }
}

1;
