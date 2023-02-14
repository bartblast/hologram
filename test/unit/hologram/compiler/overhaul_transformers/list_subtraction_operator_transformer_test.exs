defmodule Hologram.Compiler.ListSubtractionOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ListSubtractionOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ListSubtractionOperator, ListType}
end
