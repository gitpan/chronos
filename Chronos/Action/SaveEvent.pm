# $Id: SaveEvent.pm,v 1.9 2002/07/16 15:12:13 nomis80 Exp $
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
package Chronos::Action::SaveEvent;

use strict;
use Chronos::Action;
use Date::Calc qw(:all);
use Chronos::Static qw(Compare_YMDHMS Compare_YMD from_datetime userstring to_datetime to_date);
use HTML::Entities;

our @ISA = qw(Chronos::Action);

sub type {
    return 'write';
}

sub header {
    return '';
}

sub content {
    my $self    = shift;
    my $object = $self->object;
    my $chronos = $self->{parent};
    my $dbh     = $chronos->dbh;

    my $eid = $chronos->{r}->param('eid');

    if ($eid) {
        # Modification d'un événement existant
        if ( $dbh->selectrow_array("SELECT initiator FROM events WHERE eid = $eid") eq $self->object ) {
            # On est exécuté par l'initiateur de l'événement. On peut faire des actions privilégiées.
            if ( $chronos->{r}->param('delete') ) {
                # Suppression d'événement
                my $sth_delete_participants = $dbh->prepare("DELETE FROM participants WHERE eid = ?");
                my $sth_delete_events       = $dbh->prepare("DELETE FROM events WHERE eid = ?");
                my $rid                     = $dbh->selectrow_array("SELECT rid FROM events WHERE eid = $eid");
                if ($rid) {
                    my $sth = $dbh->prepare("SELECT eid FROM events WHERE rid = $rid");
                    $sth->execute;
                    while ( my $eid = $sth->fetchrow_array ) {
                        $sth_delete_participants->execute($eid);
                        $sth_delete_events->execute($eid);
                    }
                    $sth->finish;
                    $dbh->do("DELETE FROM recur WHERE rid = $rid");
                } else {
                    $sth_delete_participants->execute($eid);
                    $sth_delete_events->execute($eid);
                }
            } else {
                # Modification de la table events par l'initiateur de l'événement
                my $name            = $chronos->{r}->param('name');
                my $start_month     = $chronos->{r}->param('start_month');
                my $start_day       = $chronos->{r}->param('start_day');
                my $start_year      = $chronos->{r}->param('start_year');
                my $start_hour      = $chronos->{r}->param('start_hour');
                my $start_min       = $chronos->{r}->param('start_min');
                my $end_month       = $chronos->{r}->param('end_month');
                my $end_day         = $chronos->{r}->param('end_day');
                my $end_year        = $chronos->{r}->param('end_year');
                my $end_hour        = $chronos->{r}->param('end_hour');
                my $end_min         = $chronos->{r}->param('end_min');
                my $description     = $chronos->{r}->param('description');
                my $confirm         = $chronos->{r}->param('confirm');
                my $reminder_number = $chronos->{r}->param('reminder_number');
                my $reminder_unit   = $chronos->{r}->param('reminder_unit');
                my @participants    = $chronos->{r}->param('participants');

                check_date( $start_year, $start_month, $start_day )
                  or $self->error('startdate');
                check_time( $start_hour, $start_min, 0 ) or $self->error('starttime');
                check_date( $end_year, $end_month, $end_day ) or $self->error('enddate');
                check_time( $end_hour, $end_min, 0 ) or $self->error('endtime');

                if ( Compare_YMDHMS( $start_year, $start_month, $start_day, $start_hour, $start_min, 0, $end_year, $end_month, $end_day, $end_hour, $end_min, 0 ) == 1 )
                {
                    $self->error('endbeforestart');
                }

                $name or $self->error('missingname');

                # Tout a l'air beau, on fait l'update
                if ( my $rid = $dbh->selectrow_array("SELECT rid FROM events WHERE eid = $eid") ) {
                    $dbh->prepare("UPDATE events SET name = ?, description = ? WHERE rid = ?")->execute( $name, $description, $rid );

                    my $first_eid = $dbh->selectrow_array("SELECT eid FROM events WHERE rid = $rid ORDER BY eid LIMIT 1");
                    my ( $start, $end ) = $dbh->selectrow_array("SELECT start, end FROM events WHERE eid = $eid");
                    my ( $Dsyear, $Dsmonth, $Dsday, $Dshour, $Dsmin ) =
                      Delta_YMDHMS( from_datetime($start), $start_year, $start_month, $start_day, $start_hour, $start_min, 0 );
                    my ( $Deyear, $Demonth, $Deday, $Dehour, $Demin ) = Delta_YMDHMS( from_datetime($end), $end_year, $end_month, $end_day, $end_hour, $end_min, 0 );

                    my @delta_reminder = ( 0, 0, 0, 0 );
                    if ( $reminder_number ne '-' ) {
                        if ( $reminder_unit eq 'min' ) {
                            $delta_reminder[2] = -$reminder_number;
                        } elsif ( $reminder_unit eq 'hour' ) {
                            $delta_reminder[1] = -$reminder_number;
                        } else {
                            $delta_reminder[0] = -$reminder_number;
                        }
                    }

                    my $sth_update = $dbh->prepare("UPDATE events SET start = ?, end = ?, reminder = ? WHERE eid = ?");
                    my $sth_eid    = $dbh->prepare("SELECT eid, start, end FROM events WHERE rid = $rid");
                    $sth_eid->execute;
                    while ( my ( $eid, $start, $end ) = $sth_eid->fetchrow_array ) {
                        my ( $syear, $smonth, $sday, $shour, $smin ) = Add_Delta_YMDHMS( from_datetime($start), $Dsyear, $Dsmonth, $Dsday, $Dshour, $Dsmin, 0 );
                        my ( $eyear, $emonth, $eday, $ehour, $emin ) = Add_Delta_YMDHMS( from_datetime($end),   $Deyear, $Demonth, $Deday, $Dehour, $Demin, 0 );
                        my $reminder = $reminder_number eq '-' ? undef: to_datetime( Add_Delta_DHMS( $syear, $smonth, $sday, $shour, $smin, 0, @delta_reminder ) );
                        $sth_update->execute(
                            to_datetime( $syear, $smonth, $sday, $shour, $smin, 0 ),
                            to_datetime( $eyear, $emonth, $eday, $ehour, $emin, 0 ),
                            $reminder, $eid
                        );
                    }
                    $sth_eid->finish;
                } else {
                    my $start = sprintf '%04d-%02d-%02d %02d:%02d:00', $start_year, $start_month, $start_day, $start_hour, $start_min;
                    my $end   = sprintf '%04d-%02d-%02d %02d:%02d:00', $end_year,   $end_month,   $end_day,   $end_hour,   $end_min;

                    my $reminder;
                    if ( $reminder_number ne '-' ) {
                        my ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min, $Dd, $Dh, $Dm, );
                        if ( $reminder_unit eq 'min' ) {
                            $Dm = -$reminder_number;
                        } elsif ( $reminder_unit eq 'hour' ) {
                            $Dh = -$reminder_number;
                        } else {
                            $Dd = -$reminder_number;
                        }
                        ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min ) =
                          Add_Delta_DHMS( $start_year, $start_month, $start_day, $start_hour, $start_min, 0, $Dd, $Dh, $Dm, 0 );
                        $reminder = sprintf '%04d-%02d-%02d %02d:%02d:00', $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min;
                    }

                    $dbh->prepare("UPDATE events SET name = ?, start = ?, end = ?, description = ?, reminder = ? WHERE eid = $eid")
                      ->execute( $name, $start, $end, $description, $reminder );
                }

                my ( $year, $month, $day ) = $chronos->day;
                $chronos->{r}->header_out( "Location", "/Chronos?action=dayview&object=$object&year=$year&month=$month&day=$day" );
            }
        } elsif ( $chronos->{r}->param('confirm') ) {
            # Confirmation de la part d'un participant
            my $sth = $dbh->prepare("UPDATE participants SET status = 'CONFIRMED' WHERE eid = ? AND user = ?");
            if ( my $rid = $dbh->selectrow_array("SELECT rid FROM events WHERE eid = $eid") ) {
                my $sth_eid = $dbh->prepare("SELECT eid FROM events WHERE rid = $rid");
                $sth_eid->execute;
                while ( my $eid = $sth_eid->fetchrow_array ) {
                    $sth->execute( $eid, $self->object );
                }
                $sth_eid->finish;
            } else {
                $sth->execute( $eid, $self->object );
            }
        } elsif ( $chronos->{r}->param('cancel') ) {
            # Annulation de la part d'un participant
            my $sth = $dbh->prepare("UPDATE participants SET status = 'CANCELED' WHERE eid = ? AND user = ?");
            if ( my $rid = $dbh->selectrow_array("SELECT rid FROM events WHERE eid = $eid") ) {
                my $sth_eid = $dbh->prepare("SELECT eid FROM events WHERE rid = $rid");
                $sth_eid->execute;
                while ( my $eid = $sth_eid->fetchrow_array ) {
                    $sth->execute( $eid, $self->object );
                }
                $sth_eid->finish;
            } else {
                $sth->execute( $eid, $self->object );
            }
        } else {
            # Changement du reminder par un participant
            my $reminder_number = $chronos->{r}->param('reminder_number');
            my $reminder_unit   = $chronos->{r}->param('reminder_unit');

            if ( my $rid = $dbh->selectrow_array("SELECT rid FROM events WHERE eid = $eid") ) {
                my @reminder_delta = ( 0, 0, 0, 0 );
                if ( $reminder_unit eq 'min' ) {
                    $reminder_delta[2] = -$reminder_number;
                } elsif ( $reminder_unit eq 'hour' ) {
                    $reminder_delta[1] = -$reminder_number;
                } else {
                    $reminder_delta[0] = -$reminder_number;
                }

                my $sth_update = $dbh->prepare("UPDATE participants SET reminder = ? WHERE eid = ? AND user = ?");

                my $sth_eid = $dbh->prepare("SELECT eid, start FROM events WHERE rid = $rid");
                $sth_eid->execute;
                while ( my ( $eid, $start ) = $sth_eid->fetchrow_array ) {
                    my $reminder = $reminder_number eq '-' ? undef : to_datetime( Add_Delta_DHMS( from_datetime($start), @reminder_delta ) );
                    $sth_update->execute( $reminder, $eid, $self->object );
                }
                $sth_eid->finish;
            } else {
                my ( $syear, $smonth, $sday, $shour, $smin ) = from_datetime( $dbh->selectrow_array("SELECT start FROM events WHERE eid = $eid") );
                my $reminder;
                if ( $reminder_number ne '-' ) {
                    my ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min, $Dd, $Dh, $Dm, );
                    if ( $reminder_unit eq 'min' ) {
                        $Dm = -$reminder_number;
                    } elsif ( $reminder_unit eq 'hour' ) {
                        $Dh = -$reminder_number;
                    } else {
                        $Dd = -$reminder_number;
                    }
                    ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min ) =
                      Add_Delta_DHMS( $syear, $smonth, $sday, $shour, $smin, 0, $Dd, $Dh, $Dm, 0 );
                    $reminder = sprintf '%04d-%02d-%02d %02d:%02d:00', $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min;
                }
                $dbh->prepare("UPDATE participants SET reminder = ? WHERE eid = ? AND user = ?")->execute( $reminder, $eid, $self->object );
            }
        }
    } else {
        # Création d'événement
        my $name            = $chronos->{r}->param('name');
        my $start_month     = $chronos->{r}->param('start_month');
        my $start_day       = $chronos->{r}->param('start_day');
        my $start_year      = $chronos->{r}->param('start_year');
        my $start_hour      = $chronos->{r}->param('start_hour');
        my $start_min       = $chronos->{r}->param('start_min');
        my $end_month       = $chronos->{r}->param('end_month');
        my $end_day         = $chronos->{r}->param('end_day');
        my $end_year        = $chronos->{r}->param('end_year');
        my $end_hour        = $chronos->{r}->param('end_hour');
        my $end_min         = $chronos->{r}->param('end_min');
        my $description     = $chronos->{r}->param('description');
        my $recur           = $chronos->{r}->param('recur');
        my $recur_end_month = $chronos->{r}->param('recur_end_month');
        my $recur_end_day   = $chronos->{r}->param('recur_end_day');
        my $recur_end_year  = $chronos->{r}->param('recur_end_year');
        my $confirm         = $chronos->{r}->param('confirm');
        my $reminder_number = $chronos->{r}->param('reminder_number');
        my $reminder_unit   = $chronos->{r}->param('reminder_unit');
        my @participants    = $chronos->{r}->param('participants');

        check_date( $start_year, $start_month, $start_day )
          or $self->error('startdate');
        check_time( $start_hour, $start_min, 0 ) or $self->error('starttime');
        check_date( $end_year, $end_month, $end_day ) or $self->error('enddate');
        check_time( $end_hour, $end_min, 0 ) or $self->error('endtime');
        check_date( $recur_end_year, $recur_end_month, $recur_end_day )
          or $self->error('recurenddate');

        if ( Compare_YMDHMS( $start_year, $start_month, $start_day, $start_hour, $start_min, 0, $end_year, $end_month, $end_day, $end_hour, $end_min, 0 ) == 1 ) {
            $self->error('endbeforestart');
        }

        if ( $recur ne 'NULL' and Compare_YMD( $start_year, $start_month, $start_day, $recur_end_year, $recur_end_month, $recur_end_day ) == 1 ) {
            $self->error('recurendbeforestart');
        }

        if ( $recur ne 'NULL' and Compare_YMD( $end_year, $end_month, $end_day, $recur_end_year, $recur_end_month, $recur_end_day, ) == 1 ) {
            $self->error('recurendbeforeend');
        }

        $name or $self->error('missingname');

        # Tout a l'air beau, on fait le insert.
        if ( $recur ne 'NULL' ) {
            my ( $syear, $smonth, $sday, $shour, $smin, $eyear, $emonth, $eday, $ehour, $emin ) =
              ( $start_year, $start_month, $start_day, $start_hour, $start_min, $end_year, $end_month, $end_day, $end_hour, $end_min );
            my $recur_end = to_date( $recur_end_year, $recur_end_month, $recur_end_day );

            $dbh->prepare("INSERT INTO recur (every, last) VALUES(?, ?)")->execute( $recur, $recur_end );
            my $rid = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");

            my $sth              = $dbh->prepare("INSERT INTO events (initiator, name, start, end, description, rid, reminder) VALUES(?, ?, ?, ?, ?, ?, ?)");
            my $sth_participants = $dbh->prepare("INSERT INTO participants (eid, user, status) VALUES(?, ?, ?)");

            my $status = $confirm ? 'UNCONFIRMED' : 'CONFIRMED';

            while ( Compare_YMD( $syear, $smonth, $sday, $recur_end_year, $recur_end_month, $recur_end_day ) != 1 ) {
                my $start = to_datetime( $syear, $smonth, $sday, $shour, $smin, 0 );
                my $end   = to_datetime( $eyear, $emonth, $eday, $ehour, $emin, 0 );

                my $reminder;
                if ( $reminder_number ne '-' ) {
                    my ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min, $Dd, $Dh, $Dm, );
                    if ( $reminder_unit eq 'min' ) {
                        $Dm = -$reminder_number;
                    } elsif ( $reminder_unit eq 'hour' ) {
                        $Dh = -$reminder_number;
                    } else {
                        $Dd = -$reminder_number;
                    }
                    ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min ) =
                      Add_Delta_DHMS( $syear, $smonth, $sday, $shour, $smin, 0, $Dd, $Dh, $Dm, 0 );
                    $reminder = sprintf '%04d-%02d-%02d %02d:%02d:00', $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min;
                }

                $sth->execute( $self->object, $name, $start, $end, $description, $rid, $reminder );
                my $eid = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");
                foreach (@participants) {
                    $sth_participants->execute( $eid, $_, $status );
                }

                if ( $recur eq 'DAY' ) {
                    ( $syear, $smonth, $sday ) = Add_Delta_Days( $syear, $smonth, $sday, 1 );
                    ( $eyear, $emonth, $eday ) = Add_Delta_Days( $eyear, $emonth, $eday, 1 );
                } elsif ( $recur eq 'WEEK' ) {
                    ( $syear, $smonth, $sday ) = Add_Delta_Days( $syear, $smonth, $sday, 7 );
                    ( $eyear, $emonth, $eday ) = Add_Delta_Days( $eyear, $emonth, $eday, 7 );
                } elsif ( $recur eq 'MONTH' ) {
                    ( $syear, $smonth, $sday ) = Add_Delta_YM( $syear, $smonth, $sday, 0, 1 );
                    ( $eyear, $emonth, $eday ) = Add_Delta_YM( $eyear, $emonth, $eday, 0, 1 );
                } elsif ( $recur eq 'YEAR' ) {
                    ( $syear, $smonth, $sday ) = Add_Delta_YM( $syear, $smonth, $sday, 1, 0 );
                    ( $eyear, $emonth, $eday ) = Add_Delta_YM( $eyear, $emonth, $eday, 1, 0 );
                } else {
                    last;
                }
            }
        } else {
            my $start = sprintf '%04d-%02d-%02d %02d:%02d:00', $start_year, $start_month, $start_day, $start_hour, $start_min;
            my $end   = sprintf '%04d-%02d-%02d %02d:%02d:00', $end_year,   $end_month,   $end_day,   $end_hour,   $end_min;
            my $recur_end = sprintf '%04d-%02d-%02d', $recur_end_year, $recur_end_month, $recur_end_day;

            my $reminder;
            if ( $reminder_number ne '-' ) {
                my ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min, $Dd, $Dh, $Dm, );
                if ( $reminder_unit eq 'min' ) {
                    $Dm = -$reminder_number;
                } elsif ( $reminder_unit eq 'hour' ) {
                    $Dh = -$reminder_number;
                } else {
                    $Dd = -$reminder_number;
                }
                ( $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min ) =
                  Add_Delta_DHMS( $start_year, $start_month, $start_day, $start_hour, $start_min, 0, $Dd, $Dh, $Dm, 0 );
                $reminder = sprintf '%04d-%02d-%02d %02d:%02d:00', $remind_year, $remind_month, $remind_day, $remind_hour, $remind_min;
            }

            my $sth = $dbh->prepare("INSERT INTO events (initiator, name, start, end, description, reminder) VALUES(?, ?, ?, ?, ?, ?)");
            $sth->execute( $self->object, $name, $start, $end, $description, $reminder );

            my $eid = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");
            my $status = $confirm ? 'UNCONFIRMED' : 'CONFIRMED';
            $sth = $dbh->prepare("INSERT INTO participants (eid, user, status) VALUES($eid, ?, '$status')");
            foreach (@participants) {
                $sth->execute($_);
            }
        }

        if ($confirm) {
            my $text = $chronos->gettext;
            foreach (@participants) {
                my $email_addy = $dbh->selectrow_array("SELECT email FROM user WHERE user = @{[$dbh->quote($_)]}");
                my $mail_body  = $text->{confirm_body};
                my ( $ini_name, $ini_email ) = $dbh->selectrow_array("SELECT name, email FROM user WHERE user = @{[$dbh->quote($self->object)]}");
                my $userstring = decode_entities( userstring( $self->object, $ini_name, $ini_email ) );
                $userstring =~ s/<a.*?>(.*?)<\/a>/$1/;
                $mail_body  =~ s/\%\%INITIATOR\%\%/$userstring/;
                $mail_body  =~ s/\%\%DATE\%\%/sprintf '%s %d:%02d', Date_to_Text_Long($start_year, $start_month, $start_day), $start_hour, $start_min/e;
                $mail_body  =~ s/\%\%NAME\%\%/$name/;
                $mail_body  =~ s/\%\%DESCRIPTION\%\%/$description/;
                $mail_body  =~ s/\%\%VERSION\%\%/$chronos->VERSION/e;
                my $subject = decode_entities( $text->{confirm_subject} );
                $mail_body = decode_entities($mail_body);
                open MAIL, "| /usr/sbin/sendmail -oi -t";
                print MAIL <<EOF;
To: $email_addy
From: Chronos
Subject: $subject

$mail_body
EOF
                close MAIL;
            }
        }
    }

    my ( $year, $month, $day ) = $chronos->day;
    $chronos->{r}->header_out( "Location", "/Chronos?action=dayview&object=$object&year=$year&month=$month&day=$day" );
}

sub error {
    my $self    = shift;
    my $error   = shift;
    my $chronos = $self->{parent};
    $chronos->{r}->content_type('text/html');
    $chronos->{r}->send_http_header;
    my $text = $chronos->gettext;
    $error = $text->{"error$error"};
    $chronos->{r}->print("<html><head><title>$text->{error}</title></head><body><h1>$text->{error}</h1><p>$error</p></body></html>");
    exit 0;
}

sub redirect {
    return 1;
}

1;

# vim: set et ts=4 sw=4 ft=perl:
