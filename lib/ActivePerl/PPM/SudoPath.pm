package ActivePerl::PPM::SudoPath;

use ActiveState::Path qw(abs_path);
use File::Basename qw(basename dirname);

sub new {
    my $class = shift;
    my $self = bless {
	new => [],
    }, $class;
    my @paths = @_;

    for my $path (@paths) {
	$path = abs_path($path);
	next if -e $path;

	while (1) {
	    # This loop will terminate when $dir becomes the root
	    my $dir = dirname($path);
	    if (-d $dir) {
		push(@{$self->{new}}, $path);
		last;
	    }
	    $path = $dir;
	}
    }

    return $self;
}

sub chown {
    my($self, $uid, $gid) = @_;
    $uid ||= $ENV{SUDO_UID} || return;
    $gid ||= $ENV{SUDO_GID} || -1;

    for my $path (@{$self->{new}}) {
	_chown($uid, $gid, $path);
    }
}

sub _chown {
    my($uid, $gid, $path) = @_;
    return unless -e $path;
    warn "chown $uid $gid $path\n";
    CORE::chown($uid, $gid, $path);
    if (-d _) {
	if (opendir(my $dh, $path)) {
	    my @files = sort(grep !/^\.\.?$/, readdir($dh));
	    closedir($dh);
	    _chown($uid, $gid, "$path/$_") for @files;
	}
    }
}

1;
