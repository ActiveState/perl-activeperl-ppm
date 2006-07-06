# repolist.tcl --
#
#	This file implements package repolist, which  ...
#
# Copyright (c) 2006 ActiveState Software Inc
#
# See the file "license.terms" for information on usage and
# redistribution of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#

package require snit
package require treectrl
package require style::as
package require widget::scrolledwindow
package provide ppm::repolist 1.0

snit::widgetadaptor repolist {

    component tree

    delegate option -borderwidth to hull
    delegate option -relief to hull
    delegate option -padding to hull
    delegate option * to tree
    delegate method * to tree

    option -selectcommand -default ""
    option -itembackground -default "" -configuremethod C-itembackground
    option -sortbackground -default "#f7f7f7" -configuremethod C-sortbackground

    # color to use on details view sorted column
    variable sortcolumn "repo"
    variable sortorder "-increasing"

    constructor {args} {
	installhull using widget::scrolledwindow

	install tree using treectrl $win.tree \
	    -highlightthickness 0 -borderwidth 0 \
	    -showheader 1 -showroot no -showbuttons no -showlines no \
	    -selectmode browse -xscrollincrement 20 -scrollmargin 16 \
	    -xscrolldelay {500 50} \
	    -yscrolldelay {500 50}

	$hull setwidget $win.tree

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

    method add {id args} {
	# There should be no duplication of repos
	set item [$tree item create -button 0 -open 0 -parent 0 -visible 1]
	$tree item style set $item \
	    id styText \
	    repo styText \
	    url styText \
	    num styText \
	    checked styDate
	array set opts $args
	set opts(id) $id
	if {[info exists opts(checked)]} {
	    $tree item element configure \
		$item checked elemDate -data $opts(checked)
	    unset opts(checked)
	}
	eval [linsert [array get opts] 0 $tree item text $item]
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

    method clear {} {
	$tree item delete all
    }

    method numitems {} {
	return [$tree item numchildren root]
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

	foreach {lbl tag opts} {
	    "Id"           id      {-visible 0}
	    "Repository"   repo    {-width 150}
	    "URL"          url     {-width 120}
	    "\# packages"  num     {-width 60}
	    "Last Checked" checked {-width 120}
	} {
	    eval [list $tree column create -text $lbl -tag $tag \
		      -borderwidth 1] $opts
	}

	set selbg $::style::as::highlightbg
	set selfg $::style::as::highlightfg

	# Create elements
	$tree element create elemText text -lines 1 \
	    -fill [list $selfg {selected focus}]
	$tree element create elemDate text -lines 1 \
	    -fill [list $selfg {selected focus}] \
	    -datatype time -format "%x %X"
	$tree element create selRect rect \
	    -fill [list $selbg {selected focus} gray {selected !focus}]

	# text style
	set S [$tree style create styText]
	$tree style elements $S {selRect elemText}
	$tree style layout $S selRect -union {elemText} -iexpand news
	$tree style layout $S elemText -squeeze x -expand ns -padx 2

	# date style
	set S [$tree style create styDate]
	$tree style elements $S {selRect elemDate}
	$tree style layout $S selRect -union {elemDate} -iexpand news
	$tree style layout $S elemDate -squeeze x -expand ns -padx 2

	$tree notify install <Header-invoke>
	$tree notify bind $tree <Header-invoke> [mymethod _headerinvoke %T %C]

	$tree notify bind $tree <Selection> [mymethod _select %T %c %D %S]

	#$tree column dragconfigure -enable 1
	$tree notify install <ColumnDrag-begin>
	$tree notify install <ColumnDrag-end>
	$tree notify install <ColumnDrag-receive>
	$tree notify bind DontDelete <ColumnDrag-receive> {
	    %T column move %C %b
	}

	$tree notify install <Drag>
	$tree notify install <Drag-begin>
	$tree notify install <Drag-end>
	$tree notify install <Drag-receive>

	TreeCtrl::SetSensitive $tree {
	    {repo styText selRect elemText}
	    {url styText selRect elemText}
	    {num styText selRect elemText}
	}

	TreeCtrl::SetDragImage $tree {
	    {repo styText selRect elemText}
	}

	$tree column configure $sortcolumn -arrow up \
	    -itembackground $options(-sortbackground)
    }

    method _select {t count lost new} {
	if {$options(-selectcommand) ne ""} {
	    uplevel 1 $options(-selectcommand) $new
	}
    }
}
