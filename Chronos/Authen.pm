# $Id: Authen.pm,v 1.5 2002/08/09 16:00:14 nomis80 Exp $
#
# Copyright (C) 2002  Linux Qu�bec Technologies 
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
package Chronos::Authen;

use strict;
use Apache::Constants qw(:common);
use Chronos;

sub handler {
    my $r = shift;

    my ( $res, $sent_pw ) = $r->get_basic_auth_pw;
    return $res if $res != OK;
    my $user = $r->connection->user;

    my $reason = authenticate( $r, $user, $sent_pw );

    if ($reason) {
        $r->note_basic_auth_failure;
        $r->log_reason( $reason, $r->filename );
        return AUTH_REQUIRED;
    }
    return OK;
}

sub authenticate {
    my ( $r, $user, $sent_pw ) = @_;
    return "empty user names and passwords disallowed"
      unless $user and $sent_pw;

    my $chronos = Chronos->new($r);
    my $dbh     = $chronos->dbh;
    $user    = $dbh->quote($user);
    $sent_pw = $dbh->quote($sent_pw);
    unless (
        $dbh->selectrow_array(
"SELECT user FROM user WHERE user = $user AND password = PASSWORD($sent_pw)"
        )
      )
    {
        return "user $user: not authentified";
    }
    return '';
}

1;

# vim: set et ts=4 sw=4:
