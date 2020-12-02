# NAME

Daemon::Device - Forking daemon device construct

# VERSION

version 1.09

[![test](https://github.com/gryphonshafer/Daemon-Device/workflows/test/badge.svg)](https://github.com/gryphonshafer/Daemon-Device/actions?query=workflow%3Atest)
[![codecov](https://codecov.io/gh/gryphonshafer/Daemon-Device/graph/badge.svg)](https://codecov.io/gh/gryphonshafer/Daemon-Device)

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
        my ($device) = @_;

        while (1) {
            warn "Child $$ exists (heartbeat)\n";
            exit unless ( $device->parent_alive );
            sleep 5;
        }
    }

# DESCRIPTION

This module provides a straight-forward and simple construct to creating
applications that run as daemons and fork some number of child processes.
This module leverages the excellent [Daemon::Control](https://metacpan.org/pod/Daemon%3A%3AControl) to provide the
functionality for the daemon itself, and it manages the spawning and
monitoring of the children. It also provides some hooks into various parts of
the daemon's lifecycle.

The basic idea is that you'll end up with program that can be interacted with
like a Linux service (i.e. in /etc/init.d or similar).

    ./your_program.pl start

On start, it will initiate a single parent process and a number of children
processes. See [Daemon::Control](https://metacpan.org/pod/Daemon%3A%3AControl) for additional information about the core
part of the daemon. What Daemon::Device does beyond this is setup parent and
child creation, monitor and replace children that die off, and offer hooks.

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

One of the most important parameters is the "daemon" parameter. It's required,
and it must contain a hashref of parameters that are passed as-is to
[Daemon::Control](https://metacpan.org/pod/Daemon%3A%3AControl). (It is almost a certainty you'll want to read the
[Daemon::Control](https://metacpan.org/pod/Daemon%3A%3AControl) documentation to understand the details of the parameters
that go in this hashref.)

### spawn

This is an integer and represents the number of child processes that should be
spawned off the parent process initially. The number of child processes can be
changed during runtime by calling `adjust_spawn()`. During runtime, you can
also send INT or TERM signals to the children to kill them off. However, ensure
the "replace\_children" parameter is set to false or else the parent will spawn
new children to replace the dead ones.

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
            my ($device) = @_;

            while (1) {
                warn "Child $$ exists (heartbeat)\n";
                exit unless ( $device->parent_alive );
                sleep 5;
            }
        },
    )->run;

It's expected that if you need to keep the parent running, you'll implement
something in this subroutine that will do that, like a `while` loop.
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
dead children. The subroutine will be passed a reference to the device object.

### on\_parent\_hup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside the parent process when the parent
receives a HUP signal. The subroutine will be passed a reference to the device
object.

### on\_child\_hup

This optional parameter is a runtime hook. It expects a subroutine reference
for code that should be called from inside child processes when the child
receives a HUP signal. The subroutine will be passed a reference to the device
object.

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
the device object.

## run

The `run()` method calls the method of the same name from [Daemon::Control](https://metacpan.org/pod/Daemon%3A%3AControl).
This will make your program act like an init file, accepting input from the
command line. Run will exit with 0 for success and uses LSB exit codes.

## daemon

If you need to access the [Daemon::Control](https://metacpan.org/pod/Daemon%3A%3AControl) object inside the device, you can
do so with the `daemon()` method.

## ppid, cpid

These methods return the parent PID or child PID. From both parent processes
and child processes, `ppid` will return the parent's PID. From only child
processes, `cpid` will return the child's PID. From the parent, `cpid` will
return undef.

## children

This will return an arrayref of PIDs for all the children currently spawned.

## adjust\_spawn

The `adjust_spawn` method accepts a positive integer, and from it tells the
parent process to set a new spawn numerical value during runtime. Lets say you
have 10 children and they're fat (i.e. hogging memory) and lazy (i.e. not doing
anything) and you want to "thin the herd," so to speak. Or perhaps you only
spawned 2 children and there's more work than the 2 can handle. The
`adjust_spawn` method let's you spawn or terminate children.

When you raise the total number of spawn, the parent will order the spawning,
but the children may or may not be completely spawned by the time
`adjust_spawn` returns. Normally, this shouldn't be a problem. When you lower
the total number of spawn, `adjust_spawn` will not return until some children
are really dead sufficient to bring the total number of children to the spawn
number.

## replace\_children, parent\_hup\_to\_child

These are simple get-er/set-er methods for the `replace_children` and
`parent_hup_to_child` values, allowing you to change them during runtime.
This should be done in parents. Remember that data values are copied into
children during spawning (i.e. forking), so changing these values in children
is meaningless.

## parent\_alive

The `parent_alive` method returns true if the daemon parent still lives or
false if it doesn't live. This is useful when writing child code, since a child
should periodically check to see if it's an orphan.

    exit Daemon::Device->new(
        daemon => \%daemon_control_settings,
        child  => sub {
            my ($self) = @_;
            while (1) {
                exit unless ( $self->parent_alive );
                sleep 1;
            }
        },
    )->run;

# DATA

Each parent and child have a simple data storage mechanism in them under the
"data" parameter and "data" method, all of which is optional. To use it,
you can, if you elect, pass the "data" parameter to `new()`.

    exit Daemon::Device->new(
        daemon => \%daemon_control_settings,
        parent => \&parent,
        child  => \&child,
        data   => {
            answer => 42,
            thx    => 1138,
        },
    )->run;

This will result in the parent getting this data block, which can be accessed
via the `data()` method from within the parent. The `data()` method is a
fairly typical key/value parameter get-er/set-er.

    sub parent {
        my ($device) = @_;
        warn $device->data('answer');            # returns 42
        $device->data( 'answer' => 0 );          # sets "answer" to 0
        $device->data( 'a' => 1, 'b' => 2 );     # set multiple things
        $device->data( { 'a' => 1, 'b' => 2 } ); # set multiple things
        my $data = $device->data                 # hashref of all data
    }

When children are spawned, they will pick up a copy of whatever's in the
parent's data when the spawning takes place. This is a copy, so changing data
in one place does not change it elsewhere. Note also that in some cases you
can't guarentee the exact order or timing of spawning children.

## Helper Methods

As a convenience, you can access any single data value by referencing a method
of the same name.

    $device->data(
        noun => 'World',
        hi   => sub { say "Hello $_[0]" },
    );

    say $device->hi( $device->noun );

# MESSAGING

You can, of course, setup whatever interprocess communications you'd like. In
an attempt to be helpful, this module offers basic interprocess communications
messaging. Normally, this messaging is unused and not activated. However, by
defining an `on_message` handler in `new()`, you will be able to call a
method called `message()` to send messages between a parent and its children
or from any child to its parent. (Child-to-child communication is unsupported,
so if you need that, you'll need to create your own, better communications.)

## on\_message

This optional parameter to `new()` is a runtime hook. It expects a subroutine
reference for code that should be called from inside either the parent or
child process that receives a message sent via the `message()` method.
The subroutine will be passed a reference to the device object and an array
of messages received from a buffer. This is almost always only 1, but it could
be more, so code accordingly.

    sub on_message {
        my $device = shift;
        say "Received message: $_" for (@_);
    }

## message

This method sends a message to a parent from one of its children or from a
child to its parent. It expects the PID of the process to which the message
should be sent and the message itself, which is expected to be a simple text
string. It's up to you to encode/serialize your data for transport.

    $device->message( 1138, 'Message for you, sir.' );

## Messaging Gotchas

If you provide a PID to `message()` that is not valid (not a child of the
parent from which the message originates or not a parent from the child from
which the message originates), suffer an error you will.

Also note that sometimes during spawning of child processes it is possible
that a message from the parent can get sent to a child before that child is
ready to receive the message, in which case the message will be dropped.
If you want to get data from the parent to the child, have the child tell the
parent it's ready, then have the parent send the child data.

The `on_message` hook is universal, meaning that it's the same subroutine
that's called from both the parent and children to handle incoming messages.
You'll therefore need to write a little logic to handle the differences if
the use cases requires that.

The messaging is provided through use of a couple of [IO::Pipe](https://metacpan.org/pod/IO%3A%3APipe) objects per
child. The messaging is simple, limited, but fast. If you need something better,
you'll need to construct it yourself, or perhaps consider something like ZeroMQ.

# SEE ALSO

[Daemon::Control](https://metacpan.org/pod/Daemon%3A%3AControl), [IO::Pipe](https://metacpan.org/pod/IO%3A%3APipe).

You can also look for additional information at:

- [GitHub](https://github.com/gryphonshafer/Daemon-Device)
- [MetaCPAN](https://metacpan.org/pod/Daemon::Device)
- [GitHub Actions](https://github.com/gryphonshafer/Daemon-Device/actions)
- [Codecov](https://codecov.io/gh/gryphonshafer/Daemon-Device)
- [CPANTS](http://cpants.cpanauthors.org/dist/Daemon-Device)
- [CPAN Testers](http://www.cpantesters.org/distro/D/Daemon-Device.html)

# AUTHOR

Gryphon Shafer <gryphon@cpan.org>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2015-2021 by Gryphon Shafer.

This is free software, licensed under:

    The Artistic License 2.0 (GPL Compatible)
