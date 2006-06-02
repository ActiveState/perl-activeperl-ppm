package ActivePerl::PPM::DBH;

sub dbh {
    my $self = shift;
    return $self->{dbh} ||= $self->_init_db;
}

sub DESTROY {
    my $self = shift;
    if (my $dbh = delete $self->{dbh}) {
	$dbh->disconnect;
    }
}

1;
