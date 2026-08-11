defmodule Hologram.Policy do
  @moduledoc """
  The construct for policies shared by several entity types.

  A policy module holds `role` and `allow` declarations written exactly as they are written
  inside an entity type:

      defmodule MyApp.Policies.AdminManaged do
        use Hologram.Policy

        alias MyApp.Roles.Admin

        allow :read, to: Admin
        allow :update, to: Admin
        allow :delete, to: Admin
      end

  An entity type takes them on with `use`, and keeps declaring its own alongside:

      defmodule MyApp.Invoice do
        use Hologram.Entity
        use MyApp.Policies.AdminManaged

        attribute :number, :string

        role :admin
        allow :manage_roles, to: :admin
      end

  Policy modules compose: one may `use` another, and an entity type taking on the outer one
  receives the declarations of both. A role declared by several of them collapses into one
  declaration, as long as every declaration of it is identical.

  Declarations are evaluated where they are written, so aliases, module attributes and helper
  functions in a policy module mean what they mean there - the entity type receives values,
  not code to re-resolve.
  """

  alias Hologram.Commons.Types, as: T
  alias Hologram.Entity
  alias Hologram.Entity.Validator

  defmacro __using__(_opts) do
    quote do
      import Hologram.Policy, only: [allow: 1, allow: 2, role: 1, role: 2]

      Module.register_attribute(__MODULE__, :__policy_declarations__, accumulate: true)

      @before_compile Hologram.Policy
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    declarations =
      env.module
      |> Module.get_attribute(:__policy_declarations__)
      |> Enum.reverse()

    # The replay is a plain call executed in the including module's body, not a macro expanded
    # into it: a module body is fully expanded before any of it runs, so at expansion time the
    # accumulators use Hologram.Entity registers do not exist yet.
    replay_calls =
      Enum.map(declarations, fn declaration ->
        quote do
          Hologram.Policy.__replay__(__MODULE__, unquote(Macro.escape(declaration)))
        end
      end)

    quote do
      defmacro __using__(_opts) do
        unquote(Macro.escape({:__block__, [], replay_calls}))
      end
    end
  end

  @doc false
  @spec __replay__(module, tuple) :: :ok
  def __replay__(module, declaration) do
    cond do
      Module.has_attribute?(module, :__policies__) ->
        replay_into_entity(module, declaration)

      Module.has_attribute?(module, :__policy_declarations__) ->
        Module.put_attribute(module, :__policy_declarations__, declaration)

      true ->
        raise Hologram.CompileError,
          message:
            "policies can be used only in a module with use Hologram.Entity or use Hologram.Policy - #{inspect(module)} has neither"
    end

    :ok
  end

  @doc """
  Accumulates the given policy declaration, for replay into the entity types taking this policy on.

  Takes the same operation and spec as `Hologram.Entity.allow/2`.
  """
  @spec allow(atom, T.opts()) :: Macro.t()
  defmacro allow(operation, spec \\ []) do
    spec = Entity.replace_actor_leaves!(spec, __CALLER__.module)

    quote do
      operation = unquote(operation)
      spec = unquote(spec)

      Validator.validate_allow!(__MODULE__, operation, spec)

      @__policy_declarations__ {:allow, operation, spec}
    end
  end

  @doc """
  Accumulates the given role declaration, for replay into the entity types taking this policy on.

  Takes the same name and options as `Hologram.Entity.role/2`.
  """
  @spec role(atom, T.opts()) :: Macro.t()
  defmacro role(name, opts \\ []) do
    quote do
      name = unquote(name)
      opts = unquote(opts)

      Validator.validate_role!(__MODULE__, name, opts)

      @__policy_declarations__ {:role, name, opts}
    end
  end

  defp replay_into_entity(module, {:allow, operation, spec}) do
    Entity.__put_policy__(module, operation, spec)
  end

  defp replay_into_entity(module, {:role, name, opts}) do
    Entity.__put_role__(module, name, opts)
  end
end
