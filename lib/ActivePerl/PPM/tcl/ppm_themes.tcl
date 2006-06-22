# pkglist.tcl --
#
#	This file implements package pkglist, which  ...
#
# Copyright (c) 2006 ActiveState Software Inc
#
# See the file "license.terms" for information on usage and
# redistribution of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#

package require img::png
package require tile
package provide ppm::themes 1.0

namespace eval ::ppm {
    variable IMGDIR [file dirname [file dirname [info script]]]/images/

    variable IMG
    array set IMG {
	default		{"" package.png}
	install		{"" package_add.png}
	remove		{"" package_delete.png}
	disabled	{"" plugin_disabled.png}
	linked		{"" package_link.png}
	refresh		{"" refresh.png}
	search		{"" zoom.png}
	config		{"" cog.png}
    }
}
namespace eval ::ppm::img {
    # namespace for image commands
}

proc ::ppm::img {what} {
    variable IMG
    if {[info exists IMG($what)]} {
	if {[lindex $IMG($what) 0] eq ""} { ::ppm::load_image $what }
	return [lindex $IMG($what) 0]
    }
    return -code error "unknown image '$what'"
}

proc ::ppm::load_image {what} {
    variable IMGDIR
    variable IMG
    if {![file isdirectory $IMGDIR]} {
	return -code error "unable to find images in '$IMGDIR'"
    }
    lset IMG($what) 0 [image create photo ::ppm::img::$what \
			   -file $IMGDIR/[lindex $IMG($what) 1]]
    return [lindex $IMG($what) 0]
}

proc ::ppm::setupThemes {} {
    foreach theme [style theme names] {
	set pad [style theme settings $theme { style default TEntry -padding }]

	switch -- [llength $pad] {
	    0 { set pad [list 4 0 0 0] }
	    1 { set pad [list [expr {$pad+4}] $pad $pad $pad] }
	    2 {
		foreach {padx pady} $pad break
		set pad [list [expr {$padx+4}] $pady $padx $pady]
	    }
	    4 { lset pad 0 [expr {[lindex $pad 0]+4}] }
	}

	style theme settings $theme {
	    style layout SearchEntry {
		Entry.field -children {
		    SearchEntry.icon -side left
		    Entry.padding -children {
			Entry.textarea
		    }
		}
	    }

	    style configure SearchEntry -padding $pad
	    style element create SearchEntry.icon image [ppm::img search] \
		-padding {8 0 0 0} -sticky {}

	    style map SearchEntry -image [list disabled [ppm::img search]]
	}
    }
}
::ppm::setupThemes
