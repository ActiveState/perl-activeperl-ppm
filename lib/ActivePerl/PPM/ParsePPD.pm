package ActivePerl::PPM::ParsePPD;

use strict;

require XML::Parser::Expat;
our @ISA = qw(XML::Parser::ExpatNB);

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

    $self->{softpkg} = {};

    my $ch = sub {
        $_[0]->{txt} .= $_[1];
    };

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
                $p->{txt} = "";
		$p->setHandlers(Char => $ch);
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
		my $h = $p->{ctx}{script}{lc $tag} = {};
		$h->{exec} = $attr{EXEC} if exists $attr{EXEC};
		$h->{uri} = $attr{HREF} if exists $attr{HREF};
                $p->{txt} = "";
		$p->setHandlers(Char => $ch);
	    }
	    elsif ($tag eq "SOFTPKG") {
		my @c = $p->context;
		$p->xpcroak("$tag must be root") if @c && "@c" !~ /^REPOSITORY(SUMMARY)?$/;
		my %attr = @_;
		$p->xpcroak("Required SOFTPKG attribute NAME and VERSION missing")
		    unless exists $attr{NAME} && exists $attr{VERSION};

		%{$p->{softpkg}} = ( name => $attr{NAME}, version => $attr{VERSION}, release_date => $attr{DATE} );
		$p->{softpkg}{base} = $p->{base} if $p->{base};

		$p->{ctx} = $p->{softpkg};
	    }
	    elsif ($tag =~ /^REPOSITORY(SUMMARY)?$/) {
		$p->xpcroak("$tag must be root") if $p->depth;
		my %attr = @_;
		$p->{base} = $attr{BASE};
		$p->{arch} = $attr{ARCHITECTURE};
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
		$p->{ctx}{architecture} ||= $p->{arch} || "noarch";
		$p->{ctx} = $p->{softpkg};
	    }
	    elsif ($TEXT_TAG{$tag}) {
		$p->{ctx}{lc $tag} = $p->{txt};
                $p->setHandlers(Char => undef);
	    }
	    elsif ($tag =~ /^(UN)?INSTALL$/) {
		my $h = $p->{ctx}{script}{lc $tag};
		$h->{text} = $p->{txt}
		    unless defined($h->{uri}); # SCRIPT/HREF is preferred
                $p->setHandlers(Char => undef);
	    }
	    elsif ($tag eq "SOFTPKG") {
		my $pkg = $p->{softpkg};
		if (exists $pkg->{codebase}) {
		    $pkg->{architecture} ||= $p->{arch} || "noarch";
		}
		$handler->($pkg);
		return;
	    }
	},
    );

    return $self;
}

1;
