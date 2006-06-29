package ActivePerl::PPM::GUI;

use strict;
use Tkx ();
use ActiveState::Browser ();
use ActivePerl::PPM::Util qw(is_cpan_package);

# get our cwd for Tcl files
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $ppm = $::ppm;
$ActiveState::Browser::HTML_DIR = $ppm->area("perl")->html;

# these will be filled in the sync()
my @areas;
my @repos;

my $mw = Tkx::widget->new(".");
$mw->g_wm_withdraw();
Tkx::tk(appname => "Perl Package Manager");

Tkx::lappend('::auto_path', abs_path(dirname(__FILE__)) . "/tcl");

my $windowingsystem = Tkx::tk('windowingsystem');
my $AQUA = ($windowingsystem eq "aqua");

if ($ENV{'ACTIVEPERL_PPM_DEBUG'}) {
    Tkx::package_require('comm');
    print "DEBUG COMM PORT: " . Tkx::comm__comm('self') . "\n";

    Tkx::package_require('tkcon');
    if ($AQUA) {
	$mw->g_bind("<Command-F12>", 'catch {tkcon show}');
	$mw->g_bind("<Command-F11>", 'catch {tkcon hide}');
    } else {
	$mw->g_bind("<F12>", 'catch {tkcon show}');
	$mw->g_bind("<F11>", 'catch {tkcon hide}');
    }
    Tkx::catch("tkcon hide");
}

Tkx::package_require('tile');
Tkx::package_require('img::png');
Tkx::package_require('ppm::themes');
Tkx::package_require('tooltip');
Tkx::package_require('widget::dialog');
Tkx::package_require('widget::statusbar');
Tkx::package_require('widget::toolbar');
Tkx::package_require('widget::menuentry');
Tkx::package_require('ppm::pkglist');
Tkx::package_require('style::as');
Tkx::package_require('BWidget');
Tkx::Widget__theme(1);

Tkx::style__as__init();

if ($AQUA) {
    Tkx::set("::tk::mac::useThemedToplevel" => 1);
}

# get 'tooltip' as toplevel command
Tkx::namespace_import("::tooltip::tooltip");

Tkx::style_default('Slim.Toolbutton', -padding => 2);

# make tree widgets use theming on non-x11 platforms
if ($windowingsystem ne "x11") {
    Tkx::option_add("*TreeCtrl.useTheme", 1);
}

# purely for reciprocity debugging, expose the ppm command in Tcl
Tkx::interp(alias => "", "ppm", "", [\&::ppm]);

# Use Tk scroll on OS X, but Ttk scrollbar elsewhere by default
if ($AQUA) {
    Tkx::interp("alias", "", "::ttk::scrollbar", "", "::scrollbar");
    Tkx::option('add', "*Scrollbar.borderWidth", 0);
} else {
    Tkx::interp("alias", "", "::scrollbar", "", "::ttk::scrollbar");
}

# These variables are tied to UI elements
my %FILTER;
$FILTER{'filter'} = "";
$FILTER{'area'} = "ALL";
$FILTER{'type'} = "name abstract";
$FILTER{'id'} = "";
$FILTER{'delay'} = 500; # filter delay on key in millisecs
$FILTER{'lastfilter'} = "";
$FILTER{'lastarea'} = "";
$FILTER{'lasttype'} = $FILTER{'type'};

my %VIEW;
$VIEW{'name'} = 1;
$VIEW{'area'} = 1;
$VIEW{'installed'} = 1;
$VIEW{'available'} = 1;
$VIEW{'abstract'} = 1;
$VIEW{'author'} = 0;

$VIEW{'toolbar'} = 1;
$VIEW{'statusbar'} = 1;

my %ACTION;
$ACTION{'install'} = "";
$ACTION{'remove'} = "";

my %IMG;
$IMG{'refresh'} = Tkx::ppm__img('refresh');
$IMG{'filter'} = Tkx::ppm__img('search');
$IMG{'config'} = Tkx::ppm__img('config');
$IMG{'install'} = Tkx::ppm__img('install');
$IMG{'remove'} = Tkx::ppm__img('remove');

my $cur_pkg = undef; # Current selection package

my $action_menu;

# Create the menu structure
menus();

Tkx::bind($mw, "<Destroy>", [sub {
			     my $w = shift;
			     on_exit() if $w eq $mw->_mpath;
			 }, Tkx::Ev('%W')]);
$mw->g_wm_protocol('WM_DELETE_WINDOW', [\&on_exit]);

# Main interface
my $pw = $mw->new_ttk__paned(-orient => "vertical");
my $det_sw = $pw->new_widget__scrolledwindow();
my $details = $det_sw->new_text(-height => 7, -width => 60, -borderwidth => 1,
				-font => "ASfont", -state => "disabled",
				-wrap => "word",
				-tabs => ["10", "left", "90", "left"]);
$det_sw->setwidget($details);
my $pkglist = $pw->new_pkglist(-width => 550, -height => 350,
			       -selectcommand => [\&select_item],
			       -borderwidth => 1, -relief => 'sunken',
			       -itembackground => ["#F7F7FF", ""]);

Tkx::bind($pkglist, "<<PackageMenu>>", [sub {
	      my ($x, $y, $X, $Y) = @_;
	      $pkglist->selection('clear');
	      $pkglist->selection('add', "nearest $x $y");
	      $action_menu->g_tk___popup($X, $Y);
}, Tkx::Ev("%x", "%y", "%X", "%Y")]);
Tkx::event('add', "<<PackageMenu>>", "<Button-3>", "<Control-Button-1>");
my $toolbar = $mw->new_widget__toolbar();

$details->tag('configure', 'h1', -font => 'ASfontBold2');
$details->tag('configure', 'h2', -font => 'ASfontBold1');
$details->tag('configure', 'abstract', -font => 'ASfontBold',
	      -lmargin1 => 10, -lmargin2 => 10, -rmargin => 10);
$details->tag_configure('link', -underline => 1, -foreground => 'blue');
$details->tag_bind('link', "<Enter>", sub {
    $details->configure(-cursor => "hand2");
});
$details->tag_bind('link', "<Leave>", sub {
    $details->configure(-cursor => "");
});


my $statusbar = $mw->new_widget__statusbar(-ipad => [1, 2]);

$pw->add($pkglist, -weight => 3);
$pw->add($det_sw, -weight => 1);

Tkx::grid($toolbar, -sticky => "ew", -padx => 2);
Tkx::grid($pw, -sticky => "news", -padx => 4, -pady => 4);
Tkx::grid($statusbar, -sticky => "ew");

Tkx::grid(rowconfigure => $mw, 1, -weight => 1);
Tkx::grid(columnconfigure => $mw, 0, -weight => 1);

## Toolbar items
my $filter_menu = $toolbar->new_menu(-name => "filter_menu");
my $filter = $toolbar->new_widget__menuentry(
    -width => 1,
    -menu => $filter_menu,
    -textvariable => \$FILTER{'filter'},
);
Tkx::tooltip($filter, "Filter packages");
$toolbar->add($filter, -weight => 2);
$filter_menu->add('radiobutton', -label => "Name", -value => "name",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Abstract", -value => "abstract",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Name or Abstract",
		  -value => "name abstract",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Author", -value => "author",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter->g_bind('<Return>', [\&filter]);
$filter->g_bind('<Key>', [\&filter_onkey]);

my $albl = $toolbar->new_ttk__label(-text => "Area:");
my $area_cbx = $toolbar->new_ttk__combobox(-width => 6,
					   -values => ["ALL"],
					   -textvariable => \$FILTER{'area'});
Tkx::bind($area_cbx, "<<ComboboxSelected>>", [\&filter]);
$toolbar->add($albl, -pad => [0, 2]);
$toolbar->add($area_cbx, -pad => [0, 2, 2]);

# Action buttons
my $install_btn = $toolbar->new_ttk__button(-text => "Install",
					    -image => $IMG{'install'},
					    -style => "Toolbutton",
					    -state => "disabled");
$toolbar->add($install_btn, -separator => 1, -pad => [4, 2, 0]);
my $remove_btn = $toolbar->new_ttk__button(-text => "Remove",
					   -image => $IMG{'remove'},
					    -style => "Toolbutton",
					    -state => "disabled");
$toolbar->add($remove_btn, -pad => [0, 2]);

# Sync/config buttons
my $sync = $toolbar->new_ttk__button(-text => "Sync",
				     -image => $IMG{'refresh'},
				     -style => "Toolbutton",
				     -command => [\&full_refresh]);
Tkx::tooltip($sync, "Refresh all data");
$toolbar->add($sync, -separator => 1, -pad => [4, 2, 0]);

my $config = $toolbar->new_ttk__button(-text => "Config",
				       -image => $IMG{'config'},
				       -style => "Toolbutton");
Tkx::tooltip($config, "Configure something");
$toolbar->add($config, -pad => [0, 2]);

## Statusbar items
my %NUM;
$NUM{'total'} = 0;
$NUM{'listed'} = 0;
$NUM{'installed'} = 0;
$NUM{'install'} = 0;
$NUM{'remove'} = 0;
my $lbl;
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'total'});
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Total number of known packages");
$lbl = $statusbar->new_ttk__label(-text => "packages,");
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Total number of known packages");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'installed'});
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages installed");
$lbl = $statusbar->new_ttk__label(-text => "installed");
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages installed");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'listed'});
$statusbar->add($lbl, -separator => 1);
Tkx::tooltip($lbl, "Number of packages in filtered view");
$lbl = $statusbar->new_ttk__label(-text => "listed,");
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages in filtered view");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'install'});
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages selected for install");
$lbl = $statusbar->new_ttk__label(-text => "to install/upgrade,");
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages selected for install");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'remove'});
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages selected for removal");
$lbl = $statusbar->new_ttk__label(-text => "to remove", -anchor => 'w');
$statusbar->add($lbl, -weight => 1);
Tkx::tooltip($lbl, "Number of packages selected for removal");

## Wait dialog for when we sync
my $sync_dialog = $mw->new_widget__dialog(-title => 'Synchronize Database',
					  -parent => $mw, -place => 'over',
					  -type => 'ok',  -modal => 'local',
					  -synchronous => 0);
# Not all platforms have -topmost attribute
eval { $sync_dialog->g_wm_attributes(-topmost => 1); };
my $sfrm = $sync_dialog->new_ttk__frame();
my $slbl = $sfrm->new_ttk__label(-text => "We are sync'ing");
$sync_dialog->setwidget($sfrm);
Tkx::grid($slbl, -sticky => "ew");

# Now let's get started ...
Tkx::update('idletasks');

Tkx::after(idle => sub {
	       $mw->g_wm_deiconify();
	       Tkx::focus(-force => $mw);
	       full_refresh();
});

Tkx::MainLoop();

1;

sub refresh {
    $pkglist->clear();
    $NUM{'listed'} = 0;
    my $area = merge_area_items();
    $NUM{'installed'} = $pkglist->numitems();
    my $repo = merge_repo_items();
    $NUM{'total'} = $pkglist->numitems();
    #print "Total: $NUM{'total'}, Installed: $NUM{'installed'} of $area area items and $repo repo items\n";
    filter();
    $NUM{'listed'} = $pkglist->numitems('visible');
    $pkglist->sort();
}

sub sync {
    $ppm->repo_sync;
    @areas = $ppm->areas;
    @repos = $ppm->repos;
    $area_cbx->configure(-values => ["ALL", @areas]);
}

sub full_refresh {
    $sync_dialog->display();
    Tkx::update();
    sync();
    refresh();
    $sync_dialog->close('ok');
}

sub merge_area_items {
    my $count = 0;
    for my $area_name ($ppm->areas) {
	my $area = $ppm->area($area_name);
	my @fields = ("name", "version", "release_date", "abstract", "author");
	for my $pkg ($area->packages(@fields)) {
	    for (@$pkg) { $_ = "" unless defined }  # avoid "Use of uninitialized value" warnings
	    my ($name, $version, $release_date, $abstract, $author) = @$pkg;
	    $pkglist->add($name,
		       area => $area_name,
		       installed => $version,
		       abstract => $abstract,
		       author => $author,
		       );
	    $count++;
	}
    }
    return $count;
}

sub merge_repo_items {
    my @fields = ("name", "version", "release_date", "abstract", "author");
    my @res = $ppm->packages(@fields);
    my $count = @res;
    for (@res) {
	for (@$_) { $_ = "" unless defined }  # avoid "Use of uninitialized value" warnings
	my ($name, $version, $release_date, $abstract, $author) = @$_;
	$pkglist->add($name,
		   available => $version,
		   abstract => $abstract,
		   author => $author,
		   );
    }
    return $count;
}

sub filter {
    Tkx::after('cancel', $FILTER{'id'});
    return if ($FILTER{'filter'} eq $FILTER{'lastfilter'}
		   && $FILTER{'type'} eq $FILTER{'lasttype'}
		       && $FILTER{'area'} eq $FILTER{'lastarea'});
    my $type = $FILTER{'type'};
    $type =~ s/ / or /g;
    my $msg = "Filter packages by $type";
    $msg .= " in $FILTER{'area'} area" if $FILTER{'area'} ne "ALL";
    Tkx::tooltip($filter, $msg);
    my $count = $pkglist->filter($FILTER{'filter'}, $FILTER{'type'},
				 $FILTER{'area'});
    if ($count == -1) {
	# Something wrong with the filter
	$filter->delete(0, "end");
	$filter->insert(0, $FILTER{'lastfilter'});
	# No need to refilter - should not have changed
    } else {
	$FILTER{'lastfilter'} = $FILTER{'filter'};
	$FILTER{'lastarea'} = $FILTER{'area'};
	$FILTER{'lasttype'} = $FILTER{'type'};
	$NUM{'listed'} = $count;
    }
}

sub filter_onkey {
    Tkx::after('cancel', $FILTER{'id'});
    $FILTER{'id'} = Tkx::after($FILTER{'delay'}, [\&filter]);
}

sub ppm {
    my $func = shift;
    $ppm->$func(@_);
}

sub menus {
    Tkx::option_add("*Menu.tearOff", 0);
    my $menu = $mw->new_menu();
    $mw->configure(-menu => $menu);

    my $sm;

    # File menu
    $sm = $menu->new_menu(-name => "file");
    $menu->add_cascade(-label => "File", -menu => $sm);
    $sm->add_command(-label => "Exit", -accelerator => "Ctrl-q",
		     -command => [\&on_exit]);
    $mw->g_bind("<Control-q>" => [\&on_exit]);

    # Edit menu
    $sm = $menu->new_menu(-name => "edit");
    $menu->add_cascade(-label => "Edit", -menu => $sm);
    $sm->add_command(-label => "Cut", -state => "disabled");
    $sm->add_command(-label => "Copy", -state => "disabled");
    $sm->add_command(-label => "Paste", -state => "disabled");

    # View menu
    $sm = $menu->new_menu(-name => "view");
    $menu->add_cascade(-label => "View", -menu => $sm);
    $sm->add_checkbutton(-label => "Toolbar",
			 -variable => \$VIEW{'toolbar'},
			 -command => sub {
			     if ($VIEW{'toolbar'}) {
				 Tkx::grid($toolbar);
			     } else {
				 Tkx::grid('remove', $toolbar);
			     }
			 });
    $sm->add_checkbutton(-label => "Status Bar",
			 -variable => \$VIEW{'statusbar'},
			 -command => sub {
			     if ($VIEW{'statusbar'}) {
				 Tkx::grid($statusbar);
			     } else {
				 Tkx::grid('remove', $statusbar);
			     }
			 });
    $sm->add_separator();
    my $ssm = $sm->new_menu(-name => "fields");
    $sm->add_cascade(-label => "Fields", -menu => $ssm);
    my $colcmd = sub {
	my $col = shift;
	$pkglist->view($col, $VIEW{$col});
    };
    $ssm->add_checkbutton(-label => "Area",
			  -variable => \$VIEW{'area'},
			  -command => [$colcmd, 'area']);
    $ssm->add_checkbutton(-label => "Installed Version",
			  -variable => \$VIEW{'installed'},
			  -command => [$colcmd, 'installed']);
    $ssm->add_checkbutton(-label => "Available Version",
			  -variable => \$VIEW{'available'},
			  -command => [$colcmd, 'available']);
    $ssm->add_checkbutton(-label => "Abstract",
			  -variable => \$VIEW{'abstract'},
			  -command => [$colcmd, 'abstract']);
    $ssm->add_checkbutton(-label => "Author",
			  -variable => \$VIEW{'author'},
			  -command => [$colcmd, 'author']);

    # Action menu
    $action_menu = $sm = $menu->new_menu(-name => "action");
    $sm->configure(-postcommand => [\&on_action_post, $sm]);
    $menu->add_cascade(-label => "Action", -menu => $sm);

    # Help menu
    $sm = $menu->new_menu(-name => "help"); # must be named "help"
    $menu->add_cascade(-label => "Help", -menu => $sm);
    if (ActiveState::Browser::can_open("faq/ActivePerl-faq2.html")) {
	$sm->add_command(
	    -label => "PPM FAQ",
	    -command => [\&ActiveState::Browser::open, "faq/ActivePerl-faq2.html"],
	);
    }
    if (ActiveState::Browser::can_open("http://www.activestate.com")) {
	my $web = $sm->new_menu(-tearoff => 0);
	$sm->add_cascade(
	    -label => "Web Resources",
	    -menu => $web,
        );

        $web->add_command(
            -label => "Report Bug",
            -command => [\&ActiveState::Browser::open,
			 "http://bugs.activestate.com/enter_bug.cgi?set_product=ActivePerl"],
        );
        $web->add_command(
            -label => "ActiveState Repository",
            -command => [\&ActiveState::Browser::open,
			 "http://ppm.activestate.com/"],
        );
        $web->add_command(
            -label => "ActivePerl Home",
            -command => [\&ActiveState::Browser::open,
			 "http://www.activestate.com/Products/ActivePerl/"],
        );
        $web->add_command(
            -label => "ActiveState Home",
            -command => [\&ActiveState::Browser::open, "http://www.activestate.com"],
        );
    }

    $sm->add_separator;
    $sm->add_command(-label => "About", -command => sub { about(); });

    # Special menu on OS X
    if ($AQUA) {
	$sm = $menu->new_menu(-name => 'apple'); # must be named "apple"
	$menu->add_cascade(-label => "PPM", -menu => $sm);
	$sm->add_command(-label => "About PPM");
	$sm->add_separator();
	$sm->add_command(-label => "Preferences...",
			 -accelerator => "Command-,");
    }

    return $menu;
}

sub on_action_post {
    my $sm = shift;
    $sm->delete(0, 'end');
    if (defined($cur_pkg)) {
	$sm->add_command(-label => $cur_pkg->{name},
			 -state => "disabled");
	$sm->add_separator();
	$sm->add_command(-label => "Install") if $ACTION{'install'};
	$sm->add_command(-label => "Remove") if $ACTION{'remove'};
    } else {
	$sm->add_command(-label => "No selected package",
			 -state => "disabled");
    }
}

sub select_item {
    my $item = shift;
    $details->configure(-state => "normal");
    $details->delete('1.0', 'end');
    $details->configure(-state => "disabled");
    $cur_pkg = undef;
    return unless $item;

    # We need to figure out how we want details formatted
    my %data = Tkx::SplitList($pkglist->data($item));
    my $name = delete $data{'name'};
    my $areaid = delete $data{'area'};
    my $pkg = $ppm->package($name, $data{'available'} || undef);
    my $area = $ppm->area($areaid) if $areaid;
    $pkg = $area->package($name) if $areaid;
    my $pad = "\t";
    $details->configure(-state => "normal");
    $details->insert('1.0', "$pkg->{name}\n", 'h1');
    $details->insert('end', "$pkg->{abstract}\n", 'abstract');
    $details->insert('end', "${pad}Version:\t$pkg->{version}\n");
    $details->insert('end', "${pad}Released:\t$pkg->{release_date}\n");
    $details->insert('end', "${pad}Author:\t$pkg->{author}\n");
    if (is_cpan_package($pkg->{name})) {
	my $cpan_url = "http://search.cpan.org/dist/$pkg->{name}-$pkg->{version}/";
	if ($pkg->{name} eq "Perl") {
	    $cpan_url = sprintf "http://search.cpan.org/dist/perl-%vd", $^V;
	}
	$details->insert('end', "${pad}CPAN:\t");
	if (ActiveState::Browser::can_open($cpan_url)) {
	    $details->insert('end', $cpan_url, "link");
	    $details->tag_bind('link', "<ButtonRelease-1>", [
	        \&ActiveState::Browser::open, $cpan_url
	    ]);
	}
	else {
	    $details->insert('end', $cpan_url);
	}
	$details->insert('end', "\n");
    }
    if ($areaid) {
	$details->insert('end', "Files:\n", 'h2');
	for my $file ($area->package_files($pkg->{id})) {
	    $details->insert('end', "\t$file\n");
	}
    }
    # Remove trailing newline and prevent editing of widget
    $details->delete('end-1c');
    $details->configure(-state => "disabled");

    # Record "allowable" actions based on package info
    # XXX work on constraints
    $cur_pkg = $pkg;
    $ACTION{'install'} = "";
    $ACTION{'remove'} = "";
    $remove_btn->configure(-state => "disabled");
    $install_btn->configure(-state => "disabled");
    if ($areaid) {
	$ACTION{'remove'} = $pkg->{version};
	$remove_btn->configure(-state => "normal");
    } else {
	$ACTION{'install'} = $pkg->{version};
	$install_btn->configure(-state => "normal");
    }
}

sub about {
    require ActivePerl::PPM;
    require ActivePerl;
    my $perl_version = ActivePerl::perl_version;
    
    Tkx::tk___messageBox(-title => "About Perl Package Manager",
			 -icon => "info", -type => "ok",
			 -message => "PPM version $ActivePerl::PPM::VERSION (Beta 2)
ActivePerl version $perl_version
\xA9 2006 ActiveState Software Inc.");
}

sub on_load {
    # Restore state from saved information
    # We would need to make sure these are reflected in UI elements
    $FILTER{'filter'} = "";
    $FILTER{'area'} = "*";
    $FILTER{'type'} = "name abstract";

    $VIEW{'name'} = 1;
    $VIEW{'area'} = 1;
    $VIEW{'installed'} = 1;
    $VIEW{'available'} = 1;
    $VIEW{'abstract'} = 1;
    $VIEW{'author'} = 0;

    $VIEW{'toolbar'} = 1;
    $VIEW{'statusbar'} = 1;
}

sub on_exit {
    exit; # wait until this works

    # We should save dialog and other state information

    ## Window location and size
    my $geom = $mw->g_wm_geometry();

    ## Current filter
    $FILTER{'lastfilter'};
    $FILTER{'lastarea'};
    $FILTER{'lasttype'};

    ## Current selected package?
    if (defined($cur_pkg)) {
	my $name = $cur_pkg->{name};
    }

    ## Tree column order, widths, visibility, sort

    # this gets columns in current order (visible and not)
    my @cols = $pkglist->column('list');
    for my $col (@cols) {
	my $width = $pkglist->column('width', $col);
    }

    $VIEW{'name'};
    $VIEW{'area'};
    $VIEW{'installed'};
    $VIEW{'available'};
    $VIEW{'abstract'};
    $VIEW{'author'};

    $VIEW{'toolbar'};
    $VIEW{'statusbar'};

    exit;
}
