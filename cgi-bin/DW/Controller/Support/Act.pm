package DW::Controller::Support::Act;
use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/act',            \&act_handler,            app => 1 );
DW::Routing->register_string( '/support/actmulti',       \&actmulti_handler,       app => 1 );
DW::Routing->register_string( '/support/append_request', \&append_request_handler, app => 1 );

sub act_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $r      = $rv->{r};
    my ( $action, $spid, $authcode, $splid );
    my $vars = {};

    my $cmd = BML::get_query_string();
    if ( $cmd =~ /^(\w+);(\d+);(\w{15})(?:;(\d+))?$/ ) {
        ( $action, $spid, $authcode, $splid ) = ( $1, $2, $3, $4 );
    }

    return error_ml('.improper.arguments') unless $action =~ /(?:touch|close|unlock|lock)/;
    $vars->{title} = "Request #$spid";

    LJ::Support::init_remote($remote);
    my $sp = LJ::Support::load_request($spid);

    if ( $sp->{'authcode'} ne $authcode ) {
        return error_ml('.invalid.authcode');
    }

    my $auth = LJ::Support::mini_auth($sp);

    if ( $action eq "touch" ) {
        return error_ml('.request.locked')
            if LJ::Support::is_locked($sp);

        LJ::Support::touch_request($spid)
            or return error_ml('.touch.failed');

        return $r->redirect("$LJ::SITEROOT/support/see_request?id=$spid")
            if LJ::Support::can_close( $sp, $remote );

        return DW::Template->render_template( 'support/act.tt', $vars );
    }

    if ( $action eq 'lock' ) {
        return error_ml('.not.allowed.request')
            unless $remote && LJ::Support::can_lock( $sp, $remote );
        return error_ml('.request.already.locked')
            if LJ::Support::is_locked($sp);

        # close this request and IC on it
        LJ::Support::lock($sp);
        LJ::Support::append_request(
            $sp,
            {
                body   => '(Locking request.)',
                remote => $remote,
                type   => 'internal',
            }
        );
        return success_ml( '.request.has.been.locked',
            { "requestlink" => "href='/support/see_request?id=$sp->{spid}'" } );
    }

    if ( $action eq 'unlock' ) {
        return error_ml('.request.already.unlock')
            unless $remote && LJ::Support::can_lock( $sp, $remote );
        return error_ml('.request.not.locked')
            unless LJ::Support::is_locked($sp);

        # reopen this request and IC on it
        LJ::Support::unlock($sp);
        LJ::Support::append_request(
            $sp,
            {
                body   => '(Unlocking request.)',
                remote => $remote,
                type   => 'internal',
            }
        );
        return success_ml( '.request.has.been.unlocked',
            { "requestlink" => "href='/support/see_request?id=$sp->{spid}'" } );
    }

    if ( $action eq "close" ) {
        return error_ml('.request.cannot.close')
            unless LJ::Support::can_close( $sp, $remote, $auth );

        if ( $sp->{'state'} eq "open" ) {
            my $dbh = LJ::get_db_writer();
            $splid += 0;
            if ($splid) {
                my $sth = $dbh->prepare(
                    "SELECT userid, timelogged, spid, type FROM supportlog WHERE splid=$splid");
                $sth->execute;
                my ( $userid, $timelogged, $aspid, $type ) = $sth->fetchrow_array;

                if ( $aspid != $spid ) {
                    return error_ml('.answer.you.credited');
                }

                ## can't credit yourself.
                if ( $userid != $sp->{'requserid'} && $type eq "answer" ) {
                    my $cats   = LJ::Support::load_cats( $sp->{'spcatid'} );
                    my $secold = $timelogged - $sp->{'timecreate'};
                    my $points = LJ::Support::calc_points( $sp, $secold );
                    LJ::Support::set_points( $spid, $userid, $points );
                }
            }
            $dbh->do(
"UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() WHERE spid=$spid"
            );
        }

        if ( LJ::Support::can_close_cat( $sp, $remote ) ) {
            my $dbr   = LJ::get_db_reader();
            my $catid = $sp->{'_cat'}->{'spcatid'};
            my $sql =
"SELECT MIN(spid) FROM support WHERE spcatid=$catid AND state='open' AND timelasthelp>timetouched AND spid>$spid";
            my $sth = $dbr->prepare($sql);
            $sth->execute;
            my $next = $sth->fetchrow_array;
            if ($next) {
                return $r->redirect("$LJ::SITEROOT/support/see_request?id=$next");
            }
            else {
                $vars->{show_links} = 1;
                return DW::Template->render_template( 'support/closed.tt', $vars );
            }
        }
        $vars->{show_links} = 0;
        return DW::Template->render_template( 'support/closed.tt', $vars );
    }
    return;

}

sub actmulti_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $r      = $rv->{r};
    my $POST   = $r->post_args;

    return error_ml('error.invalidform') unless LJ::check_form_auth( $POST->{lj_form_auth} );

    my $spcatid = $POST->{spcatid};
    my $cats    = LJ::Support::load_cats($spcatid);
    my $cat     = $cats->{$spcatid};
    return error_ml('.cat.not.exist') unless $cat;

    # get ids of requests
    my @ids = map { $_ + 0 } grep { $POST->{"check_$_"} } split( ':', $POST->{ids} );
    return error_ml('.no.request') unless @ids;

    # just to be sane, limit it to 1000 requests
    @ids = splice @ids, 0, 1000 if scalar @ids > 1000;

    # what action are they trying to take?
    if ( $POST->{'action:close'} ) {
        my $can_close = 0;
        $can_close = 1 if $remote && $remote->has_priv( 'supportclose', $cat->{catkey} );
        $can_close = 1 if $cat->{public_read} && $remote && $remote->has_priv( 'supportclose', '' );
        return error_ml('.not.have.access') unless $can_close;

        # now close all of these requests
        my $dbh = LJ::get_db_writer();
        my $in  = join ',', @ids;
        $dbh->do(
"UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() "
                . "WHERE spid IN ($in) AND spcatid = ?",
            undef, $spcatid
        );

        # and now insert a log comment for all of these... note that we're not using
        # LJ::Support::append_request because that'd require us to load a bunch of requests
        # and then do a bunch of individual queries, and that sucks.
        my @stmts;
        foreach (@ids) {
            push @stmts, "($_, UNIX_TIMESTAMP(), 'internal', $remote->{userid}, "
                . "'(Request closed as part of mass closure.)')";
        }
        my $sql = "INSERT INTO supportlog (spid, timelogged, type, userid, message) VALUES ";
        $sql .= join ',', @stmts;
        $dbh->do($sql);

        # return redirection back? or success message otherwise
        return BML::redirect( sprintf( $POST->{ret}, '' ) ) if $POST->{ret};
        return success_ml('.request.specified');
    }
    elsif ( $POST->{'action:closewithpoints'} ) {
        my $can_close = 0;
        $can_close = 1 if LJ::Support::can_close_cat( { _cat => $cat }, $remote );
        return error_ml('.not.have.access') unless $can_close;

        # let's implement a limit so that we don't overload
        # the DB and/or timeout
        my @filtered_ids = splice( @ids, 0, 50 );

        my $requests = LJ::Support::load_requests( \@filtered_ids );

        foreach my $sp (@$requests) {
            LJ::Support::close_request_with_points( $sp, $cat, $remote );
        }

        return $r->redirect( sprintf( $POST->{ret}, '&mark=' . join( ',', @ids ) ) )
            if $POST->{ret};
        return success_ml('request.specified');
    }
    elsif ( $POST->{'action:move'} ) {
        return error_ml('.not.have.access.move.request')
            unless LJ::Support::can_perform_actions( { _cat => $cat }, $remote );

        my $newcat = $POST->{'changecat'} + 0;
        my $cats   = LJ::Support::load_cats();
        return error_ml('.category.invalid') unless $cats->{$newcat};

        # now move all of these requests
        my $dbh = LJ::get_db_writer();
        my $in  = join ',', @ids;
        $dbh->do( "UPDATE support SET spcatid = ? WHERE spid IN ($in) AND spcatid = ?",
            undef, $newcat, $spcatid );

        # now add movement notices
        my @stmts;
        foreach (@ids) {
            push @stmts, "($_, UNIX_TIMESTAMP(), 'internal', $remote->{userid}, "
                . "'(Mass move from $cats->{$spcatid}->{catname} to $cats->{$newcat}->{catname}.)')";
        }
        my $sql = "INSERT INTO supportlog (spid, timelogged, type, userid, message) VALUES ";
        $sql .= join ',', @stmts;
        $dbh->do($sql);

        # done now
        return $r->redirect( sprintf( $POST->{ret}, '' ) ) if $POST->{ret};
        return success_ml('.request.moved');
    }
}

sub append_request_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( form_auth => 1, anonymous => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $POST   = $r->post_args;

    my $vars = {};

    return error_ml('.invalid.noid') unless $POST->{'spid'};
    my $spid = $POST->{'spid'} + 0;
    my $sp   = LJ::Support::load_request($spid);
    return error_ml('.unknown.request') unless $sp;

    LJ::Support::init_remote($remote);
    unless ( LJ::Support::can_append( $sp, $remote, $POST->{'auth'} ) || $remote ) {
        return "<?needlogin?>";
    }

    if ( $sp->{state} eq 'closed' ) {
        $vars->{state} = 'closed';
        return DW::Template->render_template( 'support/append_request.tt', $vars );
    }
    my $status = "";
    my $scat   = $sp->{_cat};
    my $catkey = $scat->{'catkey'};

    $POST->{'summary'} = LJ::trim( $POST->{'summary'} );
    return error_ml('.invalid.nosummary')
        if $POST->{'changesum'} && !$POST->{'summary'};
    ### links to show on success
    my $auth_arg = $POST->{'auth'} ? "&amp;auth=$POST->{'auth'}" : "";
    $vars->{successlinks} = LJ::Lang::ml(
        '.successlinks2',
        {
            'number' => $sp->{'spid'},
            'aopts1' => "href='$LJ::SITEROOT/support/see_request?id=$sp->{'spid'}$auth_arg'",
            'aopts2' => "href='$LJ::SITEROOT/support/help'",
            'aopts3' => "href='$LJ::SITEROOT/support/help?cat=$scat->{'catkey'}'",
            'aopts8' => "href='$LJ::SITEROOT/support/help?cat=$scat->{'catkey'}&amp;state=green'",
            'aopts4' => "href='$LJ::SITEROOT/support/see_request?id=$sp->{'spid'}&amp;find=prev'",
            'aopts5' => "href='$LJ::SITEROOT/support/see_request?id=$sp->{'spid'}&amp;find=next'",
            'aopts6' => "href='$LJ::SITEROOT/support/see_request?id=$sp->{'spid'}&amp;find=cprev'",
            'aopts7' => "href='$LJ::SITEROOT/support/see_request?id=$sp->{'spid'}&amp;find=cnext'",
        }
    );

    ### insert record
    my $faqid = $POST->{'faqid'} + 0;

    my %answer_types = LJ::Support::get_answer_types( $sp, $remote, $POST->{'auth'} );

    my $userfacing_action_type = $POST->{replytype};
    my $internal_action_type   = $POST->{internaltype};
    return error_ml('.invalid.type')
        if !$userfacing_action_type
        && !$internal_action_type    # we need at least one of these to be defined
        || $userfacing_action_type && !defined $answer_types{$userfacing_action_type}
        || $internal_action_type   && !defined $answer_types{$internal_action_type};

    ## can we do the action we want?
    return error_ml('.internal.approve')
        if $POST->{'approveans'}
        && ( $internal_action_type ne "internal" || !LJ::Support::can_help( $sp, $remote ) );

    return error_ml('.internal.changecat')
        if $POST->{'changecat'}
        && ( $internal_action_type ne "internal"
        || !LJ::Support::can_perform_actions( $sp, $remote ) );

    return error_ml('.internal.touch')
        if ( $POST->{'touch'} || $POST->{'untouch'} )
        && ( $internal_action_type ne "internal"
        || !LJ::Support::can_perform_actions( $sp, $remote ) );

    return error_ml('.internal.changesum')
        if $POST->{'changesum'}
        && ( $internal_action_type ne "internal"
        || !LJ::Support::can_change_summary( $sp, $remote ) );

    return error_ml('.invalid.blank')
        if $POST->{reply} !~ /\S/ && $POST->{internal} !~ /\S/    # no text AND
        && !$POST->{'approveans'}
        && !$POST->{'changecat'}
        && !$POST->{'changesum'}                                  # no action taken
        && !$POST->{'touch'} && !$POST->{'untouch'} && !$POST->{'bounce_email'};

    # Load up vars for approvals
    my $res;
    my $splid;
    if ( $POST->{'approveans'} ) {
        $splid = $POST->{'approveans'} + 0;
        $res   = LJ::Support::load_response($splid);

        return error_ml('.invalid.noanswer')
            if ( $res->{'spid'} == $spid && $res->{'type'} ne "screened" );

        return LJ::bad_input('Invalid type to approve screened response as.')
            if ( ( $POST->{'approveas'} ne 'answer' ) && ( $POST->{'approveas'} ne 'comment' ) );
    }

    # Load up vars for category moves
    my $newcat;
    my $cats;
    if ( $POST->{'changecat'} ) {
        $newcat = $POST->{'changecat'} + 0;
        $cats   = LJ::Support::load_cats($newcat);

        return error_ml('.invalid.notcat')
            unless ( $cats->{$newcat} );
    }

    # get dbh now, it's always needed
    my $dbh = LJ::get_db_writer();

    ## touch/untouch request
    if ( $POST->{'touch'} ) {
        $dbh->do(
"UPDATE support SET state='open', timetouched=UNIX_TIMESTAMP(), timeclosed=0, timemodified=UNIX_TIMESTAMP() WHERE spid=$spid"
        );
        $status .= "(Inserting request into queue)\n\n";
    }
    if ( $POST->{'untouch'} ) {
        $dbh->do(
"UPDATE support SET timelasthelp=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() WHERE spid=$spid"
        );
        $status .= "(Removing request from queue)\n\n";
    }

    ## bounce request to email
    if ( $internal_action_type eq 'bounce' ) {

        return error_ml('.bounce.noemail')
            unless $POST->{'bounce_email'};

        return error_ml('.bounce.notauth')
            unless LJ::Support::can_bounce( $sp, $remote );

        # check given emails using LJ::check_email
        my @form_emails = split( /\s*,\s*/, $POST->{'bounce_email'} );

        return error_ml('.bounce.toomany')
            if @form_emails > 5;

        my @emails;    # error-checked, good emails
        my @email_errors;
        foreach my $email (@form_emails) {

            # see if it's a valid username
            unless ( $email =~ /\@/ ) {
                my $eu = LJ::load_user($email);    # $email is a username
                $email = $eu->email_raw if $eu;
            }

            LJ::check_email( $email, \@email_errors, $POST );
            @email_errors = map { "<strong>$email:</strong> $_" } @email_errors;
            return error_ml(@email_errors) if @email_errors;

            # push onto our list of valid emails
            push @emails, $email;
        }

        # append notice that this message was bounced
        $splid = LJ::Support::append_request(
            $sp,
            {
                'body' => "(Bouncing mail to '"
                    . join( ', ', @emails )
                    . "' and closing)\n\n"
                    . $POST->{'body'},
                'posterid' => $remote,
                'type'     => 'internal',
                'uniq'     => $r->note('uniq'),
                'remote'   => $remote,
            }
        );

        # bounce original request to email
        my $message = $dbh->selectrow_array(
            "SELECT message FROM supportlog " . "WHERE spid=? ORDER BY splid LIMIT 1",
            undef, $sp->{'spid'} );

        LJ::send_mail(
            {
                'to'       => join( ", ", @emails ),
                'from'     => $sp->{'reqemail'},
                'fromname' => $sp->{'reqname'},
                'headers'  => { 'X-Bounced-By' => $remote->{'user'} },
                'subject'  => "$sp->{'subject'} (support request #$sp->{'spid'})",
                'body'     => "$message\n\n$LJ::SITEROOT/support/see_request?id=$sp->{'spid'}",
            }
        );

        # close request, nobody gets credited
        $dbh->do(
"UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(), timemodified=UNIX_TIMESTAMP() WHERE spid=?",
            undef, $sp->{'spid'}
        );
        $vars->{addresslist} = "<strong>" . join( ', ', @emails ) . "</strong>";
        $vars->{state}       = 'bounce';
        return DW::Template->render_template( 'support/append_request.tt', $vars );
    }

    $dbh->do(
"UPDATE support SET state='open', timetouched=UNIX_TIMESTAMP(), timeclosed=0, timemodified=UNIX_TIMESTAMP() WHERE spid=$spid"
    ) if LJ::Support::is_poster( $sp, $remote, $POST->{'auth'} );

    ## change category
    if ( $POST->{'changecat'} ) {

        # $newcat, $cats defined above
        $dbh->do("UPDATE support SET spcatid=$newcat WHERE spid=$spid");
        $status .= "Changing from $catkey => $cats->{$newcat}->{'catkey'}\n\n";
        $sp->{'spcatid'} = $newcat;    # update category so IC e-mail goes to right place

        LJ::Hooks::run_hook(
            "support_changecat_extra_actions",
            spid   => $spid,
            catkey => $cats->{$newcat}->{catkey}
        );
    }

    ## approving a screened response
    if ( $POST->{'approveans'} ) {

        # $res, $splid defined above
        # approve
        my $qtype = $dbh->quote( $POST->{'approveas'} );
        $dbh->do("UPDATE supportlog SET type=$qtype WHERE splid=$splid");
        $status .= "(Approving $POST->{'approveas'} \#$splid)\n\n";

        LJ::Support::mail_response_to_user( $sp, $splid );
    }

    ## change summary
    if ( $POST->{'changesum'} ) {
        $POST->{'summary'} =~ s/[\n\r]//g;
        my $qnewsub = $dbh->quote( $POST->{'summary'} );
        $dbh->do("UPDATE support SET subject=$qnewsub WHERE spid=$spid");
        $status .= "Changing subject from \"$sp->{'subject'}\" to \"$POST->{'summary'}\".\n\n";
    }

    # user-facing
    if ( $POST->{reply} ) {
        $splid = LJ::Support::append_request(
            $sp,
            {
                'body'   => $POST->{reply},
                'type'   => $userfacing_action_type,
                'faqid'  => $faqid,
                'uniq'   => $r->note('uniq'),
                'remote' => $remote
            }
        );

        LJ::Support::mail_response_to_user( $sp, $splid )
            unless LJ::Support::is_poster( $sp, $remote, $POST->{'auth'} );
    }

    # then any internal status changes
    if ( $status || $POST->{internal} ) {
        $splid = LJ::Support::append_request(
            $sp,
            {
                'body'   => $status . $POST->{internal},
                'type'   => $internal_action_type,
                'uniq'   => $r->note('uniq'),
                'remote' => $remote
            }
        );

        LJ::Support::mail_response_to_user( $sp, $splid )
            unless LJ::Support::is_poster( $sp, $remote, $POST->{'auth'} );
    }

    return DW::Template->render_template( 'support/append_request.tt', $vars );

}
1;
