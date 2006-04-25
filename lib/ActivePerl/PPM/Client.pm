package ActivePerl::PPM::Client;

use strict;
use Config qw(%Config);

use ActivePerl ();
use ActivePerl::PPM::IDirs ();
use ActivePerl::PPM::Package ();
use XML::Simple ();

sub new {
    my $class = shift;

    my $home = "$ENV{HOME}/.ActivePerl";
    my @dirs;
    my $v = ActivePerl::perl_version();
    push(@dirs, "$home/$v/$Config{archname}");
    push(@dirs, "$home/$v");
    push(@dirs, "$home/$Config{archname}");
    push(@dirs, $home);

    my $dir = $home;
    for my $d (@dirs) {
	if (-d $d) {
	    $dir = $d;
	    last;
	}
    }

    my $etc = "$dir/etc";
    my $conf_file = "$etc/ppm-conf.xml";
    unless (-f $conf_file) {
	warn "Creating $conf_file\n";
	require File::Path;
	File::Path::mkpath($etc, 0, 0755);
	open(my $f, ">", $conf_file) || die "Can't create $conf_file: $!";
	print $f <<EOT;
<ppm-configuration>
   <current-idirs>site</current-idirs>
</ppm-configuration>
EOT
        close($f) || die "Can't write $conf_file: $!";

	my $repo = "$etc/ppm-repo/as";
	my $prop = "$repo/prop.xml";
	unless (-f $prop) {
	    warn "Creating $prop\n";
	    File::Path::mkpath($repo, 0, 0755);
	    open($f, ">", $prop) || die "Can't create $prop: $!";
	    print $f <<EOT;
<properties>
   <url>http://ppm.ActiveState.com/PPM/ppmserver-5.8-$^O.plex?urn:/PPM/Server/SQL</url>
   <prio>1</prio>
   <name>ActiveState Package Repository</name>
</properties>
EOT
	    close($f) || die "Can't write $prop: $!";
	}
    }

    my $conf;
    eval {
	$conf = XML::Simple::XMLin($conf_file);
    };
    if ($@) {
	warn $@;
	$conf = {};
    }

    my $self = bless {
	dir => $dir,
	etc => $etc,
	conf => $conf,
        conf_file => $conf_file,
    }, $class;
    return $self;
}

sub _write_conf {
    my $self = shift;
    XML::Simple::XMLout($self->{conf}, OutputFile => $self->{conf_file}, RootName => "ppm-configuration");
}

sub current_idirs {
    my $self = shift;
    return $self->idirs($self->current_idirs_name);
}

sub current_idirs_name {
    my $self = shift;
    my $old = $self->{conf}{"current-idirs"} || "site";
    if (@_) {
	my $new = shift;
	die "Unrecognized idirs '$new'" unless grep $_ eq $new, $self->idirs;
	$self->{conf}{"current-idirs"} = $new;
	$self->_write_conf;
    }
    return $old;
}

sub idirs {
    my $self = shift;
    if (@_) {
	require ActivePerl::PPM::IDirs;
	return  ActivePerl::PPM::IDirs->new(@_);
    }
    else {
	return ("site", "perl");
    }
}

sub _init_repos {
    my $self = shift;
    return if $self->{repos};

    require ActivePerl::PPM::Repo;

    my %repo;
    $self->{repo} = \%repo;

    my $repo_dir = "$self->{etc}/ppm-repo";
    if (opendir(my $dh, $repo_dir)) {
	while (my $id = readdir($dh)) {
	    next if $id =~ /^\./;
	    if (my $repo = ActivePerl::PPM::Repo->new("$repo_dir/$id")) {
		$repo{$id} = $repo;
	    }
	}
	closedir($dh);
    }
}

sub repo {
    my($self, $id) = @_;
    $self->_init_repos unless $self->{repo};
    return $self->{repo}{$id};
}

sub repos {
    my($self, %opt) = @_;
    $self->_init_repos unless $self->{repo};
    my @repos = sort { $self->{repo}{$a}->prio <=> $self->{repo}{$b}->prio } keys %{$self->{repo}};
    return @repos;
}

sub feature_best {
    my($self, $feature) = @_;
    $self->_init_repos unless $self->{repo};

    my $best;
    for my $repo (values %{$self->{repo}}) {
	my $b = $repo->feature_best($feature);
	if (defined($best)) {
	    $best = $b if $b && $b > $best;
	}
	else {
	    $best = $b;
	}
    }
    return $best;
}

sub package_best {
    my($self, $feature, $version) = @_;
    #warn "PKG_BEST($feature, $version)";
    $self->_init_repos unless $self->{repo};

    my @pkg;
    for my $repo (values %{$self->{repo}}) {
	push(@pkg, $repo->package_best($feature, $version));
    }
    return ActivePerl::PPM::Package::best(@pkg);
}

sub feature_have {
    my($self, $feature) = @_;
    #print "CLIENT_FEATURE_HAVE($feature)\n";
    for my $idirs_name ($self->idirs) {
	my $idirs = $self->idirs($idirs_name);
	if (defined(my $have = $idirs->feature_have($feature))) {
	    return $have;
	}
    }

    if ($feature =~ /::/) {
	require ActiveState::ModInfo;
	require ExtUtils::MakeMaker;
	if (my $path = ActiveState::ModInfo::find_module($feature)) {
	    return MM->parse_version($path) || 0;
	}
    }

    return undef;
}

sub packages_to_install_for {
    my($self, $feature, $version) = @_;
    unless (defined $version) {
	$version = $self->feature_best($feature);
	die "No $feature available\n" unless defined($version);
    }

    my @pkg;
    my @todo;
    push(@todo, [$feature, $version]);
    while (@todo) {
	#use Data::Dump; Data::Dump::dump(\@todo);
        my($feature, $want, $needed_by) = @{shift @todo};

        my $have = $self->feature_have($feature); # XXX also consider the @pkg provide
	#print "HAVE($feature) => $have\n";

        if (!$have || $have < $want) {
            if (my $pkg = $self->package_best($feature, $want)) {
		$self->check_downgrade($pkg, $feature);
		push(@pkg, $pkg);

		if (my $dep = $pkg->{require}) {
		    push(@todo, map [$_ => $dep->{$_}, $pkg->{name} ], keys %$dep);
		}
	    }
	    else {
		die "Can't find any package that provide $feature" .
		    ($want && $have ? "version $want" : "") .
		    ($needed_by ? " for $needed_by" : "");
	    }
        }
    }

    return @pkg;
}

sub check_downgrade {
    my($self, $pkg, $because) = @_;
    my @downgrade;
    for my $feature (sort keys %{$pkg->{provide}}) {
	my $have = $self->feature_have($feature);
        push(@downgrade, $feature) if $have && $have > $pkg->{provide}{$feature};
    }
    if (@downgrade) {
        die "Installing $pkg because of $because would downgrade @downgrade\n";
    }
}

1;

__END__

=head1 NAME

ActivePerl::PPM::Client - Client class

=head1 SYNOPSIS

  my $ppm = ActivePerl::PPM::Client->new

=head1 DESCRIPTION

The C<ActivePerl::PPM::Client> object ties together a set of C<idirs>
and C<repos> and allow the installed packages to be managed.

The following methods are provided:

=over

=item $client = ActivePerl::PPM::Client->new

The constructor creates a new client based on the configuration found
in the F<$HOME/.ActivePerl> directory of the current user.  If no such
directory is found it is created.

=item $client->current_idirs

Returns an object representing the current install area.  See
L<ActivePerl::PPM::IDirs> for methods available.

=item $client->current_idirs_name

=item $client->current_idirs_name( $name )

Get/set the name of the current install area.  This setting persists
between sessions.

=item $client->idirs

=item $client->idirs( $name )

With argument returns an object representing the given named install
area.  See L<ActivePerl::PPM::IDirs> for methods available.

Without argument return list of available names.

=item $client->repo( $repo_id )

Returns the repo object with the given identifier.  See
L<ActivePerl::PPM::Repo> for methods available.

=item $client->repos

Returns list of available repos.  The repos are ordered by priority.

=item $client->feature_best( $feature )

Returns the highest version number provided for the given feature.

=item $client->package_best( $feature, $version )

Returns the best package that provide the given feature at or better
than the given version.

=item $client->feature_have( $feature )

Returns the installed version number of the given feature.  Returns
C<undef> if none of the installed pacakges provide this feature.

=item $client->packages_to_install_for( $feature, $version )

Returns the list of missing packages to install in order to obtain the
requested feature at or better than the given version.  The list
consist of L<ActivePerl::PPM::Package> objects.

=back

=head1 BUGS

none.
