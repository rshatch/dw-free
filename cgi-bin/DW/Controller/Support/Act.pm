package DW::Controller::Support::Act;
use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/act',    \&act_handler,    app => 1 );
DW::Routing->register_string( '/support/actmulti',    \&actmulti_handler,    app => 1 );

sub act_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $u   = $rv->{u};
    my $r   = $rv->{r};
    my $get = $r->get_args;

    my $vars = {};

     my $cmd = BML::get_query_string();
     if ($cmd =~ /^(\w+);(\d+);(\w{15})(?:;(\d+))?$/) {
         ($action, $spid, $authcode, $splid) = ($1, $2, $3, $4);
     }

    return error_ml('.improper.arguments') unless $action =~ /(?:touch|close|unlock|lock)/;
    $vars->{title} = "Request #$spid";

    LJ::Support::init_remote($remote);
    my $sp = LJ::Support::load_request($spid);

     if ($sp->{'authcode'} ne $authcode) {
         return error_ml('.invalid.authcode');
     }

    my $auth = LJ::Support::mini_auth($sp);

     if ($action eq "touch") {
         return error_ml('.request.locked')
             if LJ::Support::is_locked($sp);

         LJ::Support::touch_request($spid)
             or return error_ml('.touch.failed');

         return $r->redirect("$LJ::SITEROOT/support/see_request?id=$spid")
             if LJ::Support::can_close($sp, $remote);
         
         return DW::Template->render_template('support/act.tt', $vars);
     }
         
         if ($action eq 'lock') {
     return error_ml('.not.allowed.request')
         unless $remote && LJ::Support::can_lock($sp, $remote);
     return error_ml('.request.already.locked')
         if LJ::Support::is_locked($sp);

     # close this request and IC on it
     LJ::Support::lock($sp);
     LJ::Support::append_request($sp, {
         body => '(Locking request.)',
         remote => $remote,
         type => 'internal',
     });
     return success_ml('.request.has.been.locked', {"requestlink"=>"href='/support/see_request?id=$sp->{spid}'"});
 }

 if ($action eq 'unlock') {
     return error_ml('.request.already.unlock')
         unless $remote && LJ::Support::can_lock($sp, $remote);
     return error_ml('.request.not.locked')
         unless LJ::Support::is_locked($sp);

     # reopen this request and IC on it
     LJ::Support::unlock($sp);
     LJ::Support::append_request($sp, {
         body => '(Unlocking request.)',
         remote => $remote,
         type => 'internal',
     });
     return success_ml('.request.has.been.unlocked', {"requestlink"=>"href='/support/see_request?id=$sp->{spid}'"});
 }

 if ($action eq "close") {
     return error_ml('.request.cannot.close')
         unless LJ::Support::can_close($sp, $remote, $auth);

     if ($sp->{'state'} eq "open") {
         my $dbh = LJ::get_db_writer();
         $splid += 0;
         if ($splid) {
             $sth = $dbh->prepare("SELECT userid, timelogged, spid, type FROM supportlog WHERE splid=$splid");
             $sth->execute;
             my ($userid, $timelogged, $aspid, $type) = $sth->fetchrow_array;

             if ($aspid != $spid) {
                 return error_ml('.answer.you.credited');
             }

             ## can't credit yourself.
             if ($userid != $sp->{'requserid'} && $type eq "answer") {
                 my $cats = LJ::Support::load_cats($sp->{'spcatid'});
                 my $secold = $timelogged - $sp->{'timecreate'};
                 my $points = LJ::Support::calc_points($sp, $secold);
                 LJ::Support::set_points($spid, $userid, $points);
             }
         }
         $dbh->do("UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() WHERE spid=$spid");
     }

     my $remote = LJ::get_remote();
     if (LJ::Support::can_close_cat($sp, $remote)) {
         my $dbr = LJ::get_db_reader();
         my $catid = $sp->{'_cat'}->{'spcatid'};
         my $sql = "SELECT MIN(spid) FROM support WHERE spcatid=$catid AND state='open' AND timelasthelp>timetouched AND spid>$spid";
         my $sth = $dbr->prepare($sql);
         $sth->execute;
         my $next = $sth->fetchrow_array;
         if ($next) {
             return $r->redirect("$LJ::SITEROOT/support/see_request?id=$next");
         }
         else {
             $vars->{show_links} = 1;
             return DW::Template->render_template('support/closed.tt', $vars);
         }
     }
     $vars->{show_links} = 0;
     return DW::Template->render_template('support/closed.tt', $vars)
 }
    return;

}

sub actmulti_handler {
    my $r = DW::Request->get;

    my ($ok, $rv) = controller(form_auth => 1);
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $u = $rv->{u};
    my $r = $rv->{r};
    my $POST = $r->post_args;

    my $vars = {};

    return error_ml('error.invalidform') unless LJ::check_form_auth($POST->{lj_form_auth});

    my $spcatid = $POST->{spcatid};
    my $cats = LJ::Support::load_cats($spcatid);
    my $cat = $cats->{$spcatid};
    return error_ml('.cat.not.exist') unless $cat;

    # get ids of requests
    my @ids = map { $_+0 } grep { $POST->{"check_$_"} } split(':', $POST->{ids});
    return error_ml('.no.request') unless @ids;

    # just to be sane, limit it to 1000 requests
    @ids = splice @ids, 0, 1000 if scalar @ids > 1000;

    # what action are they trying to take?
    if ($POST->{'action:close'}) {
        my $can_close = 0;
        $can_close = 1 if $remote && $remote->has_priv( 'supportclose', $cat->{catkey} );
        $can_close = 1 if $cat->{public_read} && $remote && $remote->has_priv( 'supportclose', '' );
        return error_ml('.not.have.access') unless $can_close;

        # now close all of these requests
        my $dbh = LJ::get_db_writer();
        my $in = join ',', @ids;
        $dbh->do("UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() " .
                 "WHERE spid IN ($in) AND spcatid = ?", undef, $spcatid);

        # and now insert a log comment for all of these... note that we're not using
        # LJ::Support::append_request because that'd require us to load a bunch of requests
        # and then do a bunch of individual queries, and that sucks.
        my @stmts;
        foreach (@ids) {
            push @stmts, "($_, UNIX_TIMESTAMP(), 'internal', $remote->{userid}, " .
                         "'(Request closed as part of mass closure.)')";
        }
        my $sql = "INSERT INTO supportlog (spid, timelogged, type, userid, message) VALUES ";
        $sql .= join ',', @stmts;
        $dbh->do($sql);

        # return redirection back? or success message otherwise
        return BML::redirect( sprintf( $POST->{ret}, '' ) ) if $POST->{ret};
        return success_ml('.request.specified');
    } elsif ( $POST->{'action:closewithpoints'} ) {
        my $can_close = 0;
        $can_close = 1 if LJ::Support::can_close_cat( { _cat => $cat }, $remote );
        return error_ml('.not.have.access') unless $can_close;

        # let's implement a limit so that we don't overload
        # the DB and/or timeout
        my @filtered_ids = splice( @ids, 0, 50 );

        my $requests = LJ::Support::load_requests( \@filtered_ids );

        foreach my $sp ( @$requests ) {
            LJ::Support::close_request_with_points( $sp, $cat, $remote );
        }

        return $r->redirect( sprintf( $POST->{ret},
                                       '&mark=' . join( ',', @ids ) ) )
            if $POST->{ret};
        return success_ml('request.specified');
    } elsif ($POST->{'action:move'}) {
        return error_ml('.not.have.access.move.request')
            unless LJ::Support::can_perform_actions({ _cat => $cat }, $remote);

        my $newcat = $POST->{'changecat'} + 0;
        my $cats = LJ::Support::load_cats();
        return error_ml('.category.invalid') unless $cats->{$newcat};

        # now move all of these requests
        my $dbh = LJ::get_db_writer();
        my $in = join ',', @ids;
        $dbh->do("UPDATE support SET spcatid = ? WHERE spid IN ($in) AND spcatid = ?",
                 undef, $newcat, $spcatid);

        # now add movement notices
        my @stmts;
        foreach (@ids) {
            push @stmts, "($_, UNIX_TIMESTAMP(), 'internal', $remote->{userid}, " .
                         "'(Mass move from $cats->{$spcatid}->{catname} to $cats->{$newcat}->{catname}.)')";
        }
        my $sql = "INSERT INTO supportlog (spid, timelogged, type, userid, message) VALUES ";
        $sql .= join ',', @stmts;
        $dbh->do($sql);

        # done now
        return $r->redirect( sprintf( $POST->{ret}, '' ) ) if $POST->{ret};
        return success_ml('.request.moved');
    }
}
1;