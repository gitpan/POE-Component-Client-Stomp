#!/usr/bin/perl
#
# File: dump_queue.pl
# Date: 27-Sep-2007
# By  : Kevin Esteb
#
# Simple test program to test POE interaction.
#

package Client;

use POE;
use Data::Dumper;
use base qw(POE::Component::Client::Stomp);

use strict;
use warnings;

# ----------------------------------------------------------------------

sub handle_connection {
    my ($kernel, $self) = @_[KERNEL,OBJECT];

    my $frame;
    my $buffer = sprintf("Connected to %s on %s", $self->host, $self->port);

    $self->log($kernel, 'info', $buffer);

    $frame = $self->stomp->connect({login => 'testing', 
                                    passcode => 'testing'});
    $kernel->yield('send_data' => $frame);

}

sub handle_connected {
    my ($kernel, $self, $frame) = @_[KERNEL,OBJECT,ARG0];

    my $nframe;

    $nframe = $self->stomp->subscribe({destination => $self->config('Queue'), 
                                       ack => 'client'});
    $kernel->yield('send_data' => $nframe);

}

sub handle_message {
    my ($kernel, $self, $frame) = @_[KERNEL,OBJECT,ARG0];

    my $message_id = $frame->headers->{'message-id'};
    my $nframe = $self->stomp->ack({'message-id' => $message_id});
    my $buffer = sprintf("Received message #%s", $message_id);
    $self->log($kernel, 'info', $buffer);
    print Dumper($frame) if ($self->config('Dump'));
    $kernel->yield('send_data' => $nframe);

}

sub log {
    my ($self, $kernel, $level, @args) = @_;

    if ($level eq 'error') {

        print "Error: @args\n";

    } elsif ($level eq 'warn') {

        print "Warn : @args\n";

    } elsif ($level eq 'debug') {

        print "Debug: @args\n" if $self->config('Debug');

    } else {

        print "Info : @args\n";

    }

}

sub handle_shutdown {
    my ($self, $kernel) = @_;

    print "Shutting down\n";

}

# =====================================================================

package main;

use POE;
use Getopt::Long;

use strict;
use warnings;

my $dump = 0;
my $debug = 0;
my $port = '61613';
my $hostname = 'localhost';
my $queue = '/queue/testing';

my $VERSION = '0.01';

# ----------------------------------------------------------------------

sub handle_signals {

    $poe_kernel->yield('shutdown');

}

sub usage {

    my ($Script) = ( $0 =~ m#([^\\/]+)$# );
    my $Line = "-" x length( $Script );

    print << "EOT";
$Script
$Line
dump_queue - Dump a STOMP message queue.
Version: $VERSION

Usage:

    $0 [--hostname] <hostname>
    $0 [--port] <port number>
    $0 [--queue] <queue name>
    $0 [--dump]
    $0 [--help]
    $0 [--debug]

    --hostname..The host where the server is localed
    --port......The port to connect too
    --queue.....The message queue to listent too
    --dump......A flag to indicate dumping of the message body
    --debug.....Print debugging messages
    --help......Print this help message.

Examples:

    $0 --hostname mq.example.com --port 61613 --queue /queue/testing
    $0 --help

EOT

}

sub setup {

    my $help;

    GetOptions('help|h|?' => \$help, 
               'hostname=s' => \$hostname,
               'port=s' => \$port,
               'queue=s' => \$queue,
               'dump' => \$dump,
               'debug' => \$debug);

    if ($help) {

        usage();
        exit 0;

    }

}

main: {

    setup();

    Client->spawn(
        RemoteAddress => $hostname,
        RemotePort => $port,
        Alias => 'testing',
        Queue => $queue,
        Dump => $dump,
        Debug => $debug,
    );

    $poe_kernel->state('got_signal', \&handle_signals);
    $poe_kernel->sig(INT => 'got_signal');

    $poe_kernel->run();

    exit 0;

}

