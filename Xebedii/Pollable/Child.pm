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

package Xebedii::Pollable::Child;

use base 'Xebedii::Pollable';

use IPC::Open3;
use POSIX ":sys_wait_h";
use Fcntl;

# A NOTE ON THE PROTOCOLS
# -----------------------
#
# In Xebedii::Pollable::Child::new (the context of the parent process):
# .Prot.Out (formerly .O/I) refers to the protocol of the communication from the parent to the child.
# .Prot.In (formerly .I/O) refers to the protocol of the communication from the child to the parent
#
# However, in the child process, these protocols are automatically reversed. This means that:
# .Prot.Out (formerly .O/I) refers to the protocol of the communication from the child to the parent
# .Prot.In (formerly .I/O) refers to the protocol of the communication from the parent to the child
#
# In all cases .Prot.Out and .Prot.In specify the protocol in use from the perspective of each
# running process.

################################################################################
# CLASS METHODS

sub new {
   my $This = shift;
   my %Args = ref $_[0] eq 'HASH' ? %{ $_[0] } : @_;

   my $Class = ref $This || $This;

   if( ref $This ) {
      foreach ( '.I/O', '.O/I', '.Prot.In', '.Prot.Out', '.Title', '.Args', '.Command', '.Function', '.Signals', '.CommandLine' ) {
         $Args{$_} = $This->{$_} if !exists $Args{$_} && exists $This->{$_};
      }
   }

   return $This->SUPER::new(%Args);
}

################################################################################
# OBJECT METHODS (REQUIRED FOR SUBCLASSING Xebedii::Pollable)

sub spawn {
   my $Instance     = shift;
   my $InstanceArgs = shift;
   my $FunctionArgs = shift;

   my $r;
   my $w;

   $| = 1;

   my $Kid = $Instance->new(%$InstanceArgs);

   my @Args;
   push( @Args, %{ $Kid->{'.Args'} } ) if $Kid->{'.Args'} && ref( $Kid->{'.Args'} ) eq 'HASH';
   push( @Args, %{$FunctionArgs} )     if $FunctionArgs   && ref($FunctionArgs)     eq 'HASH';

   $Kid->{'.Args'} = {@Args};

   my $PID;
   if( $PID = open3( $w, $r, '>&2', ( defined $Kid->{'.Command'} ? "$Kid->{'.Command'} |" : '-' ) ) ) {

      # parent code

      fcntl( $r, F_SETFL, O_NONBLOCK );
      fcntl( $w, F_SETFL, O_NONBLOCK );

      $Kid->{'.StartTime'} = time;

      if( $Kid->{'.Timeout'} ) {
         $Kid->{'.ExpiryTime'} = $Kid->{'.StartTime'} + $Kid->{'.Timeout'};
      }

      $Kid->{'.PID'}     = $PID;
      $Kid->{'.FH.OUT'}  = $w;
      $Kid->{'.FH.IN'}   = $r;
      $Kid->{'.Exited'}  = $Kid->{'.Timedout'} = 0;
      $Kid->{'.IsChild'} = 1;

      # Register with super-class
      $Kid->SUPER::create();

      return $Kid;

   }
   elsif ( defined $PID ) {

      # child code

      my $x = select(STDERR);
      $| = 1;
      select($x);

      while( my ( $S, $V ) = each %{ $Kid->{'.Signals'} } ) {
         $SIG{$S} = $V;
      }

      $Kid->{'.FH.IN'}  = *STDIN;
      $Kid->{'.FH.OUT'} = *STDOUT;

      # If these are not set, then sysread() will block in Pollable::_event() l. 64
      fcntl( $Kid->{'.FH.IN'},  F_SETFL, O_NONBLOCK );
      fcntl( $Kid->{'.FH.OUT'}, F_SETFL, O_NONBLOCK );

      # Creating reference to parent for _poll() and _pollable()
      # This object will both be used as $Self and as an entry in $Items
      $Kid->{'.NoPoll'} = 1;    # This prevents polling in __poll(). Otherwise, '.ExpiryTime' would have to be deleted, among other adjustments

      # Reversing protocols
      my $oldpr = $Kid->{'.Prot.In'} if defined $Kid->{'.Prot.In'};
      $Kid->{'.Prot.In'} = ( defined $Kid->{'.Prot.Out'} ) ? $Kid->{'.Prot.Out'} : '';
      $Kid->{'.Prot.Out'} = ( defined $oldpr ) ? $oldpr : '';
      undef $oldpr;

      $Kid->SUPER::destroyall();    # Do not inherit pollable items from parent
      $Kid->SUPER::create();        # Add reference to pollable items

      my $Fn = $Kid->{'.Function'};

      $0 = $Kid->{'.CommandLine'} if defined $Kid->{'.CommandLine'};

      &$Fn($Kid);
      exit(0);
   }
   else {

      # Couldn't fork => Serious problems
      return undef;
   }
}

sub destroy {
   my $self = shift;

   $self->close;

   # De-register from super-class
   $self->SUPER::destroy;
}

sub close {
   my $Item = shift;

   close $Item->{'.FH.IN'};
   close $Item->{'.FH.OUT'};
}

sub UID { return "PID:" . $_[0]->PID; }

sub __poll {
   my $Item = shift;

   # Do not poll parent
   return undef if defined $Item->{'.NoPoll'};

   my $PID = $Item->{'.PID'};

   my $kid = waitpid( $PID, WNOHANG );

   # Return Child if it's exited
   if( $kid == $PID ) {
      $Item->{'.ExitCode'} = $? >> 8;    # $? must be read before the close to return the correct exit code
      $Item->{'.Exited'}   = 1;

      return $Item;
   }

   # Return Child if it's expired
   if( defined $Item->{'.ExpiryTime'} && ( time >= $Item->{'.ExpiryTime'} ) ) {
      kill 9, $PID;
      waitpid( $PID, 0 );
      $Item->{'.TimedOut'} = 1;
      $Item->{'.Exited'}   = 1;

      return $Item;
   }

   return undef;
}

################################################################################
# CUSTOM OBJECT METHODS

sub PID { return $_[0]->{'.PID'} || $$; }
sub Terminate { $_[0]->{'.Terminating'}++; kill 15, $_[0]->{'.PID'}; }

sub ExitString         { return $_[0]->{'.ExitString'}; }
sub ExitCode           { return $_[0]->{'.ExitCode'}; }
sub ExitedSuccessfully { return $_[0]->{'.Exited'} && ( $_[0]->{'.ExitCode'} == 0 ); }
sub Exited             { return $_[0]->{'.Exited'}; }
sub TimedOut           { return $_[0]->{'.TimedOut'}; }
sub Terminating        { return $_[0]->{'.Terminating'}; }

# Set, or reset, a child timeout
sub Timeout {
   if( $_[1] ) { $_[0]->{'.Timeout'} = $_[1]; $_[0]->{'.ExpiryTime'} = time + $_[1]; }
   else { delete $_[0]->{'.Timeout'}; delete $_[0]->{'.ExpiryTime'}; }
}

1;
