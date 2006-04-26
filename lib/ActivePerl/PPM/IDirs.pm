package ActivePerl::PPM::IDirs;

use strict;
use Config qw(%Config);
use Carp qw(croak);
use ActiveState::ModInfo qw(fname2mod);
use ActiveState::Path qw(join_path);
use File::Compare ();
use File::Path ();
use File::Basename ();

use ActivePerl::PPM::Package ();
use ActivePerl::PPM::Logger qw(ppm_log ppm_status ppm_debug);


sub new {
    my $class = shift;
    unshift(@_, "name") if @_ == 1;
    my %opt = @_;
    my $name = delete $opt{name} || "";

    my %dirs;
    if ($name eq "perl") {
	%dirs = (
            prefix => $Config{prefix},
	    archlib => $Config{archlib},
            lib => $Config{privlib},
	    bin => $Config{bin},
            script => $Config{scriptdir},
            man1 => $Config{man1dir},
            man3 => $Config{man3dir},
            html => $Config{installhtmldir},   # XXX ActivePerl hack
	);
    }
    elsif ($name eq "site" || $name eq "vendor") {
	my $prefix = $Config{"${name}prefix"}
	    || croak("No $name InstallDirs configured for this perl");
	%dirs = (
	    prefix => $prefix,
	    archlib => $Config{"${name}arch"},
            lib => $Config{"${name}lib"},
	    bin => $Config{"${name}bin"},
            script => $Config{"${name}script"},
            man1 => $Config{"${name}man1dir"},
            man3 => $Config{"${name}man3dir"},
            html => $Config{installhtmldir},   # XXX ActivePerl hack
	);
    }
    elsif ($name) {
	die "NYI";
    }
    else {
	my $prefix = delete $opt{prefix}
	    || croak("Neither name nor prefix specified");
	%dirs = (
	    prefix => $prefix,
	    archlib => $opt{archlib},
            lib => $opt{lib},
	    bin => $opt{bin},
            script => $opt{script},
            man1 => $opt{man1},
            man3 => $opt{man3},
	    html => $opt{html},
	);
    }

    # defaults
    die "No prefix" unless $dirs{prefix};
    for my $d (qw(bin lib etc html)) {
	$dirs{$d} ||= "$dirs{prefix}/$d";
    }
    $dirs{archlib} ||= $dirs{lib};
    $dirs{script} ||= $dirs{bin};

    # cleanup
    for my $d (keys %dirs) {
	delete $dirs{$d} unless defined($dirs{$d}) && length($dirs{$d});
    }
    if ($^O eq "MSWin32") {
	s,\\,/,g for values %dirs;
    }

    my $self = bless {
        name => $name,
        dirs => \%dirs,
    }, $class;
    return $self;
}

sub DESTROY {
    my $self = shift;
    if (my $dbh = delete $self->{dbh}) {
	$dbh->disconnect;
    }
}

sub name {
    my $self = shift;
    $self->{name};
}

sub prefix {
    my $self = shift;
    $self->{dirs}{prefix};
}

sub archlib {
    my $self = shift;
    $self->{dirs}{archlib};
}

sub lib {
    my $self = shift;
    $self->{dirs}{lib};
}

sub etc {
    my $self = shift;
    $self->{dirs}{etc};
}

sub packages {
    my $self = shift;
    my $dbh = $self->dbh;
    my $aref = $dbh->selectcol_arrayref("SELECT name FROM package ORDER BY name");
    return @$aref;
}

sub dbh {
    my $self = shift;
    $self->init_db unless $self->{dbh};
    $self->{dbh};
}

sub packlists {
    my $self = shift;
    my %pkg;
    my $archlib = $self->archlib;
    my $auto = "$archlib/auto";
    require File::Find;
    File::Find::find(sub {
	return unless $_ eq ".packlist";
	my $pkg = substr($File::Find::name, length($auto) + 1);
	substr($pkg, -(length(".packlist")+1)) = "";
	$pkg =~ s,/,-,g,
        $pkg{$pkg} = $File::Find::name;
    }, $auto) if -d $auto;
    if (-f "$archlib/.packlist") {
	$pkg{"Perl"} = "$archlib/.packlist";
    }
    return wantarray ? (keys %pkg) : \%pkg;
}

sub inc {
    my $self = shift;
    my @inc;
    push(@inc, $self->archlib);
    my $lib = $self->lib;
    push(@inc, $lib) unless $lib eq $inc[0];
    return @inc;
}

sub verify {
    my($self, %opt) = @_;
    my $dbh = $self->dbh;
    my $pkg = delete $opt{package};
    my $pkg_id;
    if ($pkg) {
	$pkg_id = $self->package_id($pkg);
	croak("Package $pkg is not known") unless defined($pkg_id);
    }
    my $sth = $dbh->prepare("SELECT path, md5, mode FROM file" .
        (defined($pkg_id) ? " WHERE package_id = $pkg_id" : "") .
	" ORDER BY path");
    $sth->execute;
    my %status = (
        verified => 0,
    );
    $status{id} = $pkg_id if $pkg_id;
    while (my($path, $md5, $mode) = $sth->fetchrow_array) {
	$path = $self->_expand_path($path);
	printf "V $path $md5 %03o\n", $mode if $opt{verbose};
	if (my $info = _file_info($path)) {
	    if (defined($mode) && $mode != $info->{mode}) {
		printf "%s: wrong mode %03o expected %03o\n", $path, $info->{mode}, $mode;
		$status{wrong_mode}++;
	    }
	    if (defined $md5 && $md5 ne $info->{md5}) {
		print "$path: modified\n";
		$status{modified}++;
	    }
	}
	else {
	    print "$path: missing\n";
	    $status{missing}++;
	}
	$status{verified}++;
    }

    wantarray ? %status : !($status{wrong_mode} || $status{modified} || $status{missing});
}

sub package_id {
    my($self, $pkg) = @_;
    my $id = $self->dbh->selectrow_array("SELECT id FROM package WHERE name = ?", undef, $pkg);
    return $id;
}

sub package {
    my($self, $id) = @_;
    return undef unless defined($id);
    $id = $self->package_id($id) unless $id =~ /^\d+$/;
    return undef unless defined($id);
    return ActivePerl::PPM::Package->new_dbi($self->dbh, $id);
}

sub feature_have {
    my($self, $feature) = @_;
    my $vers = $self->dbh->selectrow_array("SELECT max(version) FROM feature WHERE name = ? AND role = 'p'", undef, $feature);
    return $vers;
}

sub install {
    my($self, @packages) = @_;

    # check packages and default file based on blib
    croak("No packages to install") unless @packages;
    for my $pkg (@packages) {
	croak("Missing package name") unless $pkg->{name};
	if (my $blib = $pkg->{blib}) {
	    for my $d (qw(arch archlib lib bin script man1 man3 html)) {
		next unless -d "$blib/$d";
		my $dd = $d;
		$dd = "archlib" if $dd eq "arch";  # :-(
		$pkg->{files}{"$blib/$d"} = "$dd:";
	    }
	}
    }

    my $dbh = $self->dbh;

    # do install
    my %state = (
        dbh => $dbh,
	self => $self,
        pkg_id => undef,
        commit => [],
        rollback => [],
	old_files => {},
    );
    eval {
	for my $pkg (@packages) {
	    my $pkg_id = $self->package_id($pkg->{name});
	    if (defined $pkg_id) {
		# XXX update version, author, abstract
	        $dbh->do("DELETE FROM feature WHERE package_id = $pkg_id");
		for (@{$dbh->selectcol_arrayref("SELECT path FROM file where package_id = $pkg_id")}) {
		    $state{old_files}{$_}++;
		}
	        $dbh->do("DELETE FROM file WHERE package_id = $pkg_id");
            }
	    else {
		$dbh->do("INSERT INTO package (name, version, author, abstract) VALUES (?, ?, ?, ?)", undef, @{$pkg}{qw(name version author abstract)});
		$pkg_id = $dbh->func('last_insert_rowid'); #$dbh->last_insert_id;
	    }
	    $state{pkg_id} = $pkg_id;

	    ppm_log("NOTICE", "Intalling $pkg->{name} with id $pkg_id");

	    my $files = $pkg->{files};
	    next unless $files;
	    for my $from (sort keys %$files) {
		die "There is no '$from' to install from" unless -l $from || -e _;
		my $to = $self->_expand_path($files->{$from});
		ppm_debug("Copy $from --> $to");
		if (-d _) {
		    die "Can't install a directory on top of $to"
			if -e $to && !-d _;
		    for ($from, $to) {
			$_ .= "/" unless m,/\z,;
		    }
		    _copy_dir(\%state, $from, $to);
		}
		elsif (-f _) {
		    _copy_file(\%state, $from, $to);
		}
		else {
		    die "Can't install $from since it's neither a regular file nor a directory";
		}
	    }
	}
	for (keys %{$state{old_files}}) {
	    _on_commit(\%state, "unlink", $self->_expand_path($_));
	}
    };

    if ($@) {
	ppm_log("ERR", "Rollback $@");
	$dbh->rollback;
	_do_action(reverse @{$state{rollback}});
	return 0;
    }
    else {
	ppm_log("NOTICE", "Commit install");
	$dbh->commit;
	_do_action(@{$state{commit}});
	return 1;
    }
}

sub _do_action {
    for my $action (@_) {
	my($op, @args) = @$action;
	ppm_debug("$op @args");
	if ($op eq "rmdir") {
	    for my $d (@args) {
		rmdir($d) || ppm_log("WARN", "Can't rmdir($d): $!");
	    }
	}
	elsif ($op eq "unlink") {
	    # Some platforms (HP-UX) cannot delete in-use executables
	    # and will produce "Text file busy" (ETXTBSY) warnings
	    # here.  So make it clear this is "just" a warning.
	    unlink(@args) || ppm_log("WARN", "Can't unlink(@args): $!");
	}
	elsif ($op eq "rename") {
	    rename($args[0], $args[1]) || ppm_log("WARN", "Can't rename(@args): $!");
	}
	else {
	    # programmer error
	    die "Don't know how to '$op'";
	}
    }
}

sub _on_rollback {
    my $state = shift;
    push(@{$state->{rollback}}, [@_]);
}

sub _on_commit {
    my $state = shift;
    push(@{$state->{commit}}, [@_]);
}

sub _copy_file {
    my($state, $from, $to) = @_;

    my $copy_to = $to;
    if (-e $to) {
	if (-f _ && File::Compare::compare($from, $to) == 0) {
	    $copy_to = undef;
	    ppm_log("INFO", "$to already present");
	}
	else {
	    my $bak = "$to.ppmbak";
	    die "Can't save to $bak since it exists" if -e $bak;
	    rename($to, $bak) || die "Can't rename as $bak: $!";
	    _on_rollback($state, "rename", $bak, $to);
	    _on_commit($state, "unlink", $bak);
	}
    }

    if ($copy_to) {
	open(my $in, "<", $from) || die "Can't open $from: $!";
	binmode($in);

	my $out;
	open($out, ">", $copy_to) || do {
	    my $err = $!;
	    my $dirname = File::Basename::dirname($copy_to);
	    unless (-d $dirname) {
		if (File::Path::mkpath($dirname)) {
		    # XXX rollback mkpath
		    if (open($out, ">", $copy_to)) {
			$err = undef;
		    }
		}
	    }
	    die "Can't create $copy_to: $err" if $err;
	};
	binmode($out);
	_on_rollback($state, "unlink", $copy_to);

	my $n;
	my $buf;
	while ( ($n = read($in, $buf, 4*1024))) {
	    print $out $buf;
	}

	die "Read failed for file $from: $!"
	    unless defined $n;

	close($in);
	close($out) || die "Write failed for file $copy_to";
	ppm_log("INFO", "$copy_to written");
    }

    my $path = $state->{self}->_relative_path($to);
    my $info = _file_info($to);

    delete $state->{old_files}{$path};
    $state->{dbh}->do("INSERT INTO file (package_id, path, md5, mode) VALUES (?, ?, ?, ?)", undef, $state->{pkg_id}, $path, $info->{md5}, $info->{mode});
}

sub _copy_dir {
    my($state, $from, $to) = @_;

    unless (-d $to) {
	# XXX should we use mkpath instead?
	mkdir($to, 0755) || die "Can't mkdir $to: $!";
	_on_rollback($state, "rmdir", $to);
    }

    opendir(my $dh, $from) || die "Can't opendir $from: $!";
    my @files = sort readdir($dh);
    closedir($dh);

    for my $f (@files) {
	next if $f eq "." || $f eq ".." || $f eq ".exists" || $f =~ /~\z/;
	my $from_file = "$from$f";
	my $to_file = "$to$f";
	if (-l $from_file) {
	    die "Can't copy link $from_file";
	}
	elsif (-f _) {
	    _copy_file($state, $from_file, $to_file);
	}
	elsif (-d _) {
	    _copy_dir($state, "$from_file/", "$to_file/");
	}
	else {
	    die "Don't know how to copy $from_file";
	}
    }
}

sub init_db {
    my $self = shift;
    my $etc = $self->etc;
    File::Path::mkpath($etc);
    require DBI;
    my $db_file = "ppm.db";
    if (my $name = $self->name) {
	$db_file = "ppm-$name.db";
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$etc/$db_file", "", "", {
        AutoCommit => 0,
        PrintError => 1,
    });
    die unless $dbh;
    $self->{dbh} = $dbh;

    my $count = $dbh->selectrow_array("SELECT count(*) FROM package");
    $self->_init_ppm_schema unless defined $count;
    $self->sync_db unless $count;
}

sub _init_ppm_schema {
    my $self = shift;
    my $dbh = $self->{dbh};
    for my $create (ActivePerl::PPM::Package->sql_create_tables()) {
	$dbh->do($create);
    }
    $dbh->do(<<'EOT');
CREATE TABLE IF NOT EXISTS file (
    package_id integer,
    path text unique not null,
    md5 char(32),
    mode integer
)
EOT
    $dbh->commit;
}

sub sync_db {
    my $self = shift;
    my $dbh = $self->dbh;
    ppm_status("Syncing PPM database with .packlists");
    require ExtUtils::Packlist;
    my $pkglists = $self->packlists;
    for my $pkg (sort keys %$pkglists) {
	my $id = $dbh->selectrow_array("SELECT id FROM package WHERE name = ?", undef, $pkg);
	if (defined $id) {
	    my($md5) = $dbh->selectrow_array("SELECT md5 FROM file WHERE package_id = ? AND path LIKE '%/.packlist'", undef, $id);
	    if ($md5 && $md5 eq _file_info($pkglists->{$pkg})->{md5}) {
		# packlist unchanged, assume unchanges package
		ppm_log("NOTICE", "$pkg seems to be up-to-date");
		next;
	    }
	    ppm_log("INFO", "Updating PPM entry for $pkg");
	}
	else {
	    $dbh->do("INSERT INTO package (name) VALUES (?)", undef, $pkg);
	    $id = $dbh->func('last_insert_rowid'); #$dbh->last_insert_id;
	    ppm_log("INFO", "Created PPM entry for $pkg");
	}

	my $pkglist = ExtUtils::Packlist->new($pkglists->{$pkg});
	$dbh->do("DELETE FROM file WHERE package_id = ?", undef, $id);
	$dbh->do("DELETE FROM feature WHERE package_id = ? AND role = 'p'", undef, $id);
	for my $f ($pkglists->{$pkg}, sort keys %$pkglist) {
	    my $path = $self->_relative_path($f);
	    my $info = _file_info($f);
	    $dbh->do("INSERT INTO file (package_id, path, md5, mode) VALUES (?, ?, ?, ?)", undef, $id, $path, $info->{md5}, $info->{mode});

	    if ($f =~ /\.pm$/) {
		require ExtUtils::MakeMaker;
		my $mod = $f;
		$mod =~ s,\\,/,g if $^O eq "MSWin32";
		$mod =~ s,^$self->{dirs}{archlib}/,, or
		    $mod =~ s,^$self->{dirs}{lib}/,,;
		$mod = fname2mod($mod);
		$mod .= "::" unless $mod =~ /::/;
		my $vers = MM->parse_version($f);
		$dbh->do("INSERT INTO feature (package_id, name, version, role) VALUES(?, ?, ?, ?)", undef, $id, $mod, $vers, "p");
	    }
	}
	$dbh->commit;
    }

    # check if any registered packages are now gone
    for my $pkg ($self->packages) {
	next if $pkglists->{$pkg};  # already processed
	my %info = $self->verify(package => $pkg);
	if ($info{verified} && $info{verified} == ($info{missing} || 0)) {
	    # all files has been deleted, nuke package
	    die "Assert" unless $info{id};
	    ppm_log("NOTICE", "The $pkg package is gone");
	    $dbh->do("DELETE FROM file WHERE package_id = ?", undef, $info{id});
	    $dbh->do("DELETE FROM feature WHERE package_id = ?", undef, $info{id});
	    $dbh->do("DELETE FROM package WHERE id = ?", undef, $info{id});
	    $dbh->commit;
	}
	else {
	    ppm_log("WARN", "The $pkg package is missing its .packlist");
	}
    }
    ppm_status("");
}

sub _relative_path {
    my($self, $path) = @_;
    $path =~ s,\\,/,g if $^O eq "MSWin32";
    $path =~ s,^\Q$self->{dirs}{prefix}\E/,prefix:,;
    return $path;
}

sub _expand_path {
    my($self, $path) = @_;
    if ($path =~ s/^([a-z][a-z\d]+)://) {
	my $d = $1;
	die "No $d dirs configured" unless exists $self->{dirs}{$d};
	$path = join_path($self->{dirs}{$d}, $path);
    }
    return $path;
}

sub _file_info {
    my $file = shift;
    open(my $fh, "<", $file) || return undef;
    binmode($fh);
    my %info;

    @info{qw(dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks)} = stat($fh);
    $info{mode} &= 07777;

    require Digest::MD5;
    $info{md5} = Digest::MD5->new->addfile($fh)->hexdigest;

    return \%info;
}

1;

__END__

=head1 NAME

ActivePerl::PPM::IDirs - Perl install location

=head1 SYNOPSIS

  my $dir = ActivePerl::PPM::IDirs->new("site");
  # or
  my $dir = ActivePerl::PPM::IDirs->new(prefix => "$ENV{HOME}/perl");

=head1 DESCRIPTION

An C<ActivePerl::PPM::IDirs> provide an interface to a Perl install
area.  Different install areas might have different protection
policies and each contain a set of installed packages and modules.  An
I<IDirs> is divided into the following areas:

=over 8

=item archlib

This is where architecture specific modules go.  Packages that are
implemented using XS code are installed here.

=item lib

This is where architecture neutral modules go.  Packages that
implemented in pure perl can be installed here.

=item bin

This is where architecture specific programs go.

=item script

This is where architecture neutral programs go.

=item etc

This is where configuration files go.

=item man1

This is where Unix style manual pages describing programs go.

=item man3

This is where Unix style manual pages describing modules go.

=item html

This is where HTML files go.

=item prefix

This just provide a prefix for the I<IDirs> as a whole.  All paths
above should be at or below C<prefix>.

=back

The following methods are provided:

=over

=item $dir = ActivePerl::PPM::IDirs->new( $name )

=item $dir = ActivePerl::PPM::IDirs->new( %opts )

Constructs a new C<ActivePerl::PPM::IDirs> object.  If constructed
based on $name, then the constructor might return C<undef> if no
I<IDirs> with the given name is known.  The "perl" and "site" I<IDirs>
are always available.  Some perls might also have a "vendor" I<IDirs>.
Additional user defined I<IDirs> might be available.

Alternatively the directories to use can be specified directly by
passing them as key/value pair %opts.  Only C<prefix> is mandatory.
All other directories are derived from this, except for the C<man*>
directories will only set up if specified explicitly.

=item $dir->name

Returns the name.  This returns the empty string for nameless I<IDirs>.

=item $dir->prefix

=item $dir->archlib

=item $dir->lib

=item $dir->bin

=item $dir->script

=item $dir->man1

=item $dir->man3

=item $dir->html

=item $dir->etc

Returns the corresponding path.

=item $dir->packages

Returns the list of packages currently installed.  In scalar context
returns the number of packages installed.

=item $dir->packlists

Returns the list of packages that have F<.packlist> files installed.
In scalar context return a hash reference; the keys are package names
and the values are full paths to the corresponding F<.packlist> file.

=item $dir->inc

Returns the list of directories to be pushed onto perl's @INC for the
current installdirs.

=item $dir->verify( %opts )

Verify that the files of the installed packages are still present and
unmodified.  Prints messages to STDOUT about files that are missing or modified.

In scalar context returns TRUE if all files where still found good.
In array context return key/value pairs suitable for assignment to a
hash.  The C<verified> value is the number of files checked.  The
C<missing>, C<modified>, C<wrong_mode> tally the files found to be
missing, modified or chmoded.

The following options are recognized:

=over

=item package => $name

Only verify the given package.

=back

=item $dir->install( \%pkg1, \%pkg2, ... )

Install the given list of packages as one atomic operation.  The
function returns TRUE if all packages installed or FALSE if
installation failed.

Each package to be installed is described by a hash reference with the
following elements:

=over

=item name => $name

The name of the package.  If a package with the given name is already
installed, then it will replaced with the new package.  This is the
only mandatory attribute.

=item version => $version

The version identifier for the given package.

=item author => $string

Who the current maintainer of the package is.  Should normally be on
the form "Givenname Lastname <user@example.com>".

=item abstract => $string

A short sentence describing the purpose of the package.

=item blib => $path

Pick up files to install from the given I<blib> style directory.  The
codebase directory of PPM packages is usually a tarball of this stuff.

=item files => \%hash

A hash describing files and directories to install.  The keys are
where to copy files from and the values are install locations.  The
install locations selects what type of directory to install into by
prefixing them with an dir identifier followed by a colon.  Example:

   files => {
      Foo => "archlib:Foo",
      "Bar.pm" => "lib:Bar.pm"
   }

This will install the "Foo" directory into the archlib area and the
"Bar.pm" module into the lib area.

=back

=back

=head1 BUGS

none.
