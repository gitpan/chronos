# $Id: Chronos.pm,v 1.47 2002/08/13 12:53:28 nomis80 Exp $
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
package Chronos;

use strict;
use Apache::DBI;
use Apache::Constants qw(:response);
use Chronos::Static qw(to_date from_date from_time Compare_YMD);
use Date::Calc qw(:all);
use Chronos::Action::Showday;
use Chronos::Action::EditEvent;
use Chronos::Action::SaveEvent;
use Apache::Request;
use Chronos::Action::Showmonth;
use Chronos::Action::Showweek;
use Chronos::Action::EditTask;
use Chronos::Action::SaveTask;
use Chronos::Action::UserPrefs;
use Chronos::Action::SaveUserPrefs;
use Chronos::Action::GetFile;
use Chronos::Action::DelFile;
use HTML::Entities;
use POSIX qw(strftime);

our $VERSION = "1.1.4.2";
sub VERSION { $VERSION }

sub handler {
    my $r       = shift;
    my $chronos = Chronos->new($r);

    # Bon, ça fait deux heures que je gosse sur une requête POST qui marchait
    # pas et je viens de découvrir quelque chose de vraiment mongol. Voici une
    # petite quote de "man Apache":
    #
    #     $r->content
    #         The $r->content method will return the entity body read from the
    #         client, but only if the request content type is "applica-
    #         tion/x-www-form-urlencoded".  When called in a scalar context,
    #         the entire string is returned.  When called in a list context, a
    #         list of parsed key => value pairs are returned.  *NOTE*: you can
    #         only ask for this once, as the entire body is read from the
    #         client.
    #
    # La petite note à la fin fait toute la différence. Si je donne des
    # paramètres en POST, ils vont être "oubliés" rendu ici parce que
    # Chronos::Authz doit savoir quel type d'action on essait de faire pour
    # pouvoir autoriser ou non. C'est pour ça qu'on doit checker pour
    # l'autorisation ici et non dans un module à part.

    if ( $chronos->action->authorized ) {
        return $chronos->go;
    } else {
        my $user   = $chronos->user;
        my $action = $chronos->{r}->param('action');
        my $object = $chronos->{r}->param('object');
        $r->note_basic_auth_failure;
        $r->log_reason(
            "user $user: not authorized (action: $action, object: $object)");
        return AUTH_REQUIRED;
    }
}

sub new {
    my $self  = shift;
    my $class = ref($self) || $self;
    my $r     = Apache::Request->new(shift);
    return bless { r => $r }, $class;
}

sub go {
    my $self = shift;

    my $lang = $self->lang;
    Language( Decode_Language($lang) );
    $ENV{LC_TIME} = $lang;

    if ( $self->action->redirect ) {
        $self->action->content;
        return REDIRECT;
    } elsif ( $self->action->freeform ) {
        return $self->action->execute;
    } else {
        $self->header;
        $self->body;
        $self->footer;
        $self->sendpage;
        return OK;
    }
}

sub lang {
    my $self        = shift;
    my $dbh         = $self->dbh;
    my $user_quoted = $dbh->quote( $self->user );
    my $lang        =
      $dbh->selectrow_array("SELECT lang FROM user WHERE user = $user_quoted")
      || 'fr';
    return $lang;
}

sub header {
    my $self = shift;

    my $object = $self->action->object;
    my $user   = $self->user;
    my $text   = $self->gettext;
    my $dbh    = $self->dbh;
    my $uri    = $self->{r}->uri;

    my ( $year, $month, $day ) = $self->day;

    # If the use is viewing today's showday, refresh every hour. When the user
    # leaves for the night, he'll come back in the morning with a showday
    # automagically showing tomorrow! (or today, whatever)
    my @today = Today();
    if (    $self->{r}->param('action') eq 'showday'
        and $today[0] == $year
        and $today[1] == $month
        and $today[2] == $day )
    {
        $self->{r}->header_out( 'Refresh',
            "3600;url=$uri?action=showday&object=$object" );
    }

    $self->{page} .= <<EOF;
<html>
<head>
    <title>Chronos $VERSION: $object</title>
    <link rel="stylesheet" href="@{[$self->stylesheet]}" type="text/css">
    <script type="text/javascript">
@{[$self->javascript]}
    </script>
</head>

<body>
<table width="100%">
    <tr><td>
        <table width="100%" cellspacing=0>
            <tr>
                <td class=top>Chronos $VERSION - <a class=header href="$uri?action=userprefs">$user</a></td>
                <td class=top align=right><select name="object" style="background-color:black; color:white" onChange="switchobject(this.value)">
EOF

    my $user_quoted = $dbh->quote( $self->user );
    my $from_user   =
      $dbh->selectall_arrayref(
"SELECT user, name, email FROM user WHERE user = $user_quoted OR public_readable = 'Y' OR public_writable = 'Y' ORDER BY name, user"
      );
    my $from_acl =
      $dbh->selectall_arrayref(
"SELECT user.user, user.name, user.email FROM user, acl WHERE acl.object = user.user AND acl.user = $user_quoted AND (acl.can_read = 'Y' OR acl.can_write = 'Y')"
      );
    my %users = map { $_->[0] => [ $_->[1], $_->[2] ] } @$from_user, @$from_acl;
    foreach (
        sort { $users{$a}[0] cmp $users{$b}[0] || $a cmp $b }
        keys %users
      )
    {
        my $string =
          ( $users{$_}[0] || $_ )
          . ( $users{$_}[1] ? " &lt;" . $users{$_}[1] . "&gt;" : '' );
        my $selected = $self->action->object eq $_ ? 'selected' : '';
        $self->{page} .= <<EOF;
        <option value="$_" $selected>$string</option>
EOF
    }

    $self->{page} .= <<EOF;
                </select></td>
            </tr>
        </table>
    </td><tr><td>
<!-- Begin @{[ref $self->action]} header -->
@{[$self->action->header]}
<!-- End @{[ref $self->action]} header -->
    </td></tr>
    <tr>
        <td>
EOF
}

sub body {
    my $self = shift;
    $self->{page} .= <<EOF;
<!-- Begin @{[ref $self->action]} body -->
@{[$self->action->content]}
<!-- End @{[ref $self->action]} body -->
EOF
}

sub footer {
    my $self = shift;
    $self->{page} .= <<EOF;
        </td>
    </tr>
</table>
</body>
EOF
}

sub user {
    my $self = shift;
    return $self->{r}->connection->user;
}

sub stylesheet {
    my $self = shift;
    return $self->conf->{STYLESHEET} || "/chronos_static/chronos.css";
}

sub javascript {
    my $self = shift;
    my ( $year, $month, $day ) = $self->day;
    my $uri    = $self->{r}->uri;
    my $action = $self->{r}->param('action');
    return <<EOF
function switchobject(object) {
    window.location = ("$uri?object=" + object + "@{[$action ? "&action=$action" : '']}&year=$year&month=$month&day=$day");
}
EOF
}

sub sendpage {
    my $self = shift;
    $self->{r}->content_type('text/html');
    $self->{r}->send_http_header;
    $self->{r}->print( $self->{page} );
}

sub conf {
    my $self = shift;
    if ( not $self->{conf} ) {
        my $file = $self->{r}->dir_config("ChronosConfig");
        $self->{conf} = Chronos::Static::conf($file);
    }
    return $self->{conf};
}

sub dbh {
    my $self    = shift;
    my $conf    = $self->conf();
    my $db_type = $conf->{DB_TYPE} || 'mysql';
    my $db_name = $conf->{DB_NAME} || 'chronos';
    my $db_host = $conf->{DB_HOST};
    my $db_port = $conf->{DB_PORT};
    my $db_user = $conf->{DB_USER} || 'chronos';
    my $db_pass = $conf->{DB_PASS};
    if ( not $db_pass ) {
        $self->{r}
          ->log_error("I need a DB_PASS directive in the configuration file");
        return;
    }

    my $dsn =
      "dbi:$db_type:$db_name"
      . ( $db_host ? ":$db_host" : '' )
      . ( $db_port ? ":$db_port" : '' );
    my $dbh =
      DBI->connect( $dsn, $db_user, $db_pass,
        { RaiseError => 1, PrintError => 0 } );
    return $dbh;
}

sub gettext {
    my $self = shift;
    if ( not $self->{text} ) {
        $self->{text} = Chronos::Static::gettext( $self->lang );
    }
    return $self->{text};
}

sub action {
    my $self = shift;

    my $action;
    if ( my $name = $self->{r}->param('action') ) {
        $action = $name;
    } elsif ( my $path_info = $self->{r}->path_info ) {
        ($action) = $path_info =~ /^\/([^\/]+)/;
    } else {
        $action = 'showday';
    }

    if ( $action eq 'showday' ) {
        return Chronos::Action::Showday->new($self);
    } elsif ( $action eq 'saveevent' ) {
        return Chronos::Action::SaveEvent->new($self);
    } elsif ( $action eq 'editevent' ) {
        return Chronos::Action::EditEvent->new($self);
    } elsif ( $action eq 'showmonth' ) {
        return Chronos::Action::Showmonth->new($self);
    } elsif ( $action eq 'showweek' ) {
        return Chronos::Action::Showweek->new($self);
    } elsif ( $action eq 'edittask' ) {
        return Chronos::Action::EditTask->new($self);
    } elsif ( $action eq 'savetask' ) {
        return Chronos::Action::SaveTask->new($self);
    } elsif ( $action eq 'userprefs' ) {
        return Chronos::Action::UserPrefs->new($self);
    } elsif ( $action eq 'saveuserprefs' ) {
        return Chronos::Action::SaveUserPrefs->new($self);
    } elsif ( $action eq 'getfile' ) {
        return Chronos::Action::GetFile->new($self);
    } elsif ( $action eq 'delfile' ) {
        return Chronos::Action::DelFile->new($self);
    } else {
        return Chronos::Action::Showday->new($self);
    }
}

sub day {
    my $self  = shift;
    my $year  = $self->{r}->param('year');
    my $month = $self->{r}->param('month');
    my $day   = $self->{r}->param('day');
    my @today = Today();
    $year  ||= $today[0];
    $month ||= $today[1];
    $day   ||= $today[2];
    return ( $year, $month, $day );
}

sub dayhour {
    my $self = shift;
    my ( $year, $month, $day ) = $self->day;
    my $hour = $self->{r}->param('hour');
    $hour = ( Now() )[0] if not defined $hour;
    return ( $year, $month, $day, $hour );
}

sub event {
    my $self = shift;
    my $eid  = shift;
    $self->{events} ||= {};
    if ( not $self->{events}{$eid} ) {
        $self->{events}{$eid} =
          $self->dbh->selectrow_hashref(
            "SELECT * FROM events WHERE eventid = $eid");
    }
    return $self->{events}{$eid};
}

sub minimonth {
    my $self   = shift;
    my $object = $self->action->object;
    my $uri    = $self->{r}->uri;
    my ( $year, $month, $day ) = @_;
    my $nocur = !$day;
    $day ||= 1;

    my ( $prev_year, $prev_month, $prev_day ) =
      Add_Delta_YM( $year, $month, $day, 0, -1 );
    my ( $next_year, $next_month, $next_day ) =
      Add_Delta_YM( $year, $month, $day, 0, 1 );
    my ( $prev_prev_year, $prev_prev_month, $prev_prev_day ) =
      Add_Delta_YM( $year, $month, $day, -1, 0 );
    my ( $next_next_year, $next_next_month, $next_next_day ) =
      Add_Delta_YM( $year, $month, $day, 1, 0 );

    my $return = <<EOF;
<!-- Begin Chronos::minimonth -->
<table class=minimonth>
    <tr>
        <!-- This is all in one big line so that it doesn't get separated. -->
        <th class=minimonth colspan=7><a class=minimonthheader href="$uri?action=showday&amp;object=$object&amp;year=$prev_prev_year&amp;month=$prev_prev_month&amp;day=$prev_prev_day">&lt;&lt;</a>&nbsp;<a class=minimonthheader href="$uri?action=showday&amp;object=$object&amp;year=$prev_year&amp;month=$prev_month&amp;day=$prev_day">&lt;</a>&nbsp;<a class=minimonthheader href="$uri?action=showmonth&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">@{[ucfirst Month_to_Text($month)]}</a>&nbsp;$year&nbsp;<a class=minimonthheader href="$uri?action=showday&amp;object=$object&amp;year=$next_year&amp;month=$next_month&amp;day=$next_day">&gt;</a>&nbsp;<a class=minimonthheader href="$uri?action=showday&amp;object=$object&amp;year=$next_next_year&amp;month=$next_next_month&amp;day=$next_next_day">&gt;&gt;</a></th>
    </tr>
    <tr>
EOF

    # Dans Date::Calc, toutes les fonctions utilisent 1 pour lundi et 7 pour
    # dimanche. C'est pourquoi le minimonth commence à partir de lundi et non
    # dimanche comme on pourrait s'y attendre. Voici ce que l'auteur de
    # Date::Calc dit pour justifier ce choix:
    #
    #     Note that in the Hebrew calendar (on which the Christian calendar
    #     is based), the week starts with Sunday and ends with the Sabbath
    #     or Saturday (where according to the Genesis (as described in the
    #     Bible) the Lord rested from creating the world).
    # 
    #     In medieval times, catholic popes have decreed the Sunday to be
    #     the official day of rest, in order to dissociate the Christian
    #     from the Hebrew belief.
    # 
    #     Nowadays, the Sunday AND the Saturday are commonly considered (and
    #     used as) days of rest, usually referred to as the "week-end".
    # 
    #     Consistent with this practice, current norms and standards (such
    #     as ISO/R 2015-1971, DIN 1355 and ISO 8601) define the Monday as
    #     the first day of the week.

    foreach ( 1 .. 7 ) {
        $return .= <<EOF;
        <td>@{[encode_entities(Day_of_Week_Abbreviation($_))]}</td>
EOF
    }

    $return .= <<EOF;
    </tr>
EOF

    my $dow_first = Day_of_Week( $year, $month, 1 );
    if ( $dow_first != 1 ) {
        $return .= <<EOF;
    <tr>
EOF
    }
    foreach ( 1 .. ( $dow_first - 1 ) ) {
        my ( $mini_year, $mini_month, $mini_day ) =
          Add_Delta_Days( $year, $month, 1, -( $dow_first - $_ ) );
        $return .= <<EOF;
        <td><a class=dayothermonth href="$uri?action=showday&amp;object=$object&amp;year=$mini_year&amp;month=$mini_month&amp;day=$mini_day">$mini_day</a></td>
EOF
    }

    my $days = Days_in_Month( $year, $month );
    my ( $curyear, $curmonth, $curday ) = Today();
    foreach ( 1 .. $days ) {
        my $tdclass = "class=curday" if $_ == $day and not $nocur;
        my $class =
          ( $_ == $curday and $month == $curmonth and $year == $curyear )
          ? 'today'
          : 'daycurmonth';

        my $dow = Day_of_Week( $year, $month, $_ );
        if ( $dow == 1 ) {
            $return .= <<EOF;
    <tr>
EOF
        }
        $return .= <<EOF;
        <td $tdclass><a class=$class href="$uri?action=showday&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$_">$_</a></td>
EOF
        if ( $dow == 7 ) {
            $return .= <<EOF;
    </tr>
EOF
        }
    }

    my $dow_last = Day_of_Week( $year, $month, $days );
    foreach ( ( $dow_last + 1 ) .. 7 ) {
        my ( $mini_year, $mini_month, $mini_day ) =
          Add_Delta_Days( $year, $month, $days, ( $_ - $dow_last ) );
        $return .= <<EOF;
        <td><a class=dayothermonth href="$uri?action=showday&amp;object=$object&amp;year=$mini_year&amp;month=$mini_month&amp;day=$mini_day">$mini_day</a></td>
EOF
    }

    my $text  = $self->gettext;
    my $today =
      $self->format_date( $self->conf->{MINIMONTH_DATE_FORMAT} || '%(long)',
        $curyear, $curmonth, $curday, 0, 0, 0 );
    $return .= <<EOF;
    </tr>
    <tr>
        <td colspan=7 class=minimonthfooter>
            <a class=daycurmonth href="$uri?action=showday&amp;object=$object&amp;year=$curyear&amp;month=$curmonth&amp;day=$curday">$text->{today}</a>, $today
        </td>
    </tr>
</table>
<!-- End Chronos::minimonth -->
EOF

    return $return;
}

# This function is used in Showmonth and Showweek to find the events happening
# in a given day.
# This really should be transformed into a method of an object Chronos::Day. But
# what use would be an object with only one method? Feel free to implement
# Chronos::Day if you wish. 
sub events_per_day {
    my $self   = shift;
    my $view   = uc shift;                # 'month' or 'week'
    my $uri    = $self->{r}->uri;
    my $dbh    = $self->dbh;
    my $object = $self->action->object;
    my ( $year, $month, $day ) = @_;
    my $conf = $self->conf;

    my $sth_events = $dbh->prepare( <<EOF );
SELECT eid, name, start_date, start_time, end_date, end_time
FROM events
WHERE
    initiator = ?
    AND start_date <= ?
    AND end_date >= ?
ORDER BY start_date, start_time, name
EOF
    my $sth_participants = $dbh->prepare( <<EOF );
SELECT events.eid, events.name, events.start_date, events.start_time, events.end_date, events.end_time
FROM events, participants
WHERE
    events.eid = participants.eid
    AND participants.user = ?
    AND events.start_date <= ?
    AND events.end_date >= ?
ORDER BY events.start_date, events.start_time, events.name
EOF

    # The two statements above take as input:
    # 1) The current object
    # 2) Today's date
    # 3) Today's date

    my $today = to_date( $year, $month, $day );

    my $return = "";
    foreach my $sth ( $sth_events, $sth_participants ) {
        $sth->execute( $object, $today, $today );
        while (
            my ( $eid, $name, $start_date, $start_time, $end_date, $end_time ) =
            $sth->fetchrow_array )
        {
            my ( $syear, $smonth, $sday, $shour, $smin, $ssec ) =
              ( from_date($start_date), from_time($start_time) );
            my ( $eyear, $emonth, $eday, $ehour, $emin, $esec ) =
              ( from_date($end_date), from_time($end_time) );
            my $range;
            if ( $syear == $year and $smonth == $month and $sday == $day ) {
                # The event starts today, we need a range
                my $format;
                if ( defined $start_time ) {
                    if (
                        Compare_YMD( $syear, $smonth, $sday, $eyear, $emonth,
                            $eday ) == 0
                      )
                    {
                        $format = $conf->{"${view}_DATE_FORMAT"} || '%k:%M';
                    } else {
                        $format = $conf->{"${view}_MULTIDAY_DATE_FORMAT"}
                          || '%F %k:%M';
                    }
                } elsif (
                    Compare_YMD( $syear, $smonth, $sday, $eyear, $emonth,
                        $eday ) != 0
                  )
                {
                    $format = $conf->{"${view}_MULTIDAY_NOTIME_DATE_FORMAT"}
                      || '%F';
                } else {
                    $format = $conf->{"${view}_NOTIME_DATE_FORMAT"} || '';
                }
                $range = encode_entities(
                    sprintf '%s - %s',
                    $self->format_date(
                        $format, $syear, $smonth, $sday, $shour, $smin, $ssec
                    ),
                    $self->format_date(
                        $format, $eyear, $emonth, $eday, $ehour, $emin, $esec
                    )
                );
            } else {
                # The events started another day and continues today. Print
                # no range.
            }

            $return .= <<EOF;
            <br>&bull; $range <a class=event href="$uri?action=editevent&amp;eid=$eid&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$name</a>
EOF
        }
        $sth->finish;
    }
    return $return;
}

sub format_date {
    my $self   = shift;
    my $format = shift;
    my ( @calc_time, @localtime );
    if ( @_ == 9 ) {
        @localtime = @_;
        @calc_time = ( $_[5] + 1900, $_[4] + 1, @_[ 3 .. 0 ] );
    } elsif ( @_ == 6 ) {
        @calc_time = @_;
        @localtime = localtime( Mktime(@_) );
    } else {
        die
'Usage: format_date(@localtime) or format_date($year, $month, $day, $hour, $min, $sec)';
    }

    my $long  = Date_to_Text_Long( @calc_time[ 0 .. 2 ] );
    my $short = Date_to_Text( @calc_time[ 0 .. 2 ] );
    $format =~ s/\%\(long\)/$long/;
    $format =~ s/\%\(short\)/$short/;
    return strftime( $format, @localtime );
}

1;
# vim: set et ts=4 sw=4:
