package ActivePerl::PPM::ParsePPD;

use strict;

require XML::Parser::Expat;
our @ISA = qw(XML::Parser::ExpatNB);

use ActiveState::Handy qw(iso_datetime);

my %TEXT_TAG = (
   ABSTRACT => 1,
   AUTHOR => 1,
);

my %IGNORE_TAG = (
   TITLE => 1,
   OS => 1,
   OSVERSION => 1,
   PROCESSOR => 1,
   PERLCORE => 1,
);

sub new {
    my $class = shift;
    my $handler = shift;
    my $self = $class->SUPER::new;

    $self->{txt} = [];
    $self->{softpkg} = {};

    $self->setHandlers(
	Start => sub {
	    my $p = shift;
	    my $tag = shift;
	    if (0) {
	        # dummy
	    }
	    elsif ($tag eq "REQUIRE" || $tag eq "PROVIDE" || $tag eq "DEPENDENCY") {
		my %attr = @_;
		if ($tag eq "DEPENDENCY") {
		    # legacy
		    $tag = "REQUIRE";
		    $attr{VERSION} = "0";
		}
		$attr{NAME} =~ s/::$// if $attr{NAME} =~ /::\w+::/;
		$p->{ctx}{lc $tag}{$attr{NAME}} = $attr{VERSION} || 0;
	    }
	    elsif ($TEXT_TAG{$tag}) {
		@{$p->{txt}} = ();
	    }
	    elsif ($tag eq "IMPLEMENTATION") {
		$p->{ctx} = {};
		push(@{$p->{softpkg}{lc $tag}}, $p->{ctx});
	    }
	    elsif ($tag eq "ARCHITECTURE") {
		my %attr = @_;
		$p->{ctx}{lc $tag} = $attr{NAME};
	    }
	    elsif ($tag eq "CODEBASE") {
		my %attr = @_;
		$p->{ctx}{lc $tag} = $attr{HREF};
	    }
	    elsif ($tag eq "INSTALL" || $tag eq "UNINSTALL") {
		my %attr = @_;
		$p->{ctx}{lc $tag} = \%attr;
		@{$p->{txt}} = ();
	    }
	    elsif ($tag eq "SOFTPKG") {
		my @c = $p->context;
		$p->xpcroak("$tag must be root") if @c && "@c" !~ /^REPOSITORY(SUMMARY)?$/;
		my %attr = @_;
		$p->xpcroak("Required SOFTPKG attribute NAME and VERSION missing")
		    unless exists $attr{NAME} && exists $attr{VERSION};
		%{$p->{softpkg}} = ( name => $attr{NAME}, version => $attr{VERSION}, release_date => ($attr{DATE} ? iso_datetime($attr{DATE}) : undef) );
		$p->{ctx} = $p->{softpkg};
	    }
	    elsif ($tag =~ /^REPOSITORY(SUMMARY)?$/) {
		$p->xpcroak("$tag must be root") if $p->depth;
	    }
	    elsif ($IGNORE_TAG{$tag}) {
		# ignore
	    }
	    else {
		$p->xpcroak("Unrecognized PPD tag $tag");
	    }
	},
	End => sub {
	    my($p, $tag) = @_;
	    if ($tag eq "IMPLEMENTATION") {
		$p->{ctx} = $p->{softpkg};
	    }
	    elsif ($TEXT_TAG{$tag} && @{$p->{txt}}) {
		$p->{ctx}{lc $tag} = join("", @{$p->{txt}});
	    }
	    elsif ($tag =~ /^(UN)?INSTALL$/ && @{$p->{txt}}) {
		$p->{ctx}{lc $tag}{script} = join("", @{$p->{txt}});
	    }
	    elsif ($tag eq "SOFTPKG") {
		$handler->($p->{softpkg});
		return;
	    }
	},
        Char => sub {
	    push(@{$_[0]->{txt}}, $_[1]);
         },
    );

    return $self;
}

1;
