package ActivePerl::PPM::Shell;

use strict;
use Tkx;

my $mw = Tkx::widget->new(".");
$mw->g_wm_withdraw;

Tkx::tk___messageBox(
    -icon => "error",
    -message => "The PPM4 graphical interface has not been implemented yet",
    -title => "Perl Package Manager",
);

1;
