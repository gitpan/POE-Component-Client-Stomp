package POE::Component::Client::Stomp;

use 5.008;
use strict;
use warnings;

use POE::Session;
use POE::Filter::Stomp;
use POE::Component::Client::TCP;

our $VERSION = '0.01';

sub new {
	my ($class) = shift;

	my %args = @_;
	my $session_id;

	$args{RemoteAddress} = 'localhost' unless defined $args{RemoteAddress};
	$args{RemotePort} = '61613' unless defined $args{RemotePort};
	$args{Filter} = 'POE::Filter::Stomp';

	$session_id = POE::Component::Client::TCP->new(%args);

	return $session_id;

}

1;

__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

POE::Component::Client::Stomp - Perl extension for the POE Environment

=head1 SYNOPSIS

 use POE;
 use POE::Component::Client::Stomp;

 POE::Component::Client::Stomp->new(
     InlineStates => {send => \&handle_send },
     Connected => \&handle_connect,
     ServerInput => \&handle_server_input,
 );

 $poe_kernel->run();

 exit 0;

 sub handle_server_input {
     my ($heap, $frame) = @_[HEAPm ARG0];

 }

 sub handle_connect {
     my ($heap, $socket, $peer_address, $peer_port) = 
         @_[HEAP, ARG0, ARG1, ARG2]$

 }

 sub handle_send {
     my ($heap, $frame) = @_[HEAP, ARG0];

     $heap->{server}->put($frame);

 }

=head1 DESCRIPTION

This module is a wrapper around POE::Component::Client::TCP. It supports 
clients that want to use the Stomp protocol to talk to Message Queue servers
such as POE::Component::Server::MessageQueue or ActiveMQ from the Apache 
Foundation.

The following defaults are provided:

     RemoteAddress - localhost
     RemotePort    - 61613

Otherwise all other parameters are passed directly to POE::Component::Client::TCP
verbatium. The module also loads POE::Filter::Stomp as the input/output 
filter. In the callback for "ServerInput" the ARG0 parameter will be a 
Net::Stomp::Frame object.

=head1 EXPORT

None by default.

=head1 SEE ALSO

 Net::Stomp::Frame
 POE::Filter::Stomp
 POE::Component::Client::TCP
 POE::Component::Server::MessageQueue

 For information on the Stomp protocol: http://stomp.codehaus.org/Protocol

=head1 AUTHOR

Kevin L. Esteb, E<lt>kesteb@wsipc.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Kevin L. Esteb

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
