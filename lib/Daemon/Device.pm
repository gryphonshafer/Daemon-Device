package Daemon::Device;
# ABSTRACT: Forking daemon device construct

use strict;
use warnings;
use 5.0113;
use Daemon::Control;
use Carp 'croak';
use POSIX ":sys_wait_h";

# VERSION

sub new {
    my $class = shift;
    croak 'new() called with uneven number of parameters' if ( @_ % 2 );

    my $self = bless( {@_}, $class );

    if ( not $self->{daemon}{user} ) {
        my $user = getlogin || getpwuid($<) || 'root';
        $self->{daemon}{user} ||= $user;
    }
    $self->{daemon}{group} ||= $self->{daemon}{user};

    croak 'new() called without "daemon" parameter as a hashref' unless ( ref( $self->{daemon} ) eq 'HASH' );
    for ( qw( program program_args ) ) {
        croak qq{new() called with "daemon" hashref containing "$_" key} if ( $self->{daemon}{$_} );
    }
    for ( qw(
        parent child
        on_startup on_shutdown on_spawn on_parent_hup on_child_hup
        on_parent_death on_child_death on_replace_child
    ) ) {
        croak qq{new() called with "$_" parameter not a coderef}
            if ( exists $self->{$_} and ref( $self->{$_} ) ne 'CODE' );
    }

    $self->{daemon}{program}      = \&parent;
    $self->{daemon}{program_args} = [$self];

    $self->{spawn}               ||= 1;
    $self->{replace_children}    //= 1;
    $self->{parent_hup_to_child} //= 1;

    $self->{children}    = [];
    $self->{parent_data} = {};
    $self->{daemon}      = Daemon::Control->new( %{ $self->{daemon} } );

    return $self;
}

sub run {
    my ($self) = @_;
    return $self->{daemon}->run;
}

sub parent {
    my ( $daemon, $self ) = @_;

    $SIG{'HUP'} = sub {
        $self->{on_parent_hup}->($self) if ( $self->{on_parent_hup} );
        if ( $self->{parent_hup_to_child} ) {
            kill( 'HUP', $_->{pid} ) for ( @{ $self->{children} } );
        }
    };

    my $terminate = sub {
        $self->{on_parent_death}->($self) if ( $self->{on_parent_death} );
        kill( 'TERM', $_->{pid} ) for ( @{ $self->{children} } );
        $self->{on_shutdown}->($self) if ( $self->{on_shutdown} );
        exit;
    };
    $SIG{$_} = $terminate for ( qw( TERM INT ABRT QUIT ) );

    $SIG{'CHLD'} = sub {
        if ( $self->{replace_children} ) {
            $self->{on_replace_child}->($self) if ( $self->{on_replace_child} );
            for ( @{ $self->{children} } ) {
                $_ = spawn($self) if ( waitpid( $_->{pid}, WNOHANG ) );
            }
        }
    };

    $self->{on_startup}->($self) if ( $self->{on_startup} );

    for ( 1 .. $self->{spawn} ) {
        push( @{ $self->{children} }, spawn($self) );
    }

    if ( $self->{parent} ) {
        $self->{parent}->($self);
    }
    else {
        wait;
    }

    return;
}

sub spawn {
    my ($self) = @_;

    my $child_data = {};
    $self->{on_spawn}->( $self, $child_data ) if ( $self->{on_spawn} );

    if ( my $pid = fork ) {
        $child_data->{pid} = $pid;
        return $child_data;
    }
    else {
        $child_data->{pid} = $$;
        child( $self, $child_data );
        exit;
    }

    return;
}

sub child {
    my ( $self, $child_data ) = @_;

    $SIG{'HUP'} = sub {
        $self->{on_child_hup}->( $self, $child_data ) if ( $self->{on_child_hup} );
    };

    my $terminate = sub {
        $self->{on_child_death}->( $self, $child_data ) if ( $self->{on_child_death} );
        exit;
    };
    $SIG{$_} = $terminate for ( qw( TERM INT ABRT QUIT ) );

    if ( $self->{child} ) {
        $self->{child}->( $self, $child_data );
    }
    else {
        sleep 1 while (1);
    }

    return;
}

sub adjust_spawn {
    my ( $self, $new_spawn_count ) = @_;
    $self->{spawn} = $new_spawn_count;

    if ( @{ $self->{children} } < $self->{spawn} ) {
        push( @{ $self->{children} }, spawn($self) ) while ( @{ $self->{children} } < $self->{spawn} );
    }
    elsif ( @{ $self->{children} } > $self->{spawn} ) {
        my $set_replace_children = $self->{replace_children};
        $self->{replace_children} = 0;

        my @killed_pids;
        while ( @{ $self->{children} } > $self->{spawn} ) {
            my $child = shift @{ $self->{children} };
            kill( 'TERM', $child->{pid} );
            push( @killed_pids, $child->{pid} );
        }

        waitpid( $_, 0 ) for (@killed_pids);
        $self->{replace_children} = $set_replace_children;
    }

    return;
}

1;
__END__

=pod

=begin :badges

=for markdown
[![Build Status](https://travis-ci.org/gryphonshafer/Daemon-Device.svg)](https://travis-ci.org/gryphonshafer/Daemon-Device)
[![Coverage Status](https://coveralls.io/repos/gryphonshafer/Daemon-Device/badge.png)](https://coveralls.io/r/gryphonshafer/Daemon-Device)

=end :badges

=head1 SYNOPSIS

    use Daemon::Device;

    exit Daemon::Device->new(
        daemon => {
            name        => 'server_thing',
            lsb_sdesc   => 'Server Thing',
            pid_file    => '/tmp/server_thing.pid',
            stderr_file => '/tmp/server_thing.err',
            stdout_file => '/tmp/server_thing.info',
        },

        spawn  => 3,        # number of children to spawn
        parent => \&parent, # code to run in the parent
        child  => \&child,  # code to run in the children

        replace_children    => 1, # if a child dies, replace it; default is 1
        parent_hup_to_child => 1, # a HUP sent to parent echos to children; default is 1
    )->run;

    sub parent {
        my ($device) = @_;

        while (1) {
            warn "Parent $$ exists (heartbeat)\n";
            $device->adjust_spawn(2);
            sleep 5;
        }
    }

    sub child {
        my ( $device, $child_data ) = @_;

        while (1) {
            warn "Child $$ exists (heartbeat)\n";
            sleep 5;
        }
    }

=head1 DESCRIPTION

This module provides a straight-forward and simple construct to creating
applications that run as daemons and fork some number of child processes.
This module leverages the excellent L<Daemon::Control> to provide the
functionality for the daemon itself, and it manages the spawning and
monitoring of the children. It also provides some hooks into various parts of
the daemon's lifecycle.

=head1 METHODS

The following are methods of this module.

=head2 new

The C<new()> method expects a series of parameters to setup the device. It
returns a Daemon::Device object that you should probably immediately call
C<run()> on.

    exit Daemon::Device->new(
        daemon => \%daemon_control_settings,
        spawn  => 3,        # number of children to spawn
        parent => \&parent, # code to run in the parent
        child  => \&child,  # code to run in the children
    )->run;

=head3 daemon

One of the most important parameter, and it is required, is the "daemon"
parameter, which contains a hashref of parameters that are passed as-is to
L<Daemon::Control>. (It is almost a certainty you'll want to read the
L<Daemon::Control> documentation to understand the details of these parameters.)

=head3 spawn

This is the number of child processes that should be spawned off the parent
process initially. The number of child processes can be changed during runtime
by calling C<adjust_spawn()>. During runtime, you can also send INT or TERM
signals to the children to kill them off. However, ensure the "replace_children"
parameter is set to false or else the parent will spawn new children to replace
the dead ones.

If "spawn" is not defined, the default of 1 child will be assumed.

=head3 parent

This is a reference to a subroutine containing the code that should be executed
in the parent process.

    exit Daemon::Device->new(
        daemon => \%daemon_control_settings,
        child  => \&child,
        parent => sub {
            my ($device) = @_;

            while (1) {
                warn "Parent $$ exists (heartbeat)\n";
                $device->adjust_spawn(2);
                sleep 5;
            }
        },
    )->run;

The subroutine is provided a reference to the device object. It's expected that
if you need to keep the parent running, you'll implement something in this
subroutine that will do that, like a C<while> loop.

If "parent" is not defined, then the parent will simply sit around and wait for
all the children to exit or for the parent to be told to exit by external
signal or other means.

=head3 child

This is a reference to a subroutine containing the code that should be executed
in every child process.

    exit Daemon::Device->new(
        daemon => \%daemon_control_settings,
        child  => sub {
            my ( $device, $child_data ) = @_;

            while (1) {
                warn "Child $$ exists (heartbeat)\n";
                sleep 5;
            }
        },
    )->run;

The subroutine is provided a reference to the device object and a "child data"
hashref that contains at least the child's PID, but may contain other things
if you so hook in somewhere and add them. More on that later. It's expected that
if you need to keep the parent running, you'll implement something in this
subroutine that will do that, like a C<while> loop.

If "child" is not defined, then the child will sit around and wait forever.
Not sure why you'd want to spawn children and then let them be lazy like this
since idle hands are the devil's playthings, though.

=head3 replace_children

This is a boolean, which defaults to true, and indicates whether or not the
parent process should spawn additional children to replace children that die
for whatever reason.

=head3 parent_hup_to_child

This is a boolean, which defaults to true, and indicates whether or not the
parent process should, when it receives a HUP signal, should echo that signal
down to all its children.

=head3 on_startup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process just prior to
the parent spawning the initial set of children. The subroutine will be passed
a reference to the device object.

=head3 on_shutdown

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process just prior to
the parent shutting down. This event happens after the parent tells all its
children to shutdown, but the children may or may not have actually shutdown
prior to this parent C<on_shutdown> event. The subroutine will be passed
a reference to the device object.

=head3 on_spawn

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process just prior to
the parent spawning any child, even children that are spawned to replace
dead children. The subroutine will be passed a reference to the device object
and a reference to an empty hashref that will end up being used as the
"child data" hashref.

All children will be given this "child data" hashref that can be used as a
data store for whatever you need from the parent inside the child. The device
itself will manage the PID key and value.

    exit Daemon::Device->new(
        daemon => \%daemon_control_settings,

        on_spawn => sub {
            my ( $device, $child_data ) = @_;
            $child_data->{pipe} = $device->{parent_data}{pipe} = IO::Pipe->new;
        },

        parent => sub {
            my ( $device, $child_data ) = @_;
            $device->{parent_data}{pipe}->writer;
            $device->{parent_data}{pipe}->say('Hey child, do some work!');
        },

        child => sub {
            my ( $device, $child_data ) = @_;
            $child_data->{pipe}->reader;

            while ( $_ = $child_data->{pipe}->getline ) {
                whine_about($_);
            }
        },

    );

=head3 on_parent_hup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process when the parent
receives a HUP signal. The subroutine will be passed a reference to the device
object.

=head3 on_child_hup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside child processes when the child
receives a HUP signal. The subroutine will be passed a reference to the device
object and the "child data" hashref.

=head3 on_parent_death

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process just after the
parent receives an instruction to shutdown. So when a parent gets a shutdown
order, this hook gets called, then the parent sends termination orders to all
its children, then triggers the C<on_shutdown> hook. The subroutine will be
passed a reference to the device object.

=head3 on_child_death

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside child processes just prior to
the child shutting down. The subroutine will be passed a reference to the
device object and the "child data" hashref.

=head3 on_replace_child

If the C<replace_children> parameter is not defined or is set to a true value,
then the parent will spawn new children to replace children that die. The
C<on_replace_child> optional parameter is a runtime hook. It expects a
subroutine reference for code that should be called from inside the parent just
prior to replacing a dead child. The subroutine will be passed a reference to
the device object and the "child data" hashref.

=head2 run

The C<run()> method calls the method of the same name from L<Daemon::Control>.
This will make your program act like an init file, accepting input from the
command line. Run will exit with 0 for success and uses LSB exit codes.

=head2 adjust_spawn

The C<adjust_spawn> method lets the parent set a new spawn numerical value
during runtime. Lets say you have 10 children and they're fat (i.e. hogging
memory) and lazy (i.e. not doing anything) and you want to "thin the herd," so
to speak. Or perhaps you only spawned 2 children and there's more work than the
2 can handle. The C<adjust_spawn> method let's you spawn or terminate children.

When you raise the total number of spawn, the parent will order the spawning,
but the children may or may not be completely spawned by the time
C<adjust_spawn> returns. Normally, this shouldn't be a problem. When you lower
the total number of spawn, C<adjust_spawn> will not return until some children
are really dead sufficient to bring the total number of children to the spawn
number.

=head1 SEE ALSO

L<Daemon::Control>.

You can also look for additional information at:

=for :list
* L<GitHub|https://github.com/gryphonshafer/Daemon-Device>
* L<CPAN|http://search.cpan.org/dist/Daemon-Device>
* L<MetaCPAN|https://metacpan.org/pod/Daemon::Device>
* L<AnnoCPAN|http://annocpan.org/dist/Daemon-Device>
* L<Travis CI|https://travis-ci.org/gryphonshafer/Daemon-Device>
* L<Coveralls|https://coveralls.io/r/gryphonshafer/Daemon-Device>
* L<CPANTS|http://cpants.cpanauthors.org/dist/Daemon-Device>
* L<CPAN Testers|http://www.cpantesters.org/distro/D/Daemon-Device.html>

=for Pod::Coverage BUILD is_authed json passwd ua user

=cut
