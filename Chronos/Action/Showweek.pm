# $Id: Showweek.pm,v 1.7 2002/07/18 12:37:02 nomis80 Exp $
#
# Copyright (C) 2002  Linux Québec Technologies
#
# This file is part of Chronos.
#
# Chronos is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# Chronos is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Foobar; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
package Chronos::Action::Showweek;

use strict;
use Chronos::Action;
use Date::Calc qw(:all);
use HTML::Entities;

our @ISA = qw(Chronos::Action);

sub type {
    return 'read';
}

sub header {
    my $self = shift;
    my $object = $self->object;
    my $chronos = $self->{parent};
    my ($year, $month, $day) = $chronos->day;
    my $text = $chronos->gettext;

    return <<EOF;
<!-- Begin Chronos::Action::Showweek header -->
<table style="border:hidden; margin-style:none" cellspacing=0 cellpadding=0 width="100%">
    <tr>
        <td class=header align=right colspan=2>
            <a href="/Chronos?action=showmonth&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{month}</a> |
            <a href="/Chronos?action=showday&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{Day}</a>
        </td>
    </tr>
</table>
<!-- End Chronos::Action::Showweek header -->
EOF
}

sub content {
    my $self = shift;
    my $object = $self->object;
    my $chronos = $self->{parent};
    my $text = $chronos->gettext;

    my ($year, $month, $day) = $chronos->day;
    my $minimonth = $chronos->minimonth($year, $month, 0);
    my $weekview = $self->weekview($year, $month, $day);
    my $tasks = $self->Chronos::Action::Showday::taskview($year, $month, $day);

    return <<EOF;
<table width="100%" style="border:hidden">
    <tr>
        <td colspan=2>
$weekview
        </td>
    </tr>
    <tr>
        <td valign=top>
$minimonth
        </td>
        <td valign=top align=right>
$tasks
        </td>
    </tr>
</table>
EOF
}

sub weekview {
    my $self = shift;
    my $object = $self->object;
    my $chronos = $self->{parent};
    my ($year, $month, $day) = @_;
    my $text = $chronos->gettext;

    my ( $prev_year,      $prev_month,      $prev_day )      = Add_Delta_Days( $year, $month, $day, -7 );
    my ( $next_year,      $next_month,      $next_day )      = Add_Delta_Days( $year, $month, $day, 7 );
    my ( $prev_prev_year, $prev_prev_month, $prev_prev_day ) = Add_Delta_YM( $year, $month, $day, -1, 0 );
    my ( $next_next_year, $next_next_month, $next_next_day ) = Add_Delta_YM( $year, $month, $day, 1,  0 );

    my $weeknum = Week_Number($year, $month, $day);
    my $weektext = $text->{weeknum};
    $weektext =~ s/\%1/$weeknum/;
    $weektext =~ s/\%2/$year/;

    my $return = <<EOF;
<!-- Begin Chronos::Action::Showweek body -->
<table width="100%" class=minimonth>
    <tr>
        <th class=minimonth colspan=7>
            <a class=minimonthheader href="/Chronos?action=showweek&amp;object=$object&amp;year=$prev_prev_year&amp;month=$prev_prev_month&amp;day=$prev_prev_day">&lt;&lt;</a>&nbsp;
            <a class=minimonthheader href="/Chronos?action=showweek&amp;object=$object&amp;year=$prev_year&amp;month=$prev_month&amp;day=$prev_day">&lt;</a>&nbsp;
            @{[encode_entities($weektext)]}&nbsp;
            <a class=minimonthheader href="/Chronos?action=showweek&amp;object=$object&amp;year=$next_year&amp;month=$next_month&amp;day=$next_day">&gt;</a>&nbsp;
            <a class=minimonthheader href="/Chronos?action=showweek&amp;object=$object&amp;year=$next_next_year&amp;month=$next_next_month&amp;day=$next_next_day">&gt;&gt;</a>
        </th>
    </tr>
    <tr>
EOF

    foreach ( 1 .. 7 ) {
        $return .= <<EOF;
        <td width="14%">@{[encode_entities(Day_of_Week_to_Text($_))]}</td>
EOF
    }

    $return .= <<EOF;
    </tr>
    <tr>
EOF

    my $dbh = $chronos->dbh;
    my $object_quoted = $dbh->quote($self->object);
    my $sth_events = $dbh->prepare("SELECT eid, name, start, end FROM events WHERE initiator = $object_quoted AND start >= ? AND start < ? ORDER BY start");
    my $sth_participants = $dbh->prepare("SELECT events.eid, events.name, events.start, events.end FROM events, participants WHERE events.eid = participants.eid AND participants.user = $object_quoted AND events.start >= ? AND events.start < ? ORDER BY events.start");

    my $dow = Day_of_Week($year, $month, $day);
    foreach ( 1 .. 7 ) {
        my ($tyear, $tmonth, $tday) = Add_Delta_Days($year, $month, $day, -($dow - $_));
        if ($_ == 1 or $tday == 1) {
            my $month_text = ucfirst Month_to_Text($tmonth);
            $return .= <<EOF;
        <td class=daycurmonth height=80><a class=daycurmonth href="/Chronos?action=showday&amp;object=$object&amp;year=$tyear&amp;month=$tmonth&amp;day=$tday">$tday</a> $month_text
EOF
        } else {
            $return .= <<EOF;
        <td class=daycurmonth height=80><a class=daycurmonth href="/Chronos?action=showday&amp;object=$object&amp;year=$tyear&amp;month=$tmonth&amp;day=$tday">$tday</a>
EOF
        }
        $return .= $chronos->events($tyear, $tmonth, $tday, $sth_events, $sth_participants);
        $return .= "</td>";
    }

    $return .= <<EOF;
    </tr>
</table>
<!-- End Chronos::Action::Showweek body -->
EOF
    return $return;
}

sub tasks {
    my $self = shift;
    my $object = $self->object;
    my ($year, $month, $day) = @_;
    my $chronos = $self->{parent};
    my $dbh = $chronos->dbh;
    my $text = $chronos->gettext;

    my $return = <<EOF;
<!-- Begin Chronos::Action::Showweek::tasks -->
<table class=dayview cellpadding=0 cellspacing=0 width="100%">
    <tr><th class=dayview colspan=2>$text->{tasklist}</th></tr>
EOF

    my $rows = 11;
    my $cols = 2;
    my $col = 1;
    my $width = int 100 / $cols;
    
    my $sth = $dbh->prepare("SELECT tid, title FROM tasks WHERE user = ? ORDER BY priority");
    $sth->execute($self->object);
    while (my ($tid, $title) = $sth->fetchrow_array) {
        $title = encode_entities($title);
        if ($col == 1) {
            $return .= "<tr>";
            $rows--;
        }
        $return .= <<EOF;
        <td class=weektaskview width="$width\%">&nbsp;<a href="/Chronos?action=edittask&amp;tid=$tid&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$title</a></td>
EOF
        if ($col == $cols) {
            $return .= "</tr>";
            $col = 1;
        } else {
            $col++;
        }
    }
    $sth->finish;

    $return .= <<EOF x ($cols - $col + 1);
        <td class=weektaskview width="$width\%">&nbsp;</td>
EOF
    $return .= "</tr>";
    $return .= ("<tr>" . ("<td class=weektaskview width=\"$width\%\">&nbsp;</td>" x $cols) . "</tr>") x $rows;
    $return .= <<EOF;
<!-- End Chronos::Action::Showweek::tasks -->
EOF
    return $return;
}

1;

# vim: set et ts=4 sw=4 ft=perl:
