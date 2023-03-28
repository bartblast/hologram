defmodule Hologram.Compiler.Transformer do
  if Application.compile_env(:hologram, :debug_transformer) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Compiler.Transformer, :transform, 1} => [
          after: {Hologram.Compiler.Transformer, :debug, 2}
        ]
      }
  end

  alias Hologram.Compiler.IR

  def transform(ast) when is_atom(ast) and ast not in [nil, false, true] do
    %IR.AtomType{value: ast}
  end

  def transform(ast) when is_boolean(ast) do
    %IR.BooleanType{value: ast}
  end
end
