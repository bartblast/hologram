defmodule Hologram.LiveReload.Standalone.Reloader do
  @moduledoc false

  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler

  @doc """
  Recompiles Elixir code and reloads changed modules.

  Uses digest-based diffing (via `Compiler.build_module_digest_plt!/0`) to reliably
  detect which modules changed, then hot reloads only those modules.

  Returns `:ok` on success, or `{:error, output}` on compilation failure.
  """
  @spec recompile_and_hot_reload :: :ok | {:error, String.t()}
  def recompile_and_hot_reload do
    old_digest_plt = Compiler.build_module_digest_plt!()

    {output, exit_code} =
      SystemUtils.cmd_cross_platform("mix", ["compile"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    if exit_code == 0 do
      new_digest_plt = Compiler.build_module_digest_plt!()
      diff = Compiler.diff_module_digest_plts(old_digest_plt, new_digest_plt)
      reload_changed_modules(diff)
    else
      {:error, output}
    end
  end

  # Reloads the module if it has a .beam file
  defp maybe_reload_module(module) do
    # :code.which/1 can return: charlist (path), :cover_compiled, :non_existing, :preloaded
    # In our case:
    # - :cover_compiled is extremely unlikely (only happens during test runs with --cover)
    # - :non_existing could theoretically happen in edge cases (e.g. file system race conditions)
    # - :preloaded is not possible (preloaded Erlang modules are filtered out by list_elixir_modules/0)    
    beam_path = :code.which(module)

    # Only reload if the module has a .beam file (charlist path)
    if is_list(beam_path) do
      :code.purge(module)
      :code.delete(module)

      binary = read_beam_binary(beam_path)
      {:module, ^module} = :code.load_binary(module, beam_path, binary)
    end
  end

  defp read_beam_binary(beam_path) do
    beam_path
    |> List.to_string()
    |> File.read!()
  end

  defp reload_changed_modules(diff) do
    modules_to_reload = diff.added_modules ++ diff.edited_modules
    Enum.each(modules_to_reload, &maybe_reload_module(&1))
  end
end
