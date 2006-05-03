package ActivePerl::PPM::RepoPackage;

use strict;
use base qw(ActivePerl::PPM::Package);

sub BASE_FIELDS {
    my $class = shift;
    return (
       $class->SUPER::BASE_FIELDS,
       [repo_id         => "integer not null"],
       [ppd_uri         => "text unique"],
       [ppd_etag        => "text"],
       [ppd_lastmod     => "text"],
       [ppd_size        => "integer"],
       [ppd_fresh_until => "integer"],
    );
}

1;

__END__

=head1 NAME

ActivePerl::PPM::RepoPackage - Package class that tracks PPD file
attributes

=head1 DESCRIPTION

C<ActivePerl::PPM::RepoPackage> is a subclass of
C<ActivePerl::PPM::Package> that adds a few fields that is used to
track changes to the corresponding PPD file.

The following are the new attributes:

=over

=item $id = $pkg->repo_id

What repo does this package come from.

=item $path = $pkg->ppd_uri

This a relative URI for the PPD file itself.

=item $str = $pkg->ppd_etag

This is the C<ETag> that the server reported for the PPD last time.

=item $str = $pkg->ppd_lastmod

This is the C<Last-Modified> date that the server reported for the PPD
last time.

=item $num = $pkg->ppd_size

This is the C<Content-Length> that the server reported for the PPD
last time.

=item $num = $pkg->ppd_fresh_until

At what time should the ppd information be refreshed from the repo.

=item

=back

=head1 SEE ALSO

L<ActivePerl::PPM::Package>, L<ActivePerl::PPM::Repo>

=head1 BUGS

none.
