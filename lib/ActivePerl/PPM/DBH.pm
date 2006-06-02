package ActivePerl::PPM::DBH;

sub dbh {
    my $self = shift;
    unless ($self->{dbh}) {
	die $self->{dbh_err} if $self->{dbh_err};
	$self->{dbh} = eval { $self->_init_db };
	if ($@) {
	    $self->{dbh_err} = $@;
	    die;
	}
    }
    return $self->{dbh};
}

sub DESTROY {
    my $self = shift;
    if (my $dbh = delete $self->{dbh}) {
	$dbh->disconnect;
    }
}

1;
