#!/usr/bin/env python3
"""smol-pi-pty: allocate a PTY and run a command in it.

Used by smol-pi to background `smolvm machine run -it` — smolvm requires
a TTY (-t) to actually execute the VM command and apply volume mounts,
but we need to run it in the background so we can poll for SSH readiness.

This script allocates a pseudo-TTY, runs the given command as a child
process attached to it, and exits when the child exits. Output from the
child is written to stderr of this script (so the caller can capture it
via normal shell redirection).

Usage:
  smol-pi-pty <command> [args ...]

Exit status: the child's exit status.
"""

import os
import pty
import select
import signal
import sys
import termios
import struct
import fcntl


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: smol-pi-pty <command> [args ...]\n")
        return 2

    command = sys.argv[1:]
    
    # Create a pseudo-TTY pair
    master_fd, slave_fd = pty.openpty()
    
    # Set a reasonable window size on the PTY so terminal-aware programs
    # don't complain (we'll get the real size from the ssh client later).
    winsize = struct.pack("HHHH", 24, 80, 0, 0)
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)
    
    # Save our real stderr so we can write PTY output to it.
    real_stderr = os.dup(2)
    
    pid = os.fork()
    if pid == 0:
        # Child: attach the slave PTY as stdin/stdout/stderr, then exec.
        os.close(master_fd)
        os.close(real_stderr)
        os.setsid()
        
        # Set the slave as the controlling terminal.
        fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
        
        os.dup2(slave_fd, 0)
        os.dup2(slave_fd, 1)
        os.dup2(slave_fd, 2)
        if slave_fd > 2:
            os.close(slave_fd)
        
        os.execvp(command[0], command)
        os._exit(127)
    
    # Parent: we don't need the slave side.
    os.close(slave_fd)
    
    # Drain the PTY output and write it to our stderr so the caller
    # can capture it. Read until the child exits.
    while True:
        try:
            r, _, _ = select.select([master_fd], [], [], 1.0)
            if master_fd in r:
                try:
                    data = os.read(master_fd, 4096)
                    if not data:
                        break
                    os.write(real_stderr, data)
                except OSError:
                    break
        except (OSError, select.error):
            break
        
        # Check if child has exited.
        try:
            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid == pid:
                # Drain remaining output.
                try:
                    while True:
                        r, _, _ = select.select([master_fd], [], [], 0.5)
                        if master_fd not in r:
                            break
                        data = os.read(master_fd, 4096)
                        if not data:
                            break
                        os.write(real_stderr, data)
                except OSError:
                    pass
                os.close(master_fd)
                os.close(real_stderr)
                if os.WIFEXITED(status):
                    return os.WEXITSTATUS(status)
                elif os.WIFSIGNALED(status):
                    return 128 + os.WTERMSIG(status)
                return 1
        except ChildProcessError:
            break
    
    os.close(master_fd)
    os.close(real_stderr)
    
    # Final waitpid.
    try:
        _, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status):
            return os.WEXITSTATUS(status)
        elif os.WIFSIGNALED(status):
            return 128 + os.WTERMSIG(status)
    except ChildProcessError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())