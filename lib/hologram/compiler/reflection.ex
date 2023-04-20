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
  Lists loaded OTP applications.

  ## Examples

    iex> list_loaded_otp_apps()
    [
      {:inets, 'INETS  CXC 138 49', '8.2.1'},
      {:logger, 'logger', '1.14.3'},
      {:stdlib, 'ERTS  CXC 138 10', '4.2'},
      {:file_system, 'A file system change watcher wrapper based on [fs](https://github.com/synrc/fs)', '0.2.10'},
      ...
    ]
  """
  @spec list_loaded_otp_apps() :: list(:atom)
  def list_loaded_otp_apps do
    apps_info = Application.loaded_applications()
    Enum.map(apps_info, fn {app, _description, _version} -> app end)
  end

  @doc """
  Returns BEAM definitions for the given module.
  If the BEAM file doesn't have debug info an empty list is returned.

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

      iex> module_beam_defs(Elixir.Hex)
      []
  """
  @spec module_beam_defs(module) :: list(tuple)
  def module_beam_defs(module) do
    debug_info =
      module
      |> :code.which()
      |> BeamFile.debug_info()

    case debug_info do
      {:ok, %{definitions: definitions}} ->
        definitions

      {:error, :no_debug_info} ->
        []
    end
  end
end
