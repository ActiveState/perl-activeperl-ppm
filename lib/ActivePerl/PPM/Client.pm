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

use ActiveState::Path qw(is_abs_path join_path);
use File::Basename;

use base 'ActivePerl::PPM::DBH';

sub new {
    my($class, $dir, $arch) = @_;

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

	my $vdir = "$home/" . ActivePerl::perl_version();
	$dir = (-d $vdir) ? $vdir : $home;
    }

    unless ($arch) {
	$arch =  $Config{archname};
	$arch .= sprintf "-%vd", substr($^V, 0, 2) if $] >= 5.008;
    }

    my $etc = $dir; # XXX or "$dir/etc";
    my @inc = defined(*main::INC_ORIG) ? @main::INC_ORIG : @INC;

    # determine what install areas exists from @INC
    my @area;
    my %area;
    my @tmp = @inc;
    while (@tmp) {
	my $dir = shift(@tmp);
	next unless is_abs_path($dir);
	if (my $name = _known_area($dir)) {
	    push(@area, $name) unless grep $_ eq $name, @area;
	    next;
	}

	my $base = File::Basename::basename($dir);
	my $archlib;
	if ($base eq $Config{archname} || $base eq "arch") {
	    $archlib = $dir;
	    $dir = File::Basename::dirname($dir);
	    $dir = join_path($dir, "lib") if $base eq "arch";
	    shift(@tmp) if $tmp[0] eq $dir;
	}
	my $lib = $dir;
	$base = File::Basename::basename($dir);
	$dir = File::Basename::dirname($dir) if $base eq "lib";

	my $name = _area_name($dir);
	while (grep $_ eq $name, @area) {
	    # make name unique
	    my $num = ($name =~ s/_(\d+)//) ? $1 : 1;
	    $name .= "_" . ++$num;
	}

	push(@area, $name);
	$area{$name} = ActivePerl::PPM::InstallArea->new(
            name => $name,
            prefix => $dir,
            lib => $lib,
            archlib => $archlib,
        );
    }

    # make sure these install areas always show up
    for my $a (qw(site perl)) {
	push(@area, $a) unless grep $_ eq $a, @area;
    }

    my $self = bless {
	dir => $dir,
	etc => $etc,
        arch => $arch,
	area => \%area,
        area_seq => \@area,
        inc => \@inc,
    }, $class;
    return $self;
}

sub _known_area {
    my $path = shift;
    return "perl" if _path_eq($path, $Config{privlib}, $Config{archlib});
    return "site" if _path_eq($path, $Config{sitelib}, $Config{sitearch});
    return "vendor" if $Config{vendorlib} && _path_eq($path, $Config{vendorlib}, $Config{vendorarch});
    return undef;
}

sub _path_eq {
    my @paths = @_;
    for (@paths) {
	s,/,\\,g if $^O eq "MSWin32";
	$_ = lc($_) if $^O eq "MSWin32" || $^O eq "darwin";
    }

    my $first = shift(@paths);
    for my $p (@paths) {
	return 1 if $first eq $p;
    }
    return 0;
}

sub _area_name {
    my $path = shift;

    # obtain name from the ppm-*-area.db file if present
    if (opendir(my $dh, "$path/etc")) {
	while (defined(my $f = readdir($dh))) {
	    if ($f =~ /^ppm-(\w+)-area.db$/) {
		if ($1 eq "perl" || $1 eq "site" || $1 eq "vendor") {
		    ppm_log("WARN", "Found $f in $path/etc");
		    last;
		}
		return $1;
	    }
	}
	closedir($dh);
    }

    # try to find a usable name from the $path
    my @path = split(/[\/\\]/, $path);
    while (@path) {
	my $segment = pop(@path);
	my $lc_segment = lc($segment);
	next if $segment eq "lib" || $segment eq "arch" || $segment eq $Config{archname};
	next if $lc_segment eq "perl" || $lc_segment eq "site" || $lc_segment eq "vendor";
	return "pdk" if $segment =~ /\bPerl Dev Kit\b/;
	next unless $segment =~ /^[\w\-.]{1,12}$/;
	return $segment;
    }

    # last resort
    return "user";
}

sub arch {
    my $self = shift;
    return $self->{arch};
}

sub areas {
    my $self = shift;
    return @{$self->{area_seq}};
}

sub area {
    my($self, $name) = @_;
    return undef unless $name;
    return $self->{area}{$name} ||= do {
	die "Install area '$name' does not exist" unless grep $_ eq $name, @{$self->{area_seq}};
	ActivePerl::PPM::InstallArea->new($name);
    }
}

sub default_install_area {
    my $self = shift;
    my $area = "site";
    if ($self->area($area)->readonly) {
	my @areas = $self->areas;
	while (defined($area = shift(@areas))) {
	    next if $area eq "perl" || $area eq "site" || $area eq "vendor";
	    next if $area eq "pdk";
	    last unless $self->area($area)->readonly;
	}
    }
    return $area;
}

sub _init_db {
    my $self = shift;
    my $etc = $self->{etc};
    File::Path::mkpath($etc);
    require DBI;
    my $file_arch = $self->{arch};
    $file_arch =~ s/\./_/g;  # don't confuse version number dots with file extension
    my $db_file = "$etc/ppm-$file_arch.db";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "", {
        AutoCommit => 0,
        PrintError => 1,
    });
    die "$db_file: $DBI::errstr" unless $dbh;

    my $v = $dbh->selectrow_array("PRAGMA user_version");
    die "Assert" unless defined $v;
    if ($v == 0) {
	ppm_log("WARN", "Setting up schema for $db_file");
	_init_ppm_schema($dbh, $self->{arch});
	$dbh->do("PRAGMA user_version = 1");
	$dbh->commit;
    }
    elsif ($v != 1) {
	die "Unrecognized database schema $v for $db_file";
    }

    $self->{dbh} = $dbh;
}

sub _init_ppm_schema {
    my($dbh, $arch) = @_;
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
    $dbh->do("INSERT INTO config(key, value) VALUES ('arch', ?)", undef, $arch);
    if (my @repo = activestate_repo()) {
	$dbh->do(qq(INSERT INTO repo(name,packlist_uri) VALUES (?, ?)), undef, @repo);
    }
}

sub activestate_repo {
    my $os = lc($^O);
    $os = "windows" if $os eq "mswin32";
    my $repo_uri = "http://ppm.activestate.com/PPMPackages/5.8-$os/";
    if ($os =~ /^(windows|linux|hpux|solaris)$/ || web_ua()->head($repo_uri)->is_success) {
	return $repo_uri unless wantarray;
	return ("ActiveState Package Repository", $repo_uri);
    }
    return;
}

sub repos {
    my $self = shift;
    @{$self->dbh->selectcol_arrayref("SELECT id FROM repo ORDER BY prio, name")};}

sub repo {
    my($self, $id) = @_;
    my $dbh = $self->dbh;
    my $hash = $dbh->selectrow_hashref("SELECT * FROM repo WHERE id = ?", undef, $id);
    if ($hash) {
	my $pkgs = $dbh->selectrow_array("SELECT count(*) FROM package WHERE repo_id = ?", undef, $id);
	$hash->{pkgs} = $pkgs;
    }
    return $hash;
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
		my $cref = $res->decoded_content(ref => 1);
		if ($res->content_type eq "text/html") {
		    my $base = $res->base;
		    require HTML::Parser;
		    my $p = HTML::Parser->new(
	                report_tags => [qw(a)],
	                start_h => [sub {
			    my $href = shift->{href} || return;
			    push(@check_ppd, URI->new_abs($href,$base)->rel($repo->{packlist_uri})) if $href =~ /\.ppd$/;
			}, "attr"],
		    );
		    $p->parse($$cref)->eof;
		    ppm_log("WARN", "No ppds found in $repo->{packlist_uri}") unless @check_ppd;

		    %delete_package = map { $_ => 1 } @{$dbh->selectcol_arrayref("SELECT id FROM package WHERE repo_id = ?", undef, $repo->{id})};
		}
		elsif ($$cref =~ /<REPOSITORY(?:SUMMARY)?\b/) {
		    _repo_delete_packages($dbh, $repo->{id});
		    require ActivePerl::PPM::ParsePPD;
		    my $p = ActivePerl::PPM::ParsePPD->new(sub {
			my $pkg = shift;
			$pkg = ActivePerl::PPM::RepoPackage->new_ppd($pkg, $self->{arch});
			$pkg->{repo_id} = $repo->{id};
			$pkg->dbi_store($dbh) if $pkg->{codebase};
		    });
		    $p->parse_more($$cref);
		    $p->parse_done;
		}
		else {
		    ppm_log("ERR", "Unrecognized repo type " . $res->content_type);
		}
	    }
	}

	for my $ppd (@check_ppd) {
	    _check_ppd($ppd, $self->{arch}, $repo, $dbh, \%delete_package);
	}

	$dbh->do("DELETE FROM package WHERE id IN (" . join(",", sort keys %delete_package) . ")")
	    if %delete_package;

	$dbh->commit;
    }
    return;
}


sub _check_ppd {
    my($rel_url, $arch, $repo, $dbh, $delete_package) = @_;

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
	my $ppd = ActivePerl::PPM::RepoPackage->new_ppd($ppd_res->decoded_content, $arch);
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
    my $self = shift;
    my $feature = shift;
    for my $area_name (@_ ? @_ : $self->areas) {
	my $area = $self->area($area_name);
	if (defined(my $have = $area->feature_have($feature))) {
	    ppm_debug("Feature $feature found in $area_name");
	    return $have;
	}
	ppm_debug("Feature $feature not found in $area_name");
    }

    if (!@_ && $feature =~ /::/) {
	require ActiveState::ModInfo;
	require ExtUtils::MakeMaker;
	if (my $path = ActiveState::ModInfo::find_module($feature, $self->{inc})) {
	    return MM->parse_version($path) || 0;
	}
	ppm_debug("Module $feature not found in \@INC");
    }

    return undef;
}

sub packages_missing {
    my($self, %args) = @_;
    my @pkg_have = @{delete $args{have} || []};
    my @area_have = @{delete $args{area} || []};
    my @todo = @{delete $args{want} || []};

    my $force = delete $args{force};
    my $follow_deps = delete $args{follow_deps} || "missing";
    if (my $want_deps = delete $args{want_deps}) {
	push(@pkg_have, @$want_deps);
	for my $pkg (@$want_deps) {
	    if ($follow_deps ne "none") {
		if (my $dep = $pkg->{require}) {
		    push(@todo, map [$_ => $dep->{$_}, $pkg->{name} ], keys %$dep);
		}
	    }
	}
    }

    if ($^W && %args) {
	require Carp;
	Carp::carp("Unknown argument '$_' passed") for sort keys %args;
    }

    return unless @todo;


    my @missing_upgrade;
    for my $feature (@todo) {
	$feature = [$feature, 0] unless ref($feature);
	my($name, $version) = @$feature;
	unless (defined $version) {
	    if (defined($version = $self->feature_best($name))) {
		$feature->[1] = $version;
	    }
	    else {
		push(@missing_upgrade, $name);
	    }
	}
    }
    if (@missing_upgrade) {
	@missing_upgrade = sort @missing_upgrade;
	my $missing = pop(@missing_upgrade);
	$missing = join(" or ", join(", ", @missing_upgrade), $missing) if @missing_upgrade;
	die "No $missing available";
    }

    my @pkg_missing;
    while (@todo) {
        my($feature, $want, $needed_by) = @{shift @todo};
	ppm_debug("Want $feature >= $want");

        my $have;
	for my $pkg (@pkg_have, @pkg_missing) {
	    $have = $pkg->{provide}{$feature};
	    if (defined $have) {
		if ($have < $want) {
		    my $msg = "Conflict for feature $feature version $have provided by $pkg->{name}, ";
		    $msg .= "$needed_by " if $needed_by;
		    $msg .= "want version $want";
		    die $msg;
		}
		push(@{$pkg->{_needed_by}}, $needed_by) if $needed_by;
		last;
	    }
	}
	$have = $self->feature_have($feature, @area_have) unless defined($have);
	ppm_debug("Have $feature $have") if defined($have);

        if ((!$needed_by && $force) ||
	    ($needed_by && $follow_deps eq "all") ||
            !defined($have) || $have < $want)
        {
            if (my $pkg = $self->package_best($feature, $want)) {
		$self->check_downgrade($pkg, $feature) unless $force;
		push(@pkg_missing, $pkg);
		if ($needed_by) {
		    push(@{$pkg->{_needed_by}}, $needed_by);
		}
		else {
		    $pkg->{_wanted}++;
		}

		if ($follow_deps ne "none") {
		    if (my $dep = $pkg->{require}) {
			push(@todo, map [$_ => $dep->{$_}, $pkg->{name} ], keys %$dep);
		    }
		}
	    }
	    else {
		die "Can't find any package that provide $feature" .
		    ($want && $have ? "version $want" : "") .
		    ($needed_by ? " for $needed_by" : "");
	    }
        }
    }

    return $self->package_set_abs_ppd_uri(@pkg_missing);
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
    my($self, @pkgs) = @_;
    my %repo_cache;
    for my $pkg (@pkgs) {
	if (defined(my $repo_id = $pkg->{repo_id})) {
	    my($uri, $etag, $lastmod) = @{$repo_cache{repo_id} ||= [$self->dbh->selectrow_array("SELECT packlist_uri, packlist_etag, packlist_lastmod FROM repo WHERE id = ?", undef, $repo_id)]};
	    if ($pkg->{ppd_uri}) {
		$pkg->{ppd_uri} = URI->new_abs($pkg->{ppd_uri}, $uri)->as_string;
	    }
	    else {
		$pkg->{ppd_uri} = $uri;
		$pkg->{ppd_etag} = $etag;
		$pkg->{ppd_lastmod} = $lastmod;
	    }
	}
    }
    return @pkgs;
}

1;

__END__

=head1 NAME

ActivePerl::PPM::Client - Client class

=head1 SYNOPSIS

  my $ppm = ActivePerl::PPM::Client->new;

=head1 DESCRIPTION

The C<ActivePerl::PPM::Client> object ties together a set of install
areas and repositories and allow the installed packages to be managed.
The install areas are deducted from the values of C<@INC> when the
object is constructed.

The following methods are provided:

=over

=item $client = ActivePerl::PPM::Client->new

=item $client = ActivePerl::PPM::Client->new( $home_dir )

The constructor creates a new client based on the configuration found
in $home_dir which defaults to F<$ENV{HOME}/.ActivePerl> directory of the
current user.  If no such directory is found it is created.

=item $client->arch

A string that identifies the architecture for the current perl.  This
must match the ARCHITECTURE/NAME attribute of PPDs for them to match.

=item $client->area( $name )

Returns an object representing the given named install area.  The
method will croak if no install area with the given $name is known.
The C<perl> and C<site> areas will always be available.  See
L<ActivePerl::PPM::InstallArea> for methods available on the returned
object.

=item $client->areas

Return list of available install area names.  The list is ordered to
match the corresponding entries in C<@INC>.

=item $client->default_install_area

Return the name of the area where installations should normally go.
Might return C<undef> if there is no appropriate default.

=item $client->repo( $repo_id )

Returns the repo object with the given identifier.  See
L<ActivePerl::PPM::Repo> for methods available on the returned object.

=item $client->repos

Returns list of available repo identifiers.  The repos are ordered by priority.

=item $client->repo_add( %attr )

Will add a new repository with the given attributes.  The method will
croak if a repository with the same C<packlist_uri> already exists.

=item $client->repo_delete( $repo_id )

Will make the client forget about the given repository.

=item $client->repo_enable( $repo_id )

=item $client->repo_enable( $repo_id, $bool )

Makes it possible to enable and disable the given reposiory.  If $bool
is provided and is FALSE, then the repository is disabled.  The return
value is TRUE if the given repository was enabled.

=item $client->repo_sync

=item $client->repo_sync( force => 1 )

Will sync the local cache of packages from the enabled repositories.
Remote repositories are not contacted if the cache is not considered
stale yet.  Pass the C<force> option with a TRUE value to force state
to be transfered again from remote repositories.

=item $client->search( $pattern )

=item $client->search( $pattern, $field,... )

Will search for packages matching the given glob style $pattern.
Without further arguments this will return a list of package names.
With $field arguments it will return a list of array references, each
one filled in with the corresponding values for maching packages.

=item $client->search_lookup( $num )

Will look up the given package from the last search() result, where
$num matches the 1-based index into the list returned by the last
search.  This will return an L<ActivePerl::PPM::RepoPackage> object.

=item $client->package( $id )

=item $client->package( $name )

=item $client->package( $name, $version )

Returns the L<ActivePerl::PPM::RepoPackage> object matching the
arguments or C<undef> if none match.  As there can be multiple
packages with the same name, an arbitrary one is selected if $name but
no $version is given.

=item $client->feature_best( $feature )

Returns the highest version number provided for the given feature by
the packages found in all enabled repositories.  The method return
C<undef> if no package provide this feature.

=item $client->package_best( $feature, $version )

Returns the best package of all enabled repositories that provide the
given feature at or better than the given version.

=item $client->feature_have( $feature )

=item $client->feature_have( $feature, @areas )

Returns the installed version number of the given feature.  Returns
C<undef> if none of the installed packages provide this feature.

If one or more @areas are provided, only look in the areas given by
these names.

=item $client->packages_missing( %args )

Returns the list of packages to install in order to obtain the
requested features.  The returned list consist of
L<ActivePerl::PPM::RepoPackage> objects.  The attribute C<_wanted>
will be TRUE if a package was requested directly.  The attribute
C<_needed_by> will be an array reference of package names listing
packages having resolved dependencies on this package.  These
attributes do not exclude each other.

The arguments to the functions are passed as key/value pairs:

=over

=item want => \@features

This is the list of features to resolve.  The elements can be plain
strings denoting feature names, or references to arrays containing a
$name, $version pair.  If $version is provided as C<undef> then this
is taken as an upgrade request and the function will try to find the
packages that provide the best possible version of this feature.

=item have => \@pkgs

List of packages you already have decided to install.  The function
will check if any of these packages provide needed features before
looking anywhere else.

=item want_deps => \@pkgs

Resolve any dependencies for the given packages.

=item area => \@areas

List of names of install areas to consider when determining if
requested features or dependencies are already installed or not.

=item force => $bool

If TRUE then return packages that provide the given features even if
they are already installed.  Will also disable check for downgrades.

=item follow_deps => $str

In what way should packages dependencies be resolved.  The provided
$str can take the values C<all>, C<missing>, or C<none>.  The default
is C<missing>.  If $str is C<all> then dependent packages are returned
even if they are already installed.  If $str is C<missing> then only
missing dependencies are returned.  If $str is C<none> then
dependencies are ignored.

=back

=back

=head1 BUGS

none.
