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

our $VERSION = '0.02';

# ---------------------------------------------------------------------

sub spawn {
    my $package = shift;

    croak "$package requires an even number of parameters" if @_ & 1;

    my %args = @_;
    my $self = bless ({}, $package);

    $args{Alias} = 'stomp-client' unless defined $args{Alias} and $args{Alias};

    $self->{CONFIG} = \%args;
    $self->{stomp} = POE::Component::Client::Stomp::Utils->new();
    $self->{attempts} = 0;

    POE::Session->create(
        object_states => [
            $self => { 
                _start => '_client_start',
                _stop => '_client_stop',
                shutdown => '_client_close',
                reconnect => '_client_start',
            },
            $self => [ qw( _server_connected _server_connection_failed
                           _server_error _server_message handle_send
                           handle_message handle_receipt handle_error
                           handle_connected handle_connection) ],
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
    $self->{Server}->{Wheel} = $wheel;
    $self->{Server}->{peeraddr} = $host;
    $self->{Server}->{peerport} = $peerport;

    $kernel->yield('handle_connection');

}

sub _server_connection_failed {
    my ($kernel, $self, $operation, $errnum, $errstr, $wheel_id) = 
        @_[KERNEL, OBJECT, ARG0 .. ARG3];

    if ($errnum == 111) {

        if ($self->{attempts} < 10) {
            
            delete $self->{Listner};
            delete $self->{Server};
            $self->{attempts}++;
            $kernel->alias_remove($self->{CONFIG}->{Alias});
            $kernel->delay(reconnect => 60);

        } else { $kernel->yield('shutdown'); }

    }

}

sub _server_error {
    my ($kernel, $self, $operation, $errnum, $errstr, $wheel_id) = 
        @_[KERNEL, OBJECT, ARG0 .. ARG3];

    if (($errnum == 0) || 
        ($errnum == 73) || 
        ($errnum == 79)) {

        if ($self->{attempts} < 10) {

            delete $self->{Listner};
            delete $self->{Server};
            $self->{attempts}++;
            $kernel->alias_remove($self->{CONFIG}->{Alias});
            $kernel->delay(reconnect => 60);

        } else { $kernel->yield('shutdown'); }

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
# Public methods
# ---------------------------------------------------------------------

sub handle_send {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

    if (defined($self->{Server}->{Wheel})) {

        $self->{Server}->{Wheel}->put($frame);

    }

}

# ---------------------------------------------------------------------
# Public methods, these should be overridden, as needed
# ---------------------------------------------------------------------

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

1;


__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

POE::Component::Client::Stomp - Perl extension for the POE Environment

=head1 SYNOPSIS

This module is an object wrapper to create clients that need to access a 
message server that communicates with the STOMP protocol. Your program could 
look as follows:

 package myclient;

 use POE:
 use base qw(POE::Component::Client::Stomp);

 use strict;
 use warnings;

 sub handle_connection {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
 
    my $nframe = $self->{stomp}->connect({login => 'testing', passcode => 'testing'});
    $kernel->yield('handle_send' => $nframe);

 }

 sub handle_connected {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

    my $nframe = $self->{stomp}->subscribe({destination => $self->{CONFIG}->{Queue}, ack => 'client'});
    $kernel->yield('handle_send' => $nframe);

 }
 
 sub handle_message {
    my ($kernel, $self, $frame) = @_[KERNEL, OBJECT, ARG0];

    my $message_id = $frame->headers->{'message-id'};
    my $nframe = $self->{stomp}->ack({'message-id' => $message_id});
    $kernel->yield('handle_send' => $nframe);

 }

 package main;

 use POE;
 use strict;

     myclient->spawn(
        Alias => 'testing',
        Queue => '/queue/testing',
    );

    $poe_kernel->run();

    exit 0;


=head1 DESCRIPTION

This module is an object wrapper. It handles the nitty-gritty details of 
setting up the communications channel to a message queue server. It will 
attempt to maintain that channel when/if that server should happen to 
disappear off the network. There is nothing more unpleasent then having to go
around to 30 servers and restarting processes.

When messages are received, specific events are generated. Those events are 
based on the message type. If you are interested in those events you should 
override the default behaviour for those events. The default behaviour is to 
do nothing.

=head1 METHODS

=over 4

=item spawn

This method initializes the object and starts a session to handle the 
communications channel. The only parameters that having meaning are:

=over 4

 Alias         - The alias for this session, defaults to 'stomp-client'
 RemoteAddress - The host where the server lives, defaults to 'localhost'
 RemotePort    - The port the server is listening on, defaults to '61613'

=back

Any other passed parameters are available in the $self->{CONFIG} hash. The 
module POE::Component::Client::Stomp::Utils is also loaded and those methods
can be reached using the $self->{stomp} variable. This module is a handy way
to create STOMP frames.

=item handle_send

You use this event to send STOMP frames to the server. 

=over 4

=item Example

 $kernel->yield('handle_send', $frame);

=back

=item handle_connection

This event is signaled and the corresponding method is called upon initial 
connection to the message server. For the most part you should send a 
"connect" frame to the server.

=over 4

=item Example

 sub handle_connection {
     my ($kernel, $self) = @_[KERNEL,$OBJECT];
 
    my $nframe = $self->{stomp}->connect({login => 'testing', 
                                          passcode => 'testing'});
    $kernel->yield('handle_send' => $nframe);
     
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
 
     my $nframe = $self->{stomp}->subscribe({destination => $self->{CONFIG}->{Queue}, ack => 'client'});
     $kernel->yield('handle_send' => $nframe);
     
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
     my $nframe = $self->{stomp}->ack({'message-id' => $message_id});
     $kernel->yield('handle_send' => $nframe);
     
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
