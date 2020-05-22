#!/usr/bin/perl
#
# DW::Controller::Support::Index
#
# This controller is for the Support Index page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Help;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use Data::Dumper;

DW::Routing->register_string('/support/help', \&help_handler, app => 1);

sub help_handler {
    my $r = DW::Request->get;

    my ($ok, $rv) = controller(anonymous => 1);
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $POST = $r->post_args;
    my $GET = $r->get_args;

    my $vars = {};

    my $sth;

    LJ::Support::init_remote($remote) if $remote;
    my $cats = LJ::Support::load_cats();
    my $state = $POST->{'state'};
    $state = 'open' unless $state && $state =~ /^(?:open|closed|green|youreplied)$/;

    my $filtercat = $POST->{'cat'};
    $vars->{state} = $state;
    $vars->{filtercat} = $filtercat;

    my @support_log;
    # if we have a cat to filter to and we have abstracts for it
    my $rct = 0;
    #TODO: cache this.
    my $dbr = LJ::get_db_reader();
    $sth = $dbr->prepare("SELECT s.* FROM support s WHERE (s.state='open' " .
        "OR (s.state='closed' AND s.timeclosed>UNIX_TIMESTAMP()-(3600*168)))");
    $sth->execute;
    push @support_log, $_ while $_ = $sth->fetchrow_hashref();
    $rct = scalar(@support_log);
    $vars->{rct} = $rct;

    my %spids_seen;
    if ($remote) {
        $sth = $dbr->prepare("SELECT s.spid FROM support s, support_youreplied yr " .
            "WHERE yr.userid=$remote->{'userid'} AND s.spid=yr.spid " .
            "AND (s.state='open' OR (s.state='closed' AND s.timeclosed>UNIX_TIMESTAMP()-(3600*168)))");


        # For the You Replied filter, we might be getting some rows multiple times (when
        # multiple log rows exist for $remote), which is still better than using DISTINCT
        # in the query which uses a temporary table, so ensure uniqueness here.
        while (my $sprow = $sth->fetchrow_hashref) {
            next if $spids_seen{$sprow->{'spid'}};
            $spids_seen{$sprow->{'spid'}} = 1;
        }
    }
    my $sort = lc $POST->{sort} || '';
    $sort = 'date' unless grep {$_ eq $sort} qw(id summary area recent);

      my $can_view_nonpublic_modtime = $remote && ($remote->has_priv('supportviewinternal') || $remote->has_priv('supporthelp'));
    my $time_active = sub {

        # timemodified is updated when ICs/screened answers are made, so first check priv
        return $_[0]->{timemodified}
            if $can_view_nonpublic_modtime && $_[0]->{timemodified};

        my $touched = $_[0]->{timetouched};
        my $lasthelp = $_[0]->{timelasthelp};

        return $lasthelp > $touched ? $lasthelp : $touched;
    };

    my @states = ("open", LJ::Lang::ml('/support/help.tt.state.open'),
        "closed", LJ::Lang::ml('/support/help.tt.state.closed'),
        "green", LJ::Lang::ml('/support/help.tt.state.green'));
    if ($remote) {
        push @states, ("youreplied", LJ::Lang::ml('/support/help.tt.statr.youreplied'));
    }
    my @filter_cats;
    foreach my $cat (LJ::Support::filter_cats($remote, $cats)) {
        push @filter_cats, $cat->{catkey}, $cat->{catname};
    }
    if ($remote && $remote->has_priv("supportread")) {
        unshift @filter_cats, '_nonpublic', '(Private)', '_nonnprivate', '(Public)';
    }
    unshift @filter_cats, "all", LJ::Lang::ml('/support/help.tt.cat.all');

    $vars->{states} = \@states;
    $vars->{sort} = $sort;
    $vars->{filter_cats} = \@filter_cats;

    my $gct = 0;
    my $snhct = 0;
    my $aacct = 0;
    my $can_close_any = 0;

    my @request_table;
    foreach my $sp (@support_log) {
        my $request;
        LJ::Support::fill_request_with_cat($sp, $cats);
        next unless (LJ::Support::can_read($sp, $remote));

        my $status = $sp->{'state'} eq "closed" ? "closed" :
        LJ::Support::open_request_status($sp->{'timetouched'},
            $sp->{'timelasthelp'});

        my $can_close = LJ::Support::can_close_cat($sp, $remote);
        $can_close_any = 1 if $can_close;


        my $color;
        if ($status eq "open") {
            $color = "green";
        }
        elsif ($status eq "closed") {
            $color = "red";
        }
        elsif ($status eq "awaiting close") {
            $status = "answered<br/>awaiting close";
            $color = "yellow";
        }
        elsif ($status eq "still needs help") {
            $status = "answered<br/><strong>still needs help</strong>";
            $color = "green";
        }

        next if $state eq "green" && $color ne "green";

        # fix up the subject if needed
        eval {
            if ($sp->{'subject'} =~ /^=\?(utf-8)?/i) {
                my @subj_data;
                require MIME::Words;
                @subj_data = MIME::Words::decode_mimewords($sp->{'subject'});
                if (scalar(@subj_data)) {
                    if (!$1) {
                        $sp->{'subject'} = Unicode::MapUTF8::to_utf8({ -string => $subj_data[0][0], -charset => $subj_data[0][1] });
                    }
                    else {
                        $sp->{'subject'} = $subj_data[0][0];
                    }
                }
            }
        };

        # other content for this request
        my $secs = sub {return time() - $_[0]};
        my $time_display = sub {
            return LJ::mysql_time($_[0]) if $GET->{rawdates};
            return LJ::ago_text($secs->($_[0]) || 1);
        };

        my $replied = $spids_seen{$sp->{'spid'}} ? "replied" : "";
        $request = {
            subject        => $sp->{'subject'},
            cat            => $sp->{_cat}->{'catname'},
            status         => $status,
            color          => $color,
            id             => $sp->{spid},
            age            => $sp->{timecreate},
            age_text       => $time_display->($sp->{timecreate}),
            untouched      => $time_active->($sp),
            untouched_text => $time_display->($time_active->($sp)),
            replied        => $replied,
            can_close      => $can_close

        };

        if ($_->{'timelasthelp'} > $_->{'timetouched'} + 5) {
            $aacct++;
        }
        elsif ($_->{'timelasthelp'} && $_->{'timetouched'} > $_->{'timelasthelp'} + 5) {
            $snhct++;
        }
        else {
            $gct++;
        }


        unless ($status eq "closed") {
            $request->{points} = LJ::Support::calc_points($sp, $secs->($sp->{timecreate}));
        }

        push @request_table, $request;

    }

    $vars->{gct} = $gct;
    $vars->{snhct} = $snhct;
    $vars->{aacct} = $aacct;
    $vars->{can_close_any} = $can_close_any;
    my @move_cats = map {$_->{'spcatid'}, "---> $_->{'catname'}"}
        LJ::Support::sorted_cats($cats);
    unshift @move_cats, '', '(no change)';
    $vars->{request_table} = \@request_table;
    $vars->{move_cats} = \@move_cats;

    return DW::Template->render_template('support/help.tt', $vars);

}

1;