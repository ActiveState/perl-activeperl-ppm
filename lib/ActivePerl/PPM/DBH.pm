package ActivePerl::PPM::DBH;

sub dbh {
    my $self = shift;
    return $self->{dbh} ||= do {
	die $self->{dbh_err} if $self->{dbh_err};
	my $dbh = eval { $self->_init_db };
	if ($@) {
	    $self->{dbh_err} = $@;
	    die;
	}
	$dbh;
    };
}

sub DESTROY {
    my $self = shift;
    if (my $dbh = delete $self->{dbh}) {
	$dbh->disconnect;
    }
}

1;
