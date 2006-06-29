package ActivePerl::PPM::GUI::pkglist;

use base qw(Tkx::widget Tkx::MegaConfig);

__PACKAGE__->_Mega("ppm_pkglist");
__PACKAGE__->_Config(
    -borderwidth  => ["."],
    -relief  => ["."],
    -padding  => ["."],
    -selectcommand => ["PASSIVE"],
    -itembackground => ["METHOD"],
    -sortbackground => ["METHOD"],
    DEFAULT => [".sw.tree"],
);

Tkx::package_require('treectrl');
Tkx::package_require('widget::scrolledwindow');

sub _Populate {
    my($class, $widget, $path, %opt) = @_;

    my $self = $class->new($path)->_parent->new_ttk__frame(-name => $path);
    $self->_class($class);

    my $sw = $self->new_widget__scrolledwindow(-name => "sw");
    my $tree = $sw->new_treectrl(
	-name => "tree",
	-highlightthickness => 0, -borderwidth => 0,
	-showheader => 1, -showroot => 1,
	-showbuttons => 0, -showlines => 0,
	-selectmode => "browse",
	-xscrollincrement => 20,
	-scrollmargin => 16,
	-xscrolldelay => ["500", "50"],
	-yscrolldelay => ["500", "50"],
    );
    $sw->setwidget($tree);
    $sw->g_pack(-fill => "both", -expand => 1);

    # Place the megawidget container into the tree's bindtags
    my @tags = Tkx::SplitList($tree->g_bindtags());
    $tree->g_bindtags([$path, @tags]);

    $self->_data->{-selectcommand} = "";
    $self->_data->{sortcolumn} = "name";
    $self->_data->{sortorder} = "-increasing";
    $self->_data->{visible} = 0;
    $self->_data->{numitems} = 0;
    $self->_data->{tree} = $tree;

    # create tree columns
    $tree->column('create', -tag => 'action',
		  -image => Tkx::ppm__img('default'),
	      );
    $tree->column('create', -tag => 'name', -text => "Package Name",
		  -width => 100, -borderwidth => 1,
	      );
    $tree->column('create', -tag => 'area', -text => "Area",
		  -width => 40, -borderwidth => 1,
	      );
    $tree->column('create', -tag => 'installed', -text => "Installed",
		  -width => 60, -borderwidth => 1,
	      );
    $tree->column('create', -tag => 'available', -text => "Available",
		  -width => 60, -borderwidth => 1,
	      );
    $tree->column('create', -tag => 'abstract', -text => "Abstract",
		  -expand => 1, -squeeze => 1, -borderwidth => 1,
	      );
    $tree->column('create', -tag => 'author', -text => "Author",
		  -width => 120, -borderwidth => 1, -visible => 0,
	      );

    my $selbg = Tkx::set('::style::as::highlightbg');
    my $selfg = Tkx::set('::style::as::highlightfg');

    # define tree elements
    $tree->element(create => 'elemImg', "image");
    $tree->element(create => 'elemText', "text",
		   -lines => 1, -fill => [$selfg, ["selected", "focus"]]);
    $tree->element(create => 'selRect', "rect",
		   -fill => [$selbg, ["selected", "focus"],
			     "gray", ["selected", "!focus"]]);

    # define tree styles
    my $style = $tree->style(create => 'styImg');
    $tree->style(elements => $style, ["selRect", "elemImg"]);
    $tree->style(layout => $style, "selRect",
		 -union => "elemImg", -iexpand => 'news');
    $tree->style(layout => $style, "elemImg",
		 -expand => 'news');

    $style = $tree->style(create => 'styText');
    $tree->style(elements => $style, ["selRect", "elemText"]);
    $tree->style(layout => $style, "selRect",
		 -union => "elemText", -iexpand => 'news');
    $tree->style(layout => $style, "elemText",
		 -expand => 'ns', -squeeze => 'x', -padx => 2);

    $tree->notify(install => "<Header-invoke>");
    $tree->notify('bind' => $tree, "<Header-invoke>",
		  [sub { $self->_headerinvoke(@_) }, Tkx::Ev('%C')]);

    $tree->notify('bind' => $tree, "<Selection>",
		  [sub {
		       if ($self->_data->{-selectcommand} ne "") {
			   Tkx::eval($self->_data->{-selectcommand}, @_);
		       }
		   }, Tkx::Ev('%S')]);

    $tree->column('dragconfigure', -enable => 1);
    $tree->notify(install => "<ColumnDrag-begin>");
    $tree->notify(install => "<ColumnDrag-end>");
    $tree->notify(install => "<ColumnDrag-receive>");
    $tree->notify(bind => "DontDelete", "<ColumnDrag-receive>",
		  "%T column move %C %b");

    $tree->column(configure => $self->_data->{sortcolumn},
		  -arrow => 'up',
		  -itembackground => $self->_data->{-sortbackground});

    $self->configure(%opt);

    $self;
}

sub _mpath {
    my $self = shift;
    my $tree = $self->_data->{tree};
    "$tree";
}

sub _config_sortbackground {
    my $self = shift;
    my $value = shift;
    my $tree = $self->_data->{tree};
    $tree->column(configure => $self->_data->{sortcolumn},
		  -itembackground => $value);
    $self->_data->{-sortbackground} = $value;
}

sub _config_itembackground {
    my $self = shift;
    my $value = shift;
    my $tree = $self->_data->{tree};
    for my $col (Tkx::SplitList($tree->column('list'))) {
	$tree->column(configure => $col,
		      -itembackground => $value);
    }
    # don't lose sort column color
    $tree->column(configure => $self->_data->{sortcolumn},
		  -itembackground => $self->_data->{-sortbackground});
    $self->_data->{-itembackground} = $value;
}

sub add {
    my $self = shift;
    my $tree = $self->_data->{tree};
    my ($name, %cols) = @_;
    my $action = delete $cols{'action'} || 'default';
    #my $action = 'default';

    my $item = $tree->item('create', -button => 0, -open => 0,
			   -parent => 0, -visible => 1);
    $tree->item('style', set => $item,
		action => "styImg",
		name => "styText",
		area => "styText",
		installed => "styText",
		available => "styText",
		abstract => "styText",
		author => "styText",
		);
    $tree->item(text => $item, "name", $name, %cols);
    my $img = Tkx::ppm__img($action);
    $tree->item('element', configure => $item,
		action => 'elemImg', -image => $img);

    $self->_data->{numitems}++;
    $self->_data->{visible}++;

    return $item;
}

sub name {
    my $self = shift;
    my $tree = $self->_data->{tree};
}

sub data {
    my $self = shift;
    my $tree = $self->_data->{tree};
    my $item = shift;
    my $name = $tree->item('text' => $item, 'name');
    my $area = $tree->item('text' => $item, 'area');
    my $avail = $tree->item('text' => $item, 'available');
    return ["area", $area, "name", $name, "available", $avail];
}

sub clear {
    my $self = shift;
    my $tree = $self->_data->{tree};
    $tree->item(delete => "all");
    $self->_data->{visible} = 0;
    $self->_data->{numitems} = 0;
}

sub numitems {
    my $self = shift;
    my $type = shift;
    if (defined($type) && $type eq "visible") {
	return $self->_data->{visible};
    }
    return $self->_data->{numitems};
}

sub filter {
    my $self = shift;
    my $tree = $self->_data->{tree};
    my ($words, $fields, $area) = @_;

    if ($area eq "*" && ($words eq "" || $words eq "*")) {
	# make everything visible
    }
    for my $word (@$words) {
    }

    my $visible = 0;
    #$self->_data->{visible} = $visible;
    return $visible;
}

sub view {
    my $self = shift;
    my $tree = $self->_data->{tree};
    my ($col, $show) = @_;
    if (defined($show)) {
	$tree->column(configure => $col, -visible => $show);
    }
    return $tree->column(cget => $col, "-visible");
}

sub sort {
    my $self = shift;
    my $tree = $self->_data->{tree};
    $tree->item(sort => 'root', $self->_data->{sortorder}, '-dictionary',
		-column => $self->_data->{sortcolumn});
}

sub _headerinvoke {
    my $self = shift;
    my $tree = $self->_data->{tree};
    my $col = shift;
    my $dir = $tree->column(cget => $self->_data->{sortcolumn}, '-arrow');
    my $sortorder = "-increasing";
    my $arrow = "up";
    if ($tree->column('compare', $col, '==', $self->_data->{sortcolumn})) {
	if ($dir ne "down") {
	    $sortorder = "-decreasing";
	    $arrow = "down";
	}
    } else {
	if ($dir eq "down") {
	    $sortorder = "-decreasing";
	    $arrow = "down";
	}
	$tree->column(configure => $self->_data->{sortcolumn},
		      -arrow => "none",
		      -itembackground => $self->_data->{-itembackground});
	$self->_data->{sortcolumn} = $col;
    }
    $self->_data->{sortorder} = $sortorder;
    $tree->column(configure => $self->_data->{sortcolumn},
		  -arrow => $arrow,
		  -itembackground => $self->_data->{-sortbackground});
    $self->sort();
}

1;

=head1 NAME

ActivePerl::PPM::GUI::pkglist - pkglist widget for the PPM::GUI

=head1 SYNOPSIS

  use Tkx;
  use ActivePerl::PPM::GUI::pkglist;

  my $mw = Tkx::widget->new(".");

  my $e = $mw->new_ppm_pkglist();
  $e->g_pack;

  my $b = $mw->new_button(
      -text => "Done",
      -command => sub {
          print $e->get, "\n";
          $mw->g_destroy;
      },
  );
  $b->g_pack;

  Tkx::MainLoop();
