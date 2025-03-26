defmodule Hologram.Test.Helpers do
  import ExUnit.Assertions
  import Hologram.Commons.Guards, only: [is_regex: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Hologram.Template, only: [sigil_HOLO: 2]

  alias Hologram.Commons.ETS
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.ProcessUtils
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Component
  alias Hologram.Server
  alias Hologram.Template.Parser
  alias Hologram.Template.Renderer
  alias Hologram.Template.Renderer.Env

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate clean_dir(file_path), to: FileUtils, as: :recreate_dir
  defdelegate ir(code, context \\ %Context{}), to: IR, as: :for_code
  defdelegate parsed_tags(markup), to: Parser, as: :parse_markup

  @doc """
  Asserts that the given module function call raises the given error (with the given error message).
  The expected error message must contain the context information that is appended by blame/2.
  """
  defmacro assert_error(error_module, expected_msg, fun_or_mfargs)

  defmacro assert_error(error_module, expected_msg, {:fn, _meta, _data} = fun) do
    quote do
      try do
        unquote(fun).()
      rescue
        error in unquote(error_module) ->
          assert_error_msg(error, unquote(expected_msg))
      end
    end
  end

  defmacro assert_error(error_module, expected_msg, {:{}, _meta, _data} = mfargs) do
    quote do
      {module, fun, args} = unquote(mfargs)

      try do
        apply(module, fun, wrap_term(args))
      rescue
        error in unquote(error_module) ->
          assert_error_msg(error, unquote(expected_msg))
      end
    end
  end

  defmacro assert_error_msg(error, expected_msg) do
    quote do
      error_msg = resolve_error_msg(unquote(error), __STACKTRACE__)

      # is_regex/1 is a guard, so we need to wrap the arg to prevent compilation warnings.
      if is_regex(wrap_term(unquote(expected_msg))) do
        assert error_msg =~ unquote(expected_msg)
      else
        assert error_msg == unquote(expected_msg)
      end
    end
  end

  @doc """
  Builds empty component struct.
  """
  @spec build_component_struct() :: Component.t()
  def build_component_struct do
    %Component{}
  end

  @doc """
  Builds an error message for ErlangError.
  """
  @spec build_erlang_error_msg(String.t()) :: String.t()
  def build_erlang_error_msg(blame) do
    "Erlang error: #{blame}"
  end

  @doc """
  Builds an error message for KeyError.
  """
  @spec build_key_error_msg(any, map) :: String.t()
  def build_key_error_msg(key, map) do
    "key #{inspect(key)} not found in: #{inspect(map, custom_options: [sort_maps: true])}"
  end

  @doc """
  Builds empty server struct.
  """
  @spec build_server_struct() :: Server.t()
  def build_server_struct do
    %Server{}
  end

  @doc """
  Encodes the given Elixir source code to JavaScript.
  """
  @spec encode_code(String.t(), Context.t()) :: String.t()
  def encode_code(code, context \\ %Context{}) do
    code
    |> ir(context)
    |> Encoder.encode_ir(context)
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
    |> Encoder.encode_ir(%Context{})
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
    make_ref()
    |> inspect()
    |> String.replace(["#", "<", ".", ">"], "")
    |> String.replace("Reference", "a")
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  @doc """
  Generates a unique random module alias.
  """
  @spec random_module() :: module
  def random_module do
    make_ref()
    |> inspect()
    |> String.replace(["#", "<", ".", ">"], "")
    |> String.replace("Reference", "M")
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  @doc """
  Generates a unique random string.
  """
  @spec random_string() :: String.t()
  def random_string do
    make_ref()
    |> inspect()
    |> String.replace(["#", "<", ".", ">"], "")
    |> String.replace("Reference", "s")
  end

  @doc """
  Returns the HTML for the given component.
  """
  @spec render_component(module, %{atom => any}, %{(atom | {any, atom}) => any}) :: String.t()
  def render_component(module, props, context) do
    props_dom = Enum.map(props, fn {name, value} -> {to_string(name), [expression: {value}]} end)

    node = {:component, module, props_dom, []}
    {html, _component_structs} = Renderer.render_dom(node, %Renderer.Env{context: context})

    html
  end

  @doc """
  Renders the given markup.
  """
  @spec render_markup(fun, %{atom => any}, Env.t()) :: String.t()
  def render_markup(template, vars \\ %{}, env \\ %Env{}) do
    vars
    |> template.()
    |> Renderer.render_dom(env)
    |> elem(0)
  end

  defmacro resolve_error_msg(error, stacktrace) do
    quote do
      {error_with_blame, _stacktrace} =
        Exception.blame(:error, unquote(error), unquote(stacktrace))

      Exception.message(error_with_blame)
    end
  end

  @doc """
  Returns the template for the given markup.
  """
  defmacro template(markup) do
    quote do
      sigil_HOLO(unquote(markup), [])
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
