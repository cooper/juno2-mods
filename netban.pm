#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# this module adds commands for Z-Lines and K-Lines.
# it requires DBD::SQLite.

# the datbase location is defined by netban:db.
# it is relative to the juno directory.

# the ZLINE and KLINE commands provide the zline and kline oper flags.

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
        utils::snotice('could not create netban database.');
        say 'could not create netban database.';
        return
    }

    # reload the bans each time the configuration is rehashed (as it usually clears them)
    register_event('rehash_done', \&load_bans);

    # load the stored bans
    load_bans();

    # register the commands
    register_command('kline', 'Ban or unban a user by their user@host mask.', \&handle_kline) or return;
    register_command('zline', 'Ban an IP or IP range.', \&handle_zline) or return;

    # success
    return 1
}

# create the tables
sub create_db {
    $dbh->do('CREATE TABLE IF NOT EXISTS kline (mask TEXT, setby TEXT, time INT, reason TEXT)') or return;
    $dbh->do('CREATE TABLE IF NOT EXISTS zline (ip TEXT, setby TEXT, time INT, resaon TEXT)') or return;
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
    say 'loading klines'
}

# handle ZLINE command
sub handle_zline {
}

# handle KLINE command
sub handle_kline {
}

1
