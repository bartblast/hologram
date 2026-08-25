defmodule Hologram.Compiler.Encoder do
  @moduledoc false

  if Application.compile_env(:hologram, :debug_encoder) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Compiler.Encoder, :encode_ir, 2} => [
          on_success: {Hologram.Compiler.Encoder, :debug, 3},
          on_error: {Hologram.Compiler.Encoder, :debug, 3}
        ]
      }
  end

  alias Hologram.Commons.IntegerUtils
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  # See Hologram.Compiler.IR: a `%Context{}` default MapSet reads as concrete and won't unify
  # with the opaque `MapSet.t()` in the spec.
  @dialyzer {:no_opaque, {:encode_term!, 1}}

  # The only characters a term's text cannot carry into the JavaScript this module emits.
  # Everything else - tabs, other control chars, non-printable and astral Unicode - is legal
  # inside a string literal and inside a script element, and travels as itself.
  #
  #   \\   would eat the character after it
  #   "    would close the literal
  #   \n   and \r are not allowed inside a literal at all
  #   NUL  is rewritten to U+FFFD by the HTML parser inside script data
  #   <    so that "</script" can never form in a page's inline script
  #
  # Bytes that are not valid UTF-8 have to go too, since a document carrying them has to be
  # valid UTF-8. They are absent here because a pattern cannot name them - see escape_bytes/1.
  @escapable_chars [<<0>>, "\n", "\r", "\"", "<", "\\"]

  # A compiled pattern holds a reference, which no module attribute can carry, and compiling one
  # costs more than escaping a short atom. So it is built once and kept where every process can
  # read it.
  @escapable_chars_pattern_key {__MODULE__, :escapable_chars_pattern}

  @doc """
  Encodes Elixir or Erlang alias as JavaScript class name.

  ## Examples

      iex> encode_as_class_name(Aaa.Bbb.Ccc)
      "Elixir_Aaa_Bbb_Ccc"

      iex> encode_as_class_name(:erlang)
      "Erlang"
      
      iex> encode_as_class_name(:aaa_bbb)
      "Erlang_Aaa_Bbb"      
  """
  @spec encode_as_class_name(module | atom) :: String.t()
  def encode_as_class_name(alias_atom)

  def encode_as_class_name(:erlang), do: "Erlang"

  def encode_as_class_name(alias_atom) do
    module_segments =
      alias_atom
      |> to_string()
      |> String.split([".", "_"])

    class_segments =
      if hd(module_segments) == "Elixir" do
        module_segments
      else
        ["Erlang" | module_segments]
      end

    Enum.map_join(class_segments, "_", &:string.titlecase/1)
  end

  @doc """
  Encodes the given string as a JavaScript string literal that can be printed into a script
  element: the quotes and backslashes a literal cannot hold raw, the line breaks it cannot span,
  and the `<` that could spell the closing tag of the element around it are escaped.

  ## Examples

      iex> encode_as_string(~S|a"b\\c</script>|)
      ~S|"a\\"b\\\\c\\u{3C}/script>"|
  """
  @spec encode_as_string(String.t()) :: String.t()
  def encode_as_string(str) do
    encode_as_string(str, true)
  end

  @doc """
  Encodes an Elixir function into a JavaScript statement.
  """
  @spec encode_elixir_function(
          String.t(),
          atom,
          non_neg_integer,
          :public | :private,
          list(IR.FunctionClause.t()),
          Context.t()
        ) :: String.t()
  def encode_elixir_function(module_name, function, arity, visibility, clauses, context) do
    async? = MapSet.member?(context.async_mfas, {context.module, function, arity})
    clause_context = %{context | arity: arity, async?: async?, function: function}
    clauses_js = encode_as_array(clauses, clause_context)

    ~s/Interpreter.defineElixirFunction("#{module_name}", "#{function}", #{arity}, "#{visibility}", #{clauses_js});/
  end

  @doc """
  Generates the interpreter registration statement carrying the clause heads of
  the given manually ported Elixir function.

  A manually ported function has no encoded clauses of its own, so its raise
  sites have nothing to report attempted clauses from - this registers the
  heads the server would blame, without their bodies.

  ## Examples

      iex> encode_elixir_function_clause_heads("Code", :ensure_compiled, 1, :public, clauses, context)
      "Interpreter.defineFunctionClauseHeads(\"Code\", \"ensure_compiled\", 1, \"public\", [...]);"
  """
  @spec encode_elixir_function_clause_heads(
          String.t(),
          atom,
          non_neg_integer,
          :public | :private,
          list(IR.FunctionClause.t()),
          Context.t()
        ) :: String.t()
  def encode_elixir_function_clause_heads(
        module_name,
        function,
        arity,
        visibility,
        clauses,
        context
      ) do
    heads_js = encode_as_array(clauses, %{context | async?: false}, &encode_clause_head/2)

    ~s/Interpreter.defineFunctionClauseHeads("#{module_name}", "#{function}", #{arity}, "#{visibility}", #{heads_js});/
  end

  @doc """
  Generates interpreter function definition JavaScript statement for the given ported Erlang function.

  If the function is implemented (has corresponding JavaScript code), wraps it in `Interpreter.defineErlangFunction`.
  If the function is not implemented, generates `Interpreter.defineNotImplementedErlangFunction`.

  ## Examples

      iex> encode_erlang_function(:erlang, :+, 2, "/path/to/erlang")
      "Interpreter.defineErlangFunction(\\"erlang\\", \\"+\\", 2, (left, right) => { ... });"

      iex> encode_erlang_function(:erlang, :not_implemented, 2, "/path/to/erlang")
      "Interpreter.defineNotImplementedErlangFunction(\\"erlang\\", \\"not_implemented\\", 2);"
  """
  @spec encode_erlang_function(module, atom, integer, String.t()) :: String.t()
  def encode_erlang_function(module, function, arity, erlang_js_dir) do
    js_code = Compiler.get_erlang_function_js(module, function, arity, erlang_js_dir)

    if js_code do
      normalized_js_code = StringUtils.normalize_newlines(js_code)

      ~s/Interpreter.defineErlangFunction("#{module}", "#{function}", #{arity}, #{normalized_js_code});/
    else
      ~s/Interpreter.defineNotImplementedErlangFunction("#{module}", "#{function}", #{arity});/
    end
  end

  @doc """
  Encodes Elixir IR to JavaScript source code.

  ## Examples

      iex> ir = %IR.ListType{
      ...>   data: [
      ...>     %IR.IntegerType{value: 1},
      ...>     %IR.AtomType{value: :abc}
      ...>   ]
      ...> }
      iex> encode_ir(ir, %Context{})
      "Type.list([Type.integer(1), Type.atom(\"abc\")])"
  """
  @intercept true
  @spec encode_ir(IR.t(), Context.t()) :: String.t()
  def encode_ir(ir, context)

  def encode_ir(%IR.AnonymousFunctionCall{function: function, args: args, line: line}, context) do
    function_js = encode_ir(function, context)
    args_js = encode_as_array(args, context)
    call = "Interpreter.callAnonymousFunction(#{function_js}, #{args_js})"
    awaited_call = if context.async?, do: "(await #{call})", else: call

    maybe_encode_frame_line(awaited_call, line, context)
  end

  def encode_ir(
        %IR.AnonymousFunctionType{
          arity: arity,
          captured_function: nil,
          captured_module: nil,
          clauses: clauses
        },
        context
      ) do
    async? = has_async_call?(clauses, context)
    clause_context = %{context | async?: async?}
    clauses_js = encode_as_array(clauses, clause_context)
    name_js = encode_anonymous_function_name(context)

    "Type.anonymousFunction(#{arity}, #{clauses_js}, context#{name_js})"
  end

  def encode_ir(
        %IR.AnonymousFunctionType{
          arity: arity,
          captured_function: captured_function,
          captured_module: captured_module,
          clauses: clauses
        },
        context
      ) do
    captured_function_js = encode_as_string(captured_function, true)

    captured_module_str =
      if Reflection.elixir_module?(captured_module) do
        Reflection.module_name(captured_module)
      else
        ":#{captured_module}"
      end

    captured_module_js = encode_as_string(captured_module_str, true)

    async? = has_async_call?(clauses, context)
    clause_context = %{context | async?: async?}
    clauses_js = encode_as_array(clauses, clause_context)

    "Type.functionCapture(#{captured_module_js}, #{captured_function_js}, #{arity}, #{clauses_js}, context)"
  end

  def encode_ir(%IR.AtomType{value: value}, _context) do
    encode_primitive_type(:atom, value, true)
  end

  # See: https://hexdocs.pm/elixir/Kernel.SpecialForms.html#%3C%3C%3E%3E/1
  def encode_ir(
        %IR.BitstringSegment{value: %IR.StringType{value: value}, modifiers: modifiers},
        context
      ) do
    # Text goes as a string; bytes that are not text go as a bitstring, which the client splices
    # in whole. See encode_bytes/1.
    value_str =
      if String.valid?(value) do
        encode_primitive_type(:string, value, true)
      else
        encode_bytes(value)
      end

    encode_bitstring_segment(value_str, modifiers, context)
  end

  # See: https://hexdocs.pm/elixir/Kernel.SpecialForms.html#%3C%3C%3E%3E/1
  def encode_ir(
        %IR.BitstringSegment{value: value, modifiers: modifiers},
        context
      ) do
    value_str = encode_ir(value, context)
    encode_bitstring_segment(value_str, modifiers, context)
  end

  def encode_ir(%IR.BitstringType{segments: segments}, %{pattern?: true} = context) do
    segments
    |> encode_bitstring_segments(context)
    |> StringUtils.wrap("Type.bitstringPattern([", "])")
  end

  def encode_ir(%IR.BitstringType{segments: segments, line: line}, %{pattern?: false} = context) do
    segments
    |> encode_bitstring_segments(context)
    |> StringUtils.wrap("Type.bitstring([", "])")
    |> maybe_encode_frame_line(line, context)
  end

  def encode_ir(%IR.Block{} = block, %{async?: true} = context) do
    "(await (#{encode_closure(block, context)})(context))"
  end

  def encode_ir(%IR.Block{} = block, context) do
    "(#{encode_closure(block, context)})(context)"
  end

  def encode_ir(%IR.Case{condition: condition, clauses: clauses, line: line}, context) do
    condition_js =
      case condition do
        %IR.Block{} = block -> encode_closure(block, context)
        expr -> encode_ir(expr, context)
      end

    clauses_js = encode_as_array(clauses, context)

    call =
      if context.async? do
        "(await Interpreter.asyncCase(#{condition_js}, #{clauses_js}, context))"
      else
        "Interpreter.case(#{condition_js}, #{clauses_js}, context)"
      end

    maybe_encode_frame_line(call, line, context)
  end

  def encode_ir(%IR.Clause{} = clause, context) do
    clause
    |> encode_clause_properties(context)
    |> encode_as_object()
  end

  def encode_ir(%IR.Comprehension{reducer: nil} = comprehension, context) do
    qualifiers =
      encode_as_array(comprehension.qualifiers, context, &encode_comprehension_qualifier/2)

    collectable = encode_ir(comprehension.collectable, context)
    unique = comprehension.unique.value
    mapper = encode_closure(comprehension.mapper, context)

    call =
      if context.async? do
        "(await Interpreter.asyncComprehension(#{qualifiers}, #{collectable}, #{unique}, #{mapper}, context))"
      else
        "Interpreter.comprehension(#{qualifiers}, #{collectable}, #{unique}, #{mapper}, context)"
      end

    maybe_encode_frame_line(call, comprehension.line, context)
  end

  def encode_ir(%IR.Comprehension{} = comprehension, context) do
    qualifiers =
      encode_as_array(comprehension.qualifiers, context, &encode_comprehension_qualifier/2)

    initial_value = encode_ir(comprehension.reducer.initial_value, context)
    clauses = encode_as_array(comprehension.reducer.clauses, context)

    call =
      if context.async? do
        "(await Interpreter.asyncComprehensionReduce(#{qualifiers}, #{initial_value}, #{clauses}, context))"
      else
        "Interpreter.comprehensionReduce(#{qualifiers}, #{initial_value}, #{clauses}, context)"
      end

    maybe_encode_frame_line(call, comprehension.line, context)
  end

  def encode_ir(%IR.Cond{clauses: clauses_ir, line: line}, context) do
    clauses_js = encode_as_array(clauses_ir, context)

    call =
      if context.async? do
        "(await Interpreter.asyncCond(#{clauses_js}, context))"
      else
        "Interpreter.cond(#{clauses_js}, context)"
      end

    maybe_encode_frame_line(call, line, context)
  end

  def encode_ir(%IR.CondClause{condition: condition_ir, body: body_ir}, context) do
    condition_js = encode_closure(condition_ir, context)
    body_js = encode_closure(body_ir, context)

    "{condition: #{condition_js}, body: #{body_js}}"
  end

  def encode_ir(%IR.ConsOperator{head: head, tail: tail}, %{pattern?: true} = context) do
    "Type.consPattern(#{encode_ir(head, context)}, #{encode_ir(tail, context)})"
  end

  def encode_ir(%IR.ConsOperator{head: head, tail: tail}, %{pattern?: false} = context) do
    "Interpreter.consOperator(#{encode_ir(head, context)}, #{encode_ir(tail, context)})"
  end

  def encode_ir(%IR.DotOperator{left: left, right: right, line: line}, context) do
    left_js = encode_ir(left, context)
    right_js = encode_ir(right, context)

    maybe_encode_frame_line("Interpreter.dotOperator(#{left_js}, #{right_js})", line, context)
  end

  def encode_ir(%IR.FloatType{value: value}, _context) do
    encode_primitive_type(:float, value, false)
  end

  def encode_ir(%IR.FunctionClause{} = clause, context) do
    params_array = encode_as_array(clause.params, %{context | pattern?: true})
    params_closure = "(context) => #{params_array}"

    # Guards are never async — Elixir guards are restricted to a safe subset of functions.
    guards_context = %{context | async?: false, guard?: true}
    guards = encode_as_array(clause.guards, guards_context, &encode_closure/2)

    body = encode_closure(clause.body, context)

    properties =
      Enum.reject(
        [
          params: params_closure,
          guards: guards,
          body: body,
          line: encode_clause_line(clause),
          blame: encode_clause_blame(clause, guards_context)
        ],
        fn {_name, value} -> is_nil(value) end
      )

    encode_as_object(properties)
  end

  def encode_ir(%IR.IntegerType{value: value}, _context) do
    encode_primitive_type(:integer, "#{value}n", false)
  end

  def encode_ir(%IR.ListType{data: data}, context) do
    data_str = encode_as_array(data, context)
    "Type.list(#{data_str})"
  end

  def encode_ir(
        %IR.LocalFunctionCall{function: function, args: args, line: line},
        %{module: module} = context
      ) do
    module_ir = %IR.AtomType{value: module}

    module_ir
    |> encode_named_function_call(function, args, context)
    |> maybe_encode_frame_line(line, context)
  end

  def encode_ir(%IR.MapType{data: data}, context) do
    data
    |> Enum.sort()
    |> Enum.map_join(", ", fn {key, value} ->
      "[" <> encode_ir(key, context) <> ", " <> encode_ir(value, context) <> "]"
    end)
    |> StringUtils.wrap("Type.map([", "])")
  end

  # Inside a pattern neither side is a value to match the other against - both
  # constrain the term being matched, and a variable on either side binds to
  # that term. So the match is carried into the pattern, to be matched against
  # each of its sides in turn.
  def encode_ir(%IR.MatchOperator{left: left, right: right}, %{pattern?: true} = context) do
    left_js = encode_ir(left, context)
    right_js = encode_ir(right, context)

    "Type.matchPattern(#{left_js}, #{right_js})"
  end

  def encode_ir(
        %IR.MatchOperator{left: left, right: right, line: line},
        %{match_operator?: true} = context
      ) do
    left = encode_ir(left, %{context | pattern?: true})
    right = encode_ir(right, context)

    maybe_encode_frame_line(
      "Interpreter.matchOperator(#{right}, #{left}, context)",
      line,
      context
    )
  end

  def encode_ir(%IR.MatchOperator{left: left, right: right, line: line}, context) do
    left = encode_ir(left, %{context | match_operator?: true, pattern?: true})
    right = encode_ir(right, %{context | match_operator?: true})

    maybe_encode_frame_line(
      "Interpreter.matchOperator(#{right}, #{left}, context)",
      line,
      context
    )
  end

  def encode_ir(%IR.MatchPlaceholder{}, _context) do
    "Type.matchPlaceholder()"
  end

  def encode_ir(%IR.ModuleAttributeOperator{name: name}, _context) do
    encode_var("@#{name}", nil)
  end

  def encode_ir(%IR.ModuleDefinition{module: module} = module_def, context) do
    module_name = Reflection.module_name(module.value)

    module_def
    |> IR.aggregate_module_funs()
    |> Enum.reduce([], fn {{function, arity}, {visibility, clauses}}, acc ->
      [encode_elixir_function(module_name, function, arity, visibility, clauses, context) | acc]
    end)
    |> Enum.reverse()
    |> Enum.join("\n\n")
  rescue
    error ->
      message =
        StringUtils.normalize_newlines("""
        can't encode #{Reflection.module_name(module.value)} module definition
        #{Exception.message(error)}\
        """)

      reraise RuntimeError, [message: message], __STACKTRACE__
  end

  # See info about the internal structure of PIDs: https://stackoverflow.com/a/262179/13040586
  def encode_ir(%IR.PIDType{value: value}, context) do
    segments =
      value
      |> :erlang.pid_to_list()
      |> List.delete_at(0)
      |> List.delete_at(-1)
      |> to_string()
      |> String.split(".")
      |> Enum.map(&IntegerUtils.parse!/1)

    encode_identifier(:pid, value, segments, context)
  end

  def encode_ir(%IR.PinOperator{variable: variable}, context) do
    encode_ir(variable, %{context | pattern?: false})
  end

  def encode_ir(%IR.PortType{value: value}, context) do
    segments =
      value
      |> :erlang.port_to_list()
      |> Enum.drop(6)
      |> List.delete_at(-1)
      |> to_string()
      |> String.split(".")
      |> Enum.map(&IntegerUtils.parse!/1)

    encode_identifier(:port, value, segments, context)
  end

  def encode_ir(%IR.ReferenceType{value: value}, context) do
    binary = :erlang.term_to_binary(value)
    {node_name, creation, id_words} = parse_reference_binary(binary)

    node_js = encode_as_string(node_name, true)
    creation_js = to_string(creation)
    id_words_js = encode_as_array(id_words, context, fn word, _ctx -> to_string(word) end)

    "Type.reference(#{node_js}, #{creation_js}, #{id_words_js})"
  end

  def encode_ir(
        %IR.RemoteFunctionCall{
          module: module,
          function: function,
          args: args,
          line: line
        },
        context
      ) do
    module
    |> encode_named_function_call(function, args, context)
    |> maybe_encode_frame_line(line, context)
  end

  # __STACKTRACE__ - the interpreter binds the boxed trace captured on the
  # handled error to the context's stacktrace field in rescue/catch clause
  # scope.
  def encode_ir(%IR.Stacktrace{}, _context) do
    "context.stacktrace"
  end

  def encode_ir(%IR.StringType{value: value}, _context) do
    if String.valid?(value) do
      encode_primitive_type(:bitstring, value, true)
    else
      encode_bytes(value)
    end
  end

  # TODO: catch_clauses, else_clauses, after_block
  def encode_ir(%IR.Try{} = ir, context) do
    body_js = encode_closure(ir.body, context)
    rescue_clauses_js = encode_as_array(ir.rescue_clauses, context)
    catch_clauses_js = encode_as_array(ir.catch_clauses, context)
    else_clauses_js = encode_as_array(ir.else_clauses, context)
    after_block_js = encode_closure(ir.after_block, context)

    args_js =
      "#{body_js}, #{rescue_clauses_js}, #{catch_clauses_js}, #{else_clauses_js}, #{after_block_js}, context"

    call =
      if context.async? do
        "(await Interpreter.asyncTry(#{args_js}))"
      else
        "Interpreter.try(#{args_js})"
      end

    maybe_encode_frame_line(call, ir.line, context)
  end

  def encode_ir(%IR.TryCatchClause{} = ir, context) do
    kind_js = encode_ir(ir.kind, %{context | pattern?: true})
    value_js = encode_ir(ir.value, %{context | pattern?: true})

    # Guards are never async - Elixir guards are restricted to a safe subset of functions.
    guards_js =
      encode_as_array(ir.guards, %{context | async?: false, guard?: true}, &encode_closure/2)

    body_js = encode_closure(ir.body, context)

    "{kind: #{kind_js}, value: #{value_js}, guards: #{guards_js}, body: #{body_js}}"
  end

  def encode_ir(%IR.TryRescueClause{} = ir, context) do
    variable_js =
      if ir.variable do
        encode_ir(ir.variable, %{context | pattern?: true})
      else
        "null"
      end

    modules_js = encode_as_array(ir.modules, context)
    body_js = encode_closure(ir.body, context)

    "{variable: #{variable_js}, modules: #{modules_js}, body: #{body_js}}"
  end

  def encode_ir(%IR.TupleType{data: data}, context) do
    data_js = encode_as_array(data, context)
    "Type.tuple(#{data_js})"
  end

  def encode_ir(%IR.Variable{name: name, version: version}, %{pattern?: true}) do
    var_name = encode_var_name(name, version)
    ~s/Type.variablePattern("#{var_name}")/
  end

  def encode_ir(%IR.Variable{name: name, version: version}, %{pattern?: false}) do
    encode_var(name, version)
  end

  def encode_ir(
        %IR.With{body: body, clauses: clauses, else_clauses: else_clauses, line: line},
        context
      ) do
    body_js = encode_closure(body, context)
    clauses_js = encode_as_array(clauses, context)
    else_clauses_js = encode_as_array(else_clauses, context)

    call =
      if context.async? do
        "(await Interpreter.asyncWith(#{body_js}, #{clauses_js}, #{else_clauses_js}, context))"
      else
        "Interpreter.with(#{body_js}, #{clauses_js}, #{else_clauses_js}, context)"
      end

    maybe_encode_frame_line(call, line, context)
  end

  def encode_ir(%IR.WithBareClause{expression: expression}, context) do
    expression_js = encode_closure(expression, context)

    "{expression: #{expression_js}}"
  end

  def encode_ir(
        %IR.WithMatchClause{match: match, guards: guards, expression: expression},
        context
      ) do
    match_js = encode_ir(match, %{context | pattern?: true})

    # Guards are never async — Elixir guards are restricted to a safe subset of functions.
    guards_js =
      encode_as_array(guards, %{context | async?: false, guard?: true}, &encode_closure/2)

    expression_js = encode_closure(expression, context)

    "{match: #{match_js}, guards: #{guards_js}, expression: #{expression_js}}"
  end

  @doc """
  Generates the ERTS registration statement carrying the metadata of the given modules.

  Each bundle registers the modules it defines, so a stacktrace frame can name the application a
  module belongs to and the source file it was compiled from. Returns an empty string when client
  stacktraces are disabled, or when none of the modules can be loaded to read their metadata
  from.

  ## Examples

      iex> encode_module_metadata_registration([Aaa.Bbb])
      "ERTS.registerModuleMetadata({\"Aaa.Bbb\": {app: \"my_app\", file: \"lib/aaa/bbb.ex\"}});"
  """
  @spec encode_module_metadata_registration(list(module)) :: String.t()
  def encode_module_metadata_registration(modules) do
    entries =
      if Hologram.client_stacktraces?() do
        modules
        |> Enum.sort()
        |> Enum.map(fn module -> {module, encode_module_metadata(module)} end)
        |> Enum.reject(fn {_module, metadata} -> metadata == "{}" end)
        |> Enum.map_join(", ", fn {module, metadata} ->
          ~s/"#{Reflection.module_name(module)}": #{metadata}/
        end)
      else
        ""
      end

    if entries == "" do
      ""
    else
      "ERTS.registerModuleMetadata({#{entries}});"
    end
  end

  @doc """
  Encodes Elixir term into JavaScript.
  If the term can be encoded into JavaScript then the result is in the shape of {:ok, js}.
  If the term can't be encoded into JavaScript then an error message is returned in the shape of {:error, message}.
  """
  @spec encode_term(any) :: {:ok, String.t()} | {:error, String.t()}
  def encode_term(term) do
    {:ok, encode_term!(term)}
  rescue
    e in ArgumentError ->
      {:error, e.message}
  end

  @doc """
  Encodes Elixir term into JavaScript, erroring out if the term can't be encoded into JavaScript.
  """
  @spec encode_term!(any) :: String.t()
  def encode_term!(term) do
    term
    |> IR.for_term!()
    |> encode_ir(%Context{})
  end

  @doc """
  Prints debug info for intercepted encode_ir/2 calls.
  """
  @spec debug(
          {module, atom, list(IR.t() | Context.t())},
          String.t() | %{__struct__: FunctionClauseError},
          integer
        ) :: :ok
  def debug({_module, _function, [ir, context] = _args}, result, _start_timestamp) do
    # credo:disable-for-lines:10 /Credo.Check.Refactor.IoPuts|Credo.Check.Warning.IoInspect/
    IO.puts("\nENCODE IR...............................\n")
    IO.puts("ir")
    IO.inspect(ir)
    IO.puts("")
    IO.puts("context")
    IO.inspect(context)
    IO.puts("")
    IO.puts("result")
    IO.inspect(result)
    IO.puts("\n........................................\n")
  end

  defp encode_as_array(data, context, encoder \\ &encode_ir/2) do
    data
    |> Enum.map_join(", ", &encoder.(&1, context))
    |> StringUtils.wrap("[", "]")
  end

  defp encode_as_object(properties) do
    properties
    |> Enum.map_join(", ", fn {name, value} -> "#{name}: #{value}" end)
    |> StringUtils.wrap("{", "}")
  end

  defp encode_as_string(value, wrap)

  defp encode_as_string(nil, false) do
    "nil"
  end

  defp encode_as_string(value, false) do
    value
    |> to_string()
    |> escape_non_printable_and_special_chars()
  end

  defp encode_as_string(value, true) do
    value
    |> encode_as_string(false)
    |> StringUtils.wrap("\"", "\"")
  end

  # The BEAM names an anonymous function after the definition it appears in,
  # numbering the ones defined there. The index is left at zero, because the
  # BEAM's counts every generated function in the module - comprehensions and
  # captures included - and it shows up in no message, only in the name itself.
  defp encode_anonymous_function_name(%Context{function: nil}), do: ""

  defp encode_anonymous_function_name(%Context{arity: arity, function: function}) do
    ", " <> encode_as_string("-#{function}/#{arity}-fun-0-", true)
  end

  defp encode_bitstring_modifier({:size, size}, context) do
    "size: #{encode_ir(size, context)}"
  end

  defp encode_bitstring_modifier({:unit, unit}, _context) do
    "unit: #{unit}n"
  end

  defp encode_bitstring_modifier({name, value}, _context) do
    ~s(#{name}: "#{value}")
  end

  defp encode_bitstring_segment(value_str, modifiers, context) do
    modifiers_str =
      modifiers
      |> Enum.map_join(", ", &encode_bitstring_modifier(&1, context))
      |> StringUtils.wrap("{", "}")

    "Type.bitstringSegment(#{value_str}, #{modifiers_str})"
  end

  defp encode_bitstring_segments(segments, context) do
    Enum.map_join(segments, ", ", &encode_ir(&1, context))
  end

  defp encode_block_body(%IR.Block{expressions: exprs}, context) do
    exprs =
      if exprs == [] do
        [%IR.AtomType{value: nil}]
      else
        exprs
      end

    expr_count = Enum.count(exprs)

    body =
      exprs
      |> Enum.with_index()
      |> Enum.map_join("", fn {expr, idx} ->
        expr_js = encode_ir(expr, context)

        last_expr? = idx == expr_count - 1
        has_match_operator? = has_match_operator?(expr)

        encode_block_expr(expr_js, last_expr?, has_match_operator?)
      end)

    "{#{body}\n}"
  end

  defp encode_block_expr(expr_js, last_expr?, has_match_operator?)

  defp encode_block_expr(expr_js, true, true) do
    StringUtils.normalize_newlines("""

    globalThis.Hologram.return = #{expr_js};
    Interpreter.updateVarsToMatchedValues(context);
    return globalThis.Hologram.return;\
    """)
  end

  defp encode_block_expr(expr_js, true, false) do
    "\nreturn #{expr_js};"
  end

  defp encode_block_expr(expr_js, false, true) do
    StringUtils.normalize_newlines("""

    #{expr_js};
    Interpreter.updateVarsToMatchedValues(context);\
    """)
  end

  defp encode_block_expr(expr_js, false, false) do
    "\n#{expr_js};"
  end

  # A string literal carries text and nothing else: the client reads it back through UTF-8, so a
  # byte that is not valid UTF-8 has no spelling in one - an escape naming the byte comes back as
  # the UTF-8 bytes of the character it named. A binary holding such a byte travels as the hex of
  # its bytes instead, and the client rebuilds them as they were. Lowercase, which is the one
  # spelling of hex the client writes and the server reads. Linear, like the escaping it replaces.
  defp encode_bytes(binary) do
    ~s/Type.bitstring("#{Base.encode16(binary, case: :lower)}", "hex")/
  end

  # The clause head is rendered at build time, but which of its parts failed to
  # match is known only at raise time, so each guard leaf travels with its own
  # closure for the client to evaluate. The leaves line up with the guard IR,
  # which carries the same and/or structure they were split at.
  defp encode_clause_blame(%IR.FunctionClause{blame: nil}, _context), do: nil

  defp encode_clause_blame(%IR.FunctionClause{blame: blame} = clause, context) do
    if Hologram.client_stacktraces?() do
      encode_clause_blame_properties(blame, clause.guards, context)
    end
  end

  defp encode_clause_blame_properties(blame, guards_ir, context) do
    params = Enum.map_join(blame.params, ", ", &encode_as_string(&1, true))

    guards =
      blame.guards
      |> Enum.zip(guards_ir)
      |> Enum.map_join(", ", fn {guard, guard_ir} ->
        encode_clause_blame_guard(guard, guard_ir, context)
      end)

    encode_as_object(
      params: StringUtils.wrap(params, "[", "]"),
      guards: StringUtils.wrap(guards, "[", "]")
    )
  end

  defp encode_clause_blame_guard(
         {operator, left, right},
         %IR.RemoteFunctionCall{module: %IR.AtomType{value: :erlang}, args: [left_ir, right_ir]},
         context
       ) do
    encode_as_object(
      operator: encode_as_string(operator, true),
      left: encode_clause_blame_guard(left, left_ir, context),
      right: encode_clause_blame_guard(right, right_ir, context)
    )
  end

  defp encode_clause_blame_guard({:leaf, source}, guard_ir, context) do
    encode_as_object(
      source: encode_as_string(source, true),
      test: encode_closure(guard_ir, context)
    )
  end

  defp encode_clause_head(%IR.FunctionClause{} = clause, context) do
    params_array = encode_as_array(clause.params, %{context | pattern?: true})
    guard_context = %{context | guard?: true}

    properties =
      Enum.reject(
        [
          params: "(context) => #{params_array}",
          guards: encode_as_array(clause.guards, guard_context, &encode_closure/2),
          blame: encode_clause_blame(clause, guard_context)
        ],
        fn {_name, value} -> is_nil(value) end
      )

    encode_as_object(properties)
  end

  defp encode_clause_line(%IR.FunctionClause{line: nil}), do: nil

  defp encode_clause_line(%IR.FunctionClause{line: line}) do
    if Hologram.client_stacktraces?() do
      to_string(line)
    end
  end

  defp encode_clause_properties(%IR.Clause{} = clause, context) do
    match = encode_ir(clause.match, %{context | pattern?: true})

    # Guards are never async — Elixir guards are restricted to a safe subset of functions.
    guards =
      encode_as_array(clause.guards, %{context | async?: false, guard?: true}, &encode_closure/2)

    body = encode_closure(clause.body, context)

    [match: match, guards: guards, body: body]
  end

  defp encode_closure(ir, context)

  defp encode_closure(nil, _context), do: "null"

  defp encode_closure(%IR.Block{} = ir, %{async?: true} = context) do
    "async (context) => #{encode_block_body(ir, context)}"
  end

  defp encode_closure(%IR.Block{} = ir, context) do
    "(context) => #{encode_block_body(ir, context)}"
  end

  defp encode_closure(ir, %{async?: true} = context) do
    "async (context) => #{encode_ir(ir, context)}"
  end

  defp encode_closure(ir, context) do
    "(context) => #{encode_ir(ir, context)}"
  end

  defp encode_comprehension_qualifier(%IR.Clause{} = clause, context) do
    type_js = encode_as_string("generator", true)
    encode_as_object([type: type_js] ++ encode_clause_properties(clause, context))
  end

  defp encode_comprehension_qualifier(
         %IR.ComprehensionBitstringGenerator{} = generator,
         context
       ) do
    type_js = encode_as_string("bitstring_generator", true)
    match_js = encode_ir(generator.match, %{context | pattern?: true})
    body_js = encode_closure(generator.body, context)

    encode_as_object(type: type_js, match: match_js, body: body_js)
  end

  defp encode_comprehension_qualifier(%IR.ComprehensionFilter{expression: expr}, context) do
    type_js = encode_as_string("filter", true)
    encode_as_object(type: type_js, filter: encode_closure(expr, context))
  end

  defp encode_dynamic_named_function_call(module, function, args, context) do
    module_js = encode_ir(module, context)
    function_js = encode_ir(function, context)
    args_js = encode_ir(args, context)

    call = "Interpreter.callNamedFunction(#{module_js}, #{function_js}, #{args_js}, context)"

    if context.async? do
      "(await #{call})"
    else
      call
    end
  end

  defp encode_identifier(type, value, segments, context) do
    encoded_node = encode_as_string(node(value), true)

    integer_encoder = fn integer, _context -> to_string(integer) end
    encoded_segments = encode_as_array(segments, context, integer_encoder)

    "Type.#{type}(#{encoded_node}, #{encoded_segments})"
  end

  # Module-level frame metadata: the module's source file (relative to its
  # source root) and the app that owns it, so client frames render the same
  # "(app vsn) file:line" prefix as server frames - the version comes from
  # ERTS.appVersions, keyed by the app named here.
  # Nil values are omitted rather than encoded as null.
  defp encode_module_metadata(module) do
    entries =
      if Code.ensure_loaded?(module) do
        [app: Application.get_application(module), file: Reflection.relative_source_path(module)]
      else
        []
      end

    fields =
      entries
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join(", ", fn {key, value} ->
        "#{key}: #{encode_as_string(value, true)}"
      end)

    "{#{fields}}"
  end

  defp encode_named_function_call(%IR.AtomType{value: :erlang}, :andalso, [left, right], context) do
    left_js = encode_closure(left, context)
    right_js = encode_closure(right, context)

    "Erlang[\"andalso/2\"](#{left_js}, #{right_js}, context)"
  end

  # Encoded as Interpreter.callNamedFunction() instead of Erlang["apply/3"]()
  # because we can't pass the runtime context to the ported function.
  defp encode_named_function_call(
         %IR.AtomType{value: :erlang},
         :apply,
         [module, function, args],
         context
       ) do
    encode_dynamic_named_function_call(module, function, args, context)
  end

  defp encode_named_function_call(%IR.AtomType{value: :erlang}, :orelse, [left, right], context) do
    left_js = encode_closure(left, context)
    right_js = encode_closure(right, context)

    "Erlang[\"orelse/2\"](#{left_js}, #{right_js}, context)"
  end

  defp encode_named_function_call(%IR.AtomType{} = module, function, args, context) do
    class = encode_as_class_name(module.value)
    arity = Enum.count(args)
    args_js = Enum.map_join(args, ", ", &encode_ir(&1, context))

    call = "#{class}[\"#{function}/#{arity}\"](#{args_js})"

    if MapSet.member?(context.async_mfas, {module.value, function, arity}) do
      "(await #{call})"
    else
      call
    end
  end

  defp encode_named_function_call(module_ir, function, args, context) do
    function_ir =
      if is_atom(function) do
        %IR.AtomType{value: function}
      else
        function
      end

    args_ir =
      if is_list(args) do
        %IR.ListType{data: args}
      else
        args
      end

    encode_dynamic_named_function_call(module_ir, function_ir, args_ir, context)
  end

  defp encode_primitive_type(type, value, as_string)

  defp encode_primitive_type(type, value, true) do
    value_str = encode_as_string(value, true)
    encode_primitive_type(type, value_str, false)
  end

  defp encode_primitive_type(type, value, false) do
    "Type.#{type}(#{value})"
  end

  defp encode_var(name, version) do
    var_name = encode_var_name(name, version)

    if String.match?(var_name, ~r/[^a-zA-Z0-9_]+/) do
      ~s'context.vars["#{var_name}"]'
    else
      "context.vars.#{var_name}"
    end
  end

  defp encode_var_name(name, nil) do
    encode_as_string(name, false)
  end

  defp encode_var_name(name, version) do
    encode_as_string(name, false) <> "_#{version}"
  end

  defp escapable_chars_pattern do
    case :persistent_term.get(@escapable_chars_pattern_key, nil) do
      nil ->
        pattern = :binary.compile_pattern(@escapable_chars)
        :persistent_term.put(@escapable_chars_pattern_key, pattern)
        pattern

      pattern ->
        pattern
    end
  end

  # Walks a binary that is not text, so that a byte which is not valid UTF-8 can be named. The
  # escapable chars are matched first, since this path answers for the whole binary.
  defp escape_bytes(str), do: escape_bytes(str, [])

  defp escape_bytes(<<0, rest::binary>>, acc), do: escape_bytes(rest, ["\\u{0}" | acc])
  defp escape_bytes("\n" <> rest, acc), do: escape_bytes(rest, ["\\n" | acc])
  defp escape_bytes("\r" <> rest, acc), do: escape_bytes(rest, ["\\r" | acc])
  defp escape_bytes("\"" <> rest, acc), do: escape_bytes(rest, ["\\\"" | acc])
  defp escape_bytes("<" <> rest, acc), do: escape_bytes(rest, ["\\u{3C}" | acc])
  defp escape_bytes("\\" <> rest, acc), do: escape_bytes(rest, ["\\\\" | acc])

  defp escape_bytes(<<char::utf8, rest::binary>>, acc) do
    escape_bytes(rest, [<<char::utf8>> | acc])
  end

  defp escape_bytes(<<byte::integer, rest::binary>>, acc) do
    # No need to pad with 0, because every byte below 16 is valid UTF-8 and matched above.
    escape_bytes(rest, ["\\x#{Integer.to_string(byte, 16)}" | acc])
  end

  defp escape_bytes("", acc), do: Enum.reverse(acc)

  defp escape_char(0), do: "\\u{0}"
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(?"), do: "\\\""
  defp escape_char(?<), do: "\\u{3C}"
  defp escape_char(?\\), do: "\\\\"

  # Every escapable char is one byte, so a match is always one byte wide.
  defp escape_matches(str, position, [], acc) do
    Enum.reverse([binary_part(str, position, byte_size(str) - position) | acc])
  end

  defp escape_matches(str, position, [{index, _length} | rest], acc) do
    run = binary_part(str, position, index - position)
    escaped = escape_char(:binary.at(str, index))

    escape_matches(str, index + 1, rest, [escaped, run | acc])
  end

  # Copies the stretches between the chars that have to be escaped rather than rebuilding the
  # text character by character: one native scan, and each stretch is a sub-binary that is never
  # copied until the result is assembled. Linear in the length of the text, where growing the
  # result with `<>` on the way out of a per-character recursion was quadratic.
  defp escape_non_printable_and_special_chars(str) do
    iodata =
      if String.valid?(str) do
        escape_matches(str, 0, :binary.matches(str, escapable_chars_pattern()), [])
      else
        escape_bytes(str)
      end

    IO.iodata_to_binary(iodata)
  end

  defp has_async_call?(clauses, context) do
    MapSet.size(context.async_mfas) > 0 and
      IR.has_call_to?(clauses, context.module, context.async_mfas)
  end

  defp has_match_operator?(ir)

  defp has_match_operator?(%IR.MatchOperator{}), do: true

  defp has_match_operator?(ir) when is_list(ir) do
    Enum.any?(ir, &has_match_operator?/1)
  end

  defp has_match_operator?(ir) when is_tuple(ir) do
    ir
    |> Tuple.to_list()
    |> has_match_operator?()
  end

  defp has_match_operator?(ir) when is_struct(ir) do
    ir
    |> Map.values()
    |> has_match_operator?()
  end

  defp has_match_operator?(ir) when is_map(ir) do
    Enum.any?(ir, fn {key, value} -> has_match_operator?(key) || has_match_operator?(value) end)
  end

  defp has_match_operator?(_ast), do: false

  # A stacktrace frame reports the line the function currently running has
  # reached, so each call records its own line before it is made - the way the
  # BEAM does it. A call the AST gave no line to records nothing, and the frame
  # keeps the line it already had.
  defp maybe_encode_frame_line(js, nil, _context), do: js

  defp maybe_encode_frame_line(js, _line, %Context{guard?: true}), do: js

  defp maybe_encode_frame_line(js, line, _context) do
    if Hologram.client_stacktraces?() do
      "(Interpreter.setFrameLine(#{line}), #{js})"
    else
      js
    end
  end

  # Parses NEWER_REFERENCE_EXT binary format to extract node name, creation number, and ID words
  # See: https://www.erlang.org/doc/apps/erts/erl_ext_dist.html
  #
  # Format structure:
  # - 131: VERSION_NUMBER (Erlang External Term Format version tag)
  # - 90: NEWER_REFERENCE_EXT tag
  # - len: number of ID words (16-bit big-endian)
  # - atom tag (119 or 100): node name encoding format
  #   - 119: SMALL_ATOM_UTF8_EXT (1-byte length, UTF-8 encoded)
  #   - 100: ATOM_EXT (2-byte length, Latin-1 encoded)
  # - atom_len: length of node name
  # - atom_bytes: node name bytes
  # - creation: creation number (32-bit big-endian)
  # - rest: ID words (each 32-bit big-endian)
  #
  # Note: Modern BEAM always produces NEWER_REFERENCE_EXT (tag 90) when serializing references.
  # Even if a reference was originally encoded with an older format (e.g., NEW_REFERENCE_EXT tag 114),
  # the BEAM automatically normalizes it to NEWER_REFERENCE_EXT when re-serializing.
  # Therefore, we only need to handle this format.
  defp parse_reference_binary(binary) do
    case binary do
      # NEWER_REFERENCE_EXT with SMALL_ATOM_UTF8_EXT (tag 119)
      <<131, 90, len::16, 119, atom_len::8, atom_bytes::binary-size(atom_len), creation::32,
        rest::binary>> ->
        id_words = parse_id_words(rest, len)
        {atom_bytes, creation, id_words}

      # NEWER_REFERENCE_EXT with ATOM_EXT (tag 100)
      <<131, 90, len::16, 100, atom_len::16, atom_bytes::binary-size(atom_len), creation::32,
        rest::binary>> ->
        id_words = parse_id_words(rest, len)
        {atom_bytes, creation, id_words}
    end
  end

  # Parses ID words from the binary (each word is 32-bit big-endian)
  defp parse_id_words(binary, count)

  defp parse_id_words(binary, count) do
    parse_id_words(binary, count, [])
  end

  defp parse_id_words(_binary, 0, acc) do
    Enum.reverse(acc)
  end

  defp parse_id_words(<<word::32, rest::binary>>, count, acc) do
    parse_id_words(rest, count - 1, [word | acc])
  end
end
