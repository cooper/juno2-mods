# Copyright (c) 2011, Mitchell Cooper

# provides LOLCAT command
# requires Acme::LOLCAT

# works exactly like PRIVMSG except translates your message to LOLCAT.
# unlike privmsg, it boings a PRIVMSG back to the client who sent it.
# it only works in channels.

package module::LOLCAT;

use warnings;
use strict;

use Acme::LOLCAT;

use API::Module;
use API::Command;
use utils qw[cut_to_limit col];

register_module('LOLCAT', 0.1, 'SPEEK LIEK A LOLCATZ', \&init, sub { return 1 });

sub init {
    register_command('lolcat', 'SPEEK LIEK A LOLCATZ', \&handle_lolcat, { params => 2 }) or return;
    return 1
}

sub handle_lolcat {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    my $msg = translate(col((split q. ., $data, 3)[2]));

    # make sure the message is at least 1 character
    $msg = cut_to_limit('msg', $msg);
    if (!length $msg) {
        $user->numeric(412);
        return
    }

    my $channel = channel::chanexists($args[1]);
    if ($channel) {
        $channel->privmsgnotice($user, 'PRIVMSG', $msg);
        $user->recvprivmsg($user->fullcloak, $channel->name, $msg, 'PRIVMSG');
        return 1
    }

    # no such channel
    $user->numeric(403.1, $args[1]);
    return

}

1
