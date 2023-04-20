defmodule Hologram.Compiler.Reflection do
  @doc """
  Determines whether the given term is an alias.

  ## Examples

      iex> alias?(Calendar.ISO)
      true

      iex> alias?(:abc)
      false
  """
  @spec alias?(any) :: boolean
  def alias?(term)

  def alias?(term) when is_atom(term) do
    term
    |> to_string()
    |> String.starts_with?("Elixir.")
  end

  def alias?(_term), do: false

  @doc """
  Lists Elixir modules belonging to the given OTP apps.
  Erlang modules are filtered out.

  ## Examples

    iex> list_elixir_modules([:hologram, :dialyzer, :sobelow])
    [
      Mix.Tasks.Sobelow,
      Sobelow,
      Sobelow.CI,
      ...,
      Mix.Tasks.Holo.Test.CheckFileNames,
      Hologram.Commons.FileUtils,
      Hologram.Commons.Parser,
      ...
    ]
  """
  @spec list_elixir_modules(list(atom)) :: list(module)
  def list_elixir_modules(apps) do
    apps
    |> Enum.reduce([], fn app, acc ->
      app
      |> Application.spec()
      |> Keyword.fetch!(:modules)
      |> Kernel.++(acc)
    end)
    |> Enum.filter(&alias?/1)
  end

  @doc """
  Returns BEAM definitions for the given module.

  ## Examples

      iex> module_beam_defs(Hologram.Compiler.Reflection)
      [
        ...,
        {{:alias?, 1}, :def, [line: 14],
        [
          {[line: 16], [{:term, [version: 0, line: 16], nil}],
            [
              {{:., [line: 16], [:erlang, :is_atom]}, [line: 16],
              [{:term, [version: 0, line: 16], nil}]}
            ],
            {{:., [line: 19], [String, :starts_with?]}, [line: 19],
            [
              {{:., [line: 18], [String.Chars, :to_string]}, [line: 18],
                [{:term, [version: 0, line: 17], nil}]},
              "Elixir."
            ]}},
          {[line: 22], [{:_, [line: 22], nil}], [], false}
        ]}
      ]
  """
  @spec module_beam_defs(module) :: list(tuple)
  def module_beam_defs(module) do
    module
    |> :code.which()
    |> BeamFile.debug_info!()
    |> Map.fetch!(:definitions)
  end
end
