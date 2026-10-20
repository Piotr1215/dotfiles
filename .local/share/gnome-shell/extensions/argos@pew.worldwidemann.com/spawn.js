// LOCAL PATCH (dotfiles): argos's script launcher, kept free of shell imports
// so a plain gjs test can run it. utilities.js re-exports it. Reapply after an
// argos update, which overwrites utilities.js. Offered upstream as
// https://github.com/p-e-w/argos/pull/192.
//
// GNOME Shell replaces GLib.spawn_async_with_pipes for every extension
// (ui/environment.js, wrapSpawnFunction) with Shell.util_spawn_async_with_pipes,
// which hands GLib a child_setup. Any child_setup sends GLib down its fork()
// path, so each launch copied the page tables of the 560 MB shell and then
// blocked the main thread reading the exec report pipe: ~20 ms per launch,
// twice a second with the two 1s scripts, seen as video stutter.
//
// Gio.Subprocess is not wrapped. With no cwd, no child_setup and INHERIT_FDS it
// takes GLib's posix_spawn (vfork) path. Costs: shell fds without O_CLOEXEC
// (GPU device nodes, sockets) stay open in the scripts; scripts inherit the
// shell's ignored SIGPIPE, which the fork path reset, so a pipeline writer
// gets EPIPE instead of dying; and the wrapper's RLIMIT_NOFILE restore is
// skipped, harmless while the shell's own soft limit is the default 1024.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

/**
 * Run argv and pass its whole stdout to callback at EOF, as upstream does,
 * not at exit: a script that closes stdout and keeps running must not hold
 * its button. flags and childSetup stay in the upstream signature but are
 * ignored: a child_setup would bring the fork back. A workingDirectory is
 * honoured, at the cost of the fork path.
 * @param {string|null} workingDirectory - cwd for the child, null to inherit
 * @param {string[]} argv - absolute path of the script, then its arguments
 * @param {string[]} envp - full environment as KEY=VALUE strings
 * @param {number} flags - ignored
 * @param {Function|null} childSetup - ignored
 * @param {Function} callback - receives stdout, "" if it could not be read
 */
export function spawnWithCallback(workingDirectory, argv, envp, flags, childSetup, callback) {
  const launcher = new Gio.SubprocessLauncher({
    flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE |
      Gio.SubprocessFlags.INHERIT_FDS,
  });
  launcher.set_environ(envp);
  if (workingDirectory)
    launcher.set_cwd(workingDirectory);

  const proc = launcher.spawnv(argv);
  const sink = Gio.MemoryOutputStream.new_resizable();
  sink.splice_async(proc.get_stdout_pipe(),
    Gio.OutputStreamSpliceFlags.CLOSE_SOURCE | Gio.OutputStreamSpliceFlags.CLOSE_TARGET,
    GLib.PRIORITY_LOW, null, (stream, result) => {
      let output = "";
      try {
        stream.splice_finish(result);
        output = new TextDecoder().decode(stream.steal_as_bytes().toArray());
      } catch (error) {
        logError(error, `argos: reading output of ${argv[0]}`);
      }
      callback(output);
    });
}
