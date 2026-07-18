defmodule Hologram.Database.Mapper do
  @moduledoc false

  alias Hologram.Reflection

  # PostgreSQL truncates identifiers to 63 bytes - derived identifiers must never rely on that.
  @max_identifier_bytes 63

  @hash_bytes 8

  @doc """
  Returns the given identifier wrapped in double quotes, with embedded double quotes escaped.
  Emitted SQL always quotes identifiers, so no derived name can ever clash with a reserved word.
  """
  @spec quote_identifier(String.t()) :: String.t()
  def quote_identifier(identifier) do
    ~s("#{String.replace(identifier, ~s("), ~s(""))}")
  end

  @doc """
  Returns the table name derived from the given entity type module.

  The name is the snake_cased module path with the leading segment stripped when it matches
  the primary OTP app's conventional root namespace - modules from other roots (guest apps,
  libraries) keep their full path. Derived names over the PostgreSQL identifier limit keep
  a readable prefix followed by a short deterministic hash of the full name.
  """
  @spec table_name(module) :: String.t()
  def table_name(entity_type) do
    segments = Module.split(entity_type)

    root =
      Reflection.otp_app()
      |> Atom.to_string()
      |> Macro.camelize()

    segments
    |> strip_root(root)
    |> Enum.map_join("_", &Macro.underscore/1)
    |> fit_identifier()
  end

  @doc """
  Validates that no two of the given entity type modules derive the same table name.

  Returns :ok, or raises Hologram.CompileError listing every colliding table name together
  with all entity type modules that derive it. Collisions are possible because snake casing
  merges module boundaries (MyApp.Blog.Post and MyApp.BlogPost both derive "blog_post").
  """
  @spec validate_table_names!(list(module)) :: :ok
  def validate_table_names!(entity_types) do
    collisions =
      entity_types
      |> Enum.group_by(&table_name/1)
      |> Enum.filter(fn {_table_name, modules} -> length(modules) > 1 end)
      |> Enum.sort()

    if collisions != [] do
      descriptions =
        Enum.map_join(collisions, "\n", fn {table_name, modules} ->
          module_names = modules |> Enum.sort() |> Enum.map_join(", ", &inspect/1)
          "  * table name \"#{table_name}\" is derived from #{module_names}"
        end)

      raise Hologram.CompileError,
        message:
          "colliding table names - rename modules so that every entity type derives a unique table name:\n#{descriptions}"
    end

    :ok
  end

  defp fit_identifier(identifier) do
    if byte_size(identifier) > @max_identifier_bytes do
      hash =
        :md5
        |> :crypto.hash(identifier)
        |> Base.encode16(case: :lower)
        |> binary_part(0, @hash_bytes)

      prefix_bytes = @max_identifier_bytes - @hash_bytes - 1

      binary_part(identifier, 0, prefix_bytes) <> "_" <> hash
    else
      identifier
    end
  end

  defp strip_root([root | [_head | _tail] = remainder], root), do: remainder

  defp strip_root(segments, _root), do: segments
end
