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
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

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
    clauses_js = encode_as_array(clauses, context)

    ~s/Interpreter.defineElixirFunction("#{module_name}", "#{function}", #{arity}, "#{visibility}", #{clauses_js});/
  end

  @doc """
  Extracts JavaScript source code for the given ported Erlang function and generates interpreter function definition JavaScript statetement.
  """
  @spec encode_erlang_function(module, atom, integer, String.t()) :: String.t()
  def encode_erlang_function(module, function, arity, erlang_source_dir) do
    file_path =
      if module == :erlang do
        "#{erlang_source_dir}/erlang.mjs"
      else
        "#{erlang_source_dir}/#{module}.mjs"
      end

    source_code =
      if File.exists?(file_path) do
        extract_erlang_function_source_code(file_path, function, arity)
      else
        nil
      end

    if source_code do
      ~s/Interpreter.defineErlangFunction("#{module}", "#{function}", #{arity}, #{source_code});/
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

  def encode_ir(%IR.AnonymousFunctionCall{function: function, args: args}, context) do
    function_js = encode_ir(function, context)
    args_js = encode_as_array(args, context)

    "Interpreter.callAnonymousFunction(#{function_js}, #{args_js})"
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
    clauses_js = encode_as_array(clauses, context)
    "Type.anonymousFunction(#{arity}, #{clauses_js}, context)"
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
      if Reflection.alias?(captured_module) do
        Reflection.module_name(captured_module)
      else
        ":#{captured_module}"
      end

    captured_module_js = encode_as_string(captured_module_str, true)

    clauses_js = encode_as_array(clauses, context)

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
    value_str = encode_primitive_type(:string, value, true)
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

  def encode_ir(%IR.BitstringType{segments: segments}, %{pattern?: false} = context) do
    segments
    |> encode_bitstring_segments(context)
    |> StringUtils.wrap("Type.bitstring([", "])")
  end

  def encode_ir(%IR.Block{} = block, context) do
    "(#{encode_closure(block, context)})(context)"
  end

  def encode_ir(%IR.Case{condition: condition, clauses: clauses}, context) do
    condition_js =
      case condition do
        %IR.Block{} = block -> encode_closure(block, context)
        expr -> encode_ir(expr, context)
      end

    clauses_js = encode_as_array(clauses, context)

    "Interpreter.case(#{condition_js}, #{clauses_js}, context)"
  end

  def encode_ir(%IR.Clause{} = clause, context) do
    match = encode_ir(clause.match, %{context | pattern?: true})
    guards = encode_as_array(clause.guards, context, &encode_closure/2)
    body = encode_closure(clause.body, context)

    "{match: #{match}, guards: #{guards}, body: #{body}}"
  end

  def encode_ir(%IR.Comprehension{} = comprehension, context) do
    generators = encode_as_array(comprehension.generators, context)
    filters = encode_as_array(comprehension.filters, context)
    collectable = encode_ir(comprehension.collectable, context)
    unique = comprehension.unique.value
    mapper = encode_closure(comprehension.mapper, context)

    "Interpreter.comprehension(#{generators}, #{filters}, #{collectable}, #{unique}, #{mapper}, context)"
  end

  def encode_ir(%IR.ComprehensionFilter{expression: expr}, context) do
    encode_closure(expr, context)
  end

  def encode_ir(%IR.Cond{clauses: clauses_ir}, context) do
    clauses_js = encode_as_array(clauses_ir, context)
    "Interpreter.cond(#{clauses_js}, context)"
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

  def encode_ir(%IR.DotOperator{left: left, right: right}, context) do
    left_js = encode_ir(left, context)
    right_js = encode_ir(right, context)

    "Interpreter.dotOperator(#{left_js}, #{right_js})"
  end

  def encode_ir(%IR.FloatType{value: value}, _context) do
    encode_primitive_type(:float, value, false)
  end

  def encode_ir(%IR.FunctionClause{} = clause, context) do
    params_array = encode_as_array(clause.params, %{context | pattern?: true})
    params_closure = "(context) => #{params_array}"

    guards = encode_as_array(clause.guards, context, &encode_closure/2)
    body = encode_closure(clause.body, context)

    "{params: #{params_closure}, guards: #{guards}, body: #{body}}"
  end

  def encode_ir(%IR.IntegerType{value: value}, _context) do
    encode_primitive_type(:integer, "#{value}n", false)
  end

  def encode_ir(%IR.ListType{data: data}, context) do
    data_str = encode_as_array(data, context)
    "Type.list(#{data_str})"
  end

  def encode_ir(
        %IR.LocalFunctionCall{function: function, args: args},
        %{module: module} = context
      ) do
    module_ir = %IR.AtomType{value: module}
    encode_named_function_call(module_ir, function, args, context)
  end

  def encode_ir(%IR.MapType{data: data}, context) do
    data
    |> Enum.sort()
    |> Enum.map_join(", ", fn {key, value} ->
      "[" <> encode_ir(key, context) <> ", " <> encode_ir(value, context) <> "]"
    end)
    |> StringUtils.wrap("Type.map([", "])")
  end

  def encode_ir(%IR.MatchOperator{left: left, right: right}, %{match_operator?: true} = context) do
    left = encode_ir(left, %{context | pattern?: true})
    right = encode_ir(right, context)

    "Interpreter.matchOperator(#{right}, #{left}, context)"
  end

  def encode_ir(%IR.MatchOperator{left: left, right: right}, context) do
    left = encode_ir(left, %{context | match_operator?: true, pattern?: true})
    right = encode_ir(right, %{context | match_operator?: true})

    "Interpreter.matchOperator(#{right}, #{left}, context)"
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
      message = """
      can't encode #{Reflection.module_name(module.value)} module definition
      #{Exception.message(error)}\
      """

      reraise RuntimeError, [message: message], __STACKTRACE__
  end

  # See info about the internal structure of PIDs: https://stackoverflow.com/a/262179/13040586
  def encode_ir(%IR.PIDType{value: pid}, context) do
    segments =
      pid
      |> :erlang.pid_to_list()
      |> List.delete_at(0)
      |> List.delete_at(-1)
      |> to_string()
      |> String.split(".")
      |> Enum.map(&IntegerUtils.parse!/1)

    encoded_node = encode_as_string(node(pid), true)

    integer_encoder = fn integer, _context -> to_string(integer) end
    encoded_segments = encode_as_array(segments, context, integer_encoder)

    "Type.pid(#{encoded_node}, #{encoded_segments})"
  end

  def encode_ir(%IR.PinOperator{variable: variable}, context) do
    encode_ir(variable, %{context | pattern?: false})
  end

  def encode_ir(%IR.PortType{value: value}, _context) do
    encode_primitive_type(:port, value, true)
  end

  def encode_ir(%IR.ReferenceType{value: value}, _context) do
    encode_primitive_type(:reference, value, true)
  end

  def encode_ir(
        %IR.RemoteFunctionCall{
          module: module,
          function: function,
          args: args
        },
        context
      ) do
    encode_named_function_call(module, function, args, context)
  end

  def encode_ir(%IR.StringType{value: value}, _context) do
    encode_primitive_type(:bitstring, value, true)
  end

  # TODO: catch_clauses, else_clauses, after_block
  def encode_ir(%IR.Try{} = ir, context) do
    body_js = encode_closure(ir.body, context)
    rescue_clauses_js = encode_as_array(ir.rescue_clauses, context)

    "Interpreter.try(#{body_js}, #{rescue_clauses_js}, [], [], null, context)"
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

  # TODO: finish implementing
  def encode_ir(%IR.With{}, _context) do
    "Interpreter.with()"
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

  defp encode_as_string(value, wrap)

  defp encode_as_string(nil, false) do
    "nil"
  end

  defp encode_as_string(value, false) when is_port(value) do
    value
    |> :erlang.port_to_list()
    |> Enum.drop(6)
    |> List.delete_at(-1)
    |> to_string()
  end

  defp encode_as_string(value, false) when is_reference(value) do
    value
    |> :erlang.ref_to_list()
    |> Enum.drop(5)
    |> List.delete_at(-1)
    |> to_string()
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
    """

    globalThis.hologram.return = #{expr_js};
    Interpreter.updateVarsToMatchedValues(context);
    return globalThis.hologram.return;\
    """
  end

  defp encode_block_expr(expr_js, true, false) do
    "\nreturn #{expr_js};"
  end

  defp encode_block_expr(expr_js, false, true) do
    """

    #{expr_js};
    Interpreter.updateVarsToMatchedValues(context);\
    """
  end

  defp encode_block_expr(expr_js, false, false) do
    "\n#{expr_js};"
  end

  defp encode_closure(ir, context)

  defp encode_closure(nil, _context), do: "null"

  defp encode_closure(%IR.Block{} = ir, context) do
    "(context) => #{encode_block_body(ir, context)}"
  end

  defp encode_closure(ir, context) do
    "(context) => #{encode_ir(ir, context)}"
  end

  defp encode_dynamic_named_function_call(module, function, args, context) do
    module_js = encode_ir(module, context)
    function_js = encode_ir(function, context)
    args_js = encode_ir(args, context)

    "Interpreter.callNamedFunction(#{module_js}, #{function_js}, #{args_js}, context)"
  end

  defp encode_named_function_call(%IR.AtomType{value: :erlang}, :andalso, [left, right], context) do
    left_js = encode_closure(left, context)
    right_js = encode_closure(right, context)

    "Erlang[\"andalso/2\"](#{left_js}, #{right_js}, context)"
  end

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

    "#{class}[\"#{function}/#{arity}\"](#{args_js})"
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

  defp escape_non_printable_and_special_chars(str)

  defp escape_non_printable_and_special_chars("\\" <> rest) do
    "\\\\" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\"" <> rest) do
    "\\\"" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\a" <> rest) do
    "\\x07" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\b" <> rest) do
    "\\b" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\f" <> rest) do
    "\\f" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\n" <> rest) do
    "\\n" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\r" <> rest) do
    "\\r" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\t" <> rest) do
    "\\t" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars("\v" <> rest) do
    "\\v" <> escape_non_printable_and_special_chars(rest)
  end

  # Line separator character (LS)
  # (JavaScript editors have problems with this char)
  defp escape_non_printable_and_special_chars(<<8_232::utf8>> <> rest) do
    "\\u{2028}" <> escape_non_printable_and_special_chars(rest)
  end

  # Paragraph separator character (PS)
  # (JavaScript editors have problems with this char)
  defp escape_non_printable_and_special_chars(<<8_233::utf8>> <> rest) do
    "\\u{2029}" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars(<<code::utf8, rest::binary>>) do
    char = <<code::utf8>>

    escaped_char =
      if String.printable?(char) do
        char
      else
        "\\u{#{Integer.to_string(code, 16)}}"
      end

    escaped_char <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars(<<char::integer, rest::binary>>) do
    # No need to pad with 0, because chars smaller that 16 will be encoded differently
    "\\x#{Integer.to_string(char, 16)}" <> escape_non_printable_and_special_chars(rest)
  end

  defp escape_non_printable_and_special_chars(""), do: ""

  defp extract_erlang_function_source_code(file_path, function, arity) do
    key = "#{function}/#{arity}"
    start_marker = "// Start #{key}"
    end_marker = "// End #{key}"

    regex =
      ~r/#{Regex.escape(start_marker)}[[:space:]]+"#{Regex.escape(key)}":[[:space:]]+(.+),[[:space:]]+#{Regex.escape(end_marker)}/s

    file_contents = File.read!(file_path)

    case Regex.run(regex, file_contents) do
      [_full_capture, source_code] -> source_code
      nil -> nil
    end
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

  defp has_match_operator?(%_struct{} = ir) do
    ir
    |> Map.from_struct()
    |> has_match_operator?()
  end

  defp has_match_operator?(ir) when is_map(ir) do
    Enum.any?(ir, fn {key, value} -> has_match_operator?(key) || has_match_operator?(value) end)
  end

  defp has_match_operator?(_ast), do: false
end
