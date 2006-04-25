package ActivePerl::PPM::Package;

use strict;
use Carp qw(croak);

sub BASE_FIELDS {
    return (
       [id       => "integer primary key"],
       [name     => "text not null"],
       [version  => "text"],
       [author   => "text"],
       [abstract => "text"],
       [codebase => "text"],
    );
}

#
# constructors
#

sub new {
    my $class = shift;
    my $self = bless +(@_ == 1 ? shift : do{ my %hash = @_; \%hash }), $class;
    croak("No name given for package") unless $self->{name};
    $self->{provide}{$self->{name}} ||= 0;  # always provide ourself
    $self;
}

sub clone {
    my $self = shift;
    require Storable;
    my $other = Storable::dclone($self);
    delete $other->{id};
    return $other;
}

#
# accessors
#

sub AUTOLOAD
{
    our $AUTOLOAD;
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
    return if $method eq "DESTROY";

    my $self = shift;
    unless (grep $_->[0] eq $method, $self->BASE_FIELDS) {
	croak(qq(Can't locate object method "$method" via package ) . (ref($self) || $self));
    }
    my $old = $self->{$method};
    if (@_) {
	$self->{$method} = shift;
    }
    return $old;
}

sub name_version {
    my $self = shift;
    my $tmp = $self->{name};
    if (my $v = $self->{version}) {
	$tmp .= "-$v";
    }
    return $tmp;
}

sub provides {
    my $self = shift;
    return %{$self->{provide}};
}

sub requires {
    my $self = shift;
    return %{$self->{require} || []};
}

#
# comparators
#

sub compare {
    my($a, $b) = @_;

    my $c = undef;

    # compare the shared features to see if we have a winner
    for my $mod (keys %{$a->{provide}}) {
        next unless exists $b->{provide}{$mod};
        my $c2 = $a->{provide}{$mod} <=> $b->{provide}{$mod};
        $c = 0 unless defined $c;
        next if $c2 == 0;
        if ($c) {
            return undef unless $c == $c2;  # conflict
        }
        else {
            $c = $c2;
        }
    }

    if (defined($c) && $c == 0) {
	# if the shared features compared the same, break the tie
	# by selecting the package with more features.
	$c = (keys %{$a->{provide}} <=> keys %{$b->{provide}});
    }

    return $c;
}

sub better_than {
    my($self, $other) = @_;
    my $c = compare($self, $other);
    unless (defined($c)) {
	croak("No ordering between package " .
	      $self->name_version . " and " . $other->name_version);
    }
    return $c > 0;
}

sub best {
    my $best = shift;
    my @dunno;
    for my $p (@_) {
        my $c = compare($best, $p);
        if (defined $c) {
            $best = $p if $c < 0;
        }
        else {
            push(@dunno, $p);
        }
    }
    die "Can't determine best" if @dunno;  # XXX can we do better

    return $best;
}

#
# SQL storage
#

sub sql_create_tables {
    my $class = shift;
    return
"CREATE TABLE IF NOT EXISTS package (\n    " .
    join(",\n    ", map join(" ", @$_), $class->BASE_FIELDS) .
"
)",
"CREATE TABLE IF NOT EXISTS feature (
     package_id integer not null,
     name text not null,
     version double,
     role char(1) not null
)"
}

my %ROLE = (
    'p' => 'provide',
    'r' => 'require',
);

sub new_dbi {
    my($class, $dbh, $id_or_name, $version) = @_;

    my @bind = ($id_or_name);
    my $where;
    if ($id_or_name =~ /^\d+$/) {
        $where = "id = ?"
    } else {
        $where = "name = ? AND ";
        if (defined $version) {
            $where .= "version = ?";
            push(@bind, $version);
        }
        else {
            $where .= "version ISNULL";
        }
    }

    my $pkg = $dbh->selectrow_hashref("SELECT * FROM package WHERE $where", undef, @bind);
    return undef unless $pkg;

    if (1) {
        my $sth = $dbh->prepare("SELECT name, version, role FROM feature WHERE package_id = ?");
        $sth->execute($pkg->{id});
        while (my($feature, $version, $role) = $sth->fetchrow_array) {
            $pkg->{$ROLE{$role}}{$feature} = $version;
        }
    }

    return $class->new($pkg);
}

sub dbi_store {
    my($self, $dbh) = @_;
    my $id = $self->{id};

    my @fields = map $_->[0], $self->BASE_FIELDS;
    shift(@fields); # get rid of id

    if (defined $id) {
	$dbh->do("UPDATE package SET " . join(", ", map "$_ = ?", @fields), undef, @{$self}{@fields});
	$dbh->do("DELETE FROM feature WHERE package_id = ?", undef, $id);
    }
    else {
	$dbh->do("INSERT INTO package (" . join(", ", @fields) . ") VALUES(" . join(", ", map "?", @fields) . ")",
		 undef, @{$self}{@fields});
	$id = $dbh->func('last_insert_rowid');
    }

    for my $role (values %ROLE) {
	my $hash = $self->{$role} || next;
	while (my($feature, $version) = each %$hash) {
	    $dbh->do("INSERT INTO feature (package_id, name, version, role) VALUES(?, ?, ?, ?)", undef,
		     $id, $feature, $version, substr($role, 0, 1));
	}
    }

    $dbh->commit;

    return $id;
}

1;

__END__

=head1 NAME

ActivePerl::PPM::Package - Package class

=head1 SYNOPSIS

  my $pkg = ActivePerl::PPM::Package->new(name => 'Foo',...);
  # or
  my $pkg = ActivePerl::PPM::Package->new(\%hash);

=head1 DESCRIPTION

The C<ActivePerl::PPM::Package> class wraps hashes that describes
packages; the unit that the PPM system manages.

=head2 Constructors

The following constructor methods are provided:

=over

=item $pkg = ActivePerl::PPM::Package->new( %opt );

=item $pkg = ActivePerl::PPM::Package->new( \%self );

The constructor either take key/value pairs or a hash reference as
argument.  The only mandatory field is C<name>.  If a hash reference
is passed then it is turned into an C<ActivePerl::PPM::Package> object
and returned; which basically pass ownership of the hash.

=item $copy = $pkg->clone

Returns a copy of the current package object.  The attributes of the
clone can be modified without changing the original.

=item ActivePerl::PPM::Package->new_dbi($dbh, $id);

=item ActivePerl::PPM::Package->new_dbi($dbh, $name, $version);

Read object from a database and return it.  Returns C<undef> if no
package with the given key is found.

=item $pkg->dbi_store( $dbh )

Writes the current package to a database.  If $pkg was constructed by
C<new_dbi> then this updates the package, otherwise this creates a new
package object in the database.

=back

=head2 Attributes

The attributes of a package can be accessed directly using hash syntax
or by accesor methods.  The most common attributes are described
below, but the set of attributes is extensible.

=over

=item $str = $pkg->id

Returns the database id of package.  This attribute is set if the
object exists in a database.

=item $str = $pkg->name

Returns the name of the package.

=item $str = $pkg->version

Returns the version identifier for the package.  This string
can be anything and there is no reliable way to order packages based
on these version strings.

=item $str = $pkg->name_version

Returns the name and version concatenated together.  This form might
be handy for display, but there is no reliable way to parse back what
is the name and what is the version identifier.

=item $str = $pkg->author

The name and email address of the current maintainer of the package.

=item $str = $pkg->abstract

A short sentence describing the purpose of the package.

=item $url = $pkg->codebase

Returns the URL to implementation; a blib tarball.

=item %features = $pkg->provides

Returns a list of (feature, version) pairs describing what features
this package provide.  A feature name with a double colon in it
represent a perl module.  A package always provide its own name as a
feature.

=item %features = $pkg->requires

Returns a list of (feature, version) pairs describing what features
this package require to be installed for it to work properly.  A
feature name with a double colon in it represent a perl module.

=head2 Comparators

The following functions/methods can be used to order packages.

=item $pkg->compare( $other )

Returns -1, 0, 1 like perl's builtin C<cmp>.  Return C<undef> if no order is defined.

=item $pkg->better_than( $other )

Returns TRUE if this package is better than the package passed as
argument.  This method will croak if no order is defined.

=item $pkg->best( @others )

=item ActivePerl::PPM::Package::best( @pkgs )

Returns the best package.  Might croak if no order is defined among
the packages passed in.

=back

=head2 Misc methods

=over

=item ActivePerl::PPM::Package->sql_create_tables

This returns SQL C<CREATE TABLE> statements used to initialize the
database that the C<new_dbi> and C<dbi_store> methods depend on.

=back

=head1 BUGS

none.
