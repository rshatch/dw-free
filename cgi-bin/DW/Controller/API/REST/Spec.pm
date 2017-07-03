#!/usr/bin/perl
#
# DW::Controller::API::REST::Icons
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

package DW::Controller::API::REST::Spec;
use DW::Controller::API::REST qw(path);

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;
use Data::Dumper;


# Define route and associated params
my $spec = path('spec.yaml', 1, {'get' => \&rest_get});

sub rest_get {
    my $self = $_[0];
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $spec = _spec_20();
    my $ver = $self->{ver};
    my %api = %DW::Controller::API::REST::API_DOCS;

    # for my $key (keys $api{ver}) {
    #     my $path = $api{ver}{$key}->{path}
    #     $spec->{paths}{$path}
    # }

    $spec->{paths} = $api{$ver};
    warn Dumper($spec);

    return $self->rest_ok($spec);

}

sub _spec_20 {
    my $self = $_[0];
    my $ver = $spec->{ver};

    my @content_types = qw(application/json);
    my @schemes = qw(https http);

    my %spec = (
        swagger => '2.0',
        info => {
            version => "$ver",
            title => "$LJ::SITENAME API",
            description => "An OpenAPI-compatible API for $LJ::SITENAME"

        },
        host => $ENV{SERVER_NAME} ||  $ENV{HTTP_HOST},
        basePath => "/api/v$ver",
        schemes => \@schemes,
        consumes => \@content_types,
        produces => \@content_types,
    );

    return \%spec;
}

1;