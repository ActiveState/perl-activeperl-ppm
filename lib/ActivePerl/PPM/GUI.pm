package ActivePerl::PPM::GUI;

use strict;
use Tkx;

# get our cwd for Tcl files
use File::Basename;
use Cwd 'abs_path';

my $ppm = $::ppm;

# these will be filled in the sync()
my @areas;
my @repos;

my $mw = Tkx::widget->new(".");
$mw->g_wm_withdraw();
Tkx::tk(appname => "Perl Package Manager");

my $dir = abs_path(dirname($INC{'ActivePerl/PPM/GUI.pm'}));
Tkx::lappend('::auto_path', $dir . "/tcl");

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
}

Tkx::package_require('tile');
Tkx::package_require('img::png');
Tkx::package_require('ppm::themes');
Tkx::package_require('tooltip');
Tkx::package_require('widget::dialog');
Tkx::package_require('widget::statusbar');
Tkx::package_require('widget::toolbar');
#Tkx::package_require('widget::menuentry');
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
    # Wait until 8.4.14 for this
    #Tkx::interp("alias", "", "::scrollbar", "", "::ttk::scrollbar");
}

# These variables are tied to UI elements
my %FILTER;
$FILTER{'last'} = "";
$FILTER{'type'} = "name";
$FILTER{'id'} = "";
$FILTER{'delay'} = 500; # filter delay on key in millisecs

my %VIEW;
$VIEW{'name'} = 1;
$VIEW{'area'} = 1;
$VIEW{'installed'} = 1;
$VIEW{'available'} = 1;
$VIEW{'abstract'} = 1;
$VIEW{'author'} = 0;

$VIEW{'toolbar'} = 1;
$VIEW{'statusbar'} = 1;

my %IMG;
$IMG{'refresh'} = Tkx::ppm__img('refresh');
$IMG{'filter'} = Tkx::ppm__img('search');

# Create the menu structure
menus();

# Main interface
my $pw = $mw->new_ttk__paned(-orient => "vertical");
my $details = $pw->new_text(-height => 7, -width => 60, -borderwidth => 1);
my $pkglist = $pw->new_pkglist(-width => 550, -height => 350,
			       -selectcommand => [\&select_item],
			       -borderwidth => 1, -relief => 'sunken');
my $toolbar = $mw->new_widget__toolbar();

$details->tag('configure', 'title',
	      -font => 'Helvetica 16 bold');

my $statusbar = $mw->new_widget__statusbar();

$pw->add($pkglist, -weight => 3);
$pw->add($details, -weight => 1);

Tkx::grid($toolbar, -sticky => "ew");
Tkx::grid($pw, -sticky => "news", -padx => 4, -pady => 4);
Tkx::grid($statusbar, -sticky => "ew");

Tkx::grid(rowconfigure => $mw, 1, -weight => 1);
Tkx::grid(columnconfigure => $mw, 0, -weight => 1);

## Toolbar items
my $filter_menu = $toolbar->new_menu(-name => "filter_menu");
my $flbl = $toolbar->new_ttk__menubutton(-text => "Filter:",
					 -image => $IMG{'filter'},
					 -style => "Toolbutton",
					 -menu => $filter_menu);
my $filter = $toolbar->new_ttk__entry(-width => 10);
#my $filter = $toolbar->new_widget__menuentry(-width => 1,
#					     -menu => $filter_menu);
Tkx::tooltip($filter, "Filter search results");
$toolbar->add($flbl, -separator => 1);
$toolbar->add($filter, -weight => 2, -separator => 0);
$filter_menu->add('radiobutton', -label => "Name", -value => "name",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Abstract", -value => "abstract",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Name and Abstract",
		  -value => "name abstract",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter_menu->add('radiobutton', -label => "Author", -value => "author",
		  -variable => \$FILTER{'type'}, -command => [\&filter]);
$filter->g_bind('<Return>', [\&filter]);
$filter->g_bind('<Key>', [\&filter_onkey]);

my $sync = $toolbar->new_ttk__button(-text => "Sync",
				     -image => $IMG{'refresh'},
				     -style => "Toolbutton",
				     -command => [\&full_refresh]);
Tkx::tooltip($sync, "Refresh all data");
$toolbar->add($sync, -separator => 1, -pad => [4, 0]);

my $config = $toolbar->new_ttk__button(-text => "Config",
				       -style => "Toolbutton");
Tkx::tooltip($config, "Configure something");
$toolbar->add($config);

## Statusbar items
my $albl = $statusbar->new_ttk__label(-text => "Area:");
my $area_cbx = $statusbar->new_ttk__combobox(-width => 6,
					     -values => ["ALL"]);
$area_cbx->set("ALL");
$statusbar->add($albl);
$statusbar->add($area_cbx);

my %NUM;
$NUM{'total'} = 0;
$NUM{'listed'} = 0;
$NUM{'installed'} = 0;
$NUM{'install'} = 0;
$NUM{'remove'} = 0;
my $lbl;
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'total'});
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-text => "packages,");
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'installed'});
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-text => "installed.");
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'listed'});
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-text => "listed,");
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'install'});
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-text => "to install/upgrade,");
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-textvariable => \$NUM{'remove'});
$statusbar->add($lbl);
$lbl = $statusbar->new_ttk__label(-text => "to remove", -anchor => 'w');
$statusbar->add($lbl, -weight => 1);

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
    merge_area_items();
    $NUM{'installed'} = $pkglist->numitems();
    merge_repo_items();
    $NUM{'total'} = $pkglist->numitems();
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
	}
    }
}

sub merge_repo_items {

    my @fields = ("name", "version", "release_date", "abstract", "author");
    my @res = $ppm->packages(@fields);

    #require Data::Dump;
    #Data::Dump::dump(@res);

    for (@res) {
	for (@$_) { $_ = "" unless defined }  # avoid "Use of uninitialized value" warnings
	my ($name, $version, $release_date, $abstract, $author) = @$_;
	$pkglist->add($name,
		   available => $version,
		   abstract => $abstract,
		   author => $author,
		   );
    }
}

sub filter {
    my $fltr = $filter->get();
    Tkx::after('cancel', $FILTER{'id'});
    return if ($fltr eq $FILTER{'last'});
    my $count = $pkglist->filter($fltr, $FILTER{'type'});
    if ($count == -1) {
	$filter->delete(0, "end");
	$filter->insert(0, $FILTER{'last'});
	# No need to refilter - should not have changed
    } else {
	$FILTER{'last'} = $fltr;
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
		     -command => sub { exit; });
    $mw->g_bind("<Control-q>" => sub { exit; });

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

    # Help menu
    $sm = $menu->new_menu(-name => "help"); # must be named "help"
    $menu->add_cascade(-label => "Help", -menu => $sm);
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

sub select_item {
    my $item = shift;
    # We need to figure out how we want details formatted
    $details->delete('1.0', 'end');
    my %data = Tkx::SplitList($pkglist->data($item));
    my $name = delete $data{'name'};
    $details->insert('1.0', $name . "\n", 'title');
    for my $key (sort keys %data) {
	$details->insert('end', $key . ":\t");
	$details->insert('end', $data{$key} . "\n");
    }
}

sub about {
    Tkx::tk___messageBox(-title => "About Perl Package Manager",
			 -icon => "info", -type => "ok",
			 -message => "Tell me about it");
}
