defmodule Hologram.Compiler.Expander do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Evaluator
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection
  alias Hologram.Compiler.Transformer

  def expand(ir, context)

  def expand(%{kind: :basic_data_type} = ir, %Context{} = context) do
    {ir, context}
  end

  def expand(%{kind: :basic_binary_operator, left: left, right: right} = ir, %Context{} = context) do
    {left, _context} = expand(left, context)
    {right, _context} = expand(right, context)

    {%{ir | left: left, right: right}, context}
  end

  def expand(%{kind: :bindings_meta} = ir, %Context{} = context) do
    {ir, context}
  end

  def expand(%IR.Alias{segments: segments}, %Context{aliases: defined_aliases} = context) do
    expanded_alias_segs = expand_alias_segs(segments, defined_aliases)
    module = Helpers.module(expanded_alias_segs)

    {%IR.ModuleType{module: module, segments: expanded_alias_segs}, context}
  end

  def expand(
        %IR.AliasDirective{alias_segs: alias_segs, as: as},
        %Context{aliases: defined_aliases} = context
      ) do
    expanded_alias_segs = expand_alias_segs(alias_segs, defined_aliases)
    new_defined_aliases = Map.put(defined_aliases, as, expanded_alias_segs)
    new_context = %{context | aliases: new_defined_aliases}

    {%IR.IgnoredExpression{}, new_context}
  end

  def expand(%IR.Block{expressions: exprs}, %Context{} = context) do
    {expanded_exprs, _new_context} =
      Enum.reduce(exprs, {[], context}, fn expr, {expanded_exprs, new_context} ->
        {expanded_expr, new_context} = expand(expr, new_context)
        {expanded_exprs ++ [expanded_expr], new_context}
      end)

    {%IR.Block{expressions: expanded_exprs}, context}
  end

  def expand(
        %IR.ImportDirective{alias_segs: alias_segs, only: only, except: except},
        %Context{aliases: defined_aliases} = context
      ) do
    expanded_alias_segs = expand_alias_segs(alias_segs, defined_aliases)
    module = Helpers.module(expanded_alias_segs)

    functions = filter_exports(:functions, Reflection.functions(module), only, except)
    macros = filter_exports(:macros, Reflection.macros(module), only, except)

    new_context =
      context
      |> Context.put_functions(module, functions)
      |> Context.put_macros(module, macros)

    {%IR.IgnoredExpression{}, new_context}
  end

  def expand(%IR.MapType{data: data}, %Context{} = context) do
    new_data =
      Enum.map(data, fn {key, value} ->
        {new_key, _context} = expand(key, context)
        {new_value, _context} = expand(value, context)
        {new_key, new_value}
      end)

    {%IR.MapType{data: new_data}, context}
  end

  def expand(
        %IR.ModuleAttributeDefinition{name: name, expression: expr},
        %Context{} = context
      ) do
    {expanded_ir, _context} = expand(expr, context)

    value =
      expanded_ir
      |> Evaluator.evaluate()
      |> Macro.escape()
      |> Transformer.transform(context)

    new_context = Context.put_module_attribute(context, name, value)

    {%IR.IgnoredExpression{}, new_context}
  end

  def expand(
        %IR.ModuleAttributeOperator{name: name},
        %Context{module_attributes: module_attributes} = context
      ) do
    {module_attributes[name], context}
  end

  def expand(
        %IR.ModuleDefinition{} = ir,
        %Context{module: nil} = context
      ) do
    {module, _context} = expand(ir.module, context)
    new_context = %{context | module: module}
    {body, _context} = expand(ir.body, new_context)

    {%{ir | module: module, body: body}, context}
  end

  def expand(%IR.ModuleDefinition{} = ir, %Context{} = context) do
    segs = context.module.segments ++ ir.module.segments
    module = %IR.ModuleType{module: Helpers.module(segs), segments: segs}

    new_context = %{context | module: module}
    {body, _context} = expand(ir.body, new_context)

    {%{ir | module: module, body: body}, context}
  end

  def expand(%IR.ModulePseudoVariable{}, %Context{module: module}) do
    module
  end

  def expand(%IR.Variable{} = ir, %Context{} = context) do
    {ir, context}
  end

  defp expand_alias_segs([head | tail] = alias_segs, defined_aliases) do
    if defined_aliases[head] do
      defined_aliases[head] ++ tail
    else
      alias_segs
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
end
