package ActivePerl::PPM::Logger;

use strict;
use base qw(Exporter);

our @EXPORT = qw(LOG_EMERG LOG_ALERT LOG_CRIT LOG_ERR LOG_WARNING LOG_NOTICE LOG_INFO LOG_DEBUG
                 ppm_logger
		 ppm_log ppm_debug ppm_status);
our @EXPORT_OK = qw();

use Carp qw(croak);
use HTTP::Date qw(time2iso);
use File::Basename qw(basename);

# syslog inspired constants
sub LOG_EMERG   () { 0 }
sub LOG_ALERT   () { 1 }
sub LOG_CRIT    () { 2 }
sub LOG_ERR     () { 3 }
sub LOG_WARNING () { 4 }
sub LOG_WARN    () { 4 }  # unofficial
sub LOG_NOTICE  () { 5 }
sub LOG_INFO    () { 6 }
sub LOG_DEBUG   () { 7 }

my $logger;

sub ppm_logger {
    return $logger ||= ActivePerl::PPM::Logger->new;
}

sub ppm_log {
    my $prio = shift;
    my $msg = shift;

    unless ($prio =~ /^\d+$/) {
	no strict 'refs';
	if (defined &{"LOG_$prio"}) {
	    $prio = &{"LOG_$prio"};
	}
	else {
	    croak("Unrecognized log priority argument of '$prio'");
	}
    }

    if (1) {
	# fill in caller info
	my $i = 0;
	CALLER: {
	    my($pkg, $file, $line) = caller($i++);
	    redo CALLER if $pkg eq __PACKAGE__;
	    $file = basename($file);
	    substr($msg, 0, 0) = "[$file:$line] ";
	};
    }

    my @t = (localtime)[reverse 0..5];
    $t[0] += 1900; # year
    $t[1] ++;      # month
    warn sprintf "%04d-%02d-%02dT%02d:%02d:%02d <%d> %s\n", @t, $prio, $msg;
}

sub ppm_debug {
    ppm_log(LOG_DEBUG, @_);
}

sub ppm_status {
    # update status bar
    my $msg = shift;
    $msg = "done" unless $msg;
    ppm_log(LOG_INFO, $msg);
}

#
#  Objects
#

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub log {
    my $self = shift;
    ppm_log(@_);  # :)
}

1;
