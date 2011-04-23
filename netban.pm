#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# this module adds commands for Z-Lines and K-Lines.
# it requires DBD::SQLite.

# the datbase location is defined by netban:db.
# it is relative to the juno directory.

# the ZLINE and KLINE commands provide the zline and kline oper flags.
# the 

package module::netban;


use warnings;
use strict;
use feature 'say';

use DBI;

use API::Module;
use API::Command;
use API::Event;
use utils qw[conf snotice];

my $dbh;

# register to API::Module
register_module('netban', 'unfinished', 'Command interface to Z-Line and K-Line.', \&init, sub { return 1 });

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

    # load the stored bans
    load_bans();

    # register the commands 
    register_command('kline', 'Ban a user by their user@host mask.', \&handle_kline) or return;
    register_command('zline', 'Ban an IP or IP range.', \&handle_zline) or return;
    register_command('unkline', 'Remove a user@host ban.', \&handle_unkline) or return;
    register_command('unzline', 'Unban an IP or IP range.', \&handle_unzline) or return;

    # success
    return 1
}

# create the tables
sub create_db {
    $dbh->do('CREATE TABLE IF NOT EXISTS kline (mask TEXT, setby TEXT, time INT, reason TEXT)') or return;
    $dbh->do('CREATE TABLE IF NOT EXISTS zline (ip TEXT, setby TEXT, time INT, reason TEXT)') or return;
    return 1
}


# connect to SQLite
sub connect_db {
    my $dbfile = conf qw/netban db/;
    return unless $dbfile;
    $dbfile = $main::DIR.'/'.$dbfile;
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

    my $sth2 = $dbh->prepare('SELECT * FROM zline');
    $sth2->execute;
    while (my $ref = $sth2->fetchrow_hashref) {
        $main::zline{delete $ref->{ip}} = $ref
    }

    # check each user for a ban
    kline_check();
    zline_check();

    return 1
}

# handle ZLINE command
sub handle_zline {
}

# handle KLINE command
sub handle_kline {
}

# handle UNZLINE command
sub handle_unzline {
}

# handle UNKLINE command
sub handle_unkline {
}

# check all users for a K-Line
sub kline_check {
    $_->checkkline foreach values %user::connection;
    return 1
}

# check all users for a Z-Line
sub zline_check {
    foreach my $user (values %user::connection) {
        foreach (keys %main::zline) {

            # found a match!
            $user->quit('Z-Lined: '.$main::zline{$_}{'reason'},
                undef,
                'Z-Lined'.((conf qw/main showzline/) ? q(: ).$main::zline{$_}{'reason'} : q..)
            ) if (hostmatch($user->{'ip'}, $_));

        }
    }
    return 1
}
1
