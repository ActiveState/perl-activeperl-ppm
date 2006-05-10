package ActivePerl::PPM::DBH;

sub dbh {
    my $self = shift;
    $self->_init_db unless $self->{dbh};
    $self->{dbh};
}

sub DESTROY {
    my $self = shift;
    if (my $dbh = delete $self->{dbh}) {
	$dbh->disconnect;
    }
}

1;
