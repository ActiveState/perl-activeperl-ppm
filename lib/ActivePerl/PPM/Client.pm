package ActivePerl::PPM::Client;

use strict;
use Config qw(%Config);

use ActivePerl ();
use ActivePerl::PPM::IDirs ();
use ActivePerl::PPM::Package ();
use ActivePerl::PPM::RepoPackage ();
use ActivePerl::PPM::PPD ();
use ActivePerl::PPM::Logger qw(ppm_log ppm_debug);
use ActivePerl::PPM::Web qw(web_ua);

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

    my $etc = $dir; # XXX or "$dir/etc";
    my @idirs = ("site", "perl");
    my %idirs;
    if (-d "$dir/lib") {
	unshift(@idirs, "home");
	require ActivePerl::PPM::IDirs;
	$idirs{home} = ActivePerl::PPM::IDirs->new(prefix => $dir, etc => $etc);
    }

    my $self = bless {
	dir => $dir,
	etc => $etc,
	idirs => \%idirs,
        idirs_seq => \@idirs,
    }, $class;
    return $self;
}

sub current_idirs {
    my $self = shift;
    return $self->idirs($self->current_idirs_name);
}

sub current_idirs_name {
    my $self = shift;
    my $old = $self->{'current-idirs'}
        || $self->dbh->selectrow_array("SELECT value FROM config WHERE key = 'current-idirs'")
        || "site";
    if (@_) {
	my $new = shift;
	die "Unrecognized idirs '$new'" unless grep $_ eq $new, $self->idirs;
	$self->{'current-idirs'} = $new;
	my $dbh = $self->dbh;
	$dbh->do("INSERT OR REPLACE INTO config (key, value) VALUES ('current-idirs', ?)", undef, $new);
	$dbh->commit;
	ppm_log("NOTICE", "$new is current idirs");
    }
    return $old;
}

sub idirs {
    my $self = shift;
    if (@_) {
	my $name = shift;
	return $self->{idirs}{$name} ||= do {
	    require ActivePerl::PPM::IDirs;
	    return  ActivePerl::PPM::IDirs->new($name);
	}
    }
    else {
	return @{$self->{idirs_seq}};
    }
}

sub dbh {
    my $self = shift;
    $self->_init_db unless $self->{dbh};
    $self->{dbh};
}

sub _init_db {
    my $self = shift;
    my $etc = $self->{etc};
    File::Path::mkpath($etc);
    require DBI;
    my $db_file = "ppm.db";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$etc/$db_file", "", "", {
        AutoCommit => 0,
        PrintError => 1,
    });
    die unless $dbh;
    $self->{dbh} = $dbh;

    my $v = $dbh->selectrow_array("PRAGMA user_version");
    die "Assert" unless defined $v;
    if ($v == 0) {
	ppm_log("WARN", "Setting up schema for $etc/$db_file");
	_init_ppm_schema($dbh);
	$dbh->do("PRAGMA user_version = 1");
	$dbh->commit;
    }
    elsif ($v != 1) {
	die "Unrecognized database schema $v for $etc/$db_file";
    }
}

sub _init_ppm_schema {
    my $dbh = shift;
    $dbh->do(<<'EOT');
CREATE TABLE config (
    key text primary key,
    value text
)
EOT
    $dbh->do(<<'EOT');
CREATE TABLE repo (
    id integer primary key,
    name text not null,
    prio integer not null default 1,
    enabled bit not null default 1,
    packlist_uri text not null,
    packlist_version text,
    packlist_etag text,
    packlist_size integer,
    packlist_lastmod text,
    packlist_fresh_until integer
)
EOT
    for my $create (ActivePerl::PPM::RepoPackage->sql_create_tables()) {
	$dbh->do($create) || die "Can't create database table";
    }

    # initial values
    $dbh->do(qq(INSERT INTO config VALUES ("current-idirs", "site")));
    #$dbh->do(qq(INSERT INTO repo(name,packlist_uri) VALUES ("ActiveState Package Repository", "http://ppm.ActiveState.com/PPM/ppmserver-5.8-$^O.plex?urn:/PPM/Server/SQL")));
    $dbh->do(qq(INSERT INTO repo(name,packlist_uri) VALUES ("ActiveState Package Repository", "http://ask/ppms/")));
}

sub repos {
    my $self = shift;
    @{$self->dbh->selectcol_arrayref("SELECT id FROM repo WHERE enabled == 1 ORDER BY prio, name")};}

sub repo {
    my($self, $id) = @_;
    $self->dbh->selectrow_hashref("SELECT * FROM repo WHERE id = ?", undef, $id);
}

sub repo_sync {
    my $self = shift;
    my @repos;
    my $dbh = $self->dbh;
    my $sth = $dbh->prepare("SELECT * FROM repo WHERE enabled == 1 ORDER BY prio, name");
    $sth->execute;
    while (my $h = $sth->fetchrow_hashref) {
	push(@repos, $h);
    }

    for my $repo (@repos) {
	my @check_ppd;
	my %delete_package;
	if ($repo->{packlist_fresh_until} && $repo->{packlist_fresh_until} >= time) {
	    @check_ppd = (); # XXX should we still check them?
	}
	else {
	    ppm_debug("Refreshing $repo->{packlist_uri}");
	    my @h;
	    push(@h, "If-None-Match", $repo->{packlist_etag}) if $repo->{packlist_etag};
	    push(@h, "If-Modified-Since", $repo->{packlist_lastmod}) if $repo->{packlist_lastmod};
	    my $res = web_ua()->get($repo->{packlist_uri}, @h);
	    #print $res->status_line, "\n";
	    if ($res->code == 304) {  # not modified
		@check_ppd = @{$dbh->selectcol_arrayref("SELECT ppd_uri FROM package WHERE repo_id = ?", undef, $repo->{id})};
	    }
	    elsif ($res->is_success) {
		$dbh->do("UPDATE repo SET packlist_etag=?, packlist_lastmod=?, packlist_size=?, packlist_fresh_until=? WHERE id=?", undef,
			 scalar($res->header("ETag")),
			 scalar($res->header("Last-Modified")),
			 scalar($res->header("Content-Length")),
			 $res->fresh_until,
			 $repo->{id});

		# parse document
		if ($res->content_type eq "text/html") {
		    my $base = $res->base;
		    require HTML::Parser;
		    my $p = HTML::Parser->new(
	                report_tags => [qw(a)],
	                start_h => [sub {
			    my $href = shift->{href};
			    push(@check_ppd, URI->new_abs($href,$base)->rel($repo->{packlist_uri})) if $href =~ /\.ppd$/;
			}, "attr"],
		    );
		    $p->parse($res->content)->eof;
		    ppm_log("WARN", "No ppds found in $repo->{packlist_url}") unless @check_ppd;

		    %delete_package = map { $_ => 1 } @{$dbh->selectcol_arrayref("SELECT id FROM package WHERE repo_id = ?", undef, $repo->{id})};
		}
		else {
		    ppm_log("ERR", "Unrecognized repo type " . $res->content_type);
		}
	    }
	}

	for my $ppd (@check_ppd) {
	    _check_ppd($ppd, $repo, $dbh, \%delete_package);
	}

	$dbh->do("DELETE FROM package WHERE id IN (" . join(",", sort keys %delete_package) . ")")
	    if %delete_package;

	$dbh->commit;
    }
    return;
}


sub _check_ppd {
    my($rel_url, $repo, $dbh, $delete_package) = @_;

    my $row = $dbh->selectrow_hashref("SELECT id, ppd_etag, ppd_lastmod, ppd_fresh_until FROM package WHERE repo_id = ? AND ppd_uri = ?", undef, $repo->{id}, $rel_url);

    my @h;
    if ($row) {
	delete $delete_package->{$row->{id}} if $delete_package;
	return if $row->{ppd_fresh_until} && $row->{ppd_fresh_until} > time;
	push(@h, "If-None-Match", $row->{ppd_etag}) if $row->{ppd_etag};
	push(@h, "If-Modified-Since", $row->{ppd_lastmod}) if $row->{ppd_lastmod};
    }

    my $abs_url = URI->new_abs($rel_url, $repo->{packlist_uri});
    my $ppd_res = web_ua()->get($abs_url, @h);
    print $ppd_res->as_string, "\n" unless $ppd_res->code eq 200 || $ppd_res->code eq 304;
    if ($ppd_res->is_success) {
	my $ppd = ActivePerl::PPM::RepoPackage->new_ppd($ppd_res->content);
	$ppd->{id} = $row->{id} if $row;
	$ppd->{repo_id} = $repo->{id};
	$ppd->{ppd_uri} = $rel_url;
	$ppd->{ppd_etag} = $ppd_res->header("ETag");
	$ppd->{ppd_size} = $ppd_res->header("Content-Length");
	$ppd->{ppd_lastmod} = $ppd_res->header("Last-Modified");
	$ppd->{ppd_fresh_until} = $ppd_res->fresh_until;

	# make URL attributes absolute (XXX make them repo relative instead?)
	my $ppd_base = $ppd_res->base;
	for my $attr (qw(codebase)) {
	    next unless exists $ppd->{$attr};
	    my $url = URI->new_abs($ppd->{$attr}, $ppd_base);
	    $ppd->{$attr} = $url->as_string;
	}

	$ppd->dbi_store($dbh);
    }
}


sub search {
    my($self, $pattern) = @_;
    $self->repo_sync;
    @{$self->dbh->selectcol_arrayref("SELECT name FROM package WHERE name like ?", undef, $pattern)};
}

sub feature_best {
    my($self, $feature) = @_;
    my $dbh = $self->dbh;
    my($max) = $dbh->selectrow_array("SELECT max(version) FROM feature WHERE name = ? AND role = 'p'",
 undef, $feature);
    return $max;
}

sub package_best {
    my($self, $feature, $version) = @_;
    my $dbh = $self->dbh;

    my $ids = $dbh->selectcol_arrayref("SELECT package.id FROM package, feature WHERE package.id = feature.package_id AND feature.role = 'p' AND feature.name = ? AND feature.version >= ?", undef, $feature, $version);

    my @pkg = map $self->package($_), @$ids;

    return ActivePerl::PPM::Package::best(@pkg);
}

sub feature_have {
    my($self, $feature) = @_;
    for my $idirs_name ($self->idirs) {
	my $idirs = $self->idirs($idirs_name);
	if (defined(my $have = $idirs->feature_have($feature))) {
	    ppm_debug("Feature $feature found in $idirs_name");
	    return $have;
	}
	ppm_debug("Feature $feature not found in $idirs_name");
    }

    if ($feature =~ /::/) {
	require ActiveState::ModInfo;
	require ExtUtils::MakeMaker;
	if (my $path = ActiveState::ModInfo::find_module($feature)) {
	    return MM->parse_version($path) || 0;
	}
	ppm_debug("Module $feature found in \@INC");
    }

    return undef;
}

sub packages_missing_for {
    my($self, $feature, $version, %opt) = @_;
    unless (defined $version) {
	$version = $self->feature_best($feature);
	die "No $feature available\n" unless defined($version);
    }

    my @pkg;
    my @todo;
    push(@todo, [$feature, $version]);
    while (@todo) {
        my($feature, $want, $needed_by) = @{shift @todo};
	ppm_debug("Want $feature >= $want");

        my $have = $self->feature_have($feature); # XXX also consider the @pkg provide
	ppm_debug("Have $feature $have") if defined($have);

        if ($opt{force} || !defined($have) || $have < $want) {
            if (my $pkg = $self->package_best($feature, $want)) {
		$self->check_downgrade($pkg, $feature) unless $opt{force};
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
	next if $feature eq $pkg->{name};
	my $have = $self->feature_have($feature);
        push(@downgrade, $feature) if $have && $have > $pkg->{provide}{$feature};
    }
    if (@downgrade) {
        die "Installing $pkg because of $because would downgrade @downgrade\n";
    }
}

sub package {
    my $self = shift;
    return ActivePerl::PPM::RepoPackage->new_dbi($self->dbh, @_);
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

=item $client->packages_missing_for( $feature, $version, %opt )

Returns the list of missing packages to install in order to obtain the
requested feature at or better than the given version.  The list
consist of L<ActivePerl::PPM::Package> objects.

=back

=head1 BUGS

none.
