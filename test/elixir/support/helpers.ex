defmodule Hologram.Test.Helpers do
  import ExUnit.Assertions
  import Hologram.Commons.Guards, only: [is_regex: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Hologram.Template, only: [sigil_H: 2]

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.KernelUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.ProcessUtils
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Component
  alias Hologram.Reflection
  alias Hologram.Server
  alias Hologram.Template.Parser
  alias Hologram.Template.Renderer
  alias Hologram.Template.Renderer.Env

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate clean_dir(file_path), to: FileUtils, as: :recreate_dir
  defdelegate ir(code, context \\ %Context{}), to: IR, as: :for_code
  defdelegate parsed_tags(markup), to: Parser, as: :parse_markup
  defdelegate pid(str), to: IEx.Helpers
  defdelegate port(str), to: IEx.Helpers
  defdelegate ref(str), to: IEx.Helpers

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
  Builds an error message for ArgumentError.
  """
  @spec build_argument_error_msg(integer(), String.t()) :: String.t()
  def build_argument_error_msg(arg_idx, blame) do
    # Based on: https://stackoverflow.com/a/39466341/13040586
    suffix_idx = rem(rem(arg_idx + 90, 100) - 10, 10) - 1
    suffix = Enum.at(["st", "nd", "rd"], suffix_idx, "th")

    """
    errors were found at the given arguments:

      * #{arg_idx}#{suffix} argument: #{blame}
    """
  end

  @doc """
  Builds empty component struct.
  """
  @spec build_component_struct() :: Component.t()
  def build_component_struct do
    %Component{}
  end

  @doc """
  Builds an error message for FunctionClauseError.
  """
  @spec build_function_clause_error_msg(String.t(), list, list) :: String.t()
  def build_function_clause_error_msg(fun_name, args \\ [], attempted_clauses \\ []) do
    args_info =
      if Enum.any?(args) do
        initial_acc = "\n\nThe following arguments were given to #{fun_name}:\n"

        args
        |> Enum.with_index()
        |> Enum.reduce(initial_acc, fn {arg, idx}, acc ->
          """
          #{acc}
              # #{idx + 1}
              #{KernelUtils.inspect(arg)}
          """
        end)
      else
        ""
      end

    attempted_clauses_count = Enum.count(attempted_clauses)

    attempted_clauses_info =
      if attempted_clauses_count > 0 do
        initial_acc = """

        Attempted function clauses (showing #{attempted_clauses_count} out of #{attempted_clauses_count}):
        """

        Enum.reduce(attempted_clauses, initial_acc, fn attempted_clause, acc ->
          """
          #{acc}
              #{attempted_clause}
          """
        end)
      else
        ""
      end

    """
    no function clause matching in #{fun_name}#{args_info}#{attempted_clauses_info}\
    """
  end

  @doc """
  Builds empty server struct.
  """
  @spec build_server_struct() :: Server.t()
  def build_server_struct do
    %Server{}
  end

  @doc """
  Builds an error message for UndefinedFunctionError.
  """
  @spec build_undefined_function_error(mfa, list({fun, arity}), boolean) :: String.t()
  def build_undefined_function_error(undefined_mfa, similar_funs \\ [], module_available? \\ true) do
    {module, fun, arity} = undefined_mfa
    module_name = Reflection.module_name(module)

    undefined_mfa_info =
      if module_available? do
        "function #{module_name}.#{fun}/#{arity} is undefined or private"
      else
        "function #{module_name}.#{fun}/#{arity} is undefined (module #{module_name} is not available)"
      end

    similar_funs_info =
      if Enum.any?(similar_funs) do
        Enum.reduce(similar_funs, ". Did you mean:\n\n", fn {fun, arity}, acc ->
          "#{acc}      * #{fun}/#{arity}\n"
        end)
      else
        ""
      end

    "#{undefined_mfa_info}#{similar_funs_info}"
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
    props_dom =
      Enum.map(props, fn {name, value} -> {to_string(name), [expression: {value}]} end)

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
  Sets up asset fixtures.
  """
  @spec setup_asset_fixtures(String.t()) :: [mapping: %{String.t() => String.t()}]
  def setup_asset_fixtures(static_dir) do
    clean_dir(static_dir)

    dir_2 = static_dir <> "/test_dir_1/test_dir_2"
    file_1_path = dir_2 <> "/test_file_1-11111111111111111111111111111111.css"
    file_2_path = dir_2 <> "/test_file_2-22222222222222222222222222222222.css"
    file_3_path = dir_2 <> "/page-33333333333333333333333333333333.js"
    file_4_path = dir_2 <> "/page-33333333333333333333333333333333.js.map"

    dir_3 = static_dir <> "/test_dir_3"
    file_5_path = dir_3 <> "/test_file_4-44444444444444444444444444444444.css"
    file_6_path = dir_3 <> "/test_file_5-55555555555555555555555555555555.css"
    file_7_path = dir_3 <> "/page-66666666666666666666666666666666.js"
    file_8_path = dir_3 <> "/page-66666666666666666666666666666666.js.map"

    dir_4 = static_dir <> "/hologram"
    file_9_path = dir_4 <> "/page-77777777777777777777777777777777.js"
    file_10_path = dir_4 <> "/page-77777777777777777777777777777777.js.map"
    file_11_path = dir_4 <> "/page-88888888888888888888888888888888.js"
    file_12_path = dir_4 <> "/page-88888888888888888888888888888888.js.map"
    file_13_path = dir_4 <> "/test_file_9-99999999999999999999999999999999.css"

    File.mkdir_p!(dir_2)
    File.mkdir_p!(dir_3)
    File.mkdir_p!(dir_4)

    file_paths = [
      file_1_path,
      file_2_path,
      file_3_path,
      file_4_path,
      file_5_path,
      file_6_path,
      file_7_path,
      file_8_path,
      file_9_path,
      file_10_path,
      file_11_path,
      file_12_path,
      file_13_path
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
