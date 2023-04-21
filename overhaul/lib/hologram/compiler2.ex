defmodule Hologram.Compiler do
  alias Hologram.Compiler.Reflection

  def compile do
    # TODO: use Application.loaded_applications/0
    # apps = [:hologram]

    modules_to_recompile =
      Reflection.list_loaded_otp_apps()
      |> Reflection.list_elixir_modules()
      |> Enum.each(fn module ->
        IO.puts("module = #{module}")
        Reflection.module_beam_defs(module) |> :erlang.phash2()
      end)
  end
end
