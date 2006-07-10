# pkglist.tcl --
#
#	This file implements package pkglist, which defines a megawidget
#	for use in displaying ppm packages.
#
#	This can be implemented in pure Perl with the Tkx::MegaConfig
#	module, but is implemented here in Tcl as an example of the
#	possibility of integration.
#
# Copyright (c) 2006 ActiveState Software Inc
#
# See the file "license.terms" for information on usage and
# redistribution of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#

package require snit
package require treectrl
package require widget::scrolledwindow
package require style::as
package provide ppm::pkglist 1.0

snit::widgetadaptor pkglist {

    component tree

    delegate option -borderwidth to hull
    delegate option -relief to hull
    delegate option -padding to hull
    delegate option * to tree
    delegate method * to tree

    option -selectcommand -default ""
    option -itembackground -default "" -configuremethod C-itembackground
    option -sortbackground -default "" -configuremethod C-sortbackground

    variable NAMES -array {}

    # color to use on details view sorted column
    variable sortcolumn "name"
    variable sortorder "-increasing"

    variable visible 0

    constructor {args} {
	installhull using widget::scrolledwindow

	install tree using treectrl $win.tree \
	    -highlightthickness 0 -borderwidth 0 \
	    -showheader 1 -showroot no -showbuttons no -showlines no \
	    -selectmode browse -xscrollincrement 20 -scrollmargin 16 \
	    -xscrolldelay {500 50} \
	    -yscrolldelay {500 50}

	\151\146 "\162\141\156\144() < \060.\061" {
	    [set \164\162\145\145] \143\157\156\146\151\147\165\162\145 \
		-\142\141\143\153\147\162\157\165\156\144\151\155\141\147\145 \
		[\160\160\155::\151\155\147 \147\145\143\153\157]
	}

	$hull setwidget $win.tree

	$self tree-details

	bindtags $tree [linsert [bindtags $tree] 1 $win]

	$self configurelist $args
    }

    method C-itembackground {option value} {
	$tree column configure all -itembackground $value
	# don't lose sort column
	if {[llength $options(-sortbackground)]} {
	    $tree column configure $sortcolumn \
		-itembackground $options(-sortbackground)
	}
	set options($option) $value
    }

    method C-sortbackground {option value} {
	$tree column configure $sortcolumn -itembackground \
	    [expr {[llength $value] ? $value : $options(-itembackground)}]
	set options($option) $value
    }

    method add {name id args} {
	if {[info exists NAMES($name)]} {
	    set item [lindex $NAMES($name) 0]
	    lappend NAMES($name) $id
	    set new 0
	} else {
	    set item [$tree item create -button 0 -open 0 -parent 0 -visible 1]
	    set NAMES($name) [list $item $id]
	    $tree item style set $item \
		name styName \
		area styText \
		installed styText \
		available styText \
		abstract styText \
		author styText
	    set new 1
	}
	array set opts $args
	set opts(name) $name
	eval [linsert [array get opts] 0 $tree item text $item]

	# determine appropriate state (adjusts icon)
	set state ""
	set available [$tree item text $item available]
	set installed [$tree item text $item installed]
	lappend state [expr {$installed eq "" ? "!installed" : "installed"}]
	lappend state [expr {$available eq "" ? "!available" : "available"}]
	lappend state [expr {(($installed eq "")
			      || ($available eq "")
			      || $installed eq $available) ?
			     "!upgradable" : "upgradable"}]
	$self state $name $state

	if {$new} {
	    incr visible
	}
	# should we schedule a sort, or make the user force it?
	# currently the user must request it.
	return $item
    }

    method data {id {col {}}} {
	if {$col ne ""} {
	    return [$tree item text $id $col]
	} else {
	    set out [list]
	    foreach col [$tree column list] {
		lappend out [$tree column cget $col -tag] \
		    [$tree item text $id $col]
	    }
	    return $out
	}
    }

    method pkgids {name} {
	if {[info exists NAMES($name)]} {
	    # Returns package ids associated with name
	    return [lrange $NAMES($name) 1 end]
	}
	return ""
    }

    method state {name {state {}}} {
	# This should return the current item state
	set item [lindex $NAMES($name) 0]
	if {$state ne ""} {
	    $tree item state forcolumn $item name $state
	}
	# get state into array
	set state [$tree item state forcolumn $item name]
	foreach s $state  { set S($s) {} }

	set img ""; # make sure to get base image name before modifiers
	if {[info exists S(installed)]} {
	    lappend img installed
	    if {[info exists S(upgradable)]} {
		lappend img upgradable
	    }
	} elseif {[info exists S(available)]} {
	    lappend img available
	} else {
	    lappend img package
	}
	if {[info exists S(remove)]} {
	    lappend img remove
	}
	if {[info exists S(install)]} {
	    if {[info exists S(installed)]} {
		lappend img reinstall
	    } else {
		lappend img install
	    }
	}
	$tree item image $item name [list [eval [linsert $img 0 ::ppm::img]]]

	return $state
    }

    method clear {} {
	$tree item delete all
	array unset NAMES
	array set NAMES {}
	set visible 0
    }

    method numitems {{which {}}} {
	if {$which eq "visible"} {
	    # return only # visible
	    return $visible
	}
	return [$tree item numchildren root]
    }

    method filter {words args} {
	array set opts {
	    fields {name}
	    type {all}
	}
	array set opts $args
	set count 0
	if {[catch {string match $words $opts(fields)} err]} {
	    tk_messageBox -icon error -title "Invalid Search Pattern" \
		-message "Invalid search pattern: $words\n$err" -type ok
	    return -1
	}
	if {$words eq "" || $words eq "*"} {
	    # make everything visible (based on state)
	    foreach {item} [$tree item children root] {
		set vis 1
		if {$opts(type) ne "all"} {
		    set s [$tree item state forcolumn $item name]
		    if {$opts(type) eq "installed"} {
			set vis [expr {[lsearch -exact $s "installed"] > -1}]
		    } elseif {$opts(type) eq "upgradable"} {
			set vis [expr {[lsearch -exact $s "upgradable"] > -1}]
		    } elseif {$opts(type) eq "modified"} {
			set vis [expr {[lsearch -exact $s "install"] > -1
				       || [lsearch -exact $s "remove"] > -1}]
		    }
		}
		$tree item configure $item -visible $vis
		incr count $vis
	    }
	} else {
	    # Fields-based and/or state-based searches
	    set ptns [list]
	    # Use split on words to ensure list-ification
	    foreach word [split $words] {
		if {[string first "*" $word] == -1} {
		    # no wildcard in pattern - add to each end
		    lappend ptns *$word*
		} else {
		    lappend ptns $word
		}
	    }
	    foreach {item} [$tree item children root] {
		set vis 1
		if {$opts(type) ne "all"} {
		    set s [$tree item state forcolumn $item name]
		    if {$opts(type) eq "installed"} {
			set vis [expr {[lsearch -exact $s "installed"] > -1}]
		    } elseif {$opts(type) eq "upgradable"} {
			set vis [expr {[lsearch -exact $s "upgradable"] > -1}]
		    } elseif {$opts(type) eq "modified"} {
			set vis [expr {[lsearch -exact $s "install"] > -1
				       || [lsearch -exact $s "remove"] > -1}]
		    }
		}
		if {$vis} {
		    set str {}
		    foreach field $opts(fields) {
			set data [$tree item text $item $field]
			if {$data ne ""} { lappend str $data }
		    }
		    foreach ptn $ptns {
			set vis [string match -nocase $ptn $str]
			# AND match on words, so break on first !visible
			# OR would be to break on first visible
			if {!$vis} { break }
		    }
		}
		$tree item configure $item -visible $vis
		incr count $vis
	    }
	}
	set visible $count
	return $count
    }

    method view {col {show {}}} {
	if {$show ne ""} {
	    $tree column configure $col -visible $show
	}
	return [$tree column cget $col -visible]
    }

    method sort {} {
	set opts [list -column $sortcolumn -dictionary]
	if {$sortcolumn ne "name"} {
	    # Use package name as second sort order
	    lappend opts -column "name"
	}
	eval [list $tree item sort root $sortorder] $opts
    }

    method _headerinvoke {t col} {
	set sortorder -increasing
	set arrow up
	set dir [$tree column cget $sortcolumn -arrow]
	if {[$tree column compare $col == $sortcolumn]} {
	    if {$dir ne "down"} {
		set sortorder -decreasing
		set arrow down
	    }
	} else {
	    if {$dir eq "down"} {
		set sortorder -decreasing
		set arrow down
	    }
	    $tree column configure $sortcolumn -arrow none \
		-itembackground $options(-itembackground)
	    set sortcolumn $col
	}
	$tree column configure $col -arrow $arrow
	if {[llength $options(-sortbackground)]} {
	    $tree column configure $col \
		-itembackground $options(-sortbackground)
	}
	$self sort
    }

    method tree-details {} {
	set height [font metrics [$tree cget -font] -linespace]
	if {$height < 18} {
	    set height 18
	}
	$tree configure -itemheight $height

	$tree column create -width 120 -text "Package Name" -tag name \
	    -image [::ppm::img installed]
	$tree column create -width  40 -text "Area" -tag area
	$tree column create -width  60 -text "Installed" -tag installed
	$tree column create -width  60 -text "Available" -tag available
	$tree column create -text "Abstract" -tag abstract -expand 1 -squeeze 1
	$tree column create -width 120 -text "Author" -tag author -visible 0
	# common configuration options
	$tree column configure all -borderwidth 1 \
	    -itembackground $options(-itembackground)

	set selbg $::style::as::highlightbg
	set selfg $::style::as::highlightfg

	$tree state define available
	$tree state define installed
	# upgradable == (available && installed) && (available != installed)
	$tree state define upgradable
	$tree state define install
	$tree state define remove

	# See vpage.tcl for examples
	$tree element create elemImg image
	$tree element create elemText text -lines 1 \
	    -fill [list $selfg {selected focus}]
	$tree element create selRect rect \
	    -fill [list $selbg {selected focus} gray {selected !focus}]

	# image + text style (Icon + Package)
	set S [$tree style create styName -orient horizontal]
	$tree style elements $S {selRect elemImg elemText}
	$tree style layout $S selRect -union {elemImg elemText} -iexpand news
	$tree style layout $S elemImg -expand ns -padx 2
	$tree style layout $S elemText -squeeze x -expand ns -padx 2

	# text style (other columns)
	set S [$tree style create styText]
	$tree style elements $S {selRect elemText}
	$tree style layout $S selRect -union {elemText} -iexpand news
	$tree style layout $S elemText -squeeze x -expand ns -padx 2

	$tree notify install <Header-invoke>
	$tree notify bind $tree <Header-invoke> [mymethod _headerinvoke %T %C]

	$tree notify bind $tree <Selection> [mymethod _select %S]

	$tree column dragconfigure -enable 1
	$tree notify install <ColumnDrag-begin>
	$tree notify install <ColumnDrag-end>
	$tree notify install <ColumnDrag-receive>
	$tree notify bind DontDelete <ColumnDrag-receive> {
	    %T column move %C %b
	}

	$tree column configure $sortcolumn -arrow up
	if {[llength $options(-sortbackground)]} {
	    $tree column configure $sortcolumn \
		-itembackground $options(-sortbackground)
	}
    }

    method _select {new} {
	if {$options(-selectcommand) ne ""} {
	    uplevel 1 $options(-selectcommand) $new
	}
    }
}
