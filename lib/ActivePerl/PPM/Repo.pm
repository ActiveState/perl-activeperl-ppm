package ActivePerl::PPM::Repo;

use strict;
use XML::Simple ();
use URI ();
use URI::file ();
use HTML::Parser ();
use ActivePerl::PPM::PPD ();
use ActivePerl::PPM::RepoPackage ();
use ActivePerl::PPM::Web qw(web_ua);
use ActivePerl::PPM::Logger qw(ppm_log);

use DBI ();

sub new {
    my($class, $dir, %opt) = @_;
    my $prop_file = "$dir/prop.xml";
    return undef unless -f $prop_file;

    my $prop = XML::Simple::XMLin($prop_file);
    my $url = $prop->{url};
    $url = URI->new($url);
    unless ($url->scheme) {
	# relative, make it absolute 
	my $repo = URI::file->new_abs("$dir/");
	$url = URI::file->new($url)->abs($repo);
    }

    my $self = bless {
	dir => $dir,
        url => $url,
        name => $prop->{name} || $dir,
	prio => $prop->{prio} || 0,
    }, $class;

    return $self;
}

sub name {
    my $self = shift;
    return $self->{name};
}

sub url {
    my $self = shift;
    return "$self->{url}";
}

sub prio {
    my $self = shift;
    return $self->{prio};
}

sub sync {
    my $self = shift;
    my $dir = $self->{dir};
    my $url = $self->{url};

    #unlink("$dir/cache.db");  # clean
    my $dbh = $self->{dbh} ||= DBI->connect("dbi:SQLite:dbname=$dir/cache.db", "", "", {
        AutoCommit => 0,
        PrintError => 1,
    });
    die unless $dbh;
    #$dbh->trace(1);
    #print "Using SQLite v$dbh->{sqlite_version}\n";

    for my $create (ActivePerl::PPM::RepoPackage->sql_create_tables()) {
	$dbh->do($create);
    }
    $dbh->do(<<'EOT');
CREATE TABLE IF NOT EXISTS config (
    last_sync integer
)
EOT

    my $last_sync = $dbh->selectrow_array("SELECT last_sync FROM config");
    if ($last_sync) {
	$last_sync = time - $last_sync;
	if ($last_sync < 60*60) {
	    use ActiveState::Duration qw(ago_eng);
	    ppm_log("INFO", "Skipping sync, last synced " . ago_eng($last_sync));
	    return;
	}
    }
    else {
	# initialize config
	$dbh->do("INSERT INTO config (last_sync) VALUES (NULL)");
    }

    # determine repo type
    my $ua = web_ua();

    my $res = $ua->get($url);
    if ($res->content_type eq "text/html") {
	my $base = $res->base;
	my @ppd;
        my $p = HTML::Parser->new(
	    report_tags => [qw(a)],
	    start_h => [sub {
	        my $href = shift->{href};
		push(@ppd, URI->new($href,$base)->abs($base)->rel($url)) if $href =~ /\.ppd$/;
            }, "attr"],
	);
	$p->parse($res->content)->eof;
	warn "No ppds found in repo\n" unless @ppd;
	$dbh->do("CREATE TEMP TABLE tmp_delete_packages AS SELECT id FROM package");
	my $select_package = "SELECT id, ppd_etag, ppd_size, ppd_mod FROM package WHERE ppd = ?";  # XXX with prepare it only works on the first round (driver bug?)
	for my $rel_url (@ppd) {
	    my $abs_url = $rel_url->abs($url);
	    my @row = $dbh->selectrow_array($select_package, undef, $rel_url);
	    #print "XXX $abs_url [@row]\n";
	    my @h;
	    if (@row) {
		$dbh->do("DELETE FROM tmp_delete_packages WHERE id = $row[0]");
		push(@h, "If-None-Match", $row[1]) if $row[1];
		push(@h, "If-Modified-Since", $row[3]) if $row[3];
	    }
	    my $ppd_res = $ua->get($abs_url, @h);
	    print $ppd_res->as_string, "\n" unless $ppd_res->code eq 200 || $ppd_res->code eq 304;
	    if ($ppd_res->is_success) {
		my $ppd = ActivePerl::PPM::RepoPackage->new_ppd($ppd_res->content);
		$ppd->{id} = $row[0] if @row;
		$ppd->{ppd} = $rel_url;
		$ppd->{ppd_etag} = $ppd_res->header("ETag");
		$ppd->{ppd_size} = $ppd_res->header("Content-Length");
		$ppd->{ppd_mod} = $ppd_res->header("Last-Modified");

		# make URL attributes absolute (XXX make them repo relative instead?)
		my $ppd_base = $ppd_res->base;
		for my $attr (qw(codebase)) {
		    next unless exists $ppd->{$attr};
		    my $url = URI->new($ppd->{$attr}, $ppd_base)->abs($ppd_base);
		    $ppd->{$attr} = $url->as_string;
		}

		$ppd->dbi_store($dbh);
	    }
	}
	$dbh->do("DELETE FROM package WHERE id IN (SELECT id FROM tmp_delete_packages)");
	$dbh->do("DELETE FROM feature WHERE package_id in (SELECT id FROM tmp_delete_packages)");
	$dbh->do("DROP TABLE tmp_delete_packages");
	$dbh->do("UPDATE config SET last_sync = ?", undef, time);
	$dbh->commit;
    }
    else {
	warn "Unrecognized repo type for $url";
    }
}

sub feature_best {
    my($self, $feature) = @_;
    $self->sync() unless $self->{dbh};
    my $dbh = $self->{dbh};
    my($max) = $dbh->selectrow_array("SELECT max(version) FROM feature WHERE name = ? AND role = 'p'", undef, $feature);
    return $max;
}

sub package_best {
    my($self, $feature, $version) = @_;
    $version ||= 0;

    $self->sync() unless $self->{dbh};
    my $dbh = $self->{dbh};

    my $ids = $dbh->selectcol_arrayref("SELECT package.id FROM package, feature WHERE package.id = feature.package_id AND feature.role = 'p' AND feature.name = ? AND feature.version >= ?", undef, $feature, $version);

    my @pkg = map $self->package($_), @$ids;

    return ActivePerl::PPM::Package::best(@pkg);
}

sub package {
    my $self = shift;

    $self->sync() unless $self->{dbh};
    my $dbh = $self->{dbh};

    return ActivePerl::PPM::RepoPackage->new_dbi($dbh, @_);
}

sub search {
    my $self = shift;
    my $pattern = shift;
    $pattern =~ s/\*/%/g;
    $self->sync() unless $self->{dbh};
    my $dbh = $self->{dbh};
    $dbh->do("CREATE TEMP TABLE search AS SELECT name, version FROM package WHERE name LIKE ?", undef, $pattern);
    $dbh->do("INSERT INTO search SELECT package.name, package.version FROM package, feature WHERE package.id = feature.package_id AND feature.name LIKE ? AND feature.role = 'p'", undef, $pattern);

    my $sth = $dbh->prepare("SELECT DISTINCT * FROM search ORDER BY name");
    $sth->execute;
    my @res;
    while (my($name, $version) = $sth->fetchrow_array) {
	$name .= "-$version" if defined($version);
	push(@res, $name);
    }
    $dbh->rollback;
    return @res;
}

1;

__END__

=head1 NAME

ActivePerl::PPM::Repo - Repository class

=head1 SYNOPSIS

  my $repo = ActivePerl::PPM::Repo->new($dirname);

=head1 DESCRIPTION

The C<ActivePerl::PPM::Repo> class provide an interface to a PPM
package repository.  A repo always lives in a local directory where
its configuration is specififed in the F<prop.xml> file and the SQLite
database C<cache.db> provide locally cached information about the
packages contained in the repo.  The C<cache.db> file can be deleted
any time and its content will be recreated and updated on demand.

The following methods are provided:

=over

=item $repo = ActivePerl::PPM::Repo->new( $dirname )

Contructs a new C<ActivePerl::PPM::Repo> object based on the given
directory.  Will return C<undef> unless a valid F<prop.xml> file is
found in the specified directory.

=item $repo->name

Returns the name of the repository.

=item $repo->url

Returns the URL of the repository.  The URL can currently reference:

=over

=item *

An HTML document with links to F<.ppd> files using any scheme that L<LWP> supports.

=item *

A local directory specified as a relative URL or full F<file:> with F<.ppd> files.

=item *

An ftp directory with F<.ppd> files.

=back

=item $repo->prio

An integer priority.  Used to order repos.  Repos with smaller
priority numbers are searched first.

=item $repo->sync

Check for updates in the remote repository URL.  Will update the local F<cache.db> file.

=item $repo->feature_best( $feature )

Returns the highest feature version number for the given feature.
Returns C<undef> if no package within the repo provide the given
feature.

=item $repo->package_best( $feature )

=item $repo->package_best( $feature, $version )

Returns an C<ActivePerl::PPM::Package> object for the best package
that provide the given feature.  The package will provide the given
feature with the given version number or better.

Returns C<undef> if no package provide the given feature.  Might croak
if no consistent order is found between the packages that provide the
given feature.

=item $repo->search( $pattern )

Returns a list of package C<name_version> strings for packages that match
the given $pattern.

=back

=head2 F<prop.xml>

The F<prop.xml> file should look something like this:

  <properties>
     <url>http://www.example.com/ppm</url>
     <prio>1</prio>
     <name>Example Package Repository</name>
  </properties>

=head1 BUGS

none.
