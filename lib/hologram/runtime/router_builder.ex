# DEFER: test

defmodule Hologram.Runtime.RouterBuilder do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Router

  @generated_module Hologram.Runtime.RouterMatcher

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    create_matcher_module()
    {:ok, nil}
  end

  def rebuild do
    stop()
    run()
  end

  def run do
    start_link(nil)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  defp add_route_segment_info(route_segment) do
    case route_segment do
      ":" <> name -> {:param, name}
      name -> {:literal, name}
    end
  end

  defp build_function_params(route_segments) do
    tuple_elems =
      Enum.map(route_segments, fn
        {:param, name} -> name
        {:literal, name} -> ~s("#{name}")
      end)
      |> Enum.join(", ")

    "{" <> tuple_elems <> "}"
  end

  defp build_match_function_def(page) do
    route_segments = get_route_segments(page)
    function_params = build_function_params(route_segments)
    page_params = build_page_params(route_segments)

    """
    def match(#{function_params}) do
      {#{page}, #{page_params}}
    end
    """
  end

  defp build_page_params(route_segments) do
    map_elems =
      route_segments
      |> Enum.reject(fn {type, _} -> type == :literal end)
      |> Enum.map(fn {_, name} -> "#{name}: #{name}" end)
      |> Enum.join(", ")

    "%{" <> map_elems <> "}"
  end

  def create_matcher_module do
    function_defs =
      Reflection.list_release_pages()
      |> Enum.reduce("", fn page, acc ->
        "#{acc}#{build_match_function_def(page)}\n"
      end)

    module_body = """
    #{function_defs}
    def match(_), do: nil
    """

    ast = Reflection.ast(module_body)

    if Hologram.Compiler.Reflection.is_module?(@generated_module) do
      :code.delete(@generated_module)
      :code.purge(@generated_module)
    end

    Module.create(@generated_module, ast, Macro.Env.location(__ENV__))
  end

  defp get_route_segments(page) do
    page.route()
    |> Router.get_path_segments()
    |> Enum.map(&add_route_segment_info/1)
  end
end
