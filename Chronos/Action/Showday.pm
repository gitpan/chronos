# $Id: Showday.pm,v 1.17 2002/07/16 20:04:42 nomis80 Exp $
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
package Chronos::Action::Showday;

use strict;
use Chronos::Action;
use Date::Calc qw(:all);
use Chronos::Static qw(from_datetime Compare_YMD);
use HTML::Entities;

our @ISA = qw(Chronos::Action);

sub type {
    return 'read';
}

sub header {
    my $self = shift;
    my $object = $self->object;
    my ( $year, $month, $day ) = $self->{parent}->day;
    my $text = $self->{parent}->gettext;
    return <<EOF;
<table style="border:hidden; margin-style:none" cellspacing=0 cellpadding=0 width="100%">
    <tr>
        <td class=header>@{[Date_to_Text_Long(Today())]}</td>
        <td class=header align=right>
            <a href="/Chronos?action=showmonth&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{month}</a> |
            <a href="/Chronos?action=showweek&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{week}</a>
        </td>
    </tr>
</table>
EOF
}

sub content {
    my $self    = shift;
    my $chronos = $self->{parent};
    my $text = $chronos->gettext;

    my ( $year, $month, $day ) = $chronos->day;
    my $minimonth = $self->{parent}->minimonth( $year, $month, $day );
    my $dayview = $self->dayview( $year, $month, $day );
    my $taskview = $self->taskview($year, $month, $day);

    return <<EOF;
<table width="100%" style="border:hidden">
    <tr>
        <td valign=top>
$minimonth
            <br>
$taskview
        </td>
        <td width="100%">
$dayview
        </td>
    </tr>
</table>
EOF
}

sub taskview {
    my $self = shift;
    my $object = $self->object;
    my ($year, $month, $day) = @_;
    my $chronos = $self->{parent};
    my $dbh = $chronos->dbh;
    my $text = $chronos->gettext;
    
    my $return = <<EOF;
<!-- Begin Chronos::Action::Showday::tasksview -->
<table class=taskview width="100%">
    <tr><th class=minimonth>$text->{tasklist}</th></tr>
    <tr><td><ul>
EOF

    my $sth = $dbh->prepare("SELECT tid, title, priority FROM tasks WHERE user = ? ORDER BY priority, title");
    $sth->execute($self->object);
    while (my ($tid, $title, $priority) = $sth->fetchrow_array) {
        $title = encode_entities($title);
        $return .= qq(<li>($priority) <a href="/Chronos?action=edittask&amp;tid=$tid&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$title</a></li>);
    }
    $sth->finish;
    $return .= qq(</ul></td></tr>\n) . <<EOF;
    <tr>
        <td class=minimonthfooter><a href="/Chronos?action=edittask&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{newtask}</a></td>
    </tr>
</table>
<!-- End Chronos::Action::Showday::taskview -->
EOF
    return $return;
}

sub dayview {
    my $self    = shift;
    my $object = $self->object;
    my $chronos = $self->{parent};
    my ( $year, $month, $day ) = @_;

    my $dbh  = $chronos->dbh;
    my $text = $chronos->gettext;

    my $return = <<EOF;
<!-- Begin Chronos::Action::Showday::dayview -->
<table class=dayview cellpadding=0 cellspacing=0 width="100%" style="border-top:none; border-left:none">
    <tr>
EOF

    my $user_quoted            = $dbh->quote( $self->object );
    my $sth_simul_events       = $dbh->prepare( "SELECT COUNT(*) FROM events WHERE initiator = $user_quoted AND ((start < ? AND end > ?) OR (start = ? and end = start))" );
    my $sth_simul_participants =
      $dbh->prepare(
          "SELECT COUNT(*) FROM events, participants WHERE events.eid = participants.eid AND participants.user = $user_quoted AND ((events.start < ? AND events.end > ?) OR (events.start = ? AND events.end = events.start))");
    my $max_simul_events;
    foreach my $hour ( 0 .. 23 ) {
        my $datetime_min = sprintf '%04d-%02d-%02d %02d-00-00', $year, $month, $day, $hour;
        my ( $year_max, $month_max, $day_max, $hour_max ) = Add_Delta_DHMS( $year, $month, $day, $hour, 0, 0, 0, 1, 0, 0 );
        my $datetime_max = sprintf '%04d-%02d-%02d %02d-00-00', $year_max, $month_max, $day_max, $hour_max;
        $sth_simul_events->execute( $datetime_max,       $datetime_min, $datetime_min );
        $sth_simul_participants->execute( $datetime_max, $datetime_min, $datetime_min );
        my $simul_events = $sth_simul_events->fetchrow_array + $sth_simul_participants->fetchrow_array;
        $sth_simul_events->finish;
        $sth_simul_participants->finish;
        $max_simul_events = $simul_events if $simul_events > $max_simul_events;
    }

    my $daystring = Date_to_Text_Long($year, $month, $day);
    $return .= <<EOF;
        <th style="border-top:hidden; border-left:hidden;"></th>
        <th class=dayview colspan=@{[($max_simul_events || 1) + 0]}>$daystring@{[$year == 1983 && $month == 2 && $day == 3 ? " (Simon Perreault's birth day!)" : '']}</th>
    </tr>
EOF

    if ( $max_simul_events == 0 ) {
        foreach my $hour ( 0 .. 23 ) {
            $return .= <<EOF;
    <tr>
        <td class=dayviewhour><a href="/Chronos?action=editevent&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day&amp;hour=$hour">$hour:00</a></td>
        <td class=dayview>&nbsp;</td>
    </tr>
EOF
        }
    } else {
        my $sth_events_first_hour = $dbh->prepare("SELECT eid, name, start, end, description, reminder FROM events WHERE initiator = $user_quoted AND events.start <= ? AND end >= ?");
        my $sth_participants_first_hour = $dbh->prepare("SELECT events.eid, events.name, events.start, events.end, events.description, participants.reminder, participants.status FROM events, participants WHERE events.eid = participants.eid AND participants.user = $user_quoted AND events.start <= ? AND events.end >= ?");
        
        my $sth_events =
          $dbh->prepare( "SELECT eid, name, start, end, description, reminder FROM events WHERE initiator = $user_quoted AND start >= ? AND start < ?");
        my $sth_participants =
          $dbh->prepare(
"SELECT events.eid, events.name, events.start, events.end, events.description, participants.reminder, participants.status FROM events, participants WHERE events.eid = participants.eid AND participants.user = $user_quoted AND events.start >= ? AND events.start < ?"
          );

        foreach my $hour ( 0 .. 23 ) {
            my ($sth1, $sth2);
            if ($hour == 0) {
                $sth1 = $sth_events_first_hour;
                $sth2 = $sth_participants_first_hour;
            } else {
                $sth1 = $sth_events;
                $sth2 = $sth_participants;
            }
            $return .= <<EOF;
    <tr>
        <td class=dayviewhour><a href="/Chronos?action=editevent&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day&amp;hour=$hour">$hour:00</a></td>
EOF
            my $datetime_min = sprintf '%04d-%02d-%02d %02d-00-00', $year, $month, $day, $hour;
            my ( $year_max, $month_max, $day_max, $hour_max ) = Add_Delta_DHMS( $year, $month, $day, $hour, 0, 0, 0, 1, 0, 0 );
            my $datetime_max = sprintf '%04d-%02d-%02d %02d-00-00', $year_max, $month_max, $day_max, $hour_max;

            foreach my $sth ($sth1, $sth2) {
                if ($hour == 0) {
                    $sth->execute( $datetime_min, $datetime_min );
                } else {
                    $sth->execute( $datetime_min, $datetime_max );
                }
                while ( my ( $eid, $name, $start, $end, $description, $reminder, $status ) = $sth->fetchrow_array ) {
                    my ($syear, $smonth, $sday, $shour, $smin, $ssec) = from_datetime($start);
                    my ($eyear, $emonth, $eday, $ehour, $emin, $esec) = from_datetime($end);

                    my ($start_row, $end_row) = ($shour, $ehour - ($emin > 0 ? 0 : 1));
                    if (Compare_YMD($syear, $smonth, $sday, $year, $month, $day) == -1) {
                        $start_row = 0;
                    }
                    if (Compare_YMD($eyear, $emonth, $eday, $year, $month, $day) == 1) {
                        $end_row = 23;
                    }
                    my $rowspan  = $end_row - $start_row + 1;
                
                    my $range;
                    if ( Compare_YMD($syear, $smonth, $sday, $eyear, $emonth, $eday) == 0 ) {
                        $range = sprintf '%d:%02d - %d:%02d', $shour, $smin, $ehour, $emin;
                    } else {
                        $range = sprintf '%s %d:%02d - %s %d:%02d', Date_to_Text_Long( $syear, $smonth, $sday ), $shour, $smin, Date_to_Text_Long( $eyear, $emonth, $eday ), $ehour, $emin;
                    }

                    my $status_text;
                    my $textkey = "status_$status";
                    if ($status) {
                        $status_text = "<br><b>$text->{$textkey}</b>";
                    }
                    $description = encode_entities($description);
                    $description =~ s/\n/<br>/g;

                    my $bell;
                    if (defined $reminder) {
                        $bell = "<img src=\"/chronos/bell.png\"> ";
                    }
                    
                    $return .= <<EOF;
        <td class=event rowspan=$rowspan>$bell$range <a class=event href="/Chronos?action=editevent&amp;eid=$eid&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$name</a>$status_text<br>$description</td>
EOF
                }
                $sth->finish;
            }

            $sth_simul_events->execute( $datetime_max,       $datetime_min, $datetime_min );
            $sth_simul_participants->execute( $datetime_max, $datetime_min, $datetime_min );
            my $colspan = $max_simul_events - $sth_simul_events->fetchrow_array - $sth_simul_participants->fetchrow_array;
            $sth_simul_events->finish;
            $sth_simul_participants->finish;
            if ($colspan) {
                $return .= <<EOF x $colspan;
        <td class=dayview>&nbsp;</td>
EOF
            }

            $return .= <<EOF;
    </tr>
EOF
        }
    }

    $return .= <<EOF;
</table>
<!-- End Chronos::Action::Showday::dayview -->
EOF

    return $return;
}

1;

# vim: set et ts=4 sw=4 ft=perl:
