#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# this module adds commands for D-Lines and K-Lines.
# it requires DBD::SQLite.

# the datbase location is defined by netban:db.
# it is relative to the juno directory.

# the DLINE and KLINE commands provide the dline and kline oper flags.
# users with these flags can also use UNDLINE and UNKLINE.

# this module also provides the LISTKLINES and LISTDLINES commands.
# they display a list of bans that is easier to read than STATS.
# these commands require the kline and dline flags as well.

# this module requires juno 1.0.6 and above.

package module::netban;


use warnings;
use strict;
use feature qw[say switch];

use DBI;

use API::Module;
use API::Command;
use API::Event;
use API::Loop;
use utils qw[conf snotice col time2seconds add_commas hostmatch];

my $dbh;

# register to API::Module
register_module('netban', 0.1, 'Command interface to D-Line and K-Line.', \&init, sub { return 1 });

sub init {

    # connect to SQLite
    if (!&connect_db) {
        snotice('could not connect to SQLite');
        say 'could not connect to SQLite';
        return
    }

    # create the table if it does not exist.
    if (!&create_db) {
        snotice('could not create netban database.');
        say 'could not create netban database.';
        return
    }

    # reload the bans each time the configuration is rehashed (as it usually clears them)
    register_event('rehash_done', \&load_bans);

    # register the loop that removes expired bans
    register_loop('expirecheck', \&expire_bans) or return;

    # load the stored bans
    load_bans();

    # register the commands

    register_command('kline', 'Ban a user by their user@host mask.', \&handle_kline, {
        params => 3,
        flag => 'kline'
    }) or return;

    register_command('dline', 'Ban an IP or IP range.', \&handle_dline, {
        params => 3,
        flag => 'dline'
    }) or return;

    register_command('unkline', 'Remove a user@host ban.', \&handle_unkline, {
        params => 1,
        flag => 'kline'
    }) or return;

    register_command('undline', 'Unban an IP or IP range.', \&handle_undline, {
        params => 1,
        flag => 'dline'
    }) or return;

    register_command('listklines', 'A K-Line list that is easier to read than STATS.', \&handle_listklines, {
        flag => 'kline'
    }) or return;

    register_command('listdlines', 'A D-Line list that is easier to read than STATS.', \&handle_listdlines, {
        flag => 'dline'
    }) or return;

    # success
    return 1
}

# handle KLINE command
sub handle_kline {

    my ($user, @args) = (shift, (split /\s+/, shift));
    shift @args;
    my ($mask, $gtime) = (lc shift @args, lc shift @args);

    # strip possible :
    my $reason = col(join ' ', @args);

    # make sure it doesn't exist already.
    if (!exists $main::kline{$mask}) {


        # validate the mask
        if ($mask !~ m/(.+)\@(.+)/) {
            $user->snt('kline', "\2$mask\2 is not a valid mask.");
            return
        }

        my $time = 0;

        # see if the time is valid
        if ($gtime) {
            $time = time2seconds($gtime);
            if (!defined $time) {
                $user->snt('kline', "invalid ban time: $gtime");
                return
            }
        }

        # otherwise it's a permanent ban.

        if (add_kline($mask, $user->fullhost, $time, time, $reason)) {
            $user->snt('kline', 'k-line added successfully.');
            snotice("$$user{nick} added a k-line for \2$mask\2 to expire in \2$gtime\2 (".add_commas($time)." seconds) [$reason]");
        }

        else {
            $user->snt('kline', 'could not write k-line to database.');
            return
        }

    }

    # it exists already
    else {
        $user->snt('kline', 'there is already a kline of that mask.');
        return
    }


    # check users for kline
    return &kline_check

}

# handle DLINE command
sub handle_dline {

    my ($user, @args) = (shift, (split /\s+/, shift));
    shift @args;
    my ($ip, $gtime) = (lc shift @args, lc shift @args);

    # strip possible :
    my $reason = col(join ' ', @args);

    # make sure it doesn't exist already.
    if (!exists $main::dline{$ip}) {


        # validate the ip
        # the regex for this is ridiculous. I give up.
        if ($ip !~ m/(\.|:)/) {
            $user->snt('dline', "\2$ip\2 is not a valid IP address.");
            return
        }

        my $time = 0;

        # see if the time is valid
        if ($gtime) {
            $time = time2seconds($gtime);
            if (!defined $time) {
                $user->snt('dline', "invalid ban time: $gtime");
                return
            }
        }

        # otherwise it's a permanent ban.

        if (add_dline($ip, $user->fullhost, $time, time, $reason)) {
            $user->snt('dline', 'k-line added successfully.');
            snotice("$$user{nick} added a d-line for \2$ip\2 to expire in \2$gtime\2 (".add_commas($time)." seconds) [$reason]");
        }

        else {
            $user->snt('dline', 'could not write d-line to database.');
            return
        }

    }

    # it exists already
    else {
        $user->snt('dline', 'there is already a dline of that IP.');
        return
    }


    # check users for dline
    return &dline_check

}

# handle UNDLINE command
sub handle_undline {
    my ($user, $ip) = (shift, (split /\s+/, shift)[1]);

    # make sure it exists
    if (exists $main::dline{$ip}) {
        $user->snt('undline', 'd-line removed.');
        snotice("$$user{nick} removed d-line on \2$ip\2 [$main::dline{$ip}{reason}]");
        return delete_dline($ip)
    }

    # no such kline
    else {
        $user->snt('undline', "\2$ip\2 is not a banned IP. (they're case-sensitive.)");
        return
    }

}

# handle UNKLINE command
sub handle_unkline {
    my ($user, $mask) = (shift, (split /\s+/, shift)[1]);

    # make sure it exists
    if (exists $main::kline{$mask}) {
        $user->snt('unkline', 'k-line removed.');
        snotice("$$user{nick} removed k-line on \2$mask\2 [$main::kline{$mask}{reason}]");
        return delete_kline($mask)
    }

    # no such kline
    else {
        $user->snt('unkline', "\2$mask\2 is not a banned mask. (they're case-sensitive.)");
        return
    }

}

# handle LISTKLINES command
sub handle_listklines {
    my $user = shift;
    my ($m, $t, $s, $e) = (4, 9, 8, 9);
    $user->servernotice('*** K-Line list');

    # fetch the width of the sections
    while (my ($mask, $kl) = each %main::kline) {
        $m = length $mask if length $mask > $m;
        next unless $kl->{time};
        my $time = length POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $kl->{time});
        $t = $time if $time > $t;
        $s = length((split '!', $kl->{setby})[0]) if length((split '!', $kl->{setby})[0]) > $s;
        my $etime = length POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $kl->{expiretime});
        $e = $etime if $etime > $e;
    }

    # extra space to make it easier to read
    $m++; $t++; $s++; $e++;

    # section bar
    $user->servernotice(sprintf "%-${m}s %-${t}s %-${s}s %-${e}s %s", 'mask', 'time set', 'set by', 'expires', 'reason');
    $user->servernotice(sprintf "%-${m}s %-${t}s %-${s}s %-${e}s %s", qw[---- -------- ------ ------- ------]);

    # send the klines
    while (my ($mask, $kl) = each %main::kline) {
        $user->servernotice(sprintf "\2%-${m}s\2 %-${t}s %-${s}s %-${e}s %s",
            $mask,
            $kl->{time} ? POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $kl->{time}) : 'permanent',
            $kl->{setby} ? (split '!', $kl->{setby})[0] : '<config>',
            $kl->{expiretime} ? POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $kl->{expiretime}) : 'permanent',
            $kl->{reason}
        );
    }

    $user->servernotice('*** End of K-Line list.');
    return 1
}

# handle LISTDLINES command
sub handle_listdlines {
    my $user = shift;
    my ($m, $t, $s, $e) = (2, 9, 8, 9);
    $user->servernotice('*** D-Line list');

    # fetch the width of the sections
    while (my ($ip, $dl) = each %main::dline) {
        $m = length $ip if length $ip > $m;
        next unless $dl->{time};
        my $time = length POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $dl->{time});
        $t = $time if $time > $t;
        $s = length((split '!', $dl->{setby})[0]) if length((split '!', $dl->{setby})[0]) > $s;
        my $etime = length POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $dl->{expiretime});
        $e = $etime if $etime > $e;
    }

    # extra space to make it easier to read
    $m++; $t++; $s++; $e++;

    # section bar
    $user->servernotice(sprintf "%-${m}s %-${t}s %-${s}s %-${e}s %s", 'IP', 'time set', 'set by', 'expires', 'reason');
    $user->servernotice(sprintf "%-${m}s %-${t}s %-${s}s %-${e}s %s", qw[-- -------- ------ ------- ------]);

    # send the dlines
    while (my ($ip, $dl) = each %main::dline) {
        $user->servernotice(sprintf "\2%-${m}s\2 %-${t}s %-${s}s %-${e}s %s",
            $ip,
            $dl->{time} ? POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $dl->{time}) : 'permanent',
            $dl->{setby} ? (split '!', $dl->{setby})[0] : '<config>',
            $dl->{expiretime} ? POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime $dl->{expiretime}) : 'permanent',
            $dl->{reason}
        );
    }

    $user->servernotice('*** End of D-Line list.');
    return 1
}

# create the tables
sub create_db {
    $dbh->do('CREATE TABLE IF NOT EXISTS kline (mask TEXT, setby TEXT, time INT, expiretime INT, reason TEXT)') or return;
    $dbh->do('CREATE TABLE IF NOT EXISTS dline (ip TEXT, setby TEXT, time INT, expiretime INT, reason TEXT)') or return;
    return 1
}


# connect to SQLite
sub connect_db {
    my $dbfile = conf qw/netban db/;
    return unless $dbfile;
    $dbfile = $main::DIR.q[/].$dbfile;
    $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", q.., q..) or return;
    return 1
}

# load the stored klines
sub load_bans {

    # klines
    my $sth = $dbh->prepare('SELECT * FROM kline');
    $sth->execute;
    while (my $ref = $sth->fetchrow_hashref) {
        $main::kline{delete $ref->{mask}} = $ref
    }

    my $sth2 = $dbh->prepare('SELECT * FROM dline');
    $sth2->execute;
    while (my $ref = $sth2->fetchrow_hashref) {
        $main::dline{delete $ref->{ip}} = $ref
    }

    # check each user for a ban
    kline_check();
    dline_check();

    return 1
}

# add a K-Line
sub add_kline {
    my ($mask, $setby, $seconds, $currenttime, $reason) = @_;

    my $expiretime = $currenttime + $seconds;

    # insert into db
    $dbh->do('INSERT INTO kline VALUES (?, ?, ?, ?, ?)', undef, $mask, $setby, $currenttime, $expiretime, $reason) or return;

    # add to kline list
    $main::kline{$mask} = {
        setby => $setby,
        expiretime => $expiretime,
        reason => $reason,
        time => $currenttime
    };

    # success
    return 1

}

# add a D-Line
sub add_dline {
    my ($ip, $setby, $seconds, $currenttime, $reason) = @_;

    my $expiretime = $currenttime + $seconds;

    # insert into db
    $dbh->do('INSERT INTO dline VALUES (?, ?, ?, ?, ?)', undef, $ip, $setby, $currenttime, $expiretime, $reason) or return;

    # add to kline list
    $main::dline{$ip} = {
        setby => $setby,
        expiretime => $expiretime,
        reason => $reason,
        time => $currenttime
    };

    # success
    return 1

}

# delete a KLINE by mask
sub delete_kline {
    my $mask = shift;
    if (exists $main::kline{$mask}) {
        $dbh->do('DELETE FROM kline WHERE mask = ?', undef, $mask) or return;
        return delete $main::kline{$mask}
    }

    # no such kline
    else {
        return
    }

    return 1
}

# delete a DLINE by IP
sub delete_dline {
    my $ip = shift;
    if (exists $main::dline{$ip}) {
        $dbh->do('DELETE FROM dline WHERE ip = ?', undef, $ip) or return;
        return delete $main::dline{$ip}
    }

    # no such dline
    else {
        return
    }

    return 1
}

# check all users for a K-Line
sub kline_check {
    $_->checkkline foreach values %user::connection;
    return 1
}

# check all users for a D-Line
sub dline_check {
    foreach my $user (values %user::connection) {
        foreach (keys %main::dline) {

            # found a match!
            $user->quit('D-Lined: '.$main::dline{$_}{'reason'},
                undef,
                'D-Lined'.((conf qw/main showdline/) ? q(: ).$main::dline{$_}{'reason'} : q..)
            ) if (hostmatch($user->{'ip'}, $_))

        }
    }
    return 1
}

# remove expired bans
sub expire_bans {

    # check k-lines
    while (my ($mask, $kl) = each %main::kline) {

        # either a config kline or a permanent kline
        next unless $kl->{expiretime};

        # check if the time is up
        if ($kl->{expiretime} - time <= 0) {
            delete_kline($mask);
            snotice("expired kline: \2$mask\2 [$$kl{reason}]")
        }

    }

    # check d-lines
    while (my ($ip, $dl) = each %main::dline) {

        # either a config kline or a permanent dline
        next unless $dl->{expiretime};

        # check if the time is up
        if ($dl->{expiretime} - time <= 0) {
            delete_dline($ip);
            snotice("expired dline: \2$ip\2 [$$dl{reason}]")
        }

    }

    return 1
}

1
