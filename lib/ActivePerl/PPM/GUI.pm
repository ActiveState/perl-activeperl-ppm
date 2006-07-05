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
Tkx::package_require('ppm::repolist');
Tkx::package_require('style::as');
Tkx::package_require('BWidget');
Tkx::Widget__theme(1);

Tkx::style__as__init();

if ($AQUA) {
    Tkx::set("::tk::mac::useThemedToplevel" => 1);
}

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
$FILTER{'type'} = "name abstract";
$FILTER{'lasttype'} = $FILTER{'type'};
$FILTER{'upgradeable'} = 0;
$FILTER{'installed'} = 0;
$FILTER{'modified'} = 0;
$FILTER{'laststates'} = ();

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
$IMG{'go'} = Tkx::ppm__img('go');
$IMG{'f_upgradeable'} = Tkx::ppm__img('upgradeable', "filter");
$IMG{'f_installed'} = Tkx::ppm__img('installed', "filter");
$IMG{'f_modified'} = Tkx::ppm__img('modified', "filter");

my $cur_pkg = undef; # Current selection package

my $action_menu;
my $fields_menu;

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

my $config_dlg = $mw->new_widget__dialog(-title => 'PPM Configuration',
					 -parent => $mw, -place => 'over',
					 -type => 'ok',  -modal => 'none',
					 -synchronous => 0);
my $repolist;
my $repo_add;
my $repo_del;
build_config($config_dlg);

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

# Filter state buttons
my $filter_inst = $toolbar->new_ttk__checkbutton(
    -text => "Installed", -image => $IMG{'f_installed'},
    -style => "Toolbutton", -variable => \$FILTER{'installed'},
    -command => [\&filter],
);
$toolbar->add($filter_inst, -pad => [0, 2]);
Tkx::tooltip($filter_inst, "Filter on installed packages");
my $filter_upgr = $toolbar->new_ttk__checkbutton(
    -text => "Upgradeable", -image => $IMG{'f_upgradeable'},
    -style => "Toolbutton", -variable => \$FILTER{'upgradeable'},
    -command => [\&filter],
);
$toolbar->add($filter_upgr, -pad => [0, 2]);
Tkx::tooltip($filter_upgr, "Filter on upgradeable packages");
my $filter_mod = $toolbar->new_ttk__checkbutton(
    -text => "Modified", -image => $IMG{'f_modified'},
    -style => "Toolbutton", -variable => \$FILTER{'modified'},
    -command => [\&filter],
);
$toolbar->add($filter_mod, -pad => [0, 2]);
Tkx::tooltip($filter_mod, "Filter on packages to install/remove");

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
my $go_btn = $toolbar->new_ttk__button(-text => "Go",
				       -image => $IMG{'go'},
				       -style => "Toolbutton",
				       -state => "disabled");
$toolbar->add($go_btn, -pad => [0, 2]);

# Sync/config buttons
my $sync = $toolbar->new_ttk__button(-text => "Sync",
				     -image => $IMG{'refresh'},
				     -style => "Toolbutton",
				     -command => [\&full_refresh]);
Tkx::tooltip($sync, "Synchronize database");
$toolbar->add($sync, -separator => 1, -pad => [4, 2, 0]);

my $config = $toolbar->new_ttk__button(-text => "Config",
				       -image => $IMG{'config'},
				       -style => "Toolbutton",
				       -command => sub {
					   $config_dlg->display();
					   Tkx::focus(-force => $config_dlg);
				       });
Tkx::tooltip($config, "PPM Configuration");
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
    filter();
    $NUM{'listed'} = $pkglist->numitems('visible');
    $pkglist->sort();
}

sub sync {
    $ppm->repo_sync;
    @repos = $ppm->repos;
    $repolist->clear();
    for my $repoid (@repos) {
	my $repo = $ppm->repo($repoid);
	$repolist->add($repoid,
		       repo => $repo->{name},
		       url => $repo->{packlist_uri},
		       num => $repo->{pkgs},
		       checked => $repo->{packlist_last_access},
		   );
    }

    @areas = $ppm->areas;
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
	my @fields = ("id", "name", "version", "release_date", "abstract", "author");
	for my $pkg ($area->packages(@fields)) {
	    for (@$pkg) { $_ = "" unless defined }  # avoid "Use of uninitialized value" warnings
	    my ($id, $name, $version, $release_date, $abstract, $author) = @$pkg;
	    $pkglist->add($name, $id,
			  area => $area_name,
			  installed => $version,
			  abstract => $abstract,
			  author => $author,
			  icon => 'installed',
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
    Tkx::after('cancel', $FILTER{'id'});
    my @states = ();
    push(@states, "installed") if $FILTER{'installed'};
    push(@states, "upgradeable") if ($FILTER{'upgradeable'} || $FILTER{'installed'});
    push(@states, "install", "remove", "upgrade") if $FILTER{'modified'};
    return if ($FILTER{'filter'} eq $FILTER{'lastfilter'}
		   && $FILTER{'type'} eq $FILTER{'lasttype'}
			   && @states eq $FILTER{'laststates'});
    my $type = $FILTER{'type'};
    $type =~ s/ / or /g;
    Tkx::tooltip($filter, "Filter packages by $type");
    my $count = $pkglist->filter($FILTER{'filter'},
				 fields => $FILTER{'type'},
				 states => [@states],
			     );
    if ($count == -1) {
	# Something wrong with the filter
	$filter->delete(0, "end");
	$filter->insert(0, $FILTER{'lastfilter'});
	# No need to refilter - should not have changed
    } else {
	$FILTER{'lastfilter'} = $FILTER{'filter'};
	$FILTER{'lasttype'} = $FILTER{'type'};
	$FILTER{'laststates'} = @states;
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
			 -command => [\&view, 'toolbar']);
    $sm->add_checkbutton(-label => "Status Bar",
			 -variable => \$VIEW{'statusbar'},
			 -command => [\&view, 'statusbar']);
    $sm->add_separator();
    my $ssm = $fields_menu = $sm->new_menu(-name => "fields");
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
	my $name = $cur_pkg->{name};
	$sm->add_command(-label => "Install $name") if $ACTION{'install'};
	$sm->add_command(-label => "Remove $name") if $ACTION{'remove'};
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
    my @ids = $pkglist->pkgids($name);
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

sub select_repo_item {
    my $item = shift;
    $repo_del->configure(-state => "disabled");
    return unless $item;

    # We need to figure out how we want details formatted
    my %data = Tkx::SplitList($repolist->data($item));
    $repo_del->configure(-state => "normal");
}

sub build_config {
    my $top = shift;
    my $f = Tkx::widget->new($top->getframe());
    $f->configure(-padding => 4);

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
    my $addl = $f->new_ttk__label(-text => "Add Repository:",
				  -font => 'ASfontBold');
    my $addf = $f->new_ttk__frame(-padding => [6, 2, 6, 0]);
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
    #my $opt1 = $addf->new_ttk__label(-text => $opttxt, -font => "ASfont-1");
    Tkx::grid($rnamel, $rnamee, '-', -sticky => 'sew', -pady => 1);
    Tkx::grid($rlocnl, $rlocne, '-', -sticky => 'sew', -pady => 1);
    Tkx::grid($ruserl, $rusere, $opt0, -sticky => 'sew', -pady => 1);
    Tkx::grid($rpassl, $rpasse, 'x', -sticky => 'sew', -pady => 1);
    Tkx::grid(columnconfigure => $addf, 1, -weight => 1, -minsize => 20);

    Tkx::grid($sw, '-', '-', -sticky => 'news');
    Tkx::grid($addl, $repo_add, $repo_del, -sticky => 'sw', -pady => [4, 0]);
    Tkx::grid($addf, '-', '-', -sticky => 'news');
    Tkx::grid(columnconfigure => $f, 0, -weight => 1);
    Tkx::grid(rowconfigure => $f, 0, -weight => 1);
}

sub on_load {
    # Restore state from saved information
    # We would need to make sure these are reflected in UI elements
    $FILTER{'filter'} = $ppm->config_get("gui.filter") || "";
    $FILTER{'type'} = $ppm->config_get("gui.filter.type") || "name abstract";
    $FILTER{'upgradeable'} = $ppm->config_get("gui.filter.upgradeable") || 0;
    $FILTER{'installed'} = $ppm->config_get("gui.filter.installed") || 0;
    $FILTER{'modified'} = $ppm->config_get("gui.filter.modified") || 0;

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
        "gui.filter.type" => $FILTER{'lasttype'},
        "gui.filter.upgradeable" => $FILTER{'upgradeable'},
        "gui.filter.installed" => $FILTER{'installed'},
        "gui.filter.modified" => $FILTER{'modified'},
    );

    ## Current selected package?
    if (defined($cur_pkg)) {
	my $name = $cur_pkg->{name};
    }

    ## Tree column order, widths, visibility, sort

    # this gets columns in current order (visible and not)
    my @cols = $pkglist->column('list');
    for my $col (@cols) {
	#my $width = $pkglist->column('width', $col);
    }

    $ppm->config_save(map { ("gui.view.$_" => $VIEW{$_}) } keys %VIEW);

    exit;
}
