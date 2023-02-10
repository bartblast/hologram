defmodule Hologram.Compiler.OverhaulTransformer do
  alias Hologram.Compiler.AliasTransformer
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  alias Hologram.Compiler.{
    AdditionOperatorTransformer,
    AliasDirectiveTransformer,
    AnonymousFunctionTypeTransformer,
    BinaryTypeTransformer,
    BlockTransformer,
    CallTransformer,
    CaseExpressionTransformer,
    ConsOperatorTransformer,
    DivisionOperatorTransformer,
    DotOperatorTransformer,
    EqualToOperatorTransformer,
    ForExpressionTransformer,
    FunctionDefinitionTransformer,
    IfExpressionTransformer,
    ImportDirectiveTransformer,
    LessThanOperatorTransformer,
    ListConcatenationOperatorTransformer,
    ListSubtractionOperatorTransformer,
    ListTypeTransformer,
    MatchOperatorTransformer,
    MembershipOperatorTransformer,
    ModuleAttributeDefinitionTransformer,
    ModuleDefinitionTransformer,
    MultiplicationOperatorTransformer,
    NotEqualToOperatorTransformer,
    QuoteTransformer,
    PipeOperatorTransformer,
    RelaxedBooleanAndOperatorTransformer,
    RelaxedBooleanNotOperatorTransformer,
    RelaxedBooleanOrOperatorTransformer,
    RequireDirectiveTransformer,
    StrictBooleanAndOperatorTransformer,
    StructTypeTransformer,
    SubtractionOperatorTransformer,
    TypeOperatorTransformer,
    TupleTypeTransformer,
    UnaryNegativeOperatorTransformer,
    UnaryPositiveOperatorTransformer,
    UnquoteTransformer,
    UseDirectiveTransformer
  }

  alias Hologram.Compiler.IR
  alias Hologram.Compiler.IR.Alias

  alias Hologram.Compiler.IR.{
    AtomType,
    BooleanType,
    FloatType,
    IntegerType,
    ModuleAttributeOperator,
    ModulePseudoVariable,
    NilType,
    ProtocolDefinition,
    StringType,
    Symbol,
    Typespec
  }

  # OPERATORS

  # must be defined before binary addition operator
  def transform({:+, _, [_]} = ast) do
    UnaryPositiveOperatorTransformer.transform(ast)
  end

  def transform({:+, _, _} = ast) do
    AdditionOperatorTransformer.transform(ast)
  end

  def transform([{:|, _, _}] = ast) do
    ConsOperatorTransformer.transform(ast)
  end

  def transform({:/, _, _} = ast) do
    DivisionOperatorTransformer.transform(ast)
  end

  def transform({{:., _, _}, _, _} = ast) do
    DotOperatorTransformer.transform(ast)
  end

  def transform({:==, _, _} = ast) do
    EqualToOperatorTransformer.transform(ast)
  end

  def transform({:<, _, _} = ast) do
    LessThanOperatorTransformer.transform(ast)
  end

  def transform({:++, _, _} = ast) do
    ListConcatenationOperatorTransformer.transform(ast)
  end

  def transform({:--, _, _} = ast) do
    ListSubtractionOperatorTransformer.transform(ast)
  end

  def transform({:=, _, _} = ast) do
    MatchOperatorTransformer.transform(ast)
  end

  def transform({:in, _, _} = ast) do
    MembershipOperatorTransformer.transform(ast)
  end

  # must be defined before module attribute operator
  def transform({:@, _, [{:spec, _, [{:"::", _, _}]}]}) do
    %Typespec{}
  end

  def transform({:@, _, [{name, _, ast}]}) when not is_list(ast) do
    %ModuleAttributeOperator{name: name}
  end

  def transform({:*, _, _} = ast) do
    MultiplicationOperatorTransformer.transform(ast)
  end

  def transform({:!=, _, _} = ast) do
    NotEqualToOperatorTransformer.transform(ast)
  end

  def transform({:|>, _, _} = ast) do
    PipeOperatorTransformer.transform(ast)
  end

  def transform({:&&, _, _} = ast) do
    RelaxedBooleanAndOperatorTransformer.transform(ast)
  end

  def transform({:__block__, _, [{:!, _, _}]} = ast) do
    RelaxedBooleanNotOperatorTransformer.transform(ast)
  end

  def transform({:!, _, _} = ast) do
    RelaxedBooleanNotOperatorTransformer.transform(ast)
  end

  def transform({:||, _, _} = ast) do
    RelaxedBooleanOrOperatorTransformer.transform(ast)
  end

  def transform({:and, _, _} = ast) do
    StrictBooleanAndOperatorTransformer.transform(ast)
  end

  # must be defined before binary subtraction operator
  def transform({:-, _, [_]} = ast) do
    UnaryNegativeOperatorTransformer.transform(ast)
  end

  def transform({:-, _, _} = ast) do
    SubtractionOperatorTransformer.transform(ast)
  end

  def transform({:"::", _, _} = ast) do
    TypeOperatorTransformer.transform(ast)
  end

  # TYPES

  def transform(ast) when is_atom(ast) and ast not in [nil, false, true] do
    if Reflection.is_alias?(ast) do
      AliasTransformer.transform(ast)
    else
      %AtomType{value: ast}
    end
  end

  def transform({:<<>>, _, _} = ast) do
    BinaryTypeTransformer.transform(ast)
  end

  def transform(ast) when is_list(ast) do
    ListTypeTransformer.transform(ast)
  end

  def transform({:%{}, _, data}) do
    {module, new_data} = Keyword.pop(data, :__struct__)

    data_ir =
      Enum.map(new_data, fn {key, value} ->
        {transform(key), transform(value)}
      end)

    if module do
      segments = Helpers.alias_segments(module)
      module_ir = %IR.ModuleType{module: module, segments: segments}
      %IR.StructType{module: module_ir, data: data_ir}
    else
      %IR.MapType{data: data_ir}
    end
  end

  def transform({:%, _, [alias_ast, map_ast]}) do
    module = transform(alias_ast)
    data = transform(map_ast).data

    %IR.StructType{module: module, data: data}
  end

  def transform({:{}, _, _} = ast) do
    TupleTypeTransformer.transform(ast)
  end

  def transform({_, _} = ast) do
    TupleTypeTransformer.transform(ast)
  end

  # DEFINITIONS

  def transform({:def, _, _} = ast) do
    FunctionDefinitionTransformer.transform(ast)
  end

  def transform({:defp, _, _} = ast) do
    FunctionDefinitionTransformer.transform(ast)
  end

  def transform({:defmacro, _, _}) do
    %IR.IgnoredExpression{type: :macro_definition}
  end

  def transform({:defmodule, _, _} = ast) do
    ModuleDefinitionTransformer.transform(ast)
  end

  # TODO: implement
  def transform({:defprotocol, _, _}) do
    %ProtocolDefinition{}
  end

  def transform({:@, _, [{_, _, exprs}]} = ast) when is_list(exprs) do
    ModuleAttributeDefinitionTransformer.transform(ast)
  end

  # DIRECTIVES

  def transform({:alias, _, _} = ast) do
    AliasDirectiveTransformer.transform(ast)
  end

  def transform({:import, _, _} = ast) do
    ImportDirectiveTransformer.transform(ast)
  end

  def transform({:require, _, _} = ast) do
    RequireDirectiveTransformer.transform(ast)
  end

  def transform({:use, _, _} = ast) do
    UseDirectiveTransformer.transform(ast)
  end

  # CONTROL FLOW

  def transform({:case, _, _} = ast) do
    CaseExpressionTransformer.transform(ast)
  end

  def transform({:for, _, _} = ast) do
    ForExpressionTransformer.transform(ast)
  end

  def transform({:if, _, _} = ast) do
    IfExpressionTransformer.transform(ast)
  end

  # OTHER

  def transform({:__aliases__, _, segments}) do
    %Alias{segments: segments}
  end

  def transform({:quote, _, _} = ast) do
    QuoteTransformer.transform(ast)
  end

  def transform({:unquote, _, _} = ast) do
    UnquoteTransformer.transform(ast)
  end

  def transform({:__ENV__, _, _}) do
    %IR.EnvPseudoVariable{}
  end

  def transform({:__MODULE__, _, _}) do
    %IR.ModulePseudoVariable{}
  end

  def transform({name, _, args} = ast)
      when is_atom(name) and is_list(args) do
    CallTransformer.transform(ast)
  end

  def transform({_, [context: _, imports: _], _} = ast) do
    CallTransformer.transform(ast)
  end

  def transform({name, _, _}) when is_atom(name) do
    %Symbol{name: name}
  end
end
