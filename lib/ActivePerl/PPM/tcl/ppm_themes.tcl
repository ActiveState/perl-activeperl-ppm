# ppm_themes.tcl --
#
#	This file implements package ...
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
    variable IMGDIR [file dirname [file dirname [info script]]]/images

    variable IMG ; # array of creates images
    array set IMG {}
    variable MAP ; # array mapping of semantic name -> image file
    array set MAP {
	default		{package.png}
	installed	{package_installed.png}
	install		{package_add.png}
	remove		{package_delete.png}
	disabled	{package_disabled.png}
	linked		{package_link.png}
	upgrade		{package_upgrade.png}
	upgradeable	{package_upgradeable.png}
	modified	{package_go.png}
	go		{package_go.png}
	refresh		{refresh.png}
	search		{zoom.png}
	config		{cog.png}
	gecko		{gecko.png}
	add		{add.png}
	delete		{delete.png}
	accept		{accept.png}
	filter_modifier	{zoom_corner.png}
    }
}
namespace eval ::ppm::img {
    # namespace for image commands
}

proc ::ppm::img {what {type {}}} {
    variable MAP
    variable IMG
    if {[info exists MAP($what)]} {
	set file $MAP($what)
    } else {
	set file $what
    }
    set key $what/$type
    if {![info exists IMG($key)]} {
	variable IMGDIR
	if {![file isdirectory $IMGDIR] || ![file exists $IMGDIR/$file]} {
	    return -code error \
		"unable to find image '$IMGDIR/$file' for '$what'"
	}
	set IMG($key) [image create photo ::ppm::img::$key -file $IMGDIR/$file]
	if {$type eq ""} {
	} elseif {$type eq "filter"} {
	    set mod [img "filter_modifier"]
	    $IMG($key) copy $mod; # add in modifier to top-left corner
	} else {
	    return -code error "unknown filter \"$type\""
	}
    }
    return $IMG($key)
}

proc ::ppm::img_name {img} {
    # get regular name from image
    regexp {^::ppm::img::([^/]+)/(.*)$} $img -> name type]
    return $name
}
