#!/usr/bin/perl
#
# DW::Controller::API::REST::Moods
#
# API controls for the icon system
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::Moods;

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;
use DW::Mood;

# Define route and associated params
my $moods = DW::Controller::API::REST->path('moods.yaml', 1, {'get' => \&rest_get_list});


sub rest_get_list {
	my ( $self ) = @_;
    return $self->rest_ok( DW::Mood->get_moods );
}

1;
