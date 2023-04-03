defmodule Hologram.Compiler.Reflection do
  @doc """
  Determines whether the given term is an alias.

  ## Examples

      iex> is_alias?(Calendar.ISO)
      true

      iex> is_alias?(:abc)
      false
  """
  @spec is_alias?(any) :: boolean
  def is_alias?(term)

  def is_alias?(term) when is_atom(term) do
    term
    |> to_string()
    |> String.starts_with?("Elixir.")
  end

  def is_alias?(_), do: false

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
      Keyword.fetch!(Application.spec(app), :modules) ++ acc
    end)
    |> Enum.filter(&is_alias?/1)
  end
end
