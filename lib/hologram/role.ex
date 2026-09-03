defmodule Hologram.Role do
  @moduledoc """
  The construct for global roles - roles held app-wide rather than on an entity.

  A global role is defined as a module:

      defmodule MyApp.Roles.Admin do
        use Hologram.Role
      end

  The module itself is the role's identity everywhere it is named - in the policy lines
  granting to it, and in the calls granting it to a user:

      allow :read, to: MyApp.Roles.Admin

      Hologram.Auth.grant_role(user, MyApp.Roles.Admin)

  A role held on a particular entity is declared inside the entity type instead, with
  `Hologram.Entity.role/2` - those role names are plain atoms, scoped to their entity type.

  ## Options

    * `:extends` - a role module, or a list of them, whose capabilities this role carries.
      A holder of the extending role satisfies every requirement for the extended one:

          defmodule MyApp.Roles.Admin do
            use Hologram.Role, extends: MyApp.Roles.Support
          end
  """

  alias Hologram.Entity.Validator

  defmacro __using__(opts) do
    quote do
      Validator.validate_use_role_opts!(__MODULE__, unquote(opts))

      @__hologram_role_extends__ List.wrap(unquote(opts)[:extends])

      @doc """
      Returns true to indicate that the callee module is a global role module (has "use Hologram.Role" directive).

      ## Examples

          iex> __is_hologram_role__()
          true
      """
      @spec __is_hologram_role__() :: boolean
      def __is_hologram_role__, do: true

      @doc """
      Returns the role modules that the callee role extends, in declaration order.

      ## Examples

          iex> __extends__()
          [MyApp.Roles.Support]
      """
      @spec __extends__() :: list(module)
      def __extends__, do: @__hologram_role_extends__
    end
  end
end
