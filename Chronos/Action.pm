# $Id: Action.pm,v 1.5 2002/07/16 15:12:13 nomis80 Exp $
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
package Chronos::Action;

use strict;
use Apache::Constants qw(:common);

sub new {
    my $self   = shift;
    my $class  = ref($self) || $self;
    return bless { parent => shift }, $class;
}

sub description {
    my $self = shift;
    my $text = $self->{parent}->gettext;
    return $text->{"action_$self->{name}"};
}

sub object {
    my $self = shift;
    return $self->{parent}->{r}->param('object') || $self->{parent}->user;
}

sub authorized {
    my $self   = shift;
    my $user   = $self->{parent}->user;
    my $object = $self->object;
    if ( not $object ) {
        return 0;
    } elsif ( $user eq $object ) {
        return 1;
    } else {
        my $dbh           = $self->{parent}->dbh;
        my $user_quoted   = $dbh->quote($user);
        my $object_quoted = $dbh->quote($object);
        if ( $self->type eq 'read' ) {
            if (
                $dbh->selectrow_array(
"SELECT public_readable FROM user WHERE user = $object_quoted"
                ) eq 'Y'
                or $dbh->selectrow_array(
"SELECT can_read FROM acl WHERE user = $user_quoted AND object = $object_quoted"
                ) eq 'Y'
              )
            {
                return 1;
            } else {
                return 0;
            }
        } elsif ( $self->type eq 'write' ) {
            if (
                $dbh->selectrow_array(
"SELECT public_writable FROM user WHERE user = $object_quoted"
                ) eq 'Y'
                or $dbh->selectrow_array(
"SELECT can_write FROM acl WHERE user = $user_quoted AND object = $object_quoted"
                ) eq 'Y'
              )
            {
                return 1;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }
}

sub redirect {
    return 0;
}

1;

# vim: set et ts=4 sw=4 ft=perl:
