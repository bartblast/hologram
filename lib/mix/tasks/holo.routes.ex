defmodule Mix.Tasks.Holo.Routes do
  @moduledoc """
  Prints the list of page routes, ordered by route path.
  """

  use Mix.Task
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run(_args) do
    print_header()
    print_routes()

    :ok
  end

  defp print(output) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(output)
  end

  defp print_divider do
    "-"
    |> String.duplicate(80)
    |> print()
  end

  defp print_header do
    print_divider()
    print("ROUTE / MODULE / SOURCE FILE")
    print_divider()
  end

  defp print_route({route, module}) do
    print(route)
    print(Reflection.module_name(module))
    print(Reflection.source_path(module))
    print_divider()
  end

  defp print_routes do
    Reflection.list_pages()
    |> Enum.map(&{&1.__route__(), &1})
    |> Enum.sort()
    |> Enum.each(&print_route/1)
  end
end
