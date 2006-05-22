package ActivePerl::PPM::Client;

use strict;
use Config qw(%Config);

use ActivePerl ();
use ActivePerl::PPM::InstallArea ();
use ActivePerl::PPM::Package ();
use ActivePerl::PPM::RepoPackage ();
use ActivePerl::PPM::PPD ();
use ActivePerl::PPM::Logger qw(ppm_log ppm_debug);
use ActivePerl::PPM::Web qw(web_ua);

use base 'ActivePerl::PPM::DBH';

sub new {
    my($class, $dir) = @_;
    $dir ||= $ENV{ACTIVEPERL_PPM_HOME};
    unless ($dir) {
	my $home = do {
	    if ($^O eq "MSWin32") {
		require Win32;
		my $appdata = Win32::GetFolderPath(Win32::CSIDL_APPDATA()) ||
		    $ENV{APPDATA} || $ENV{HOME};
		die "No valid setting for APPDATA\n" unless $appdata;
		"$appdata/ActiveState/ActivePerl";
	    }
	    else {
		"$ENV{HOME}/.ActivePerl";
	    }
	};
	my @dirs;
	my $v = ActivePerl::perl_version();
	push(@dirs, "$home/$v/$Config{archname}");
	push(@dirs, "$home/$v");
	push(@dirs, "$home/$Config{archname}");
	push(@dirs, $home);

	$dir = $home;
	for my $d (@dirs) {
	    if (-d $d) {
		$dir = $d;
		last;
	    }
	}
    }

    my $etc = $dir; # XXX or "$dir/etc";
    my @area = ("site", "perl");
    my %area;
    if (-d "$dir/lib") {
	unshift(@area, "home");
	$area{home} = ActivePerl::PPM::InstallArea->new(prefix => $dir, etc => $etc);
    }

    my $self = bless {
	dir => $dir,
	etc => $etc,
	area => \%area,
        area_seq => \@area,
    }, $class;
    return $self;
}

sub areas {
    my $self = shift;
    return @{$self->{area_seq}};
}

sub area {
    my($self, $name) = @_;
    return undef unless $name;
    return $self->{area}{$name} ||= ActivePerl::PPM::InstallArea->new($name);
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
    packlist_uri text not null unique,
    packlist_version text,
    packlist_last_status_code int,
    packlist_last_access integer,
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
    my $os = lc($^O);
    $os = "windows" if $os eq "mswin32";
    my $repo_uri = "http://ppm.activestate.com/PPMPackages/5.8-$os/";
    if ($os =~ /^(windows|linux|hpux|solaris)$/ || web_ua()->head($repo_uri)->is_success) {
	$dbh->do(qq(INSERT INTO repo(name,packlist_uri) VALUES ("ActiveState Package Repository", ?)), undef, $repo_uri);
    }
}

sub repos {
    my $self = shift;
    @{$self->dbh->selectcol_arrayref("SELECT id FROM repo ORDER BY prio, name")};}

sub repo {
    my($self, $id) = @_;
    $self->dbh->selectrow_hashref("SELECT * FROM repo WHERE id = ?", undef, $id);
}

sub repo_enable {
    my $self = shift;
    my $id = shift;
    my $enabled = @_ ? (shift(@_) ? 1 : 0) : 1;

    my $dbh = $self->dbh;
    if ($self->dbh->do("UPDATE repo SET enabled = ?, packlist_etag = NULL, packlist_lastmod = NULL, packlist_size = NULL, packlist_fresh_until = NULL WHERE id = ?", undef, $enabled, $id)) {
	if ($enabled) {
	    $dbh->commit;
	    $self->repo_sync;
	}
	else {
	    _repo_delete_packages($dbh, $id);
	    $dbh->commit;
	}
    }
}

sub repo_add {
    my($self, %attr) = @_;
    my $dbh = $self->dbh;
    local $dbh->{PrintError} = 0;
    if ($dbh->do("INSERT INTO repo (name, packlist_uri, prio) VALUES (?, ?, ?)", undef,
	         $attr{name}, $attr{packlist_uri}, ($attr{prio} || 0)))
    {
	my $id = $dbh->func('last_insert_rowid');
	$dbh->commit;
	$self->repo_sync;
	return $id;
    }
    my $err = $DBI::errstr;
    if (my $repo = $self->dbh->selectrow_hashref("SELECT * FROM repo WHERE packlist_uri = ?", undef, $attr{packlist_uri})) {
	die "Repo ", $repo->{name} || $repo->{id}, " already set up with URL $attr{packlist_uri}";
    }
    die $err;
}

sub repo_delete {
    my($self, $id) = @_;
    my $dbh = $self->dbh;
    _repo_delete_packages($dbh, $id);
    $dbh->do("DELETE FROM repo WHERE id = ?", undef, $id);
    $dbh->commit;
}

sub _repo_delete_packages {
    my($dbh, $id) = @_;
    $dbh->do("DELETE FROM feature WHERE package_id IN (SELECT id FROM package WHERE repo_id = ?)", undef, $id);
    $dbh->do("DELETE FROM script WHERE package_id IN (SELECT id FROM package WHERE repo_id = ?)", undef, $id);
    $dbh->do("DELETE FROM package WHERE repo_id = ?", undef, $id);
}



sub repo_sync {
    my($self, %opt) = @_;
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
	if (!$opt{force} && $repo->{packlist_fresh_until} && $repo->{packlist_fresh_until} >= time) {
	    @check_ppd = (); # XXX should we still check them?
	    ppm_log("DEBUG", "$repo->{packlist_uri} is still fresh");
	}
	else {
	    my $ua = web_ua();
	    my $res;
	    if ($repo->{packlist_last_status_code}) {
		# if we continue to get errors from repo, only hit it occasionally
		if (!$opt{force} &&
		    HTTP::Status::is_error($repo->{packlist_last_status_code}) &&
		    (time - $repo->{packlist_last_access} < 5 * 60))
		{
		    ppm_log("WARN", "$repo->{packlist_uri} is known to err, skipping sync");
		    next;
		}
	    }
	    else {
		# first time, try to find package.lst
		my $uri = $repo->{packlist_uri};
		unless ($uri =~ m,/package.lst$,) {
		    $uri = URI->new($uri);
		    my @try;
		    my $uri_slash = $uri;
		    unless ($uri_slash->path =~ m,/$,) {
			$uri_slash = $uri->clone;
			$uri_slash->path( $uri->path . "/");
		    }
		    push(@try, URI->new_abs("package.xml", $uri_slash));
		    push(@try, URI->new_abs("package.lst", $uri_slash));
		    my $try;
		    for $try (@try) {
			my $try_res = $ua->get($try);
			if ($try_res->is_success && $try_res->decoded_content =~ /<REPOSITORY(?:SUMMARY)?\b/) {
			    $repo->{packlist_uri} = $try->as_string;
			    $dbh->do("UPDATE repo SET packlist_uri = ? WHERE id = ?", undef, $repo->{packlist_uri}, $repo->{id});
			    $res = $try_res;
			    ppm_log("WARN", "Will use $repo->{packlist_uri} instead");
			    last;
			}
		    }
		}
	    }

	    unless ($res) {
		my @h;
		if (!$opt{force}) {
		    push(@h, "If-None-Match", $repo->{packlist_etag}) if $repo->{packlist_etag};
		    push(@h, "If-Modified-Since", $repo->{packlist_lastmod}) if $repo->{packlist_lastmod};
		}
		$res = $ua->get($repo->{packlist_uri}, @h);
	    }
	    $dbh->do("UPDATE repo SET packlist_last_status_code = ?, packlist_last_access = ? WHERE id = ?", undef, $res->code, time, $repo->{id});
	    #print $res->status_line, "\n";
	    if ($res->code == 304) {  # not modified
		@check_ppd = @{$dbh->selectcol_arrayref("SELECT ppd_uri FROM package WHERE ppd_uri NOTNULL AND repo_id = ?", undef, $repo->{id})};
		$dbh->do("UPDATE repo SET packlist_fresh_until=? WHERE id=?", undef, $res->fresh_until, $repo->{id});
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
		    $p->parse($res->decoded_content)->eof;
		    ppm_log("WARN", "No ppds found in $repo->{packlist_uri}") unless @check_ppd;

		    %delete_package = map { $_ => 1 } @{$dbh->selectcol_arrayref("SELECT id FROM package WHERE repo_id = ?", undef, $repo->{id})};
		}
		elsif ($res->decoded_content =~ /<REPOSITORY(?:SUMMARY)?\b/) {
		    _repo_delete_packages($dbh, $repo->{id});
		    require ActivePerl::PPM::ParsePPD;
		    my $p = ActivePerl::PPM::ParsePPD->new(sub {
			my $pkg = shift;
			$pkg = ActivePerl::PPM::RepoPackage->new_ppd($pkg);
			$pkg->{repo_id} = $repo->{id};
			$pkg->dbi_store($dbh);
		    });
		    $p->parse_more($res->decoded_content);
		    $p->parse_done;
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
    if ($row && $ppd_res->code == 304) {  # not modified
	$dbh->do("UPDATE package SET ppd_fresh_until = ? WHERE id = ?", undef, $ppd_res->fresh_until, $row->{id});
    }
    elsif ($ppd_res->is_success) {
	my $ppd = ActivePerl::PPM::RepoPackage->new_ppd($ppd_res->decoded_content);
	$ppd->{id} = $row->{id} if $row;
	$ppd->{repo_id} = $repo->{id};
	$ppd->{ppd_uri} = $rel_url;
	$ppd->{ppd_etag} = $ppd_res->header("ETag");
	$ppd->{ppd_lastmod} = $ppd_res->header("Last-Modified");
	$ppd->{ppd_fresh_until} = $ppd_res->fresh_until;

	# make URL attributes relative to $abs_url
	my $ppd_base = $ppd_res->base;
	for my $attr (qw(codebase)) {
	    next unless exists $ppd->{$attr};
	    my $url = URI->new_abs($ppd->{$attr}, $ppd_base)->rel($abs_url);
	    $ppd->{$attr} = $url->as_string;
	}

	$ppd->dbi_store($dbh);
    }
}


sub search {
    my($self, $pattern, @fields) = @_;

    @fields = ("name") unless @fields;

    my $dbh = $self->dbh;

    $dbh->do("DROP TABLE IF EXISTS search");
    $dbh->commit;

 SEARCH: {
	if ($pattern =~ /::/) {
	    my $op = ($pattern =~ /\*/) ? "GLOB" : "=";
	    $dbh->do("CREATE TABLE search AS SELECT id FROM package WHERE id IN (SELECT package_id FROM feature WHERE name $op ? AND role = 'p') ORDER BY name", undef, $pattern);
	}

	if ($pattern eq '*') {
	    $dbh->do("CREATE TABLE search AS SELECT id FROM package ORDER BY name");
	}

	unless ($pattern =~ /\*/) {
	    $dbh->do("CREATE TABLE search AS SELECT id FROM package WHERE name = ?", undef, $pattern);
	    last SEARCH if $dbh->selectrow_array("SELECT count(*) FROM search");
	    # try again with a wider net
	    $dbh->rollback;
	    $pattern = "*$pattern*";
	}
	$dbh->do("CREATE TABLE search AS SELECT id FROM package WHERE lower(name) GLOB ? ORDER BY name", undef, lc($pattern));
    }
    $dbh->commit;

    my $fields = join(", ", map "package.$_", @fields);
    my $select_arrayref = @fields > 1 ? "selectall_arrayref" : "selectcol_arrayref";
    return @{$dbh->$select_arrayref("SELECT $fields FROM package,search WHERE package.id = search.id ORDER by search.rowid")};
}

sub search_lookup {
    my($self, $row) = @_;
    my $dbh = $self->dbh;
    my $id = $dbh->selectrow_array("SELECT id FROM search WHERE rowid = $row");
    return $self->package($id) if defined $id;
    return undef;
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
    for my $area_name ($self->areas) {
	my $area = $self->area($area_name);
	if (defined(my $have = $area->feature_have($feature))) {
	    ppm_debug("Feature $feature found in $area_name");
	    return $have;
	}
	ppm_debug("Feature $feature not found in $area_name");
    }

    if ($feature =~ /::/) {
	require ActiveState::ModInfo;
	require ExtUtils::MakeMaker;
	my $inc_ref = defined(*main::INC_ORIG) ? \@main::INC_ORIG : \@INC;
	if (my $path = ActiveState::ModInfo::find_module($feature, $inc_ref)) {
	    return MM->parse_version($path) || 0;
	}
	ppm_debug("Module $feature not found in \@INC");
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

        my $have;
	for my $pkg (@pkg) {
	    $have = $pkg->{provide}{$feature};
	    if (defined $have) {
		if ($have < $want) {
		    die "Conflict for feature $feature version $have provided by $pkg->{name}, want version $want";
		}
		last;
	    }
	}
	$have = $self->feature_have($feature) unless defined($have);
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
        push(@downgrade, [$feature, $have, $pkg->{provide}{$feature}])
	    if $have && $have > $pkg->{provide}{$feature};
    }
    if (@downgrade) {
	my $msg = "Installing " . $pkg->name_version;
	$msg .= " to get $because" if $pkg->{name} ne $because;
	$msg .= " would downgrade";
	for my $d (@downgrade) {
	    $msg .= " $d->[0] from version $d->[1] to $d->[2] and";
	}
	$msg =~ s/ and$//;
	die $msg;
    }
}

sub package {
    my $self = shift;
    return ActivePerl::PPM::RepoPackage->new_dbi($self->dbh, @_);
}

sub package_set_abs_ppd_uri {
    my($self, $pkg) = @_;
    my($uri, $etag, $lastmod) = $self->dbh->selectrow_array("SELECT packlist_uri, packlist_etag, packlist_lastmod FROM repo WHERE id = ?", undef, $pkg->{repo_id});
    if ($pkg->{ppd_uri}) {
	$pkg->{ppd_uri} = URI->new_abs($pkg->{ppd_uri}, $uri)->as_string;
    }
    else {
	$pkg->{ppd_uri} = $uri;
	$pkg->{ppd_etag} = $etag;
	$pkg->{ppd_lastmod} = $lastmod;
    }
    return $pkg;
}

1;

__END__

=head1 NAME

ActivePerl::PPM::Client - Client class

=head1 SYNOPSIS

  my $ppm = ActivePerl::PPM::Client->new

=head1 DESCRIPTION

The C<ActivePerl::PPM::Client> object ties together a set of install areas
and repositories and allow the installed packages to be managed.

The following methods are provided:

=over

=item $client = ActivePerl::PPM::Client->new

=item $client = ActivePerl::PPM::Client->new( $home_dir )

The constructor creates a new client based on the configuration found
in $home_dir which defaults to F<$ENV{HOME}/.ActivePerl> directory of the
current user.  If no such directory is found it is created.

=item $client->area( $name )

Returns an object representing the given named install area.  See
L<ActivePerl::PPM::InstallArea> for methods available.

=item $client->areas

Return list of available install area names.

=item $client->repo( $repo_id )

Returns the repo object with the given identifier.  See
L<ActivePerl::PPM::Repo> for methods available.

=item $client->repos

Returns list of available repo identifiers.  The repos are ordered by priority.

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
