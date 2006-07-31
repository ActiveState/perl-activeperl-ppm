package ActivePerl::PPM::GUI;

BEGIN {
    # Don't allow these env vars to disrupt ppm Tkx usage unless we are
    # ourselves in debug mode.
    unless (defined $ENV{ACTIVEPERL_PPM_DEBUG}) {
        delete $ENV{$_} for qw(PERL_TCL_DLL PERL_TCL_DL_PATH);
    }
}

use strict;
use Tkx ();
use ActiveState::Browser ();
use ActivePerl::PPM::Util qw(is_cpan_package clean_err);

# get our cwd for Tcl files
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $ppm = $::ppm;
$ActiveState::Browser::HTML_DIR = $ppm->area("perl")->html;

# these will be filled in the sync()
my %AREAS;
my %REPOS;
my $INSTALL_AREA = $ppm->default_install_area;

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
	Tkx::bind(all => "<Command-F12>", 'catch {tkcon show}');
	Tkx::bind(all => "<Command-F11>", 'catch {tkcon hide}');
    } else {
	Tkx::bind(all => "<F12>", 'catch {tkcon show}');
	Tkx::bind(all => "<F11>", 'catch {tkcon hide}');
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
Tkx::package_require('ppm::arealist');
Tkx::package_require('style::as');
Tkx::package_require('BWidget');
Tkx::Widget__theme(1);

Tkx::style__as__init();

if ($AQUA) {
    Tkx::set("::tk::mac::useThemedToplevel" => 1);
}

if ($windowingsystem eq "win32") {
    # Due to a bug in Tk when wrapped as tkkit, we need to call the
    # iconbitmap setting on the main window an extra time.
    my $icon = Tkx::wm_iconbitmap($mw);
    Tkx::wm_iconbitmap($mw, $icon);
    Tkx::wm_iconbitmap($mw, -default => $^X);
}
elsif ($windowingsystem eq "x11") {
    Tkx::wm_iconphoto($mw, "-default", Tkx::ppm__img('perl'));
}

# This code makes themed frames use the notebook's background color.
# We restrict the use of this to those frames in notebooks.
Tkx::style(layout => "NotebookPane",
	   ["NotebookPane.background", -sticky => "news", -expand => 1]);
Tkx::option_add("*TNotebook.TFrame.style", "NotebookPane");

# get 'tooltip' as toplevel command
Tkx::namespace_import("::tooltip::tooltip");

#Tkx::style_default('Slim.Toolbutton', -padding => 2);

# make tree widgets use theming on non-x11 platforms
if ($windowingsystem ne "x11") {
    Tkx::option_add("*TreeCtrl.useTheme", 1);
}

# purely for reciprocity debugging, expose the ppm command in Tcl
Tkx::interp(alias => "", "ppm", "", [\&ppm]);

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
$FILTER{'type'} = "installed"; # all installed upgradable modified
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
$IMG{'go'} = [Tkx::ppm__img('go')];
$IMG{'f_all'} = [Tkx::ppm__img('available', 'filter')];
$IMG{'f_upgradable'} = [Tkx::ppm__img('package', 'filter', 'upgradable')];
$IMG{'f_installed'} = [Tkx::ppm__img('package', 'filter')];
$IMG{'f_modified'} = [Tkx::ppm__img('package', 'filter', 'modified')];

my $action_menu;
my $fields_menu;
my $view_menu;
my $file_menu;

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
my $pkglist = $pw->new_pkglist(-width => 550, -height => 350,
			       -selectcommand => [\&select_item],
			       -borderwidth => 1, -relief => 'sunken',
			       -itembackground => ["#F7F7FF", ""],
			       -takefocus => 1);

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

# Details / Status areas
my @smallfont = ();
if ($AQUA) {
    @smallfont = (-font => "ASfont-1");
}
my @text_opts = (-height => 7, -width => 40, -borderwidth => 0,
		 -font => "ASfont", -state => "disabled",
		 -wrap => "word", -highlightthickness => 0);
my $pw_nb = $pw->new_ttk__notebook(-padding => 0);

my $status_sw = $pw_nb->new_widget__scrolledwindow();
my $status_box = $status_sw->new_text(@text_opts);
$status_sw->setwidget($status_box);

my $details_sw = $pw_nb->new_widget__scrolledwindow();
my $details = $details_sw->new_text(@text_opts,
				    -tabs => ["10", "left", "90", "left"]);
$details_sw->setwidget($details);

for my $tw ($details, $status_box) {
    # Allow each text widget the same tag set
    $tw->tag('configure', 'h1', -font => 'ASfontBold2');
    $tw->tag('configure', 'h2', -font => 'ASfontBold1');
    $tw->tag('configure', 'abstract', -font => 'ASfontBold',
	     -lmargin1 => 10, -lmargin2 => 10, -rmargin => 10);
    $tw->tag_configure('link', -underline => 1, -foreground => 'blue');
    $tw->tag_bind('link', "<Enter>", sub {
		      $tw->configure(-cursor => "hand2");
		  });
    $tw->tag_bind('link', "<Leave>", sub {
		      $tw->configure(-cursor => "");
		  });
}

$pw_nb->add($status_sw, -text => "Status");
$pw_nb->add($details_sw, -text => "Details");
$pw_nb->select($status_sw);

$pw->add($pkglist, -weight => 3);
$pw->add($pw_nb, -weight => 1);

my $scroll_cmd = sub {
    my $dir = shift;
    my $tw = ($pw_nb->select() eq $status_sw ? $status_box : $details);
    $tw->yview("scroll", $dir, "page");
};
Tkx::bind($mw, "<Key-space>", [$scroll_cmd, 1]);
Tkx::bind($mw, "<Shift-Key-space>", [$scroll_cmd, -1]);

my $toolbar = $mw->new_widget__toolbar();

my $statusbar = $mw->new_widget__statusbar(-ipad => [1, 2]);

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
my $arealist;
build_prefs_dialog($prefs_dialog);

## Toolbar items

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

# Filter entry with filter.fields menu
my $filter_menu = $toolbar->new_menu(-name => "filter_menu");
my $filter = $toolbar->new_widget__menuentry(
    -width => 1, -takefocus => 1,
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

# Action buttons
my $install_btn = $toolbar->new_ttk__button(-text => "Install",
					    -image => $IMG{'install'},
					    -style => "Toolbutton",
					    -state => "disabled");
$toolbar->add($install_btn, -separator => 1, -pad => [4, 2, 0]);
Tkx::tooltip($install_btn, "Mark for install [+]");
my $remove_btn = $toolbar->new_ttk__button(-text => "Remove",
					   -image => $IMG{'remove'},
					   -style => "Toolbutton",
					   -state => "disabled");
$toolbar->add($remove_btn, -pad => [0, 2]);
Tkx::tooltip($remove_btn, "Mark for remove [-]");
my $go_btn = $toolbar->new_ttk__button(-text => "Go",
				       -image => $IMG{'go'},
				       -style => "Toolbutton",
				       -state => "disabled",
				       -command => [\&run_actions]);
$toolbar->add($go_btn, -pad => [4, 2, 0]);
Tkx::tooltip($go_btn, "Run marked actions");

# Add [+] and [-] key bindings for install/remove to pkglist
Tkx::bind($pkglist, "<Key-plus>", sub { $install_btn->invoke(); });
Tkx::bind($pkglist, "<Key-minus>", sub { $remove_btn->invoke(); });

# Sync/config buttons
my $sync_btn = $toolbar->new_ttk__button(-text => "Refresh",
					 -image => $IMG{'refresh'},
					 -style => "Toolbutton",
					 -command => [\&full_refresh]);
Tkx::tooltip($sync_btn, "Refresh all data");
$toolbar->add($sync_btn, -separator => 1, -pad => [4, 2]);

my $prefs_btn = $toolbar->new_ttk__button(-text => "Preferences",
					  -image => $IMG{'prefs'},
					  -style => "Toolbutton",
					  -command => sub {
					   $prefs_dialog->display();
					   Tkx::focus(-force => $prefs_dialog);
				       });
Tkx::tooltip($prefs_btn, "PPM Preferences");
$toolbar->add($prefs_btn);

if ($AQUA) {
    # Aqua isn't properly displaying the button disabled, so get the
    # effect through a greyed image
    for my $w ($filter_all, $filter_inst, $filter_upgr, $filter_mod,
	       $install_btn, $remove_btn, $go_btn, $sync_btn, $prefs_btn) {
	my $img = $w->cget("-image");
	if ($img) {
	    my $disimg = Tkx::ppm__img(
		Tkx::SplitList(Tkx::ppm__imgname($img)), "gray");
	    $w->configure(-image => [$img, disabled => $disimg]);
	}
    }
}

## Statusbar items
my %NUM;
$NUM{'total'} = 0;
$NUM{'listed'} = 0;
$NUM{'installed'} = 0;
$NUM{'install'} = 0;
$NUM{'remove'} = 0;
my $lbl;
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'total'}, @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Total number of known packages");
$lbl = $statusbar->new_ttk__label(-text => "packages,", @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Total number of known packages");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'listed'}, @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages in filtered view");
$lbl = $statusbar->new_ttk__label(-text => "listed", @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages in filtered view");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'installed'},
				  @smallfont);
$statusbar->add($lbl, -separator => 1);
Tkx::tooltip($lbl, "Number of packages installed");
$lbl = $statusbar->new_ttk__label(-text => "installed,", @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages installed");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'install'},
				  @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages selected for install");
$lbl = $statusbar->new_ttk__label(-text => "to install/upgrade,", @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages selected for install");
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'remove'}, @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages selected for removal");
$lbl = $statusbar->new_ttk__label(-text => "to remove", -anchor => 'w',
				  @smallfont);
$statusbar->add($lbl);
Tkx::tooltip($lbl, "Number of packages selected for removal");

$lbl = $statusbar->new_ttk__label(-text => "Install Area:", -anchor => 'e',
				  @smallfont);
$statusbar->add($lbl, -separator => 1, -weight => 1);
$lbl = $statusbar->new_ttk__label(-textvariable => \$INSTALL_AREA,
				  -font => "ASfontBold-1");
$statusbar->add($lbl);

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

sub repo_sync {
    %REPOS = ();
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
	$repolist->enable($repo_id, $repo->{enabled});
    }
}

sub area_sync {
    %AREAS = ();
    $arealist->clear();
    for my $area_name ($ppm->areas) {
	my $area = $AREAS{$area_name} = $ppm->area($area_name);
	$arealist->add($area->name,
		       num => scalar $area->packages,
		       prefix => $area->prefix,
		       inc => $area->inc,
		   );
	$arealist->state($area->name, "readonly") if $area->readonly;
    }
    if (!defined($AREAS{$INSTALL_AREA})) {
	$INSTALL_AREA = $ppm->default_install_area || "";
    }
    if ($INSTALL_AREA) {
	$arealist->state($INSTALL_AREA, "default");
    }
}

sub full_refresh {
    status_message("Synchronizing Database ... ", tag => "h2");
    Tkx::update();
    repo_sync();
    area_sync();
    refresh();
    status_message("DONE\n", tag => "h2");
}

sub merge_area_items {
    my $count = 0;
    for my $area_name (sort keys %AREAS) {
	my $area = $AREAS{$area_name};
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

sub verify {
    my $package = shift;
    my @areas = grep $_->initialized, map $ppm->area($_), $ppm->areas;
    if ($package) {
	@areas = grep $_->package_id($package), @areas;
	unless (@areas) {
	    # can't happen
	    status_message("Package '$package' is not installed\n");
	    return;
	}
	status_message("Verifying $package ...\n", tag => "h2");
    }
    else {
	status_message("Verifying all packages ...\n", tag => "h2");
    }
    my %status;
    for my $area (@areas) {
	my %s = $area->verify(
	    package => $package,
            badfile_cb => sub {
               my $what = shift;
               if ($what eq "wrong_mode") {
                   status_message(sprintf "%s: wrong mode %03o expected %03o\n", @_);
               }
               else {
		   status_message("$_[0]: $what\n");
               }
            },
        );
	while (my($k,$v) = each %s) {
	    $status{$k} += $v;
	}
    }
    for my $v (qw(verified missing modified)) {
	next if $v ne "verified" && !$status{$v};
	my $s = $status{$v} == 1 ? "" : "s";
	status_message("$status{$v} file$s $v\n");
    }
}

sub menus {
    Tkx::option_add("*Menu.tearOff", 0);
    my $menu = $mw->new_menu();
    $mw->configure(-menu => $menu);

    my ($sm, $ssm);

    # File menu
    $sm = $file_menu = $menu->new_menu(-name => "file");
    $menu->add_cascade(-label => "File", -menu => $sm);
    $sm->add_command(-label => "Refresh All Data",
		     -command => sub { $sync_btn->invoke(); });
    $sm->add_command(-label => "Verify Packages",
		     -command => [\&verify]);
    $sm->add_command(-label => "Run Marked Actions", -state => "disabled",
		     -command => sub { $go_btn->invoke(); });
    $mw->g_bind("<<RunActions>>" => sub { $go_btn->invoke(); });
    if ($AQUA) {
	$sm->entryconfigure("Run Marked Actions",
			    -accelerator => "Command-Enter");
	Tkx::event("add", "<<RunActions>>", "<Command-Key-Return>",
		   "<Command-Key-KP_Enter>");
	Tkx::bind(all => "<Command-q>" => [\&on_exit]);
    } else {
	$sm->entryconfigure("Run Marked Actions",
			    -accelerator => "Ctrl+Enter");
	Tkx::event("add", "<<RunActions>>", "<Control-Key-Return>",
		   "<Control-Key-KP_Enter>");
	$sm->add_separator();
	$sm->add_command(-label => "Exit", -command => [\&on_exit]);
	$sm->entryconfigure("Exit", -accelerator => "Ctrl+q");
	Tkx::bind(all => "<Control-q>" => [\&on_exit]);
    }

    # Edit menu
    $sm = $menu->new_menu(-name => "edit");
    $menu->add_cascade(-label => "Edit", -menu => $sm);
    $sm->add_command(-label => "Cut",
		     -command => sub {
			 Tkx::event_generate(Tkx::focus(), "<<Cut>>");
		     });
    $sm->add_command(-label => "Copy",
		     -command => sub {
			 Tkx::event_generate(Tkx::focus(), "<<Copy>>");
		     });
    $sm->add_command(-label => "Paste",
		     -command => sub {
			 Tkx::event_generate(Tkx::focus(), "<<Paste>>");
		     });
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
    $sm->add_command(-label => "No Selected Package", -state => "disabled");

    # Help menu - name it help for special behavior, but not on OS X, where
    # that causes us to not get cascades allowed.
    my $mname = ($AQUA ? "nothelp" : "help");
    $sm = $menu->new_menu(-name => $mname);
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

    if (!$AQUA) {
	$sm->add_separator;
	$sm->add_command(-label => "About", -command => sub { about(); });
    }

    # Special menu on OS X
    if ($AQUA) {
	$sm = $menu->new_menu(-name => 'apple'); # must be named "apple"
	$menu->add_cascade(-label => "PPM", -menu => $sm);
	$sm->add_command(-label => "About PPM",
			 -command => sub { about(); });
	$sm->add_separator();
	# OS X enables the Preferences item when you create this proc
	Tkx::proc("tk::mac::ShowPreferences", "args",
		  sub { $prefs_dialog->display(); });
	Tkx::bind(all => "<Command-comma>", "tk::mac::ShowPreferences");
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
    my $area = $ppm->area($areaid) if $areaid;
    my ($pkg, $repo_pkg);
    $pkg = $repo_pkg = $ppm->package($name, $data{'available'} || undef);
    if ($areaid) {
	$pkg = $area->package($name);
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
    if (my $name = is_cpan_package($pkg->{name})) {
	my $cpan_url = "http://search.cpan.org/dist/$name-$pkg->{version}/";
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
    $pw_nb->select($details_sw);

    ## Record "allowable" actions based on package info
    # XXX work on constraints
    if (!defined($ACTION{$item})) {
	$ACTION{$item}{'install'} = 0;
	$ACTION{$item}{'remove'} = 0;
	$ACTION{$item}{'area'} = $area;
	$ACTION{$item}{'repo_pkg'} = $repo_pkg;
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
		if ($ACTION{$item}{'remove'}) {
		    $ACTION{$item}{'remove'} = 0;
		} else {
		    $ACTION{$item}{'remove'} = 1;
		}
	    }
	    queue_for_remove($item, $name);
	};
	$remove_btn->configure(-state => "normal",
			       -command => [$cmd, 1]);
	my $txt = "Remove $name $data{'installed'}";
	$menu->add_checkbutton(-label => $txt,
			       -variable => \$ACTION{$item}{'remove'},
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
		if ($ACTION{$item}{'install'}) {
		    $ACTION{$item}{'install'} = 0;
		    $ACTION{$item}{'remove'} = 0;
		} else {
		    $ACTION{$item}{'install'} = 1;
		    $ACTION{$item}{'remove'} = 1;
		}
	    } else {
		# the checkbutton only modifies install, take care remove
		if ($ACTION{$item}{'install'}) {
		    $ACTION{$item}{'remove'} = 1;
		} else {
		    $ACTION{$item}{'remove'} = 0;
		}
	    }
	    queue_for_remove($item, $name);
	    queue_for_install($item, $name);
	};
	my $txt = ($data{'installed'} eq $data{'available'}) ?
	    "Reinstall" : "Upgrade";
	$install_btn->configure(-state => "normal",
				-command => [$cmd, 1]);
	$txt = "$txt $name to $data{'available'}";
	$menu->add_checkbutton(-label => $txt,
			       -variable => \$ACTION{$item}{'install'},
			       -command => $cmd);
	if (!$INSTALL_AREA || $AREAS{$INSTALL_AREA}->readonly) {
	    $menu->entryconfigure($txt, -state => "disabled");
	    $install_btn->configure(-state => "disabled");
	}
    } elsif ($data{'available'}) {
	my $cmd = sub {
	    my $was_btn = shift || 0;
	    if ($was_btn) {
		if ($ACTION{$item}{'install'}) {
		    $ACTION{$item}{'install'} = 0;
		} else {
		    $ACTION{$item}{'install'} = 1;
		}
	    }
	    queue_for_install($item, $name);
	};
	$install_btn->configure(-state => "normal",
				-command => [$cmd, 1]);
	my $txt = "Install $name $data{'available'}";
	$menu->add_checkbutton(-label => $txt,
			       -variable => \$ACTION{$item}{'install'},
			       -command => $cmd);
	if (!$INSTALL_AREA || $AREAS{$INSTALL_AREA}->readonly) {
	    $menu->entryconfigure($txt, -state => "disabled");
	    $install_btn->configure(-state => "disabled");
	}
    }
    if (!$data{'available'} && !$data{'installed'}) {
	# Oddball packages that have no version?
	$menu->add_command(-label => "$name", -state => "disabled");
    }
    if ($data{'installed'}) {
	# Add "Verify" action
	$menu->add_separator();
	$menu->add_command(-label => "Verify $name $data{'installed'}",
			   -command => [\&verify, $name]);
    }
}

sub queue_for_install {
    my ($item, $name) = @_;
    if ($ACTION{$item}{'install'}) {
	$pkglist->state($item, "install");
	$NUM{'install'}++;
	status_message("$name marked for install\n");
    } else {
	$pkglist->state($item, "!install");
	$NUM{'install'}--;
	status_message("$name unmarked for install\n");
    }
    update_actions();
}

sub queue_for_remove {
    my ($item, $name) = @_;
    if ($ACTION{$item}{'remove'}) {
	$pkglist->state($item, "remove");
	$NUM{'remove'}++;
	status_message("$name marked for remove\n");
    } else {
	$pkglist->state($item, "!remove");
	$NUM{'remove'}--;
	status_message("$name unmarked for remove\n");
    }
    update_actions();
}

sub update_actions {
    if ($NUM{'install'} || $NUM{'remove'}) {
	$go_btn->configure(-state => "normal");
	$file_menu->entryconfigure("Run Marked Actions", -state => "normal");
	$filter_mod->configure(-state => "normal");
	$view_menu->entryconfigure("Packages to Install/Remove",
				   -state => "normal");
    } else {
	$go_btn->configure(-state => "disabled");
	$file_menu->entryconfigure("Run Marked Actions", -state => "disabled");
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
    for my $item (sort keys %ACTION) {
	# First remove any area pacakges
	if ($ACTION{$item}{'remove'}) {
	    my $name = $pkglist->data($item, "name");
	    my $area = $ACTION{$item}{'area'};
	    my $area_name = $area->name;
	    my $txt = "Remove $name from $area_name area ... ";
	    status_message($txt);
	    eval { $area->uninstall($name); };
	    if ($@) {
		status_message("\nERROR:\n" . clean_err($@) . "\n", tag => "abstract");
	    } else {
		status_message("DONE\n");
	    }
	}
    }
    for my $item (sort keys %ACTION) {
	# Then install
	if ($ACTION{$item}{'install'}) {
	    my $name = $pkglist->data($item, "name");
	    my $repo_pkg = $ACTION{$item}{'repo_pkg'};
	    my $area_name = $INSTALL_AREA;
	    my $txt = "Install $name to $area_name area\n";
	    status_message($txt);
	    eval { $ppm->install(
		packages => [$repo_pkg],
		area => $INSTALL_AREA,
	    ); };
	    if ($@) {
		status_message("ERROR:\n" . clean_err($@) . "\n", tag => "abstract");
	    } else {
		status_message("\tInstalled $name\n");
	    }
	}
    }
    refresh();
}

sub select_repo_item {
    my $item = shift;
    return unless $item;
    my $what = shift || "";
    my %data = Tkx::SplitList($repolist->data($item));
    # We need to figure out how we want details formatted
    if ($what eq "remove") {
	my $res = Tkx::tk___messageBox(
	    -title => "Remove Repository?",
	    -icon => "warning",
	    -type => "yesno",
	    -message => "Really remove repository?",
	    -parent => $prefs_dialog,
	);
	return unless $res eq "yes";
	$ppm->repo_delete($data{id});
	full_refresh();
	return;
    }
    if ($what eq "enable") {
	my $state = $repolist->enable($data{id});
	$state = $ppm->repo_enable($data{id}, $state);
	# feed back result, in case we aren't allowed to change state
	$repolist->enable($data{id}, $state);
	full_refresh();
	return;
    }
    if ($what eq "setname") {
	my $newname = shift;
	$ppm->repo_set_name($data{id}, $newname);
	return;
    }
};

sub select_area_item {
    my $item = shift;
    return unless $item;
    my $what = shift || "";
    my %data = Tkx::SplitList($arealist->data($item));
    if ($what eq "default") {
	if ($AREAS{$data{name}}->readonly) {
	    Tkx::bell();
	    return;
	}
	eval { $arealist->state($INSTALL_AREA, "!default"); };
	$INSTALL_AREA = $data{name};
	$arealist->state($INSTALL_AREA, "default");
    }
}

sub build_prefs_dialog {
    my $top = shift;

    # Preferences tabs
    my $nb = $top->new_ttk__notebook();
    Tkx::ttk__notebook__enableTraversal($nb);
    $top->setwidget($nb);

    my ($f, $sw);
    # Areas tab
    $f = $nb->new_ttk__frame(-padding => 8);
    $nb->add($f, -text => "Areas", -underline => 0);
    # Select this tab as default
    $nb->select($f);

    $sw = $f->new_widget__scrolledwindow();
    $arealist = $sw->new_arealist(-width => 450, -height => 100,
				  -selectcommand => [\&select_area_item],
				  -borderwidth => 1, -relief => 'sunken',
				  -itembackground => ["#F7F7FF", ""]);
    $sw->setwidget($arealist);
    my $areal = $f->new_widget__panelframe(-text => "Add Area:");
    my $areaf = $areal->new_ttk__frame(-padding => [6, 2]);
    $areal->setwidget($areaf);

    Tkx::grid(columnconfigure => $areaf, 0, -weight => 1);

    Tkx::grid($sw, -sticky => 'news');
    #Tkx::grid($areal, -sticky => 'news', -pady => [4, 0]);
    Tkx::grid(columnconfigure => $f, 0, -weight => 1);
    Tkx::grid(rowconfigure => $f, 0, -weight => 1);

    # Repositories tab
    $f = $nb->new_ttk__frame(-padding => 8);
    $nb->add($f, -text => "Repositories", -underline => 0);

    $sw = $f->new_widget__scrolledwindow();
    $repolist = $sw->new_repolist(-width => 450, -height => 100,
				  -selectcommand => [\&select_repo_item],
				  -borderwidth => 1, -relief => 'sunken',
				  -itembackground => ["#F7F7FF", ""]);
    $sw->setwidget($repolist);
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
				 -message => "Error adding repository:\n" . clean_err($@),
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
    #$FILTER{'filter'} = $ppm->config_get("gui.filter") || "";
    #$FILTER{'fields'} = $ppm->config_get("gui.filter.fields")
    #|| "name abstract";
    #$FILTER{'type'} = $ppm->config_get("gui.filter.type") || "installed";
    $INSTALL_AREA = $ppm->config_get("gui.install_area")
	|| $ppm->default_install_area;

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

    ## Current install area
    $ppm->config_save("gui.install_area", $INSTALL_AREA || "");

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
			 -message => "PPM version $ActivePerl::PPM::VERSION
ActivePerl version $perl_version
\xA9 2006 ActiveState Software Inc.");
}

sub status_message {
    my $msg = shift;
    my %opts = @_;
    my $tag = delete $opts{tag} || "";
    my $ins = delete $opts{insert} || "end";
    my $clr = delete $opts{clear} || 0;

    if (defined($pw_nb) && defined($status_box)) {
	$pw_nb->select($status_sw);
	$status_box->configure(-state => "normal");
	$status_box->delete("1.0", "end") if $clr;
	$status_box->insert($ins, $msg, $tag);
	$status_box->configure(-state => "disabled");
	$status_box->see($ins);
	Tkx::update('idletasks');
    }
    if ($ENV{'ACTIVEPERL_PPM_DEBUG'}) {
	print $msg;
    }
}

BEGIN {
    package ActivePerl::PPM::GUI::Status;

    require ActivePerl::PPM::Status;
    our @ISA = qw(ActivePerl::PPM::Status);

    my $prefixed;

    sub begin {
	my $self = shift;
	my $what = shift;
	ActivePerl::PPM::GUI::status_message("$what ... ");
	$prefixed = 1;
	$self->SUPER::begin($what, @_);
    }

    sub tick {
	# XXX update some progressbar
	Tkx::update('idletasks');
	if ($ENV{'ACTIVEPERL_PPM_DEBUG'}) {
	    print "#";
	}
    }

    sub end {
	my $self = shift;
	my $outcome = shift || "DONE";
	my $what = $self->SUPER::end;
	if ($prefixed) {
	    $outcome .= "\n";
	    $prefixed = 0;
	} else {
	    $outcome = "$what $outcome\n";
	}
	ActivePerl::PPM::GUI::status_message($outcome);
    }
}
