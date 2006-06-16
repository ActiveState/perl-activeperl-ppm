# pkglist.tcl --
#
#	This file implements package pkglist, which  ...
#
# Copyright (c) 2006 ActiveState Software Inc
#
# See the file "license.terms" for information on usage and
# redistribution of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#

package require snit
package require widget::scrolledwindow
package require Tablelist_tile
package provide ppm::pkglist 1.0

#
# Get the current windowing system ("x11", "win32", or
# "aqua") and add some entries to the Tk option database
#
if {[tk windowingsystem] eq "x11"} {
    option add *Tablelist*selectBackground	#447bcd
    option add *Tablelist*selectForeground	white
}
option add *Tablelist.activeStyle	frame
option add *Tablelist.background	gray98
option add *Tablelist.stripeBackground	#e0e8f0
option add *Tablelist.setGrid		yes
option add *Tablelist.movableColumns	yes
option add *Tablelist.labelCommand	tablelist::sortByColumn
option add *Tablelist.labelCommand2	tablelist::addToSortColumns

snit::widgetadaptor pkglist {

    component table

    delegate option {-borderwidth -relief} to hull
    delegate option * to table
    delegate method * to table

    variable NAMES -array {}
    variable ITEMS

    # color to use on details view sorted column
    variable sortcolor "#fff7ff"
    variable sortcolumn "name"
    variable sortorder "-increasing"

    variable visible 0

    variable highlightText "blue"
    variable highlight     "yellow"

    constructor {args} {
	installhull using widget::scrolledwindow

	install table using tablelist::tablelist $win.table \
	    -borderwidth 0 \
	    -listvariable [myvar ITEMS] \
	    -columns {
		2  "Action"		center
		24 "Package Name"	left
		6  "Area"		left
		6  "Installed Version"	left
		6  "Available Version"	left
		32 "Abstract"		left
		20 "Author"		left
	    }
	#0 "Release Date"	left

	$hull setwidget $win.table

	$table columnconfigure 0 -name action -resizable 0 -showarrow 0
	$table columnconfigure 1 -name name
	$table columnconfigure 2 -name area
	$table columnconfigure 3 -name installed
	$table columnconfigure 4 -name available
	$table columnconfigure 5 -name abstract
	$table columnconfigure 6 -name author
	#$table columnconfigure 7 -name release -sortmode integer \
	    -formatcommand [mymethod formatDate]

	$self configurelist $args
    }

    method formatDate {val} {
	return [clock format $val -format "%Y-%m-%d"]
    }

    method add {name args} {
	if {[info exists NAMES($name)]} {
	    set idx $NAMES($name)
	} else {
	    set idx -1
	}
	set opts(name) $name
	array set opts {
	    action ""
	    area ""
	    installed ""
	    available ""
	    abstract ""
	    author ""
	}
	if {$idx >= 0} {
	    # previous data
	    set data [lindex $ITEMS $idx]
	    set opts(action)	[lindex $data 0]
	    set opts(area)	[lindex $data 2]
	    set opts(installed)	[lindex $data 3]
	    set opts(available)	[lindex $data 4]
	    set opts(abstract)	[lindex $data 5]
	    set opts(author)	[lindex $data 6]
	}
	# new data merged in
	array set opts $args
	# order opts into dataset
	set data [list "" $opts(name) $opts(area) \
		      $opts(installed) $opts(available) \
		      $opts(abstract) $opts(author)]
	if {$idx < 0} {
	    set NAMES($name) [llength $ITEMS]
	    lappend ITEMS $data
	    incr visible
	} else {
	    lset ITEMS $idx $data
	}
	# should we schedule a sort, or make the user force it?
	# currently the user must request it.
    }

    method clear {} {
	$table delete 0 end
	array unset NAMES
	array set NAMES {}
	set ITEMS {}
	set visible 0
    }

    method numitems {{type {}}} {
	if {$type eq "visible"} {
	    # return only # visible
	    return $visible
	}
	return [array size NAMES]
    }

    method filter {ptn {what name}} {
	set count 0
	if {[catch {string match $ptn $what} err]} {
	    tk_messageBox -icon error -title "Invalid Search Pattern" \
		-message "Invalid search pattern: $ptn\n$err" -type ok
	    return -1
	}
	if {$ptn eq ""} {
	    # make everything visible
	} elseif {[info exists NAMES($ptn)]} {
	    # exact match on one item
	    set count 1
	} elseif {$what eq "name"} {
	    foreach {name} [array names NAMES] {
		set vis [string match -nocase $ptn $name]
		#$tree item configure $NAMES($name) -visible $vis
		incr count $vis
	    }
	} else {
	    foreach {item} $ITEMS {
		#array set opts $ITEMS($item)
#		set vis [expr {[info exists opts($what)] &&
#			       [string match -nocase $ptn $opts($what)]}]
#		$tree item configure $item -visible $vis
		incr count $vis
		#unset opts
	    }
	}
	set visible $count
	return $count
    }

    method sort {} {
	#$table sort
    }

}
