# $Id: EditEvent.pm,v 1.8 2002/07/16 15:12:13 nomis80 Exp $
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
package Chronos::Action::EditEvent;

use strict;
use Chronos::Action;
use Date::Calc qw(:all);
use Chronos::Static qw(from_datetime from_date userstring);
use HTML::Entities;

our @ISA = qw(Chronos::Action);

sub type {
    return 'read';
}

sub authorized {
    my $self = shift;
    my $chronos = $self->{parent};
    my $dbh = $chronos->dbh;
    my $object = $self->object;
    my $object_quoted = $dbh->quote($object);

    if ($self->SUPER::authorized == 0) {
        return 0;
    }

    if (my $eid = $chronos->{r}->param('eid')) {
        return 1 if $object eq $dbh->selectrow_array("SELECT initiator FROM events WHERE eid = $eid");
        return 1 if $dbh->selectrow_array("SELECT user FROM participants WHERE eid = $eid AND user = $object_quoted");
        return 0
    } else {
        return 1;
    }
}

sub header {
    my $self = shift;
    my $object = $self->object;
    my ($year, $month, $day) = $self->{parent}->day;
    my $text = $self->{parent}->gettext;
    return <<EOF;
<table style="border:hidden; margin-style:none" cellspacing=0 cellpadding=0 width="100%">
    <tr>
        <td class=header>@{[Date_to_Text_Long(Today())]}</td>
        <td class=header align=right>
            <a href="/Chronos?action=showmonth&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{month}</a> |
            <a href="/Chronos?action=showweek&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{week}</a> |
            <a href="/Chronos?action=showday&amp;object=$object&amp;year=$year&amp;month=$month&amp;day=$day">$text->{Day}</a>
        </td>
    </tr>
</table>
EOF
}

sub content {
    my $self    = shift;
    my $chronos = $self->{parent};

    my ( $year, $month, $day, $hour ) = $chronos->dayhour;
    my $minimonth = $self->{parent}->minimonth( $year, $month, $day );
    my $form = $self->form( $year, $month, $day, $hour );

    return <<EOF;
<table width="100%" style="border:hidden">
    <tr>
        <td valign=top>$minimonth</td>
        <td width="100%">$form</td>
    </tr>
</table>
EOF
}

sub form {
    my $self    = shift;
    my $object = $self->object;
    my $chronos = $self->{parent};
    my $text    = $chronos->gettext;
    my ( $year, $month, $day, $hour ) = @_;
    my $dbh = $chronos->dbh;

    my $eid = $chronos->{r}->param('eid');
    my %event;
    if ($eid) {
        %event = %{ $dbh->selectrow_hashref("SELECT * FROM events WHERE eid = $eid") };
    }
    @event{qw(syear smonth sday shour smin ssec)} = from_datetime( $event{start} );
    @event{qw(eyear emonth eday ehour emin esec)} = from_datetime( $event{end} );
    if ( $event{rid} ) {
        @event{qw(recurrent recur_until)} = $dbh->selectrow_array("SELECT every, last FROM recur WHERE rid = $event{rid}");
        @event{qw(ryear rmonth rday)}     = from_date( $event{recur_until} );
    }

    if ( $eid and $event{initiator} ne $self->object ) {
        # Modification d'un événement existant par un participant
        my $stext = encode_entities( sprintf '%s %d:%02d', Date_to_Text_Long( @event{qw(syear smonth sday)} ), @event{qw(shour smin)} );
        my $etext = encode_entities( sprintf '%s %d:%02d', Date_to_Text_Long( @event{qw(eyear emonth eday)} ), @event{qw(ehour emin)} );
        my $recur = $event{recurrent} ? $text->{ "eventrecur" . lc $event{recurrent} } : $text->{eventnotrecur};
        my $rtext = $event{recur_until} ? encode_entities( Date_to_Text_Long( @event{qw(ryear rmonth rday)} ) ) : '-';

        my $initiator_quoted = $dbh->quote( $event{initiator} );
        my $participants     = userstring( $dbh->selectrow_array("SELECT user, name, email FROM user WHERE user = $initiator_quoted") ) . " <b>($text->{initiator})</b>";
        my $sth              =
          $dbh->prepare(
            "SELECT user.user, user.name, user.email, participants.status FROM user, participants WHERE participants.eid = $eid AND participants.user = user.user ORDER BY user.name, user.user");
        $sth->execute;

        while ( my ( $user, $name, $email, $status ) = $sth->fetchrow_array ) {
            my $userstring = userstring( $user, $name, $email );
            my $statusstring = $text->{"status_$status"};
            $participants .= "<br>$userstring <b>($statusstring)</b>";
            if ( $user eq $self->object ) {
                if ( $status ne 'CANCELED' ) {
                    $participants .= " <input type=submit name=cancel value=\"$text->{cancel}\">";
                }
                if ( $status ne 'CONFIRMED' ) {
                    $participants .= " <input type=submit name=confirm value=\"$text->{confirm}\">";
                }
            }
        }
        $sth->finish;

        my $return = <<EOF;
<form method=POST action="/Chronos">
<input type=hidden name=action value=saveevent>
<input type=hidden name=object value="$object">
<input type=hidden name=year value=$year>
<input type=hidden name=month value=$month>
<input type=hidden name=day value=$day>
<input type=hidden name=eid value=$eid>

<table class=editevent>
    <tr>
        <td class=eventlabel>$text->{eventname}</td>
        <td>$event{name}</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventstart}</td>
        <td>$stext</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventend}</td>
        <td>$etext</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventdescription}</td>
        <td>$event{description}</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventrecur}</td>
        <td>$recur</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventrecurend}</td>
        <td>$rtext</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventparticipants}</td>
        <td>$participants</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{reminder}</td>
EOF

        my ( %selunit, %selnumber );
        my $reminder_datetime;
        if ( $event{initiator} eq $self->object ) {
            $reminder_datetime = $event{reminder};
        } else {
            $reminder_datetime = $dbh->selectrow_array("SELECT reminder FROM participants WHERE eid = $eid");
        }
        if ( defined $reminder_datetime ) {
            my ( $Dd, $Dh, $Dm ) = Delta_DHMS( from_datetime($reminder_datetime), from_datetime( $event{start} ) );
            if ($Dd and not $Dh) {
                $selunit{day} = 'selected';
                $selnumber{$Dd} = 'selected';
            } elsif ($Dh) {
                $selunit{hour} = 'selected';
                $selnumber{$Dh + 24 * $Dd} = 'selected';
            } elsif ($Dm) {
                $selunit{min} = 'selected';
                $selnumber{$Dm} = 'selected';
            }
        }

        my $reminder_number = "<select name=reminder_number><option>-</option>";
        foreach ( 1, 2, 4, 8, 12, 24, 36, 48 ) {
            $reminder_number .= "<option $selnumber{$_}>$_</option>";
        }
        $reminder_number .= "</select>";
        my $reminder_unit = "<select name=reminder_unit>";
        foreach (qw(min hour day)) {
            $reminder_unit .= "<option value=$_ $selunit{$_}>$text->{$_}</option>";
        }
        $reminder_unit .= "</select>";
        my $remind_me = $text->{remind_me};
        $remind_me =~ s/\%1/$reminder_number/;
        $remind_me =~ s/\%2/$reminder_unit/;
        $return .= <<EOF;
        <td>$remind_me</td>
    </tr>
    <tr>
        <td colspan=2>
            <input type=submit value="$text->{eventsave}">
EOF
        if ( $event{initiator} eq $self->object ) {
            $return .= <<EOF;
            &nbsp;<input type=submit name=delete value="$text->{eventdel}">
EOF
        }
        $return .= <<EOF;
        </td>
    </tr>
</table>

</form>
EOF
        return $return;

    } else {
        # Création d'un nouvel événement ou modification d'un événement existant par l'initiateur
        my $return = <<EOF;
<form method=POST action="/Chronos">
<input type=hidden name=action value=saveevent>
<input type=hidden name=object value="$object">
<input type=hidden name=year value=$year>
<input type=hidden name=month value=$month>
<input type=hidden name=day value=$day>
EOF
        if ($eid) {
            $return .= <<EOF;
<input type=hidden name=eid value=$eid>
EOF
        }
        $return .= <<EOF;

<table class=editevent>
    <tr>
        <td class=eventlabel>$text->{eventname}</td>
        <td><input name=name value="$event{name}"></td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventstart}</td>
        <td>
            <select name=start_month>
EOF
        foreach ( 1 .. 12 ) {
            my $month_name = Month_to_Text($_);
            my $selected = $_ == ( $event{smonth} || $month ) ? 'selected' : '';
            $return .= <<EOF;
                <option value=$_ $selected>$month_name</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=start_day>
EOF
        foreach ( 1 .. 31 ) {
            my $selected = $_ == ( $event{sday} || $day ) ? 'selected' : '';
            $return .= <<EOF;
                <option $selected>$_</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=start_year>
EOF
        foreach ( ( $year - 5 ) .. ( $year + 5 ) ) {
            my $selected = $_ == ( $event{syear} || $year ) ? 'selected' : '';
            $return .= <<EOF;
                <option $selected>$_</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=start_hour>
EOF
        foreach ( '00' .. '23' ) {
            my $selected = $_ == ( $event{shour} || $hour ) ? 'selected' : '';
            my $value = int $_;
            $return .= <<EOF;
                <option value=$value $selected>$_</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=start_min>
EOF
        foreach ( 0, 15, 30, 45 ) {
            my $string = sprintf ':%02d', $_;
            my $selected = $_ == $event{smin} ? 'selected' : '';
            $return .= <<EOF;
                <option value=$_ $selected>$string</option>
EOF
        }
        $return .= <<EOF;
            </select>
        </td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventend}</td>
        <td>
            <select name=end_month>
EOF
        foreach ( 1 .. 12 ) {
            my $month_name = Month_to_Text($_);
            my $selected = $_ == ( $event{emonth} || $month ) ? 'selected' : '';
            $return .= <<EOF;
                <option value=$_ $selected>$month_name</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=end_day>
EOF
        foreach ( 1 .. 31 ) {
            my $selected = $_ == ( $event{eday} || $day ) ? 'selected' : '';
            $return .= <<EOF;
                <option $selected>$_</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=end_year>
EOF
        foreach ( ( $year - 5 ) .. ( $year + 5 ) ) {
            my $selected = $_ == ( $event{eyear} || $year ) ? 'selected' : '';
            $return .= <<EOF;
                <option $selected>$_</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=end_hour>
EOF
        foreach ( '00' .. '23' ) {
            my $selected = $_ == ( $event{ehour} || $hour + 2 ) ? 'selected' : '';
            my $value = int $_;
            $return .= <<EOF;
                <option value=$value $selected>$_</option>
EOF
        }
        $return .= <<EOF;
            </select>
            <select name=end_min>
EOF
        foreach ( 0, 15, 30, 45 ) {
            my $string = sprintf ':%02d', $_;
            my $selected = $_ == $event{emin} ? 'selected' : '';
            $return .= <<EOF;
                <option value=$_ $selected>$string</option>
EOF
        }

        $return .= <<EOF;
            </select>
        </td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventdescription}</td>
        <td><textarea name=description cols=30 rows=3>$event{description}</textarea></td>
    </tr>
EOF
        unless ($eid) {
            $return .= <<EOF;
    <tr>
        <td class=eventlabel>$text->{eventrecur}</td>
        <td>
            <select name=recur>
                <option value="NULL">$text->{eventnotrecur}</option>
                <option value="DAY">$text->{eventrecurday}</option>
                <option value="WEEK">$text->{eventrecurweek}</option>
                <option value="MONTH">$text->{eventrecurmonth}</option>
                <option value="YEAR">$text->{eventrecuryear}</option>
            </select>
        </td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventrecurend}</td>
        <td>
            <select name=recur_end_month>
EOF
            foreach ( 1 .. 12 ) {
                my $month_name = Month_to_Text($_);
                my $selected = $_ == ( $event{rmonth} || $month ) ? 'selected' : '';
                $return .= <<EOF;
                <option value=$_ $selected>$month_name</option>
EOF
            }
            $return .= <<EOF;
            </select>
            <select name=recur_end_day>
EOF
            foreach ( 1 .. 31 ) {
                my $selected = $_ == ( $event{rday} || $day ) ? 'selected' : '';
                $return .= <<EOF;
                <option $selected>$_</option>
EOF
            }
            $return .= <<EOF;
            </select>
            <select name=recur_end_year>
EOF
            foreach ( ( $year - 5 ) .. ( $year + 5 ) ) {
                my $selected = $_ == ( $event{ryear} || $year ) ? 'selected' : '';
                $return .= <<EOF;
                <option $selected>$_</option>
EOF
            }
            $return .= <<EOF;
            </select>
        </td>
    </tr>
EOF
        } else {
            my $recur = $event{recurrent} ? $text->{ "eventrecur" . lc $event{recurrent} } : $text->{eventnotrecur};
            my $rtext = $event{recur_until} ? encode_entities( Date_to_Text_Long( @event{qw(ryear rmonth rday)} ) ) : '-';
            $return .= <<EOF;
    <tr>
        <td class=eventlabel>$text->{eventrecur}</td>
        <td>$recur</td>
    </tr>
    <tr>
        <td class=eventlabel>$text->{eventrecurend}</td>
        <td>$rtext</td>
    </tr>
EOF
        }
            
        $return .= <<EOF;
    <tr>
        <td class=eventlabel>$text->{eventparticipants}</td>
        <td>
EOF

        if ($eid) {
            my ( $user, $name, $email ) =
              $dbh->selectrow_array("SELECT user.user, user.name, user.email FROM user, events WHERE events.eid = $eid AND events.initiator = user.user");
            my $userstring = userstring( $user, $name, $email );
            $return .= <<EOF;
            $userstring <b>($text->{initiator})</b>
EOF

            my $sth =
              $dbh->prepare(
                "SELECT user.user, user.name, user.email, participants.status FROM user, participants WHERE participants.eid = $eid AND participants.user = user.user ORDER BY user.name, user.user");
            $sth->execute;
            while ( my ( $user, $name, $email, $status ) = $sth->fetchrow_array ) {
                my $userstring = userstring( $user, $name, $email );
                my $statusstring = $text->{"status_$status"};
                $return .= <<EOF;
            <br>$userstring <b>($statusstring)</b>
EOF
                if ( $user eq $self->object ) {
                    if ( $status ne 'CANCELED' ) {
                        $return .= "<input type=submit name=cancel value=\"$text->{cancel}\">";
                    }
                    if ( $status ne 'CONFIRMED' ) {
                        $return .= "<input type=submit name=confirm value=\"$text->{confirm}\">";
                    }
                }
            }
            $sth->finish;
        } else {
            $return .= <<EOF;
            <select size=5 multiple name=participants>
EOF
            my $sth = $dbh->prepare("SELECT user, name, email FROM user WHERE user != ? ORDER BY name, user");
            $sth->execute( $self->object );
            while ( my ( $user, $name, $email ) = $sth->fetchrow_array ) {
                my $string = ($name || $user) . ($email ? " &lt;$email&gt;" : '');
                $return .= <<EOF;
                <option value="$user">$string</option>
EOF
            }
            $sth->finish;
            $return .= <<EOF;
            </select>
EOF
        }

        $return .= <<EOF;
        </td>
    </tr>
EOF
        if ( not $eid ) {
            $return .= <<EOF;
    <tr>
        <td class=eventlabel>$text->{eventconfirm}</td>
        <td><input type=checkbox name=confirm></td>
    </tr>
EOF
        }
        $return .= <<EOF;
    <tr>
        <td class=eventlabel>$text->{reminder}</td>
EOF

        my ( %selunit, %selnumber );
        if ($eid) {
            my $reminder_datetime;
            if ( $event{initiator} eq $self->object ) {
                $reminder_datetime = $event{reminder};
            } else {
                $reminder_datetime = $dbh->selectrow_array("SELECT reminder FROM participants WHERE eid = $eid");
            }
            if ( defined $reminder_datetime ) {
                my ( $Dd, $Dh, $Dm ) = Delta_DHMS( from_datetime($reminder_datetime), from_datetime( $event{start} ) );
                if ($Dd and not $Dh) {
                    $selunit{day} = 'selected';
                    $selnumber{$Dd} = 'selected';
                } elsif ($Dh) {
                    $selunit{hour} = 'selected';
                    $selnumber{$Dh + 24 * $Dd} = 'selected';
                } elsif ($Dm) {
                    $selunit{min} = 'selected';
                    $selnumber{$Dm} = 'selected';
                }
            }
        }

        my $reminder_number = "<select name=reminder_number><option>-</option>";
        foreach ( 1, 2, 4, 8, 12, 24, 36, 48 ) {
            $reminder_number .= "<option $selnumber{$_}>$_</option>";
        }
        $reminder_number .= "</select>";
        my $reminder_unit = "<select name=reminder_unit>";
        foreach (qw(min hour day)) {
            $reminder_unit .= "<option value=$_ $selunit{$_}>$text->{$_}</option>";
        }
        $reminder_unit .= "</select>";
        my $remind_me = $text->{remind_me};
        $remind_me =~ s/\%1/$reminder_number/;
        $remind_me =~ s/\%2/$reminder_unit/;
        $return .= <<EOF;
        <td>$remind_me</td>
    </tr>
    <tr>
        <td colspan=2>
            <input type=submit value="$text->{eventsave}">
EOF
        if ( $eid and $event{initiator} eq $self->object ) {
            $return .= <<EOF;
            &nbsp;<input type=submit name=delete value="$text->{eventdel}">
EOF
        }
        $return .= <<EOF;
        </td>
    </tr>
</table>

</form>
EOF

        return $return;
    }
}

1;

# vim: set et ts=4 sw=4 ft=perl:
