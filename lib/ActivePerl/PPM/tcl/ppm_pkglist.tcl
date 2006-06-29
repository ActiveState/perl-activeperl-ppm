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
    option -itembackground -default "" -configuremethod C-itembackground
    option -sortbackground -default "#f7f7f7" -configuremethod C-sortbackground

    variable NAMES -array {}
    variable ITEMS -array {}

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

	$tree debug configure -enable no -display no

	$self tree-details

	bindtags $tree [linsert [bindtags $tree] 1 $win]

	$self configurelist $args
    }

    method C-itembackground {option value} {
	foreach col [$tree column list] {
	    $tree column configure $col -itembackground $value
	}
	# don't lose sort column
	$tree column configure $sortcolumn \
	    -itembackground $options(-sortbackground)
	set options($option) $value
    }

    method C-sortbackground {option value} {
	$tree column configure $sortcolumn -itembackground $value
	set options($option) $value
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
	eval [linsert [array get opts] 0 $tree item text $item]
	set img ""
	if {[info exists opts(action)]} {
	    set img [::ppm::img $opts(action)]
	} else {
	    if {$new} {
		set img [::ppm::img default]
	    } else {
		set img [::ppm::img upgradeable]
	    }
	}
	if {$img ne ""} {
	    $tree item element configure $item action elemImg -image $img
	}
	if {$new} {
	    incr visible
	}
	# should we schedule a sort, or make the user force it?
	# currently the user must request it.
	return $item
    }

    method name {id} {
	if {[info exists NAMES($id)]} {
	    return $id
	}
	if {[info exists ITEMS($id)]} {
	    array set opts $ITEMS($id)
	    return $opts(name)
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

    method filter {words {fields name} {area ALL}} {
	set count 0
	if {[catch {string match $words $fields} err]} {
	    tk_messageBox -icon error -title "Invalid Search Pattern" \
		-message "Invalid search pattern: $words\n$err" -type ok
	    return -1
	}
	if {$area eq "ALL" && ($words eq "" || $words eq "*")} {
	    # make everything visible
	    foreach {item} [array names ITEMS] {
		$tree item configure $item -visible 1
		incr count 1
	    }
	} else {
	    # Fields-based and/or area searches
	    set ptns [list]
	    foreach word $words {
		if {[string first "*" $word] == -1} {
		    # no wildcard in pattern - add to each end
		    lappend ptns *$word*
		} else {
		    lappend ptns $word
		}
	    }
	    foreach {item} [array names ITEMS] {
		array set opts $ITEMS($item)
		set vis [expr {$area eq "ALL" ||
			       ([info exists opts(area)] &&
				$opts(area) eq $area)}]
		if {$vis} {
		    set str {}
		    foreach field $fields {
			if {[info exists opts($field)]} {
			    lappend str $opts($field)
			}
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
		unset opts
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
	    $tree column configure $sortcolumn -arrow none \
		-itembackground $options(-itembackground)
	    set sortcolumn $col
	}
	$tree column configure $col -arrow $arrow \
	    -itembackground $options(-sortbackground)
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
	    -borderwidth 1
	$tree column create -width  40 -text "Area" -tag area \
	    -borderwidth 1
	$tree column create -width  60 -text "Installed" \
	    -tag installed -borderwidth 1
	$tree column create -width  60 -text "Available" \
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

	$tree column configure $sortcolumn -arrow up \
	    -itembackground $options(-sortbackground)

	if {0} {
	    TreeCtrl::SetSensitive $tree {
		{name styName elemText}
	    }
	}
    }

    method _select {t count lost new} {
	if {$options(-selectcommand) ne ""} {
	    uplevel 1 $options(-selectcommand) $new
	}
    }
}
