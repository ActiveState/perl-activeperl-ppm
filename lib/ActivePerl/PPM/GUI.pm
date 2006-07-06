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
my %AREAS;
my %REPOS;

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
Tkx::package_require('widget::panelframe');
Tkx::package_require('ppm::pkglist');
Tkx::package_require('ppm::repolist');
Tkx::package_require('style::as');
Tkx::package_require('BWidget');
Tkx::Widget__theme(1);

Tkx::style__as__init();

if ($AQUA) {
    Tkx::set("::tk::mac::useThemedToplevel" => 1);
}

if ($windowingsystem eq "win32") {
    $mw->g_wm_iconbitmap(-default => $^X);
}

# This code makes themed frames use the notebook's background color.
# We restrict the use of this to those frames in notebooks.
Tkx::style(layout => "NotebookPane",
	   ["NotebookPane.background", -sticky => "news", -expand => 1]);
Tkx::option_add("*TNotebook.TFrame.style", "NotebookPane");
Tkx::option_add("*TNotebook.TLabelframe.style", "NotebookPane");

# get 'tooltip' as toplevel command
Tkx::namespace_import("::tooltip::tooltip");

#Tkx::style_default('Slim.Toolbutton', -padding => 2);

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
$FILTER{'id'} = "";
$FILTER{'delay'} = 500; # filter delay on key in millisecs
$FILTER{'filter'} = "";
$FILTER{'lastfilter'} = "";
$FILTER{'fields'} = "name abstract";
$FILTER{'lastfields'} = $FILTER{'fields'};
$FILTER{'type'} = "all"; # all installed upgradable modified
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

my %IMG;
$IMG{'refresh'} = [Tkx::ppm__img('refresh')];
$IMG{'prefs'} = [Tkx::ppm__img('config')];
$IMG{'install'} = [Tkx::ppm__img('package', 'install')];
$IMG{'remove'} = [Tkx::ppm__img('package', 'remove')];
$IMG{'go'} = [Tkx::ppm__img('package', 'modified')];
$IMG{'f_all'} = [Tkx::ppm__img('available', 'filter')];
$IMG{'f_upgradable'} = [Tkx::ppm__img('package', 'filter', 'upgradable')];
$IMG{'f_installed'} = [Tkx::ppm__img('package', 'filter')];
$IMG{'f_modified'} = [Tkx::ppm__img('package', 'filter', 'modified')];

my $action_menu;
my $fields_menu;
my $view_menu;

on_load();

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
	      if ($pkglist->identify($x, $y) =~ "header") {
		  $fields_menu->g_tk___popup($X, $Y);
	      } else {
		  $pkglist->selection('clear');
		  $pkglist->selection('add', "nearest $x $y");
		  $action_menu->g_tk___popup($X, $Y);
	      }
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

my $prefs_dialog = $mw->new_widget__dialog(
    -title => 'PPM Preferences', -padding => 4,
    -parent => $mw, -place => 'over',
    -type => 'ok', -modal => 'none',
    -synchronous => 0, -separator => 0,
);
my $repolist;
my $repo_add;
my $repo_del;
build_prefs_dialog($prefs_dialog);

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
		  -variable => \$FILTER{'fields'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Abstract", -value => "abstract",
		  -variable => \$FILTER{'fields'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Name or Abstract",
		  -value => "name abstract",
		  -variable => \$FILTER{'fields'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Author", -value => "author",
		  -variable => \$FILTER{'fields'}, -command => [\&filter]);
$filter->g_bind('<Return>', [\&filter]);
$filter->g_bind('<Key>', [\&filter_onkey]);

# Filter state buttons
my $filter_all = $toolbar->new_ttk__radiobutton(
    -text => "All", -image => $IMG{'f_all'},
    -style => "Toolbutton", -variable => \$FILTER{'type'},
    -command => [\&filter], -value => "all",
);
$toolbar->add($filter_all, -pad => [0, 2]);
Tkx::tooltip($filter_all, "All packages");
my $filter_inst = $toolbar->new_ttk__radiobutton(
    -text => "Installed", -image => $IMG{'f_installed'},
    -style => "Toolbutton", -variable => \$FILTER{'type'},
    -command => [\&filter], -value => "installed",
);
$toolbar->add($filter_inst, -pad => [0, 2]);
Tkx::tooltip($filter_inst, "Installed packages");
my $filter_upgr = $toolbar->new_ttk__radiobutton(
    -text => "Upgradable", -image => $IMG{'f_upgradable'},
    -style => "Toolbutton", -variable => \$FILTER{'type'},
    -command => [\&filter], -value => "upgradable",
);
$toolbar->add($filter_upgr, -pad => [0, 2]);
Tkx::tooltip($filter_upgr, "Upgradable packages");
my $filter_mod = $toolbar->new_ttk__radiobutton(
    -text => "Modified", -image => $IMG{'f_modified'},
    -style => "Toolbutton", -variable => \$FILTER{'type'},
    -command => [\&filter], -value => "modified",
);
$toolbar->add($filter_mod, -pad => [0, 2]);
Tkx::tooltip($filter_mod, "Packages to install/remove");

# Action buttons
my $install_btn = $toolbar->new_ttk__button(-text => "Install",
					    -image => $IMG{'install'},
					    -style => "Toolbutton",
					    -state => "disabled");
$toolbar->add($install_btn, -separator => 1, -pad => [4, 2, 0]);
Tkx::tooltip($install_btn, "Mark for install");
my $remove_btn = $toolbar->new_ttk__button(-text => "Remove",
					   -image => $IMG{'remove'},
					   -style => "Toolbutton",
					   -state => "disabled");
$toolbar->add($remove_btn, -pad => [0, 2]);
Tkx::tooltip($remove_btn, "Mark for remove");
my $go_btn = $toolbar->new_ttk__button(-text => "Go",
				       -image => $IMG{'go'},
				       -style => "Toolbutton",
				       -state => "disabled",
				       -command => [\&run_actions]);
$toolbar->add($go_btn, -pad => [0, 2]);
Tkx::tooltip($go_btn, "Run marked actions");

# Sync/config buttons
my $sync_btn = $toolbar->new_ttk__button(-text => "Sync",
					 -image => $IMG{'refresh'},
					 -style => "Toolbutton",
					 -command => [\&full_refresh]);
Tkx::tooltip($sync_btn, "Synchronize database");
$toolbar->add($sync_btn, -separator => 1, -pad => [4, 2, 0]);

my $prefs_btn = $toolbar->new_ttk__button(-text => "Preferences",
					  -image => $IMG{'prefs'},
					  -style => "Toolbutton",
					  -command => sub {
					   $prefs_dialog->display();
					   Tkx::focus(-force => $prefs_dialog);
				       });
Tkx::tooltip($prefs_btn, "PPM Preferences");
$toolbar->add($prefs_btn, -pad => [0, 2]);

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
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'listed'});
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages in filtered view");
$lbl = $statusbar->new_ttk__label(-text => "listed");
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages in filtered view");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'installed'});
$statusbar->add($lbl, -separator => 1);
Tkx::tooltip($lbl, "Number of packages installed");
$lbl = $statusbar->new_ttk__label(-text => "installed,");
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages installed");
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

## Action dialog for committing to install/remove
my $action_box;
my $action_dialog = $mw->new_widget__dialog(-title => 'Commit Actions',
					    -parent => $mw, -place => 'over',
					    -type => 'ok',
					    -synchronous => 0);
build_action_dialog($action_dialog);

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

map view($_), keys %VIEW;

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
    %ACTION = ();
    $NUM{'install'} = 0;
    $NUM{'remove'} = 0;
    update_actions();
    filter(1);
    $NUM{'listed'} = $pkglist->numitems('visible');
    $pkglist->sort();
}

sub sync {
    $ppm->repo_sync;
    $repolist->clear();
    for my $repo_id ($ppm->repos) {
	my $repo = $REPOS{$repo_id} = $ppm->repo($repo_id);
	$repolist->add($repo_id,
		       repo => $repo->{name},
		       url => $repo->{packlist_uri},
		       num => $repo->{pkgs},
		       checked => $repo->{packlist_last_access},
		   );
    }

    for my $area_name ($ppm->areas) {
	$AREAS{$area_name} = $ppm->area($area_name);
    }
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
    for my $area_name (sort keys %AREAS) {
	my $area = $AREAS{$area_name};
	my @fields = ("id", "name", "version", "release_date", "abstract", "author");
	for my $pkg ($area->packages(@fields)) {
	    for (@$pkg) { $_ = "" unless defined }  # avoid "Use of uninitialized value" warnings
	    my ($id, $name, $version, $release_date, $abstract, $author) = @$pkg;
	    $pkglist->add($name, $id,
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
    my @fields = ("id", "name", "version", "release_date", "abstract", "author");
    my @res = $ppm->packages(@fields);
    my $count = @res;
    for (@res) {
	for (@$_) { $_ = "" unless defined }  # avoid "Use of uninitialized value" warnings
	my ($id, $name, $version, $release_date, $abstract, $author) = @$_;
	$pkglist->add($name, $id,
		   available => $version,
		   abstract => $abstract,
		   author => $author,
		   );
    }
    return $count;
}

sub filter {
    my $force = shift || 0;
    Tkx::after('cancel', $FILTER{'id'});
    return if (!$force && $FILTER{'filter'} eq $FILTER{'lastfilter'}
		   && $FILTER{'fields'} eq $FILTER{'lastfields'}
		       && $FILTER{'type'} eq $FILTER{'lasttype'});
    my $fields = $FILTER{'fields'};
    $fields =~ s/ / or /g;
    Tkx::tooltip($filter, "Filter packages by $fields");
    my $count = $pkglist->filter($FILTER{'filter'},
				 fields => $FILTER{'fields'},
				 type => $FILTER{'type'},
			     );
    if ($count == -1) {
	# Something wrong with the filter
	$filter->delete(0, "end");
	$filter->insert(0, $FILTER{'lastfilter'});
	# No need to refilter - should not have changed
    } else {
	$FILTER{'lastfilter'} = $FILTER{'filter'};
	$FILTER{'lastfields'} = $FILTER{'fields'};
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

sub view {
    my $view = shift;
    if ($view =~ 'bar$') {
	my $w = ($view eq 'statusbar' ? $statusbar : $toolbar);
	if ($VIEW{$view}) {
	    Tkx::grid($w);
	} else {
	    Tkx::grid('remove', $w);
	}
    } else {
	$pkglist->view($view, $VIEW{$view});
    }
}

sub menus {
    Tkx::option_add("*Menu.tearOff", 0);
    my $menu = $mw->new_menu();
    $mw->configure(-menu => $menu);

    my ($sm, $ssm);

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
    if (!$AQUA) {
	$sm->add_separator();
	$sm->add_command(-label => "Preferences",
			 -command => sub { $prefs_dialog->display(); });
    }

    # View menu
    $sm = $view_menu = $menu->new_menu(-name => "view");
    $menu->add_cascade(-label => "View", -menu => $sm);
    $sm->add_checkbutton(-label => "Toolbar",
			 -variable => \$VIEW{'toolbar'},
			 -command => [\&view, 'toolbar']);
    $sm->add_checkbutton(-label => "Status Bar",
			 -variable => \$VIEW{'statusbar'},
			 -command => [\&view, 'statusbar']);
    $sm->add_separator();
    $sm->add_radiobutton(-label => "All Packages",
			 -variable => \$FILTER{'type'},
			 -value => "all",
			 -command => [\&filter]);
    $sm->add_radiobutton(-label => "Installed Packages",
			 -variable => \$FILTER{'type'},
			 -value => "installed",
			 -command => [\&filter]);
    $sm->add_radiobutton(-label => "Upgradable Packages",
			 -variable => \$FILTER{'type'},
			 -value => "upgradable",
			 -command => [\&filter]);
    # this text linked in update_actions for entryconfigure
    $sm->add_radiobutton(-label => "Packages to Install/Remove",
			 -variable => \$FILTER{'type'},
			 -value => "modified",
			 -command => [\&filter]);
    $sm->add_separator();
    $ssm = $fields_menu = $sm->new_menu(-name => "fields");
    $sm->add_cascade(-label => "Fields", -menu => $ssm);
    $ssm->add_checkbutton(-label => "Area",
			  -variable => \$VIEW{'area'},
			  -command => [\&view, 'area']);
    $ssm->add_checkbutton(-label => "Installed",
			  -variable => \$VIEW{'installed'},
			  -command => [\&view, 'installed']);
    $ssm->add_checkbutton(-label => "Available",
			  -variable => \$VIEW{'available'},
			  -command => [\&view, 'available']);
    $ssm->add_checkbutton(-label => "Abstract",
			  -variable => \$VIEW{'abstract'},
			  -command => [\&view, 'abstract']);
    $ssm->add_checkbutton(-label => "Author",
			  -variable => \$VIEW{'author'},
			  -command => [\&view, 'author']);

    # Action menu
    $action_menu = $sm = $menu->new_menu(-name => "action");
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
			 -accelerator => "Command-,",
			 -command => sub { $prefs_dialog->display(); });
    }

    return $menu;
}

sub select_item {
    my $item = shift;
    $details->configure(-state => "normal");
    $details->delete('1.0', 'end');
    $details->configure(-state => "disabled");
    my $menu = $action_menu;
    $menu->delete(0, 'end');
    $menu->add_command(-label => "No selected package", -state => "disabled");
    return unless $item;

    # We need to figure out how we want details formatted
    my %data = Tkx::SplitList($pkglist->data($item));
    my $name = $data{'name'};
    my $areaid = $data{'area'};
    my @ids = $pkglist->pkgids($name);
    my $area = $ppm->area($areaid) if $areaid;
    my ($pkg, $repo_pkg, $area_pkg);
    $pkg = $repo_pkg = $ppm->package($name, $data{'available'} || undef);
    if ($areaid) {
	$pkg = $area_pkg = $area->package($name);
    }
    my $pad = "\t";
    $details->configure(-state => "normal");
    $details->insert('1.0', "$pkg->{name}\n", 'h1');
    $details->insert('end', "$pkg->{abstract}\n", 'abstract') if $pkg->{abstract};
    $details->insert('end', "${pad}Version:\t$pkg->{version}\n");
    if (my $date = $pkg->{release_date}) {
	$date =~ s/ .*//;  # drop time
	$details->insert('end', "${pad}Released:\t$date\n");
    }
    $details->insert('end', "${pad}Author:\t$pkg->{author}\n") if $pkg->{author};
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
	$details->insert('end', "\nFiles:\n", 'h2');
	for my $file ($area->package_files($pkg->{id})) {
	    $details->insert('end', "\t$file\n");
	}
    }
    # Remove trailing newline and prevent editing of widget
    $details->delete('end-1c');
    $details->configure(-state => "disabled");

    ## Record "allowable" actions based on package info
    # XXX work on constraints
    if (!defined($ACTION{$name})) {
	$ACTION{$name}{'install'} = 0;
	$ACTION{$name}{'remove'} = 0;
	$ACTION{$name}{'area'} = $area;
	$ACTION{$name}{'area_pkg'} = $area_pkg;
	$ACTION{$name}{'repo_pkg'} = $repo_pkg;
    }
    # The icon represents the current actionable state:
    #   default installed upgradable install remove upgrade
    $remove_btn->configure(-state => "disabled");
    $install_btn->configure(-state => "disabled");
    $menu->delete(0, 'end');
    if ($data{'installed'}) {
	my $cmd = sub {
	    my $was_btn = shift || 0;
	    if ($was_btn) {
		if ($ACTION{$name}{'remove'}) {
		    $ACTION{$name}{'remove'} = 0;
		} else {
		    $ACTION{$name}{'remove'} = $data{'installed'};
		}
	    }
	    queue_for_remove(%data);
	};
	$remove_btn->configure(-state => "normal",
			       -command => [$cmd, 1]);
	my $txt = "Remove $name $data{'installed'}";
	$menu->add_checkbutton(-label => $txt,
			       -variable => \$ACTION{$name}{'remove'},
			       -onvalue => $data{'installed'},
			       -command => $cmd);
	if ($data{'area'} && (($data{'area'} eq "perl")
				  || $AREAS{$data{'area'}}->readonly)) {
	    # perl area items should not be removed
	    $menu->entryconfigure($txt, -state => "disabled");
	    $remove_btn->configure(-state => "disabled");
	}
    }
    if ($data{'available'} && $data{'installed'}) {
	my $cmd = sub {
	    my $was_btn = shift || 0;
	    if ($was_btn) {
		# Add in reversal of previous state
		if ($ACTION{$name}{'install'}) {
		    $ACTION{$name}{'install'} = 0;
		    $ACTION{$name}{'remove'} = 0;
		} else {
		    $ACTION{$name}{'install'} = $data{'available'};
		    $ACTION{$name}{'remove'} = $data{'installed'};
		}
	    } else {
		# the checkbutton only modifies install, take care remove
		if ($ACTION{$name}{'install'}) {
		    $ACTION{$name}{'remove'} = $data{'installed'};
		} else {
		    $ACTION{$name}{'remove'} = 0;
		}
	    }
	    queue_for_remove(%data);
	    queue_for_install(%data);
	};
	my $txt = ($data{'installed'} eq $data{'available'}) ?
	    "Reinstall" : "Upgrade";
	$install_btn->configure(-state => "normal",
				-command => [$cmd, 1]);
	$menu->add_checkbutton(-label => "$txt $name to $data{'available'}",
			       -variable => \$ACTION{$name}{'install'},
			       -onvalue => $data{'available'},
			       -command => $cmd);
    } elsif ($data{'available'}) {
	my $cmd = sub {
	    my $was_btn = shift || 0;
	    if ($was_btn) {
		if ($ACTION{$name}{'install'}) {
		    $ACTION{$name}{'install'} = 0;
		} else {
		    $ACTION{$name}{'install'} = $data{'available'};
		}
	    }
	    queue_for_install(%data);
	};
	$install_btn->configure(-state => "normal",
				-command => [$cmd, 1]);
	$menu->add_checkbutton(-label => "Install $name $data{'available'}",
			       -variable => \$ACTION{$name}{'install'},
			       -onvalue => $data{'available'},
			       -command => $cmd);
    }
    if (!$data{'available'} && !$data{'installed'}) {
	# Oddball packages that have no version?
	$menu->add_command(-label => "$name", -state => "disabled");
    }
}

sub queue_for_install {
    my %data = @_;
    my $name = $data{'name'};
    my $ver = $ACTION{$name}{'install'};
    my $state;
    if ($ver) {
	$state = $pkglist->state($name, "install");
	$NUM{'install'}++;
    } else {
	$state = $pkglist->state($name, "!install");
	$NUM{'install'}--;
    }
    update_actions();
    print "$name $ver :: STATE: $state\n";
}

sub queue_for_remove {
    my %data = @_;
    my $name = $data{'name'};
    my $ver = $ACTION{$name}{'remove'};
    my $state;
    if ($ver) {
	$state = $pkglist->state($name, "remove");
	$NUM{'remove'}++;
    } else {
	$state = $pkglist->state($name, "!remove");
	$NUM{'remove'}--;
    }
    update_actions();
    print "$name $ver :: STATE: $state\n";
}

sub update_actions {
    if ($NUM{'install'} || $NUM{'remove'}) {
	$go_btn->configure(-state => "normal");
	$filter_mod->configure(-state => "normal");
	$view_menu->entryconfigure("Packages to Install/Remove",
				   -state => "normal");
    } else {
	$go_btn->configure(-state => "disabled");
	$filter_mod->configure(-state => "disabled");
	$view_menu->entryconfigure("Packages to Install/Remove",
				   -state => "disabled");
    }
}

sub run_actions {
    my $msg = "Ready to ";
    if ($NUM{'install'}) {
	$msg .= "install $NUM{'install'} package";
	$msg .= "s" if $NUM{'install'} > 1;
    }
    if ($NUM{'remove'}) {
	$msg .= " and " if $NUM{'install'};
	$msg .= "remove $NUM{'remove'} package";
	$msg .= "s" if $NUM{'remove'} > 1;
    }
    $msg .= "?";
    my $res = Tkx::tk___messageBox(
	-title => "Commit Actions?", -type => "okcancel", -parent => $mw,
	-icon => "question", -message => $msg,
    );
    if ($res eq "ok") {
	commit_actions();
    }
}

sub commit_actions {
    $action_dialog->display();
    $action_box->configure(-state => "normal");
    for my $name (sort keys %ACTION) {
	# First remove any area pacakges
	my $area = $ACTION{$name}{'area'};
	my $area_pkg = $ACTION{$name}{'area_pkg'};
	if ($ACTION{$name}{'remove'}) {
	    my $area_name = $area->name;
	    my $txt = "Remove $name from $area_name area\n";
	    $action_box->insert('end', $txt);
	    Tkx::update('idletasks');
	    print $txt;
	    eval { $area->uninstall($name); };
	    if ($@) {
		$txt = "\tERROR:\n$@\n";
		$action_box->insert('end', $txt);
		print $txt;
	    } else {
		$action_box->insert('end', "\tRemoved $name\n");
	    }
	}
    }
    for my $name (sort keys %ACTION) {
	# Then install
	my $repo_pkg = $ACTION{$name}{'repo_pkg'};
	if ($ACTION{$name}{'install'}) {
	    my $area_name = $ppm->default_install_area;
	    my $txt = "Install $name to $area_name area\n";
	    $action_box->insert('end', $txt);
	    Tkx::update('idletasks');
	    print $txt;
	    eval { $ppm->install(packages => [$repo_pkg]); };
	    if ($@) {
		$txt = "\tERROR:\n$@\n";
		$action_box->insert('end', $txt);
		print $txt;
	    } else {
		$action_box->insert('end', "\tInstalled $name\n");
	    }
	}
    }
    $action_box->configure(-state => "disabled");
    refresh();
}

sub build_action_dialog {
    my $top = shift;
    my $f = Tkx::widget->new($top->getframe());
    $f->configure(-padding => 4);

    my $l = $f->new_ttk__label(-text => "Commit actions:");
    my $sw = $f->new_widget__scrolledwindow();
    $action_box = $sw->new_text(
	-height => 8, -width => 60, -borderwidth => 1,
	-font => "ASfont", -state => "disabled",
	-wrap => "word",
    );
    $sw->setwidget($action_box);
    Tkx::grid($l, -sticky => "w");
    Tkx::grid($sw, -sticky => "news");
    Tkx::grid(columnconfigure => $f, 0, -weight => 1);
    Tkx::grid(rowconfigure => $f, 1, -weight => 1);
}

sub select_repo_item {
    my $item = shift;
    $repo_del->configure(-state => "disabled");
    return unless $item;

    # We need to figure out how we want details formatted
    my %data = Tkx::SplitList($repolist->data($item));
    $repo_del->configure(-state => "normal");
}

sub build_prefs_dialog {
    my $top = shift;

    # Preferences tabs
    my $nb = $top->new_ttk__notebook();
    Tkx::ttk__notebook__enableTraversal($nb);
    $top->setwidget($nb);

    my $f;
    # Areas tab
    $f = $nb->new_ttk__frame(-padding => 8);
    $nb->add($f, -text => "Areas", -underline => 0);
    # Select this tab as default
    $nb->select($f);

    Tkx::grid(columnconfigure => $f, 0, -weight => 1);
    Tkx::grid(rowconfigure => $f, 0, -weight => 1);

    # Repositories tab
    $f = $nb->new_ttk__frame(-padding => 8);
    $nb->add($f, -text => "Repositories", -underline => 0);

    my $sw = $f->new_widget__scrolledwindow();
    $repolist = $sw->new_repolist(-width => 450, -height => 100,
				  -selectcommand => [\&select_repo_item],
				  -borderwidth => 1, -relief => 'sunken',
				  -itembackground => ["#F7F7FF", ""]);
    $sw->setwidget($repolist);
    $repo_add = $f->new_ttk__button(-text => "Add",
				    -image => Tkx::ppm__img('add'));
    $repo_del = $f->new_ttk__button(-text => "Delete", -state => "disabled",
				    -image => Tkx::ppm__img('delete'));
    my $addl = $f->new_widget__panelframe(-text => "Add Repository:");
    my $addf = $addl->new_ttk__frame(-padding => [6, 2]);
    $addl->setwidget($addf);
    my $rnamel = $addf->new_ttk__label(-text => "Name:", -anchor => 'w');
    my $rnamee = $addf->new_ttk__entry();
    my $rlocnl = $addf->new_ttk__label(-text => "Location:", -anchor => 'w');
    my $rlocne = $addf->new_ttk__entry();
    my $ruserl = $addf->new_ttk__label(-text => "Username:", -anchor => 'w');
    my $rusere = $addf->new_ttk__entry();
    my $rpassl = $addf->new_ttk__label(-text => "Password:", -anchor => 'w');
    my $rpasse = $addf->new_ttk__entry();
    my $opttxt = "(optional, for FTP and HTTP repositories only)";
    my $opt0 = $addf->new_ttk__label(-text => $opttxt, -font => "ASfont-1");
    my $add_sub = sub {
	my $name = $rnamee->get();
	my $url = $rlocne->get();
	my $user = $rusere->get();
	my $pass = $rpasse->get();
	return unless $name && $url;
	# This requires duplication of code from do_repo
	if (-d $url) {
	    require URI::file;
	    $url = URI::file->new_abs($url);
	}
	if ($user) {
	    $user .= ":$pass" if defined $pass;
	    $url = URI->new($url);
	    $url->userinfo($user);
	    $url = $url->as_string;
	}
	eval { $ppm->repo_add(name => $name, packlist_uri => $url); };
	if ($@) {
	    Tkx::tk___messageBox(-title => "Error Adding Repository",
				 -message => "Error adding repository:\n$@",
				 -type => "ok", -icon => "error");
	} else {
	    full_refresh();
	}
    };
    my $save_btn = $addf->new_ttk__button(-text => "Add",
					  -command => $add_sub);
    Tkx::grid($rnamel, $rnamee, '-', -sticky => 'sew', -pady => 1);
    Tkx::grid($rlocnl, $rlocne, '-', -sticky => 'sew', -pady => 1);
    Tkx::grid($ruserl, $rusere, $opt0, -sticky => 'sew', -pady => 1);
    Tkx::grid($rpassl, $rpasse, $save_btn, -sticky => 'sew', -pady => 1);
    Tkx::grid(configure => $save_btn, -sticky => 'e');
    Tkx::grid(columnconfigure => $addf, 1, -weight => 1, -minsize => 20);

    Tkx::grid($sw, -sticky => 'news');
    Tkx::grid($addl, -sticky => 'news', -pady => [4, 0]);
    Tkx::grid(columnconfigure => $f, 0, -weight => 1);
    Tkx::grid(rowconfigure => $f, 0, -weight => 1);
}

sub on_load {
    # Restore state from saved information
    # We would need to make sure these are reflected in UI elements
    $FILTER{'filter'} = $ppm->config_get("gui.filter") || "";
    $FILTER{'fields'} = $ppm->config_get("gui.filter.fields")
	|| "name abstract";
    $FILTER{'type'} = $ppm->config_get("gui.filter.type") || "all";

    my @view_keys = keys %VIEW;
    my @view_vals = $ppm->config_get(map "gui.view.$_", @view_keys);
    while (@view_keys) {
	my $k = shift @view_keys;
	my $v = shift @view_vals;
	$VIEW{$k} = $v if defined $v;
    }
}

sub on_exit {
    # We should save dialog and other state information

    ## Window location and size
    $ppm->config_save("gui.geometry", $mw->g_wm_geometry);

    ## Current filter
    $ppm->config_save(
        "gui.filter" => $FILTER{'lastfilter'},
        "gui.filter.fields" => $FILTER{'lastfields'},
        "gui.filter.type" => ($FILTER{'lasttype'} eq 'modified' ? "all" : $FILTER{'lasttype'}),
    );

    ## Current selected package?

    ## Tree column order, widths, visibility, sort

    # this gets columns in current order (visible and not)
    my @cols = $pkglist->column('list');
    for my $col (@cols) {
	#my $width = $pkglist->column('width', $col);
    }

    $ppm->config_save(map { ("gui.view.$_" => $VIEW{$_}) } keys %VIEW);

    exit;
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

BEGIN {
    package ActivePerl::PPM::GUI::Status;

    require ActivePerl::PPM::Status;
    our @ISA = qw(ActivePerl::PPM::Status);

    my $prefixed;

    sub begin {
	my $self = shift;
	my $what = shift;
	$action_box->configure(-state => "normal");
	$action_box->insert('end', "$what ... ");
	$action_box->configure(-state => "disabled");
	Tkx::update('idletasks');
	if ($ENV{'ACTIVEPERL_PPM_DEBUG'}) {
	    print "$what ... ";
	}
	$prefixed = 1;
	$self->SUPER::begin($what, @_);
    }

    sub tick {
	$action_box->configure(-state => "normal");
	$action_box->insert('end', "#");
	$action_box->configure(-state => "disabled");
	if ($ENV{'ACTIVEPERL_PPM_DEBUG'}) {
	    print "#";
	}
	# XXX update some progressbar
	Tkx::update('idletasks');
    }

    sub end {
	my $self = shift;
	my $outcome = shift || "DONE";
	my $what = $self->SUPER::end;
	$action_box->configure(-state => "normal");
	if ($prefixed) {
	    $outcome .= "\n";
	    $prefixed = 0;
	} else {
	    $outcome = "$what $outcome\n";
	}
	$action_box->insert('end', $outcome);
	$action_box->configure(-state => "disabled");
	Tkx::update('idletasks');
	if ($ENV{'ACTIVEPERL_PPM_DEBUG'}) {
	    print $outcome;
	}
    }
}
