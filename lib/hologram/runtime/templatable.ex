defmodule Hologram.Runtime.Templatable do
  alias Hologram.Compiler.AST
  alias Hologram.Runtime.ComponentClient
  alias Hologram.Template.Builder

  defmacro __using__(_opts) do
    quote do
      alias Hologram.Runtime.Templatable

      @doc """
      Returns a template in the form of an anonymous function that given variable bindings returns a VDOM tree.
      """
      @callback template() :: (map -> list)
    end
  end

  @doc """
  Resolves the colocated template path for the given templatable module (page, layout, component) given its file path.
  """
  @spec colocated_template_path(String.t()) :: String.t()
  def colocated_template_path(templatable_file) do
    Path.rootname(templatable_file) <> ".holo"
  end

  @doc """
  Returns the AST of template/0 function definition that uses markup fetched from the give template file.
  If the given template file doesn't exist nil is returned.
  """
  @spec maybe_define_template_fun(String.t(), module) :: AST.t() | nil
  def maybe_define_template_fun(template_path, behaviour) do
    if File.exists?(template_path) do
      markup = File.read!(template_path)

      quote do
        @impl unquote(behaviour)
        def template do
          sigil_H(unquote(markup), [])
        end
      end
    end
  end

  @doc """
  Puts the given key-value pair to the component client state.
  """
  @spec put_state(ComponentClient.t(), atom, any) :: ComponentClient.t()
  def put_state(%{state: state} = client, key, value) do
    %{client | state: Map.put(state, key, value)}
  end

  defmacro sigil_H({:<<>>, _meta, [markup]}, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defmacro sigil_H(markup, _modifiers) do
    build_h_sigil_ast(markup)
  end

  defp build_h_sigil_ast(markup) do
    quote do
      fn var!(data) ->
        _fix_unused_data_var = var!(data)
        unquote(Builder.build(markup))
      end
    end
  end
end
