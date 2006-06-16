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
Tkx::tk(appname => "Perl Package Manager");

my $dir = abs_path(dirname($INC{'ActivePerl/PPM/GUI.pm'}));
Tkx::lappend('::auto_path', $dir . "/tcl");


if ($ENV{'ACTIVEPERL_PPM_DEBUG'}) {
    Tkx::package_require('comm');
    print "DEBUG COMM PORT: " . Tkx::comm__comm('self') . "\n";

    Tkx::package_require('tkcon');
    $mw->g_bind("<F12>", 'catch {tkcon show}');
    $mw->g_bind("<F11>", 'catch {tkcon hide}');
}

Tkx::package_require('tile');
Tkx::package_require('tooltip');
Tkx::package_require('ppm::pkglist');
Tkx::package_require('style::as');
Tkx::package_require('BWidget');
Tkx::Widget__theme(1);

Tkx::style__as__init();

my $windowingsystem = Tkx::tk('windowingsystem');
my $AQUA = ($windowingsystem eq "aqua");
if ($AQUA) {
    Tkx::set("::tk::mac::useThemedToplevel" => 1);
}

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
} else {
    # Wait until 8.4.14 for this
    #Tkx::interp("alias", "", "::scrollbar", "", "::ttk::scrollbar");
}

my $last_filter = "";

menus();

my $pw = $mw->new_ttk__paned(-orient => "vertical");
my $details = $pw->new_text(-height => 7, -width => 60, -borderwidth => 1);
my $pkglist = $pw->new_pkglist(-width => 550, -height => 350,
			       -selectcommand => [\&select_item]);

my $statusbar = $mw->new_StatusBar();

$pw->add($pkglist, -weight => 3);
$pw->add($details, -weight => 1);

Tkx::grid($pw, -sticky => "news");
Tkx::grid($statusbar, -sticky => "ew");

Tkx::grid(rowconfigure => $mw, 0, -weight => 1);
Tkx::grid(columnconfigure => $mw, 0, -weight => 1);

my $albl = $statusbar->new_ttk__label(-text => "Area:");
my $area_cbx = $statusbar->new_ttk__combobox(-width => 6,
					     -values => ["ALL"]);
$area_cbx->set("ALL");
$statusbar->add($albl, -separator => 0);
$statusbar->add($area_cbx, -separator => 0);

my $flbl = $statusbar->new_ttk__label(-text => "Filter:");
my $filter = $statusbar->new_ttk__entry(-width => 10);
my $filter_cbx = $statusbar->new_ttk__combobox(-width => 8,
					       -values =>
					       ["Name", "Abstract", "Author"]);
$filter_cbx->set("Name");
$statusbar->add($flbl, -separator => 0);
$statusbar->add($filter, -weight => 2, -separator => 0);
$statusbar->add($filter_cbx, -separator => 0);

Tkx::bind($filter_cbx, "<<ComboboxSelected>>", sub {
    filter();
});

my $numitems = 0;
my $ilbl = $statusbar->new_ttk__label(-text => "Items");
my $items_lbl = $statusbar->new_ttk__label(-width => 4,
					   -textvariable => \$numitems);
$statusbar->add($items_lbl, -separator => 0, -pad => [4, 0]);
$statusbar->add($ilbl, -separator => 0);

my $sync = $statusbar->new_ttk__button(-text => "Sync",
				       -style => "Slim.Toolbutton",
				       -command => sub {
					   sync();
					   refresh();
				       });
$statusbar->add($sync, -separator => 1, -pad => [4, 0]);

my $config = $statusbar->new_ttk__button(-text => "Config",
					 -style => "Slim.Toolbutton");
$statusbar->add($config, -separator => 0);

Tkx::update();

Tkx::bind($filter, "<Return>", [\&filter]);

Tkx::after(idle => sub {
    sync();
    refresh();
});

Tkx::MainLoop();

1;

sub refresh {
    $pkglist->clear();
    $numitems = 0;
    merge_area_items();
    merge_repo_items();
    filter();
    $numitems = $pkglist->numitems('visible');
    $pkglist->sort();
}

sub sync {
    $ppm->repo_sync;
    @areas = $ppm->areas;
    @repos = $ppm->repos;
    $area_cbx->configure(-values => ["ALL", @areas]);
}

sub merge_area_items {
    for my $area_name ($ppm->areas) {
	my $area = $ppm->area($area_name);
	my @fields = ("name", "version", "release_date", "abstract", "author");
	for my $pkg ($area->packages(@fields)) {
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

sub merge_repo_items() {
    my($pattern, @fields) = @_;

    @fields = ("name", "version", "release_date", "abstract", "author") unless @fields;
    my @res = $ppm->search($pattern, @fields);

    #require Data::Dump;
    #Data::Dump::dump(@res);

    for (@res) {
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
    my $fltr_type = lc($filter_cbx->get());
    my $count = $pkglist->filter($fltr, $fltr_type);
    if ($count == -1) {
	$filter->delete(0, "end");
	$filter->insert(0, $last_filter);
	# No need to refilter - should not have changed
    } else {
	$last_filter = $fltr;
	$numitems = $count;
    }
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
    $sm->add_checkbutton(-label => "Status Bar", -state => "disabled");
    $sm->add_checkbutton(-label => "Toolbar", -state => "disabled");

    # Help menu
    $sm = $menu->new_menu(-name => "help");
    $menu->add_cascade(-label => "Help", -menu => $sm);
    $sm->add_command(-label => "About", -state => "disabled",
		     -command => sub { about(); });

    return $menu;
}

sub select_item {
    my $item = shift;
    # We need to figure out how we want details formatted
    $details->delete('1.0', 'end');
    my @data = $pkglist->data($item);
    $details->insert('1.0', @data);
}

sub about {
}
