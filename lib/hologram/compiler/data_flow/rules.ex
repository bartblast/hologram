defmodule Hologram.Compiler.DataFlow.Rules do
  @moduledoc false

  # A rules module holds hand-written answers for a library's functions, which the analysis uses
  # instead of following their code (see Hologram.Compiler.DataFlow): a library that builds its
  # values at runtime from what it introspects is answered by what its introspection says. The
  # compiler finds the rules modules with no configuration: the built-in ones (see built_in/0).
  #
  # The rules modules are asked in order, the first answer winning: a library built on another (Ash
  # on Ecto) comes before it, so what it knows of its own modules wins over what the other's
  # reflection says of them. Two questions are asked: what a function gives (summary/2), and what a
  # record of a module holds (record/2), which a rules module asks when it needs a record another
  # library may know better, so a record has one answer however it was loaded.
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
  Returns, as a tree, what the named part of an answer gives, from what each argument of the call is:
  its atoms and struct modules, the atoms right inside its structs' fields, and a bag's atoms and
  struct modules at any depth, sorted (the analysis computes them on its shared values, so a rule
  never walks one); the rule takes the modules it knows among them.
  """
  @callback resolve(atom, [[atom]], DataFlow.t()) :: DataFlow.tree()

  @doc """
  Returns, as a tree, the records of the given module when the rules module's library builds them
  (for Ash, a resource), or nil.
  """
  @callback record(module, DataFlow.t()) :: DataFlow.tree() | nil

  @optional_callbacks record: 2

  @doc """
  Returns the built-in rules modules, which the analysis asks unless it is given others.
  """
  @spec built_in() :: [module]
  def built_in, do: [Hologram.Compiler.DataFlow.Rules.Ash]

  @doc """
  Returns the records of the given module that the first of the given flow context's rules modules
  that knows them answers (see `c:record/2`), or nil when none does.
  """
  @spec record(module, DataFlow.t()) :: DataFlow.tree() | nil
  def record(module, flow) do
    Enum.find_value(flow.rules, fn rules_module ->
      if Code.ensure_loaded?(rules_module) and function_exported?(rules_module, :record, 2),
        do: rules_module.record(module, flow)
    end)
  end

  @doc """
  Returns what the given rules module answers for the named part of an answer, from what each
  argument of the call is (see `c:resolve/3`).
  """
  @spec resolve(module, atom, [[atom]], DataFlow.t()) :: DataFlow.tree()
  def resolve(rules_module, name, atoms_per_arg, flow),
    do: rules_module.resolve(name, atoms_per_arg, flow)

  @doc """
  Returns the answer of the first of the given flow context's rules modules that answers the given
  function (see `c:summary/2`), or nil when none does.
  """
  @spec summary(mfa, DataFlow.t()) :: DataFlow.tree() | nil
  def summary(mfa, flow) do
    Enum.find_value(flow.rules, & &1.summary(mfa, flow))
  end
end
