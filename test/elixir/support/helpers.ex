defmodule Hologram.Test.Helpers do
  import Hologram.Template, only: [sigil_H: 2]

  alias Hologram.Commons.ETS
  alias Hologram.Commons.PLT
  alias Hologram.Commons.ProcessUtils
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Component
  alias Hologram.Runtime.PageDigestRegistry
  alias Hologram.Template.Parser
  alias Hologram.Template.Renderer

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate ir(code, context), to: IR, as: :for_code
  defdelegate parsed_tags(markup), to: Parser, as: :parse_markup
  defdelegate pid(str), to: IEx.Helpers

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
  @spec ets_table_exists?(ETS.tid()) :: boolean
  def ets_table_exists?(table_ref_or_name) do
    table_ref_or_name
    |> :ets.info()
    |> is_list()
  end

  @doc """
  Determines whether the given ETS table name has been registered.
  """
  @spec ets_table_name_registered?(atom) :: boolean
  def ets_table_name_registered?(table_name) do
    # Can't use: table_name |> :ets.whereis() |> is_reference()
    # because Dialyzer will warn about breaking the opacity of the term.
    :ets.whereis(table_name) != :undefined
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
  Determines whether a persistent term with the given key exists.
  """
  @spec persistent_term_exists?(any) :: boolean
  def persistent_term_exists?(key) do
    key in Enum.map(:persistent_term.get(), fn {name, _value} -> name end)
  end

  @doc """
  Determines whether the given process name has been registered.
  """
  @spec process_name_registered?(atom) :: boolean
  def process_name_registered?(name) do
    name in Process.registered()
  end

  @doc """
  Generates a unique random atom.
  """
  @spec random_atom() :: atom
  def random_atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    :"#{inspect(make_ref())}"
  end

  @doc """
  Generates a unique random module alias.
  """
  @spec random_module() :: module
  def random_module do
    random_string()
    |> String.replace(["#", "<", ".", ">"], "")
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  @doc """
  Generates a unique random string.
  """
  @spec random_string() :: String.t()
  def random_string do
    "#{inspect(make_ref())}"
  end

  @doc """
  Returns the HTML for the given component.
  """
  @spec render_component(module, %{atom => any}, %{(atom | {any, atom}) => any}) :: String.t()
  def render_component(module, props, context) do
    props_dom =
      Enum.map(props, fn {name, value} -> {to_string(name), [expression: {value}]} end)

    node = {:component, module, props_dom, []}
    {html, _clients} = Renderer.render_dom(node, context, [])

    html
  end

  @doc """
  Sets up asset fixtures.
  """
  @spec setup_asset_fixtures(String.t()) :: [mapping: %{String.t() => String.t()}]
  def setup_asset_fixtures(static_path) do
    clean_dir(static_path)

    dir_2_path = static_path <> "/test_dir_1/test_dir_2"
    file_1_path = dir_2_path <> "/test_file_1-11111111111111111111111111111111.css"
    file_2_path = dir_2_path <> "/test_file_2-22222222222222222222222222222222.css"
    file_3_path = dir_2_path <> "/page-33333333333333333333333333333333.js"

    dir_3_path = static_path <> "/test_dir_3"
    file_4_path = dir_3_path <> "/test_file_4-44444444444444444444444444444444.css"
    file_5_path = dir_3_path <> "/test_file_5-55555555555555555555555555555555.css"
    file_6_path = dir_3_path <> "/page-66666666666666666666666666666666.js"

    dir_4_path = static_path <> "/hologram"
    file_7_path = dir_4_path <> "/page-77777777777777777777777777777777.js"
    file_8_path = dir_4_path <> "/page-88888888888888888888888888888888.js"
    file_9_path = dir_4_path <> "/test_file_9-99999999999999999999999999999999.css"

    File.mkdir_p!(dir_2_path)
    File.mkdir_p!(dir_3_path)
    File.mkdir_p!(dir_4_path)

    file_paths = [
      file_1_path,
      file_2_path,
      file_3_path,
      file_4_path,
      file_5_path,
      file_6_path,
      file_7_path,
      file_8_path,
      file_9_path
    ]

    Enum.each(file_paths, &File.write!(&1, ""))

    [
      mapping: %{
        "test_dir_1/test_dir_2/test_file_1.css" =>
          "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css",
        "test_dir_1/test_dir_2/test_file_2.css" =>
          "/test_dir_1/test_dir_2/test_file_2-22222222222222222222222222222222.css",
        "test_dir_1/test_dir_2/page.js" =>
          "/test_dir_1/test_dir_2/page-33333333333333333333333333333333.js",
        "test_dir_3/test_file_4.css" =>
          "/test_dir_3/test_file_4-44444444444444444444444444444444.css",
        "test_dir_3/test_file_5.css" =>
          "/test_dir_3/test_file_5-55555555555555555555555555555555.css",
        "test_dir_3/page.js" => "/test_dir_3/page-66666666666666666666666666666666.js",
        "hologram/test_file_9.css" => "/hologram/test_file_9-99999999999999999999999999999999.css"
      }
    ]
  end

  @doc """
  Sets up page digest registry process.
  """
  @spec setup_page_digest_registry(module) :: :ok
  def setup_page_digest_registry(stub) do
    setup_page_digest_registry_dump(stub)
    PageDigestRegistry.start_link([])

    :ok
  end

  @doc """
  Sets up page digest registry dump file.
  """
  @spec setup_page_digest_registry_dump(module) :: :ok
  def setup_page_digest_registry_dump(stub) do
    dump_path = stub.dump_path()

    File.rm(dump_path)

    PLT.start()
    |> PLT.put(:module_a, :module_a_digest)
    |> PLT.put(:module_b, :module_b_digest)
    |> PLT.put(:module_c, :module_c_digest)
    |> PLT.dump(dump_path)

    :ok
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
