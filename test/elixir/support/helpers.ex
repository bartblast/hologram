defmodule Hologram.Test.Helpers do
  import Hologram.Template, only: [sigil_H: 2]

  alias Hologram.Commons.ProcessUtils
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Component
  alias Hologram.Template.Parser
  alias Hologram.Template.Renderer

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate ir(code, context), to: IR, as: :for_code
  defdelegate parsed_tags(markup), to: Parser, as: :parse_markup

  @doc """
  Removes all files and directories inside the given directory.
  """
  @spec clean_dir(String.t()) :: :ok
  def clean_dir(path) do
    File.rm_rf!(path)
    File.mkdir_p!(path)

    :ok
  end

  @doc """
  Builds empty Component.Client struct.
  """
  @spec build_component_client() :: Component.Client.t()
  def build_component_client do
    %Component.Client{}
  end

  @doc """
  Builds empty Component.Server struct.
  """
  @spec build_component_server() :: Component.Server.t()
  def build_component_server do
    %Component.Server{}
  end

  @doc """
  Determines whether the given ETS table exists.
  """
  @spec ets_table_exists?(:ets.tid()) :: boolean
  def ets_table_exists?(table_ref_or_name) do
    table_ref_or_name
    |> :ets.info()
    |> is_list()
  end

  @doc """
  Installs Hologram JS deps.
  """
  @spec install_lib_js_deps() :: :ok
  def install_lib_js_deps do
    opts = [cd: "assets", into: IO.stream(:stdio, :line)]
    System.cmd("npm", ["install"], opts)
    :ok
  end

  @doc """
  Encodes Elixir source code to JavaScript source code.

  ## Examples

      iex> js("[1, :abc]")
      "Type.list([Type.integer(1), Type.atom(\"abc\")])"
  """
  @spec js(String.t()) :: String.t()
  def js(code) do
    code
    |> ir(%Context{})
    |> Encoder.encode(%Context{})
  end

  @doc """
  Determines whether the given process name has been registered.
  """
  @spec process_name_registered?(atom) :: boolean
  def process_name_registered?(name) do
    name in Process.registered()
  end

  @doc """
  Generates a random atom.
  """
  @spec random_atom() :: atom
  def random_atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    :"#{inspect(make_ref())}"
  end

  @doc """
  Returns the HTML for the given component.
  """
  @spec render_component(module, %{atom => any}, %{(atom | {any, atom}) => any}) :: String.t()
  def render_component(module, props, context) do
    props_dom =
      Enum.map(props, fn {name, value} -> {to_string(name), [expression: {value}]} end)

    node = {:component, module, props_dom, []}
    {html, _clients} = Renderer.render(node, context, [])

    html
  end

  @doc """
  Returns the template for the given markup.
  """
  defmacro template(markup) do
    quote do
      sigil_H(unquote(markup), [])
    end
  end

  @doc """
  Waits until the specified process is no longer running.

  ## Examples

      iex> wait_for_process_cleanup(:my_process)
      :ok
  """
  @spec wait_for_process_cleanup(atom) :: :ok
  def wait_for_process_cleanup(name) do
    if ProcessUtils.running?(name) do
      :timer.sleep(1)
      wait_for_process_cleanup(name)
    else
      :ok
    end
  end
end
