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

package DW::Controller::Support::Index;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/index',         \&index_handler,        app => 1 );
DW::Routing->register_string( '/support/changenotify',  \&changenotify_handler, app => 1 );
DW::Routing->register_string( '/support/stock_answers', \&stock_answer_handler, app => 1 );

sub index_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $user;
    my $user_url;

    my $vars = {};

    my $currentproblems = LJ::load_include("support-currentproblems");
    LJ::CleanHTML::clean_event( \$currentproblems, {} );
    $vars->{currentproblems} = $currentproblems;

    # Get remote username and journal URL, or example user's username and journal URL
    if ($remote) {
        $user     = $remote->user;
        $user_url = $remote->journal_base;
    }
    else {
        my $u = LJ::load_user($LJ::EXAMPLE_USER_ACCOUNT);
        $user     = $u ? $u->user         : "<b>[Unknown or undefined example username]</b>";
        $user_url = $u ? $u->journal_base : "<b>[Unknown or undefined example username]</b>";
    }

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare(
        "SELECT statkey FROM stats WHERE statcat='pop_faq' ORDER BY statval DESC LIMIT 10");
    $sth->execute;

    while ( my $f = $sth->fetchrow_hashref ) {
        $f = LJ::Faq->load( $f->{statkey}, lang => LJ::Lang::get_effective_lang() );
        $f->render_in_place( { user => $user, url => $user_url } );
        my $q = $f->question_html;
        push @{ $vars->{f} },
            {
            q     => $q,
            faqid => $f->faqid
            };
    }

    return DW::Template->render_template( 'support/index.tt', $vars );

}

sub changenotify_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $FORM   = $r->post_args;
    my $mode   = $FORM->{'mode'} || "modify";
    my $vars   = {};

    LJ::Support::init_remote($remote);
    my $cats        = LJ::Support::load_cats();
    my @filter_cats = LJ::Support::filter_cats( $remote, $cats );
    if ( $mode eq "modify" ) {
        my %notify;
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare(
            "SELECT spcatid, level FROM supportnotify WHERE userid=$remote->{'userid'}");
        $sth->execute;
        while ( my ( $spcatid, $level ) = $sth->fetchrow_array ) {
            ## if user used to be able to read a category, subscribed, then lost
            ## privs, this ensures any future save will turn off things they
            ## don't have access to:
            if ( LJ::Support::can_read_cat( $cats->{$spcatid}, $remote ) ) {
                $notify{$spcatid} = $level;
            }
        }

        my %valname = (
            "off" => LJ::Lang::ml('.option.off'),
            "new" => LJ::Lang::ml('.option.new'),
            "all" => LJ::Lang::ml('.option.all'),
        );
        my @cat_selects;
        foreach my $cat (@filter_cats) {
            my $select = {
                id      => $cat->{'spcatid'},
                name    => $cat->{'catname'},
                options => []
            };
            $select->{id}      = $cat->{'spcatid'};
            $select->{name}    = $cat->{'catname'};
            $select->{options} = [];
            foreach my $val ( "off", "new", "all" ) {
                if ( $notify{ $cat->{'spcatid'} } eq $val ) { $select->{sel} = $val; }
                push @{ $select->{options} }, $val, $select->{options};
            }
            push @cat_selects, $select;
        }
        $vars->{cat_selects} = \@cat_selects;
        $vars->{mode}        = "modify";
    }
    if ( $mode eq "save" ) {
        return error_ml('error.invalidform') unless LJ::check_form_auth( $FORM->{lj_form_auth} );
        $remote->set_prop( 'opt_getselfsupport' => $FORM->{opt_getselfsupport} ? 1 : 0 );

        my $dbh = LJ::get_db_writer();
        $dbh->do("DELETE FROM supportnotify WHERE userid=$remote->{'userid'}");
        my $sql;

        foreach my $cat (@filter_cats) {
            my $id      = $cat->{'spcatid'};
            my $setting = $FORM->{"spcatid_$id"};
            if (   $setting eq "all"
                || $setting eq "new" )
            {
                if ($sql) { $sql .= ", "; }
                else      { $sql .= "REPLACE INTO supportnotify (spcatid, userid, level) VALUES "; }
                $sql .= "($id, $remote->{'userid'}, '$setting')";
            }
        }
        if ($sql) { $dbh->do($sql); }

        $vars->{mode} = "save";
    }
    $vars->{remote} = $remote;
    return DW::Template->render_template( 'support/changenotify.tt', $vars );

}

sub stock_answer_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $GET    = $r->get_args;

    my $vars = {};

    # most things have a category id
    my $spcatid = ( $GET->{spcatid} || $POST->{spcatid} || 0 ) + 0;
    my $cats    = LJ::Support::load_cats();
    return error_ml('.category.not.exist') unless !$spcatid || $cats->{$spcatid};

    $vars->{spcatid} = $spcatid;

    # editing is based on ability to grant supporthelp.  and throw an error if they
    # posted but can't edit.
    my $canedit =
        (      $spcatid
            && $remote
            && $remote->has_priv( 'admin', "supporthelp/$cats->{$spcatid}->{catkey}" ) )
        || ( $remote && $remote->has_priv( 'admin', 'supporthelp' ) );
    $vars->{canedit} = $canedit;
    if ( $r->did_post ) {
        return error_ml('error.invalidform') unless LJ::check_form_auth( $POST->{lj_form_auth} );
        return error_ml('.not.have.access.to.actions') unless $canedit;
    }

    # viewing is based on having supporthelp over the particular category you're viewing.
    my %canview;    # spcatid => 0/1
    foreach my $cat ( values %$cats ) {
        $canview{ $cat->{spcatid} } = 1
            if LJ::Support::support_check_priv( { _cat => $cat }, $remote, 'supportviewstocks' );
    }
    return error_ml('.not.have.access.to.view.answers') unless %canview;
    return error_ml('.not.have.access.to.view.answers.in.cat') if $spcatid && !$canview{$spcatid};

    # filter down the category list
    $cats = { map { $_->{spcatid}, $_ } grep { $canview{ $_->{spcatid} } } values %$cats };

    my $ansid = ( $GET->{ansid} || 0 ) + 0;

    my $self = "$LJ::SITEROOT/support/stock_answers";
    $vars->{url} = $self;

    if ( $POST->{'action:delete'} ) {
        my $dbh = LJ::get_db_writer();
        return error_ml('.unable.get.database.handle')
            unless $dbh;

        my $ct = $dbh->do( "DELETE FROM support_answers WHERE ansid = ? AND spcatid = ?",
            undef, $ansid, $spcatid );
        return error_ml( $dbh->errstr ) if $dbh->err;
        return error_ml('.no.answer') unless $ct;
        return $r->redirect("$self?spcatid=$spcatid&deleted=1");
    }

    if ( $POST->{'action:new'} || $POST->{'action:save'} ) {
        my ( $subj, $body ) = ( $POST->{subject}, $POST->{body} );

        foreach my $ref ( \$subj, \$body ) {
            $$ref =~ s/^\s+//;
            $$ref =~ s/\s+$//;

            # FIXME: more stuff to clean it up?
        }

        return error_ml('.fill.out.all.friends')
            unless $spcatid && $subj && $body;

        my $dbh = LJ::get_db_writer();
        return error_ml('.unable.database.handle')
            unless $dbh;

        if ( $POST->{'action:new'} ) {
            my $newid = LJ::alloc_global_counter('A');
            return error_ml('.unable.allocate.counter')
                unless $newid;

            $dbh->do(
"INSERT INTO support_answers (ansid, spcatid, subject, body, lastmodtime, lastmoduserid) "
                    . "VALUES (?, ?, ?, ?, UNIX_TIMESTAMP(), ?)",
                undef, $newid, $spcatid, $subj, $body, $remote->{userid}
            );
            return error_ml( $dbh->errstr ) if $dbh->err;

            return $r->redirect("$self?user=$remote->{user}&spcatid=$spcatid&ansid=$newid&added=1");
        }
        else {
            return error_ml('.no.answer.id') unless $ansid;

            $dbh->do(
                "UPDATE support_answers SET subject = ?, body = ?, lastmodtime = UNIX_TIMESTAMP(), "
                    . "lastmoduserid = ? WHERE ansid = ?",
                undef, $subj, $body, $remote->{userid}, $ansid
            );
            return error_ml( $dbh->errstr ) if $dbh->err;

            return $r->("$self?user=$remote->{user}&spcatid=$spcatid&ansid=$ansid&saved=1");
        }
    }
    if ( $GET->{new} ) {
        my @options = 0, "( please select )", map { $_, $cats->{$_}->{catname} }
            grep { $canview{$_} }
            sort { $cats->{$a}->{catname} cmp $cats->{$b}->{catname} }
            keys %$cats;
        $vars->{selected} = $spcatid;
        $vars->{options}  = \@options;
        $vars->{status}   = 'new';
        return DW::Template->render_template( 'support/stock_answers.tt', $vars );
    }

    my $dbr = LJ::get_db_reader();
    return error_ml('.no.database.available') unless $dbr;

    my $cols = "ansid, spcatid, subject, lastmodtime, lastmoduserid";
    $cols .= ", body" if $ansid;

    my $sql  = "SELECT $cols FROM support_answers";
    my @bind = ();

    if ( $spcatid || $ansid ) {
        $sql .= " WHERE ";
        if ($spcatid) {
            $sql .= "spcatid = ?";
            push @bind, $spcatid;
        }
        if ($ansid) {
            $sql .= ( $spcatid ? " AND " : "" ) . "ansid = ?";
            push @bind, $ansid;
        }
    }

    my $sth = $dbr->prepare($sql);
    $sth->execute(@bind);
    return error_ml( $sth->errstr ) if $sth->err;

    my @filter_options = 0, "( none )", map { $_, $cats->{$_}->{catname} }
        sort { $cats->{$a}->{catname} cmp $cats->{$b}->{catname} } keys %$cats;
    $vars->{filter_options} = \@filter_options;

    my %answers;
    while ( my $row = $sth->fetchrow_hashref ) {
        $answers{ $row->{spcatid} }->{ $row->{ansid} } = {
            subject     => $row->{subject},
            body        => $row->{body},
            lastmodtime => $row->{lastmodtime},
            lastmoduser => LJ::load_userid( $row->{lastmoduserid} ),
        };
    }

    if ( $GET->{added} ) {
        $vars->{added} = 1;
    }
    elsif ( $GET->{saved} ) {
        $vars->{saved} = 1;
    }
    elsif ( $GET->{deleted} ) {
        $vars->{deleted} = 1;
    }

    my @sorted_cats;

    foreach my $catid ( sort { $cats->{$a}->{catname} cmp $cats->{$b}->{catname} } keys %$cats ) {

        my $override = $LJ::SUPPORT_STOCKS_OVERRIDE{ $cats->{$catid}->{catkey} };
        next unless %{ $answers{$catid} || {} } || $override && ( !$spcatid || $catid == $spcatid );
        my $temp_cat = {
            id            => $catid,
            name          => $cats->{$catid}->{catname},
            override_name => $cats->{$override}->{catname},
            show_override => ( $override && ( !$spcatid || $catid == $spcatid ) ),
            answers       => []
        };

        foreach my $ansid (
            sort { $answers{$catid}->{$a}->{subject} cmp $answers{$catid}->{$b}->{subject} }
            keys %{ $answers{$catid} } )
        {
            my ( $subj, $body, $lmu, $lmt ) =
                map { $answers{$catid}->{$ansid}->{$_} } qw(subject body lastmoduser lastmodtime);
            my $temp_answer = {
                subject => $subj,
                body    => $body,
                id      => $ansid
            };
            if ($body) {
                $temp_answer->{lastmod} = LJ::ljuser($lmu) . " on " . LJ::mysql_time($lmt);
            }
            push $temp_cat->{answers}, $temp_answer;
        }
        push @sorted_cats, $temp_cat;
    }

    $vars->{sorted_cats} = \@sorted_cats;
    return DW::Template->render_template( 'support/index.tt', $vars );

}
1;
