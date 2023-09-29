defmodule Mix.Tasks.Holo.Routes do
  @moduledoc """
  Prints the list of page routes, ordered by route path.
  """

  use Mix.Task
  alias Hologram.Commons.Reflection

  @doc false
  @impl Mix.Task
  def run(_args) do
    print_header()
    print_routes()

    :ok
  end

  defp print_divider do
    "-"
    |> String.duplicate(80)
    |> IO.puts()
  end

  defp print_header do
    print_divider()
    IO.puts("ROUTE / MODULE / SOURCE FILE")
    print_divider()
  end

  defp print_route({route, module}) do
    IO.puts(route)
    IO.puts(Reflection.module_name(module))
    IO.puts(Reflection.source_path(module))
    print_divider()
  end

  defp print_routes do
    Reflection.list_pages()
    |> Enum.map(&{&1.__route__(), &1})
    |> Enum.sort()
    |> Enum.each(&print_route/1)
  end
end
