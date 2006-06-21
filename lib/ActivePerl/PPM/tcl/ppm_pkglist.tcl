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
package require treectrl
package require widget::scrolledwindow
package provide ppm::pkglist 1.0

snit::widgetadaptor pkglist {

    component tree

    delegate option -borderwidth to hull
    delegate option -relief to hull
    delegate option -padding to hull
    delegate option * to tree
    delegate method * to tree

    option -selectcommand -default ""

    variable NAMES -array {}
    variable ITEMS -array {}

    # color to use on details view sorted column
    variable sortcolor "#fff7ff"
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

	$hull setwidget $win.tree

	$tree debug configure -enable no -display no

	$self tree-details

	$self configurelist $args
    }

    method add {name args} {
	if {[info exists NAMES($name)]} {
	    set item $NAMES($name)
	    set new 0
	} else {
	    set item [$tree item create -button 0 -open 0 -parent 0 -visible 1]
	    set NAMES($name) $item
	    $tree item style set $item \
		action styAction \
		name styName \
		area styName \
		installed styName \
		available styName \
		abstract styName \
		author styName
	    set new 1
	}
	array set opts $args
	set opts(name) $name
	set ITEMS($item) [array get opts]
	if {1} {
	    eval [linsert [array get opts] 0 $tree item text $item]
	} else {
	    set config [list]
	    # If we config more than text elements, we'll need this
	    foreach {key val} [array get opts] {
		lappend config $key elemText -text $val ,
	    }
	    # trim off last ","
	    eval [linsert [lrange $config 0 end-1] 0 \
		      $tree item element configure $item]
	}
	if {$new} {
	    set img [::ppm::img default]
	    incr visible
	} else {
	    set img [::ppm::img install]
	}
	$tree item element configure $item action elemImg -image $img
	# should we schedule a sort, or make the user force it?
	# currently the user must request it.
    }

    method name {id} {
	if {[info exists NAMES($id)]} {
	    return $id
	}
	if {[info exists ITEMS($id)]} {
	    array set opts $ITEMS($id)
	    return $ITEMS(name)
	}
	return ""
    }

    method data {id} {
	if {[info exists ITEMS($id)]} {
	    return $ITEMS($id)
	}
	if {[info exists NAMES($id)]} {
	    return $ITEMS($NAMES($id))
	}
	return ""
    }

    method state {id} {
	# This should return the selected install state
    }

    method clear {} {
	$tree item delete all
	array unset NAMES
	array unset ITEMS
	array set NAMES {}
	array set ITEMS {}
	set visible 0
    }

    method numitems {{type {}}} {
	if {$type eq "visible"} {
	    # return only # visible
	    return $visible
	}
	return [array size ITEMS]
    }

    method filter {ptn {fields name}} {
	set count 0
	if {[catch {string match $ptn $fields} err]} {
	    tk_messageBox -icon error -title "Invalid Search Pattern" \
		-message "Invalid search pattern: $ptn\n$err" -type ok
	    return -1
	}
	if {$ptn eq "" || $ptn eq "*"} {
	    # make everything visible
	    foreach {item} [array names ITEMS] {
		$tree item configure $item -visible 1
		incr count 1
	    }
	} elseif {0 && [info exists NAMES($ptn)]} {
	    # Don't do exact match for PPM::GUI
	    # exact match on one item - case sensitive
	    foreach {item} [array names ITEMS] {
		$tree item configure $item -visible 0
	    }
	    $tree item configure $NAMES($ptn) -visible 1
	    set count 1
	} else {
	    # Fields-based searches
	    if {[string first "*" $ptn] == -1} {
		# no wildcard in pattern - add to each end
		set ptn *$ptn*
	    }
	    if {$fields eq "name"} {
		foreach {name} [array names NAMES] {
		    set vis [string match -nocase $ptn $name]
		    $tree item configure $NAMES($name) -visible $vis
		    incr count $vis
		}
	    } else {
		foreach {item} [array names ITEMS] {
		    array set opts $ITEMS($item)
		    foreach field $fields {
			set vis [expr {[info exists opts($field)] &&
				       [string match -nocase $ptn $opts($field)]}]
			if {$vis} { break }
		    }
		    $tree item configure $item -visible $vis
		    incr count $vis
		    unset opts
		}
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
	$tree item sort root $sortorder -column $sortcolumn -dictionary
    }

    method _headerinvoke {t col} {
	if {[$tree column compare $col == action]} {
	    # sort on the action column?
	    return
	}
	if {[$tree column compare $col == $sortcolumn]} {
	    if {[$tree column cget $sortcolumn -arrow] eq "down"} {
		set sortorder -increasing
		set arrow up
	    } else {
		set sortorder -decreasing
		set arrow down
	    }
	} else {
	    if {[$tree column cget $sortcolumn -arrow] eq "down"} {
		set sortorder -decreasing
		set arrow down
	    } else {
		set sortorder -increasing
		set arrow up
	    }
	    $tree column configure $sortcolumn -arrow none -itembackground {}
	    set sortcolumn $col
	}
	$tree column configure $col -arrow $arrow -itembackground $sortcolor
	$self sort
    }

    method tree-details {} {
	set height [font metrics [$tree cget -font] -linespace]
	if {$height < 18} {
	    set height 18
	}
	$tree configure -itemheight $height

	$tree column create -image [::ppm::img default] -tag action \
	    -borderwidth 1 -button 0 -resize 0
	$tree column create -width 100 -text "Package Name" -tag name \
	    -arrow up -itembackground $sortcolor \
	    -borderwidth 1
	$tree column create -width  40 -text "Area" -tag area \
	    -borderwidth 1
	$tree column create -width  60 -text "Installed Version" \
	    -tag installed -borderwidth 1
	$tree column create -width  60 -text "Available Version" \
	    -tag available -borderwidth 1
	$tree column create -text "Abstract" -tag abstract \
	    -borderwidth 1 -expand 1 -squeeze 1
	$tree column create -width 120 -text "Author" -tag author \
	    -borderwidth 1 -visible 0

	set w [listbox $win.l]
	set selbg [$w cget -selectbackground]
	set selfg [$w cget -selectforeground]
	destroy $w
	# See vpage.tcl for examples
	$tree element create elemImg image
	$tree element create elemText text -lines 1 \
	    -fill [list $selfg {selected focus}]
	$tree element create selRect rect \
	    -fill [list $selbg {selected focus} gray {selected !focus}]

	# column 0: image (Action)
	set S [$tree style create styAction]
	$tree style elements $S {selRect elemImg}
	$tree style layout $S selRect -union [list elemImg] -iexpand news
	$tree style layout $S elemImg -expand news

	# column 1: text (Package)
	set S [$tree style create styName]
	$tree style elements $S {selRect elemText}
	$tree style layout $S selRect -union [list elemText] -iexpand news
	$tree style layout $S elemText -squeeze x -expand ns -padx 2

	$tree notify install <Header-invoke>
	$tree notify bind $tree <Header-invoke> [mymethod _headerinvoke %T %C]

	$tree notify bind $tree <Selection> [mymethod _select %T %c %D %S]

	$tree column dragconfigure -enable 1
	$tree notify install <ColumnDrag-begin>
	$tree notify install <ColumnDrag-end>
	$tree notify install <ColumnDrag-receive>
	$tree notify bind DontDelete <ColumnDrag-receive> {
	    %T column move %C %b
	}

	if {0} {
	    TreeCtrl::SetSensitive $tree {
		{name styName elemText}
	    }
	}
    }

    method _select {t count lost new} {
	if {$count != 1} {
	    # how would we have more than one item selected?
	    return
	}
	if {$options(-selectcommand) ne ""} {
	    uplevel 1 $options(-selectcommand) $new
	}
    }
}
