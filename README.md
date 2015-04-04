# NAME

Daemon::Device - Forking daemon device construct

# VERSION

version 1.000

[![Build Status](https://travis-ci.org/gryphonshafer/Daemon-Device.svg)](https://travis-ci.org/gryphonshafer/Daemon-Device)
[![Coverage Status](https://coveralls.io/repos/gryphonshafer/Daemon-Device/badge.png)](https://coveralls.io/r/gryphonshafer/Daemon-Device)

# SYNOPSIS

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

# DESCRIPTION

This module provides a straight-forward and simple construct to creating
applications that run as daemons and fork some number of child processes.
This module leverages the excellent [Daemon::Control](https://metacpan.org/pod/Daemon::Control) to provide the
functionality for the daemon itself, and it manages the spawning and
monitoring of the children. It also provides some hooks into various parts of
the daemon's lifecycle.

# METHODS

The following are methods of this module.

## new

The `new()` method expects a series of parameters to setup the device. It
returns a Daemon::Device object that you should probably immediately call
`run()` on.

    exit Daemon::Device->new(
        daemon => \%daemon_control_settings,
        spawn  => 3,        # number of children to spawn
        parent => \&parent, # code to run in the parent
        child  => \&child,  # code to run in the children
    )->run;

### daemon

One of the most important parameter, and it is required, is the "daemon"
parameter, which contains a hashref of parameters that are passed as-is to
[Daemon::Control](https://metacpan.org/pod/Daemon::Control). (It is almost a certainty you'll want to read the
[Daemon::Control](https://metacpan.org/pod/Daemon::Control) documentation to understand the details of these parameters.)

### spawn

This is the number of child processes that should be spawned off the parent
process initially. The number of child processes can be changed during runtime
by calling `adjust_spawn()`. During runtime, you can also send INT or TERM
signals to the children to kill them off. However, ensure the "replace\_children"
parameter is set to false or else the parent will spawn new children to replace
the dead ones.

If "spawn" is not defined, the default of 1 child will be assumed.

### parent

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
subroutine that will do that, like a `while` loop.

If "parent" is not defined, then the parent will simply sit around and wait for
all the children to exit or for the parent to be told to exit by external
signal or other means.

### child

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
subroutine that will do that, like a `while` loop.

If "child" is not defined, then the child will sit around and wait forever.
Not sure why you'd want to spawn children and then let them be lazy like this
since idle hands are the devil's playthings, though.

### replace\_children

This is a boolean, which defaults to true, and indicates whether or not the
parent process should spawn additional children to replace children that die
for whatever reason.

### parent\_hup\_to\_child

This is a boolean, which defaults to true, and indicates whether or not the
parent process should, when it receives a HUP signal, should echo that signal
down to all its children.

### on\_startup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process just prior to
the parent spawning the initial set of children. The subroutine will be passed
a reference to the device object.

### on\_shutdown

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process just prior to
the parent shutting down. This event happens after the parent tells all its
children to shutdown, but the children may or may not have actually shutdown
prior to this parent `on_shutdown` event. The subroutine will be passed
a reference to the device object.

### on\_spawn

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

### on\_parent\_hup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process when the parent
receives a HUP signal. The subroutine will be passed a reference to the device
object.

### on\_child\_hup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside child processes when the child
receives a HUP signal. The subroutine will be passed a reference to the device
object and the "child data" hashref.

### on\_parent\_death

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process just after the
parent receives an instruction to shutdown. So when a parent gets a shutdown
order, this hook gets called, then the parent sends termination orders to all
its children, then triggers the `on_shutdown` hook. The subroutine will be
passed a reference to the device object.

### on\_child\_death

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside child processes just prior to
the child shutting down. The subroutine will be passed a reference to the
device object and the "child data" hashref.

### on\_replace\_child

If the `replace_children` parameter is not defined or is set to a true value,
then the parent will spawn new children to replace children that die. The
`on_replace_child` optional parameter is a runtime hook. It expects a
subroutine reference for code that should be called from inside the parent just
prior to replacing a dead child. The subroutine will be passed a reference to
the device object and the "child data" hashref.

## run

The `run()` method calls the method of the same name from [Daemon::Control](https://metacpan.org/pod/Daemon::Control).
This will make your program act like an init file, accepting input from the
command line. Run will exit with 0 for success and uses LSB exit codes.

## adjust\_spawn

The `adjust_spawn` method lets the parent set a new spawn numerical value
during runtime. Lets say you have 10 children and they're fat (i.e. hogging
memory) and lazy (i.e. not doing anything) and you want to "thin the herd," so
to speak. Or perhaps you only spawned 2 children and there's more work than the
2 can handle. The `adjust_spawn` method let's you spawn or terminate children.

When you raise the total number of spawn, the parent will order the spawning,
but the children may or may not be completely spawned by the time
`adjust_spawn` returns. Normally, this shouldn't be a problem. When you lower
the total number of spawn, `adjust_spawn` will not return until some children
are really dead sufficient to bring the total number of children to the spawn
number.

# SEE ALSO

[Daemon::Control](https://metacpan.org/pod/Daemon::Control).

You can also look for additional information at:

- [GitHub](https://github.com/gryphonshafer/Daemon-Device)
- [CPAN](http://search.cpan.org/dist/Daemon-Device)
- [MetaCPAN](https://metacpan.org/pod/Daemon::Device)
- [AnnoCPAN](http://annocpan.org/dist/Daemon-Device)
- [Travis CI](https://travis-ci.org/gryphonshafer/Daemon-Device)
- [Coveralls](https://coveralls.io/r/gryphonshafer/Daemon-Device)
- [CPANTS](http://cpants.cpanauthors.org/dist/Daemon-Device)
- [CPAN Testers](http://www.cpantesters.org/distro/D/Daemon-Device.html)

# AUTHOR

Gryphon Shafer <gryphon@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Gryphon Shafer.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
