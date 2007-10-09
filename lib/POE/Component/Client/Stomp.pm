package POE::Component::Client::Stomp;

use POE;
use Carp;
use Socket;
use POE::Filter::Stomp;
use POE::Wheel::ReadWrite;
use POE::Wheel::SocketFactory;
use POE::Component::Client::Stomp::Utils;

use 5.008;
use strict;
use warnings;

use constant DEFAULT_HOST => 'localhost';
use constant DEFAULT_PORT => 61613;

our $VERSION = '0.03';

# ---------------------------------------------------------------------

sub spawn {
    my $package = shift;

    croak "$package requires an even number of parameters" if @_ & 1;

    my %args = @_;
    my $self = bless ({}, $package);

    $args{Alias} = 'stomp-client' unless defined $args{Alias} and $args{Alias};

    $self->{CONFIG} = \%args;
    $self->{stomp} = POE::Component::Client::Stomp::Utils->new();
    $self->{attempts} = 1;

    POE::Session->create(
        object_states => [
            $self => { 
                _start => '_client_start',
                _stop => '_client_stop',
                shutdown => '_client_close',
                reconnect => '_client_start',
            },
            $self => [ qw( _server_connected _server_connection_failed
                           _server_error _server_message send_data
                           handle_message handle_receipt handle_error
                           handle_connected handle_connection
			               gather_data) ],
        ],
        (ref $args{options} eq 'HASH' ? (options => $args{options}) : () ),
    );

    return $self;

}

sub _client_start {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    $kernel->alias_set($self->{CONFIG}->{Alias});

    $self->{Listner} = POE::Wheel::SocketFactory->new(
        RemoteAddress => $self->{CONFIG}->{RemoteAddress} || DEFAULT_HOST,
        RemotePort    => $self->{CONFIG}->{RemotePort} || DEFAULT_PORT,
        SuccessEvent  => '_server_connected',
        FailureEvent  => '_server_connection_failed',
    );

}

sub _client_stop {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

}

sub _client_close {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    delete $self->{Listner};
    $kernel->alias_remove($self->{CONFIG}->{Alias});

}

sub _server_connected {
    my ($kernel, $self, $socket, $peeraddr, $peerport, $wheel_id) = 
       @_[KERNEL, OBJECT, ARG0 .. ARG3];

    my $wheel = POE::Wheel::ReadWrite->new(
        Handle => $socket,
        Filter => POE::Filter::Stomp->new(),
        InputEvent => '_server_message',
        ErrorEvent => '_server_error',
    );

    my $host = gethostbyaddr($peeraddr, AF_INET);

    $self->{attempts} = 0;
    $self->{Wheel} = $wheel;
    $self->{Host} = $host;
    $self->{Port} = $peerport;

    $kernel->yield('handle_connection');

}

sub _server_connection_failed {
    my ($kernel, $self, $operation, $errnum, $errstr, $wheel_id) = 
        @_[KERNEL, OBJECT, ARG0 .. ARG3];

	$self->log($kernel, 'error', "Operation: $operation; Reason: $errnum - $errstr");

    if ($errnum == 111) {

        if ($self->{attempts} < 10) {

			$self->log($kernel, 'warn', "Attempting connect: $self->{attempts}");
            delete $self->{Listner};
            delete $self->{Server};
            $self->{attempts}++;
            $kernel->delay(reconnect => 60);

        } else { 

			$self->log($kernel, 'warn', 'Shutting down, to many reconnection attempts');
			$kernel->yield('shutdown'); 

		}

    }

}

sub _server_error {
    my ($kernel, $self, $operation, $errnum, $errstr, $wheel_id) = 
        @_[KERNEL, OBJECT, ARG0 .. ARG3];

	$self->log($kernel, 'error', "Operation: $operation; Reason: $errnum - $errstr");

    if (($errnum == 0) || 
        ($errnum == 73) || 
        ($errnum == 79)) {

        if ($self->{attempts} < 10) {

			$self->log($kernel, 'warn', "Attempting reconnection: $self->{attempts}");
            delete $self->{Listner};
            delete $self->{Server};
            $self->{attempts}++;
            $kernel->delay(reconnect => 60);

        } else { 

			$self->log($kernel, 'warn', 'Shutting down, to many reconnection attempts');
			$kernel->yield('shutdown'); 

		}

    }

}

sub _server_message {
    my ($kernel, $self, $frame, $wheel_id) = @_[KERNEL, OBJECT, ARG0, ARG1];

    if ($frame->command eq 'CONNECTED') {

        $kernel->yield('handle_connected', $frame);

    } elsif ($frame->command eq 'MESSAGE') {

        $kernel->yield('handle_message', $frame);

    } elsif ($frame->command eq 'RECEIPT') {

        $kernel->yield('handle_receipt', $frame);

    } elsif ($frame->command eq 'ERROR') {

        $kernel->yield('handle_error', $frame);

    }

}

# ---------------------------------------------------------------------
# Public accessors
# ---------------------------------------------------------------------

sub stomp {
	my $self = shift;

	return $self->{stomp};

}

sub config {
	my ($self, $arg) = @_;

	return $self->{CONFIG}->{$arg};

}

sub host {
	my ($self) = @_;

	return $self->{Host};

}

sub port {
	my ($self) = @_;

	return $self->{Port};

}
	
# ---------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------

sub send_data {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

    if (defined($self->{Wheel})) {

        $self->{Wheel}->put($frame);

    }

}

# ---------------------------------------------------------------------
# Public methods, these should be overridden, as needed
# ---------------------------------------------------------------------

sub log {
    my ($self, $kernel, $level, @args) = @_;

	print "$level: @args\n";

}

sub handle_connection {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

}

sub handle_connected {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

}

sub handle_message {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

}

sub handle_receipt {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

}

sub handle_error {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

}

sub gather_data {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

}

1;


__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

POE::Component::Client::Stomp - Perl extension for the POE Environment

=head1 SYNOPSIS

This module is a class used to create clients that need to access a 
message server that communicates with the STOMP protocol. Your program could 
look as follows:

 package Client;

 use POE:
 use base qw(POE::Component::Client::Stomp);

 use strict;
 use warnings;

 sub handle_connection {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
 
    my $nframe = $self->stomp->connect({login => 'testing', 
                                        passcode => 'testing'});
    $kernel->yield('send_data' => $nframe);

 }

 sub handle_connected {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

    my $nframe = $self->stomp->subscribe({destination => $self->config('Queue'), 
                                          ack => 'client'});
    $kernel->yield('send_data' => $nframe);

 }
 
 sub handle_message {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

    my $message_id = $frame->headers->{'message-id'};
    my $nframe = $self->stomp->ack({'message-id' => $message_id});
    $kernel->yield('send_data' => $nframe);

 }

 package main;

 use POE;
 use strict;

    Client->spawn(
        Alias => 'testing',
        Queue => '/queue/testing',
    );

    $poe_kernel->run();

    exit 0;


=head1 DESCRIPTION

This module handles the nitty-gritty details of setting up the communications 
channel to a message queue server. You will need to sub-class this module
with your own for it to be usefull.

An attempt to maintain that channel will be made when/if that server should 
happen to disappear off the network. There is nothing more unpleasent then 
having to go around to dozens of servers and restarting processes.

When messages are received, specific events are generated. Those events are 
based on the message type. If you are interested in those events you should 
override the default behaviour for those events. The default behaviour is to 
do nothing.

=head1 METHODS

=over 4

=item spawn

This method initializes the class and starts a session to handle the 
communications channel. The only parameters that having meaning are:

=over 4

 Alias         - The session alias, defaults to 'stomp-client'
 RemoteAddress - The servers hostname, defaults to 'localhost'
 RemotePort    - The servers port, defaults to '61613'

=back

All other parameters are stored within an internal config.

=item send_data

You use this event to send Stomp frames to the server. 

=over 4

=item Example

 $kernel->yield('send_data', $frame);

=back

=item handle_connection

This event is signaled and the corresponding method is called upon initial 
connection to the message server. For the most part you should send a 
"connect" frame to the server.

=over 4

=item Example

 sub handle_connection {
     my ($kernel, $self) = @_[KERNEL,$OBJECT];
 
    my $nframe = $self->stomp->connect({login => 'testing', 
                                        passcode => 'testing'});
    $kernel->yield('send_data' => $nframe);
     
 }

=back

=item handled_connected

This event and corresponing method is called when a "CONNECT" frame is 
received from the server. This means the server will allow you to start
generating/processing frames.

=over 4

=item Example

 sub handle_connected {
     my ($kernel, $self, $frame) = @_[KERNEL,$OBJECT,ARG0];
 
     my $nframe = $self->stomp->subscribe({destination => $self->config('Queue'), 
                                           ack => 'client'});
     $kernel->yield('send_data' => $nframe);
     
 }

This example shows you how to subscribe to a particilar queue. The queue name
was passed as a parameter to spawn() so it is available in the $self->{CONFIG}
hash.

=back

=item handle_message

This event and corresponding method is used to process "MESSAGE" frames. 

=over 4

=item Example

 sub handle_message {
     my ($kernel, $self, $frame) = @_[KERNEL,$OBJECT,ARG0];
 
     my $message_id = $frame->headers->{'message-id'};
     my $nframe = $self->stomp->ack({'message-id' => $message_id});
     $kernel->yield('send_data' => $nframe);
     
 }

This example really doesn't do much other then "ack" the messages that are
received. 

=back

=item handle_receipt

This event and corresponding method is used to process "RECEIPT" frames. 

=over 4

=item Example

 sub handle_receipt {
     my ($kernel, $self, $frame) = @_[KERNEL,$OBJECT,ARG0];
 
     my $receipt = $frame->headers->{receipt};
     
 }

This example really doesn't do much, and you really don't need to worry about
receipts unless you ask for one when you send a frame to the server. So this 
method could be safely left with the default.

=back

=item handle_error

This event and corresponding method is used to process "ERROR" frames. 

=over 4

=item Example

 sub handle_error {
     my ($kernel, $self, $frame) = @_[KERNEL,$OBJECT,ARG0];
 
 }

This example really doesn't do much. Error handling is pretty much what the
process needs to do when something unexpected happens.

=back

=item gather_data

This event and corresponding method is used to "gather data". What is done
with the data is up to the program.

=over 4

=item Example

 sub gather_data {
     my ($kernel, $self) = @_[KERNEL,$OBJECT];
 
 }

=back

=item log

This method is used internally to send a log message to stdout. It can be 
overridden to hook into your perferred logging module. This module currently
uses the following levels internally: 'warn', 'error'

=over 4

=item Example

 sub log {
     my ($self, $kernel, $level, @args) = @_;

     if ($level eq 'error') {

         $kernel->post('logger' => error => @args);

     } elsif ($level eq 'warn') {

         $kernel->post('logger' => warn => @args);

    }

 }

=back

=head1 ACCESSORS

=over 4

=item stomp

This returns an object to the interal POE::Component::Client::Stomp::Utils 
object. This is very useful for creating Stomp frames.

=over 4

=item Example

 $frame = $self->stomp->connect({login => 'testing', 
                                 passcode => 'testing'});
 $kernel->yield('send_data' => $frame);

=back

=item config

This accessor is used to return items from the internal config. The config is
loaded from the parameters that were used when spawn() was called.

=over 4

=item Example

 $logger = $self->config('Logger');

=back

=head1 SEE ALSO

 Net::Stomp::Frame
 POE::Filter::Stomp
 POE::Component::Server::MessageQueue
 POE::Compoment::Client::Stomp::utils;

 For information on the Stomp protocol: http://stomp.codehaus.org/Protocol

=head1 AUTHOR

Kevin L. Esteb, E<lt>kesteb@wsipc.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Kevin L. Esteb

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
