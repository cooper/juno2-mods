#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# this module provides SYNC command - a simple way to grant users' access
# all at once as set by channel mode A.

package module::sync;

use warnings;
use strict;

use API::Module;
use API::Command;

# register the module
register_module('sync', 0.2, 'Sync channel access modes to the auto-access list.', \&init, sub { return 1 });

# initialization subroutine
sub init {

    # register the SYNC command
    register_command('sync', 'Sync channel access modes to the auto-access list.', \&sync, { params => 1 }) or return;

    return 1
}

# handle the SYNC command
sub sync {
    my $user = shift;
    my $name = (split /\s+/, shift)[1];
    my $channel = channel::chanexists($name);

    # make sure the channel exists
    if (!$channel) {
        $user->numeric(401, $name);
        return
    }

    # check for privs
    if ($channel->has($user, 'owner')) {

        # check each user for access
        $channel->doauto(user::lookupbyid($_)) foreach keys %{$channel->{users}};

        return 1
    }

    # permission denied
    else {
        $user->numeric(482, $channel->name, 'owner')
    }

    return
}

1
