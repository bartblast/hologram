defmodule Hologram.Router do
  alias Hologram.Compiler.Reflection

  defmacro __using__(_) do
    quote do
      import Hologram.Router, only: [hologram_routes: 0]
    end
  end

  # TODO: test
  defmacro hologram_routes do
    if Reflection.has_release_page_list?() do
      for page <- Reflection.list_release_pages() do
        if function_exported?(page, :route, 0) do
          quote do
            get unquote(page.route()), Hologram.Runtime.Controller, :index,
              private: %{hologram_page: unquote(page)}
          end
        end
      end
    end
  end

  # Routes are defined in page modules and the router aggregates the routes dynamically by reflection.
  # So everytime a route is updated in a page module, we need to explicitely recompile the router module, so that
  # it rebuilds the list of routes.
  def reload_routes() do
    router_path = Reflection.release_router_path()

    opts = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)
    Code.compile_file(router_path)
    Code.compiler_options(ignore_module_conflict: opts.ignore_module_conflict)
  end
end
