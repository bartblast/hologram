defmodule Hologram.Compiler.DataFlow.Rules do
  @moduledoc false

  # A rules module holds hand-written answers for a library's functions, which the analysis uses
  # instead of following their code (see Hologram.Compiler.DataFlow): a library that builds its
  # values at runtime from what it introspects is answered by what its introspection says. The
  # compiler finds the rules modules with no configuration: the built-in ones (see built_in/0).
  #
  # A rules module answers with plain trees (see Hologram.Compiler.DataFlow.tree/0), which the
  # analysis interns once per function: a rule never walks or expands a shared value. What it
  # computes once per compile (records, type shapes) it keeps in the flow context's rule cache.

  alias Hologram.Compiler.DataFlow

  @doc """
  Returns the answer for the given function, in terms of its parameters like a model (see
  `Hologram.Compiler.DataFlow.Models`), as a tree; or nil when the rules module has none, and the
  analysis follows the function's code.
  """
  @callback summary(mfa, DataFlow.t()) :: DataFlow.tree() | nil

  @doc """
  Returns, as a tree, what the named part of an answer gives, from the module atoms among the leaves
  of each argument of the call (the analysis computes them on its shared values, so a rule never
  walks one).
  """
  @callback resolve(atom, [[module]], DataFlow.t()) :: DataFlow.tree()

  @doc """
  Returns the built-in rules modules, which the analysis asks unless it is given others.
  """
  @spec built_in() :: [module]
  def built_in, do: []

  @doc """
  Returns the answer of the first of the given flow context's rules modules that answers the given
  function (see `c:summary/2`), or nil when none does.
  """
  @spec summary(mfa, DataFlow.t()) :: DataFlow.tree() | nil
  def summary(mfa, flow) do
    Enum.find_value(flow.rules, & &1.summary(mfa, flow))
  end
end
