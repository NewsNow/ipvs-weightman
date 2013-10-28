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

# Spawns a child to run a function.
# If the child exits normally, it's exit is returned.
# If the child has not returned within 'ChildTimeout' seconds, it is killed brutally and undef is returned.

use strict;

package Xebedii::Pollable;

my $Events = [];
my $Items  = {};

use IPC::Open3;
use POSIX qw(:errno_h :fcntl_h :sys_wait_h);
use Fcntl;

################################################################################
# CONSTRUCTOR

sub new {
   my $This = shift;
   my %Args = ref $_[0] eq 'HASH' ? %{ $_[0] } : @_;

   my $Class = ref $This || $This;

   my $New = \%Args;

   $New->{'.Prot.In'} ||= $New->{'.I/O'};    # Legacy option
   $New->{'.Prot.In'} ||= 'Object';          # Default

   $New->{'.Prot.Out'} ||= $New->{'.O/I'};       # Legacy option
   $New->{'.Prot.Out'} ||= $New->{'.Prot.In'};

   return bless $New, $Class;
}

sub create {
   my $self = shift;

   $Items->{ $self->UID } = $self;
}

sub destroy {
   my $self = shift;

   delete $Items->{ $self->UID };
}

sub destroyall {

   # Purges the list of pollable items
   $Items = {};
}

sub UID {
   my $self = shift;

   # Default UID
   return int($self);
}

# Base class definition for sub-class __poll methods.
sub __poll { return undef; }

sub _event_read {
   my $Item = shift;

   local $_;
   my $Bytes = 0;

   while(1) {
      my $s = sysread( $Item->{'.FH.IN'}, $_, 10240 );

      if( defined $s and $s > 0 ) {
         $Item->{'.Buffer.IN'} .= $_;
         $Bytes += $s;

         # Now we read again to check for more data -- can cause problems if sysread above blocks (make sure that $Item->FH.IN is non-blocking).
         # If for any reason we'd like an option for $Item->FH.IN to be left in blocking mode, then a solution could be to 'select' on $Item->FH.IN here
         # to see if there is further input available before doing 'next', otherwise doing 'return'.
         next;
      }

      if( $Bytes == 0 ) {

         # This is an error condition, discovered empirically: select() has just indicated there is data
         # to read on the file descriptor, but on reading we get no bytes.

         # DEBUG
         # printf STDERR "Item %s: Alive=%d FH.IN=%d - zero bytes must be broken\n", $Item->UID, $Item->Alive, fileno($Item->{'.FH.IN'});
         $Item->{'.FH.IN.Broken'} = 1;
      }

      return undef;
   }
}

sub _event_write {
   my $Item = shift;

   # Nothing to send? Then nothing to do.
   return undef unless $Item->{'.Buffer.OUT'} ne '';

   my $Bytes = 0;

   for( my $i = 0; 1; $i++ ) {
      my $s = syswrite( $Item->{'.FH.OUT'}, $Item->{'.Buffer.OUT'}, length( $Item->{'.Buffer.OUT'} ) );

      if( defined $s && $s > 0 ) {

         # DEBUG
         # printf STDERR "Item %s: Alive=%d FH.OUT=%d syswrite returned $s on loop $i with error %d after attempting to send %d bytes\n", $Item->UID, $Item->Alive, fileno( $Item->{'.FH.OUT'} ), int($!), length( $Item->{'.Buffer.OUT'} );

         substr( $Item->{'.Buffer.OUT'}, 0, $s ) = '';
         $Bytes += $s;

         # Now we read again to check for more data -- can cause problems if sysread above blocks (make sure that $Item->FH.OUT is non-blocking).
         # If for any reason we'd like an option for $Item->FH.OUT to be left in blocking mode, then a solution could be to 'select' on $Item->FH.OUT here
         # to see if there is further output that can be done before doing 'next', otherwise doing 'return'.
         next;
      }

      # DEBUG
      # printf STDERR "Item %s: Alive=%d FH.OUT=%d syswrite returned $s on loop $i with error %d after sending '%s'\n", $Item->UID, $Item->Alive, fileno( $Item->{'.FH.OUT'} ), int($!), $Item->{'.Buffer.OUT'};

      # $s is undef, or $s == 0
      if( $Bytes == 0 ) {

         # This is an error condition, discovered empirically: select() has just indicated data can be written
         # on the file descriptor, but on writing we get no bytes.

         $Item->{'.FH.OUT.Broken'} = 1;
      }

      return undef;
   }
}

sub Title { return $_[0]->{'.Title'} || $_[0]->UID; }
sub Type { return $_[0]->{'.Type'}; }

sub Alive    { return !$_[0]->Exited; }
sub Exited   { return exists( $_[0]->{'.Exited'} ) ? $_[0]->{'.Exited'} : 0; }
sub TimedOut { return exists( $_[0]->{'.TimedOut'} ) ? $_[0]->{'.TimedOut'} : 0; }

################################################################################
# ACCESSORY FUNCTIONS

sub fhbits {
   my $bits = '';
   for(@_) {
      vec( $bits, fileno($_), 1 ) = 1 if defined fileno($_);
   }
   $bits;
}

################################################################################
# CHAR/LINE/OBJECT OUTPUT METHODS

use Storable qw( store_fd fd_retrieve freeze thaw );

# Output char, line or frozen data-structure.
#
# If called by a Child object on self, sends data to parent.
# If called on a Parent object on a Child object, sends data to child.
# If called by a Parent object on a Socket::TCP, sends data to the socket.
sub Send {
   my $Self = shift;
   my $Ref  = shift;

   my $Prot_Out = $Self->{'.Prot.Out'};

   if( $Prot_Out eq 'Char' ) {
   }
   elsif ( $Prot_Out eq 'Line' ) {
      $Ref .= "\n";
   }
   else {
      my $F = freeze( \$Ref );
      $Ref = length($F) . "\n" . $F;
   }

   $Self->{'.Buffer.OUT'} .= $Ref;

   # Now try and flush buffers.
   $Self->_event_write();

   # Return true if there buffer is fully flushed.
   return $Self->{'.Buffer.OUT'} eq '';
}

################################################################################
# CHAR/LINE/OBJECT INPUT METHODS

# Parse and assemble char, line or data-structure from input:
# - in char mode, assemble in the '.Buffer.IN' property;
# - in line mode, assemble in the '.Output' property;
# - in object mode, assemble in the '.Output' property.
#
# Returns $Self if input is 'ready', undef otherwise.
sub _parse {
   my $Self = shift;

   return undef if defined $Self->{'.Output'};

   if( $Self->{'.Prot.In'} eq 'Char' ) {
      return undef unless length( $Self->{'.Buffer.IN'} );

      $Self->{'.Output'} = $Self->{'.Buffer.IN'};
      delete $Self->{'.Buffer.IN'};
      return $Self;
   }

   if( $Self->{'.Prot.In'} eq 'Line' ) {
      return $Self if defined $Self->{'.Buffer.IN'} and $Self->{'.Buffer.IN'} =~ s/^(.*?)\n/$Self->{'.Output'} = $1; ''/es;
      return undef;
   }

   # Object protocol
   if( !$Self->{'.Storable.Bytes'} ) {

      if( defined $Self->{'.Buffer.IN'} and $Self->{'.Buffer.IN'} =~ /^(\d+)\n/s ) {
         $Self->{'.Storable.Bytes'} = $1;
         $Self->{'.Buffer.IN'} =~ s/^\d+\n//s;
      }
      else {
         return undef;
      }
   }

   return undef unless length( $Self->{'.Buffer.IN'} ) >= $Self->{'.Storable.Bytes'};

   $Self->{'.Output'} = ${ thaw( substr( $Self->{'.Buffer.IN'}, 0, $Self->{'.Storable.Bytes'}, '' ) ) };
   delete $Self->{'.Storable.Bytes'};

   return $Self;
}

# Returns what's received (input from child/child output), as assembled by 'sub _parse'
sub Received { return $_[0]->{'.Output'}; }

# Resets child 'receive' property.
sub ReceivedReset { delete $_[0]->{'.Output'}; }

################################################################################
# CLASS METHODS

sub _pollable {
   return grep { $_->Alive } values %$Items;
}

sub _poll {
   my $Self  = shift;
   my $Sleep = shift;
   use POSIX ":sys_wait_h";

   # 1st, select() on all the childrens handles and read in any pending buffered data
   # 2nd, wait on any zombie children and log the child as having completed

   my @AliveItems = grep { $_->Alive } values %$Items;

   my @fds_in = map { $_->{'.FH.IN'} } @AliveItems;
   my @fds_out = grep { defined $_ } map { $_->{'.FH.OUT'} } @AliveItems;

   my $rin = &fhbits(@fds_in);
   my $win = &fhbits(@fds_out);
   my $ein = $rin;

   for( my $i = 0; $i < 2; $i++ ) {

      # On the 1st pass, return immediately if there is no I/O - we'll check for dead/expiring children and return the first child from @$Events, if there is one.
      # If there isn't anything in @$Events, we conduct the 2nd pass. On the 2nd pass, we'll wait $Sleep seconds for I/O - so as not to thrash the CPU - and return
      # the first child from @$Events if there is one. If not, then we finally return undef.
      #
      # P.S. While it may be tempting to only execute the below select if @fds_in is true, then nothing would prevent _poll from thrashing the CPU in the case where there
      # are no pollable entities.

      my $rout;
      my $wout;
      my $eout;
      my $s;

      if($i) {

         # 2nd pass: read, don't write, do wait.
         $s = select( $rout = $rin, undef, undef, $Sleep );
      }
      else {

         # 1st pass: read, write, but don't wait.
         $s = select( $rout = $rin, $wout = $win, undef, 0 );
      }

      # The reason why we loop across all the kids and handles, instead of only across those with input,
      # is because we don't want processes with input to get more attention than those that have no input,
      # and thus prevent the latter from being expired in a timely manner.
      foreach my $Item (@AliveItems) {

         # FIXME: This line isn't needed is it?
         local $_;

         my $PollEvent = 0;

         if( @fds_in && ( $s != -1 ) && vec( $rout, fileno( $Item->{'.FH.IN'} ), 1 ) ) {
            $PollEvent++ if $Item->_event_read;
         }

         if( @fds_out && ( $s != -1 ) && vec( $wout, fileno( $Item->{'.FH.OUT'} ), 1 ) ) {
            $PollEvent++ if $Item->_event_write;
         }

         $PollEvent++ if $Item->__poll;

         # FIXME:
         # Why call _parse unless we had just called _event_read?
         # Why not do: $PollEvent++ if $Item->parse; Then: if( $PollEvent ) { ... }

         # Watch out for ordering and lazy evaluation!
         # $Item->__poll must be run before $Item->_parse, but $Item->_parse must be run too!
         # if( $Item->_parse || $Item->__poll) wouldn't do the same thing!
         if( $Item->_parse || $PollEvent ) {

            # Consider the implications before merging the logic below with that above - the Parse method needs to run as it actually does something!
            push( @$Events, $Item ) unless grep { $_ == $Item } @$Events;
         }

      }

      return shift(@$Events) if @$Events;

   }

   return undef;
}

1;
