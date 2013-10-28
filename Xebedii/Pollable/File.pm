#!/usr/bin/perl

################################################################################################
# LICENCE INFORMATION
#
# This file is part of ipvs-weightman, an IPVS Real Server Checker and Weight Manager.
#
# ipvs-weightman is authored by Struan Bartlett <struan dot bartlett @ NewsNow dot co dot uk>
# and is copyright (c) 2013 NewsNow Publishing Limited.
#
# ipvs-weightman is licensed for use, modification and/or distribution under the same terms
# as Perl itself.
#
################################################################################################

use strict;

package Xebedii::Pollable::File;

use base 'Xebedii::Pollable';

my $LocalHandles = {};

use IPC::Open3;
use POSIX ":sys_wait_h";
use Fcntl;

sub open {
   my $self = shift;

   my $LH = $self->new(%$self);

   my $rw;
   if( open( $rw, "+<", $self->{'.Path'} ) ) {

      fcntl( $rw, F_SETFL, O_NONBLOCK );

      $LH->{'.FH.OUT'}  = $rw;
      $LH->{'.FH.IN'}   = $rw;
      $LH->{'.Prot.In'} = 'Line';
      $LH->{'.IsFH'}    = 1;

      $LocalHandles->{ fileno($rw) } = $LH;

      # Register with super-class
      $LH->SUPER::create();
   }
}

sub destroy {
   my $self = shift;

   # Remember to employ fileno *before* closing the filehandles (after which fileno() returns undef)
   delete $LocalHandles->{ fileno( $self->{'.FH.IN'} ) };
   delete $LocalHandles->{ fileno( $self->{'.FH.OUT'} ) };

   $self->close;

   # De-register from super-class
   $self->SUPER::destroy;
}

sub close {
   my $Item = shift;

   close $Item->{'.FH.IN'};
}

sub UID { return "FILE:" . fileno( $_[0]->{'.FH.IN'} ); }

1;
