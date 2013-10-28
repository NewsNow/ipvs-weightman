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

package Xebedii::Pollable::Socket::TCP;

use base 'Xebedii::Pollable';

my $LocalHandles = {};

use IO::Socket::INET;
use POSIX ":sys_wait_h";
use Fcntl;

sub listen {
   my $self = shift;

   my $LH = $self->new(%$self);

   my $Sock;
   if( $Sock = IO::Socket::INET->new( Listen    => 5,
                                      LocalAddr => $self->{'LocalAddr'},
                                      LocalPort => $self->{'LocalPort'},
                                      Proto     => 'tcp',
                                      ReuseAddr => 1,
                                      Blocking  => 0
       )
     ) {

      $LH->{'.FH.IN'} = $Sock;
      $LH->{'.UID'}   = $LH->SUPER::UID();
      $LH->{'.Type'}  = 'TCP::Listening';

      $LocalHandles->{ fileno($Sock) } = $LH;

      # Register with super-class
      $LH->SUPER::create();
   }
   else {
      die "$0: failed to open socket: '$!'";
   }
}

sub accept {
   my $self = shift;

   my $LH = $self->new(%$self);

   my $Sock;
   if( $Sock = $self->{'.FH.IN'}->accept() ) {

      fcntl( $Sock, F_SETFL, O_NONBLOCK );

      $LH->{'.FH.OUT'} = $Sock;
      $LH->{'.FH.IN'}  = $Sock;
      $LH->{'.Type'}   = 'TCP';
      $LH->{'.UID'}    = $LH->SUPER::UID();

      $LocalHandles->{ fileno($Sock) } = $LH;

      # Register with super-class
      $LH->SUPER::create();

      return $LH;
   }
   else {
      die "$0: $!";
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

sub UID { return "TCP:" . $_[0]->{'.UID'}; }

sub _event_read {
   my $Item = shift;

   return $Item->SUPER::_event_read() unless $Item->{'.Type'} eq 'TCP::Listening';

   $Item->{'.New'} = $Item->accept();

   return $Item;
}

sub Alive { return !$_[0]->{'.Exited'}; }

sub __poll {
   my $Item = shift;

   # Return item if its filehandles have broken
   if( $Item->{'.FH.IN.Broken'} || $Item->{'.FH.OUT.Broken'} ) {
      $Item->{'.Exited'} = 1;
      return $Item;
   }

   # Return item if it has expired
   if( defined $Item->{'.ExpiryTime'} && ( time >= $Item->{'.ExpiryTime'} ) ) {
      $Item->{'.TimedOut'} = 1;
      $Item->{'.Exited'}   = 1;

      return $Item;
   }

   return undef;
}

sub Accepted {
   return $_[0]->{'.New'};
}

sub Reset {
   delete $_[0]->{'.New'};
}

1;
