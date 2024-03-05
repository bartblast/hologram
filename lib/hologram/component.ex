defmodule Hologram.Component do
  use Hologram.Runtime.Templatable

  alias Hologram.Component
  alias Hologram.Operation

  defstruct context: %{}, next_command: nil, state: %{}

  @type t :: %__MODULE__{
          context: %{atom => any} | %{{module, atom} => any},
          next_command: Operation.t() | nil,
          state: %{atom => any}
        }

  defmacro __using__(_opts) do
    template_path = colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Component
        import Hologram.Router.Helpers, only: [asset_path: 1]
        import Hologram.Template, only: [sigil_H: 2]
        import Templatable, only: [put_context: 3, put_state: 2, put_state: 3]

        alias Hologram.Component

        @before_compile Component

        @behaviour Component

        @external_resource unquote(template_path)

        @doc """
        Returns true to indicate that the callee module is a component module (has "use Hologram.Component" directive).

        ## Examples

            iex> __is_hologram_component__()
            true
        """
        @spec __is_hologram_component__() :: boolean
        def __is_hologram_component__, do: true

        @impl Component
        def init(_props, component, server), do: {component, server}

        defoverridable init: 3
      end,
      maybe_define_template_fun(template_path, __MODULE__),
      register_props_accumulator()
    ]
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns the list of property definitions for the compiled component.
      """
      @spec __props__() :: list({atom, atom, keyword})
      def __props__, do: @__props__
    end
  end

  @doc """
  Resolves the colocated template path for the given component module given its file path.
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
  Accumulates the given property definition in __props__ module attribute.
  """
  @spec prop(atom, atom, keyword) :: Macro.t()
  defmacro prop(name, type, opts \\ []) do
    quote do
      Module.put_attribute(__MODULE__, :__props__, {unquote(name), unquote(type), unquote(opts)})
    end
  end

  @doc """
  Returns the AST of code that registers __props__ module attribute.
  """
  @spec register_props_accumulator() :: AST.t()
  def register_props_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__props__, accumulate: true)
    end
  end
end
