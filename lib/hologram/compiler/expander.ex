defmodule Hologram.Compiler.Expander do
  import Hologram.Compiler.Macros, only: [expand: 3]

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Detransformer
  alias Hologram.Compiler.Evaluator
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Reflection
  alias Hologram.Compiler.Transformer

  def expand(ir, context)

  # --- OPERATORS ---

  expand(%IR.AdditionOperator{} = ir, %Context{} = context) do
    expand_binary_operator(ir, context)
  end

  expand(%IR.EqualToOperator{} = ir, %Context{} = context) do
    expand_binary_operator(ir, context)
  end

  expand(
    %IR.MatchOperator{bindings: bindings, left: left, right: right},
    %Context{} = context
  ) do
    new_bindings = expand_list(bindings, context)
    {new_left, _context} = expand(left, context)
    {new_right, _context} = expand(right, context)
    new_ir = %IR.MatchOperator{bindings: new_bindings, left: new_left, right: new_right}

    new_variables =
      new_bindings
      |> Enum.map(& &1.name)
      |> MapSet.new()
      |> MapSet.union(context.variables)

    new_context = %{context | variables: new_variables}

    {new_ir, new_context}
  end

  expand(
    %IR.ModuleAttributeOperator{name: name},
    %Context{module_attributes: module_attributes} = context
  ) do
    {module_attributes[name], context}
  end

  # --- DATA TYPES ---

  expand(%IR.AtomType{} = ir, %Context{} = context) do
    {ir, context}
  end

  expand(%IR.BooleanType{} = ir, %Context{} = context) do
    {ir, context}
  end

  expand(%IR.FloatType{} = ir, %Context{} = context) do
    {ir, context}
  end

  expand(%IR.IntegerType{} = ir, %Context{} = context) do
    {ir, context}
  end

  expand(%IR.MapType{data: data}, %Context{} = context) do
    new_data =
      Enum.map(data, fn {key, value} ->
        {new_key, _context} = expand(key, context)
        {new_value, _context} = expand(value, context)
        {new_key, new_value}
      end)

    {%IR.MapType{data: new_data}, context}
  end

  expand(%IR.ModuleType{} = ir, %Context{} = context) do
    {ir, context}
  end

  expand(%IR.NilType{} = ir, %Context{} = context) do
    {ir, context}
  end

  # --- PSEUDO-VARIABLES ---

  expand(%IR.EnvPseudoVariable{}, %Context{} = context) do
    ir =
      context
      |> Context.build_env()
      |> Helpers.term_to_ir()

    {ir, context}
  end

  expand(%IR.ModulePseudoVariable{}, %Context{module: module} = context) do
    {module, context}
  end

  # --- DEFINITIONS ---

  expand(
    %IR.ModuleAttributeDefinition{name: name, expression: expr},
    %Context{} = context
  ) do
    {expanded_ir, _context} = expand(expr, context)

    value =
      expanded_ir
      |> List.wrap()
      |> hd()
      |> Evaluator.evaluate()
      |> Helpers.term_to_ir()

    new_context = Context.put_module_attribute(context, name, value)

    {%IR.IgnoredExpression{type: :module_attribute_definition}, new_context}
  end

  expand(
    %IR.ModuleDefinition{} = ir,
    %Context{module: nil} = context
  ) do
    {module, _context} = expand(ir.module, context)
    new_context = %{context | module: module}
    {body, _context} = expand(ir.body, new_context)

    {%{ir | module: module, body: body}, context}
  end

  expand(%IR.ModuleDefinition{} = ir, %Context{} = context) do
    segs = context.module.segments ++ ir.module.segments
    module = %IR.ModuleType{module: Helpers.module(segs), segments: segs}

    new_context = %{context | module: module}
    {body, _context} = expand(ir.body, new_context)

    {%{ir | module: module, body: body}, context}
  end

  # --- DIRECTIVES ---

  expand(
    %IR.AliasDirective{alias_segs: alias_segs, as: as},
    %Context{aliases: aliases} = context
  ) do
    expanded_alias_segs = expand_alias_segs(alias_segs, aliases)
    new_aliases = Map.put(aliases, as, expanded_alias_segs)
    new_context = %{context | aliases: new_aliases}

    {%IR.IgnoredExpression{type: :alias_directive}, new_context}
  end

  expand(
    %IR.ImportDirective{alias_segs: alias_segs, only: only, except: except},
    %Context{aliases: aliases} = context
  ) do
    expanded_alias_segs = expand_alias_segs(alias_segs, aliases)
    module = Helpers.module(expanded_alias_segs)

    functions = filter_exports(:functions, Reflection.functions(module), only, except)
    macros = filter_exports(:macros, Reflection.macros(module), only, except)

    new_context =
      context
      |> Context.put_functions(module, functions)
      |> Context.put_macros(module, macros)

    {%IR.IgnoredExpression{type: :import_directive}, new_context}
  end

  # --- CONTROL FLOW ---

  expand(%IR.Alias{segments: segments}, %Context{aliases: aliases} = context) do
    module_segs = expand_alias_segs(segments, aliases)
    module = Helpers.module(module_segs)

    {%IR.ModuleType{module: module, segments: module_segs}, context}
  end

  expand(%IR.Block{expressions: exprs}, %Context{} = context) do
    {new_exprs, _new_context} = expand_list_and_context(exprs, context)

    {%IR.Block{expressions: new_exprs}, context}
  end

  # TODO: test
  expand(%IR.Call{module: nil, function: function, args: args}, %Context{} = context) do
    arity = Enum.count(args)

    module =
      Context.resolve_macro_module(context, function, arity) ||
        Context.resolve_function_module(context, function, arity) ||
        context.module

    segments = Helpers.alias_segments(module)
    module = %IR.ModuleType{module: module, segments: segments}

    %IR.Call{module: module, function: function, args: args}
    |> expand(context)
  end

  # TODO: test
  expand(%IR.Call{module: module_ir, function: function, args: args}, %Context{} = context) do
    {%{module: module} = new_module_ir, _context} = expand(module_ir, context)
    new_args = expand_list(args, context)
    arity = Enum.count(new_args)

    exprs =
      if Reflection.has_macro?(module, function, arity) do
        args_ast = Detransformer.detransform_list(new_args)
        expand_macro(context, module, function, args_ast)
      else
        [%IR.FunctionCall{module: new_module_ir, function: function, args: new_args}]
      end

    expand_list_and_context(exprs, context)
  end

  expand(%IR.FunctionCall{} = ir, %Context{} = context) do
    {ir, context}
  end

  expand(%IR.Variable{} = ir, %Context{} = context) do
    {ir, context}
  end

  # --- BINDINGS ---

  expand(%IR.Binding{access_path: access_path} = ir, %Context{} = context) do
    new_access_path = expand_list(access_path, context)

    {%{ir | access_path: new_access_path}, context}
  end

  expand(%IR.ListIndexAccess{} = ir, %Context{} = context) do
    {ir, context}
  end

  expand(%IR.MapAccess{key: key} = ir, %Context{} = context) do
    {new_key, _context} = expand(key, context)

    {%{ir | key: new_key}, context}
  end

  expand(%IR.MatchAccess{} = ir, %Context{} = context) do
    {ir, context}
  end

  # --- OTHER IR ---

  expand(%IR.IgnoredExpression{} = ir, %Context{} = context) do
    {ir, context}
  end

  # --- HELPERS ---

  defp expand_alias_segs([head | tail] = alias_segs, aliases) do
    if aliases[head] do
      aliases[head] ++ tail
    else
      alias_segs
    end
  end

  defp expand_binary_operator(%{left: left, right: right} = ir, context) do
    {left, _context} = expand(left, context)
    {right, _context} = expand(right, context)

    {%{ir | left: left, right: right}, context}
  end

  defp expand_list(list, context) do
    Enum.reduce(list, [], fn ir, acc ->
      {new_ir, _context} = expand(ir, context)
      [new_ir | acc]
    end)
    |> Enum.reverse()
  end

  defp expand_list_and_context(list, context) do
    Enum.reduce(list, {[], context}, fn expr, {exprs_acc, context_acc} ->
      {new_expr, new_context} = expand(expr, context_acc)
      {List.flatten(exprs_acc ++ [new_expr]), new_context}
    end)
  end

  defp expand_macro(context, module, function, args_ast) do
    env = Context.build_env(context)

    expanded_ir =
      module
      |> apply(:"MACRO-#{function}", [env | args_ast])
      |> Normalizer.normalize()
      |> Transformer.transform()

    case expanded_ir do
      %IR.Block{expressions: exprs} ->
        exprs

      expr ->
        [expr]
    end
  end

  defp filter_exports(type, exports, only, except)

  defp filter_exports(:functions, exports, :functions, []) do
    exports
  end

  defp filter_exports(:functions, exports, :functions, except) do
    Enum.reject(exports, &(&1 in except))
  end

  defp filter_exports(:functions, _exports, :macros, _except) do
    []
  end

  defp filter_exports(:macros, exports, :macros, []) do
    exports
  end

  defp filter_exports(:macros, exports, :macros, except) do
    Enum.reject(exports, &(&1 in except))
  end

  defp filter_exports(:macros, _exports, :functions, _except) do
    []
  end

  defp filter_exports(_type, exports, :sigils, []) do
    Enum.filter(exports, fn {name, arity} ->
      to_string(name) =~ ~r/^sigil_[a-zA-Z]$/ && arity == 2
    end)
  end

  defp filter_exports(_type, exports, :sigils, except) do
    Enum.filter(exports, fn {name, arity} = export ->
      to_string(name) =~ ~r/^sigil_[a-zA-Z]$/ && arity == 2 && export not in except
    end)
  end

  defp filter_exports(_type, exports, [], []) do
    exports
  end

  defp filter_exports(_type, exports, only, []) do
    Enum.filter(exports, &(&1 in only))
  end

  defp filter_exports(_type, exports, [], except) do
    Enum.reject(exports, &(&1 in except))
  end

  # def expand(%IR.Symbol{name: name}, %Context{} = context) do
  #   if MapSet.member?(context.variables, name) do
  #     {%IR.Variable{name: name}, context}
  #   else
  #     %IR.Call{module: nil, function: name, args: []}
  #     |> expand(context)
  #   end
  # end
end
