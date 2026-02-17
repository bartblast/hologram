defmodule Hologram.Benchmarks do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Compiler

  @doc """
  Generates 2 module digest PLTs that fullfill the conditions given in the arguments.

  If the arguments are floats they are treated as percentage (0.2 == 20%),
  otherwise they are treated as (literal) number of modules.
  """
  @spec generate_module_digest_plts(integer, integer, integer) :: {PLT.t(), PLT.t()}
  def generate_module_digest_plts(added_modules_spec, removed_modules_spec, edited_modules_spec) do
    validate_args(added_modules_spec, removed_modules_spec, edited_modules_spec)

    module_digests =
      Compiler.build_module_digest_plt!()
      |> PLT.get_all()
      |> Map.to_list()

    num_modules = Enum.count(module_digests)

    {num_added_modules, num_removed_modules, num_edited_modules} =
      calculate_num_modules(
        num_modules,
        added_modules_spec,
        removed_modules_spec,
        edited_modules_spec
      )

    num_untouched_modules =
      num_modules - num_added_modules - num_removed_modules - num_edited_modules

    added_modules_chunk = Enum.take(module_digests, num_added_modules)

    removed_modules_chunk =
      module_digests
      |> Enum.drop(num_added_modules)
      |> Enum.drop(-num_untouched_modules)
      |> Enum.drop(-num_edited_modules)

    old_edited_modules_chunk =
      module_digests
      |> Enum.drop(num_added_modules)
      |> Enum.drop(num_removed_modules)
      |> Enum.drop(-num_untouched_modules)

    untouched_modules_chunk = Enum.take(module_digests, -num_untouched_modules)

    old_module_digest_plt =
      PLT.start(
        items: removed_modules_chunk ++ old_edited_modules_chunk ++ untouched_modules_chunk
      )

    new_edited_modules_chunk =
      Enum.map(old_edited_modules_chunk, fn {module, digest} ->
        {module, digest + 1}
      end)

    new_module_digest_plt =
      PLT.start(items: added_modules_chunk ++ new_edited_modules_chunk ++ untouched_modules_chunk)

    {old_module_digest_plt, new_module_digest_plt}
  end

  # Only one guard for one argument is needed, because the arguments are validated.
  defp calculate_num_modules(
         num_modules,
         added_modules_spec,
         removed_modules_spec,
         edited_modules_spec
       )
       when is_float(added_modules_spec) do
    {trunc(added_modules_spec * num_modules), trunc(removed_modules_spec * num_modules),
     trunc(edited_modules_spec * num_modules)}
  end

  # No guards are needed in the fallback, because the arguments are validated.
  defp calculate_num_modules(
         _num_modules,
         added_modules_spec,
         removed_modules_spec,
         edited_modules_spec
       ) do
    {added_modules_spec, removed_modules_spec, edited_modules_spec}
  end

  defp validate_args(added_modules_spec, removed_modules_spec, edited_modules_spec)
       when is_float(added_modules_spec) and added_modules_spec >= 0.0 and
              is_float(removed_modules_spec) and
              removed_modules_spec >= 0.0 and is_float(edited_modules_spec) and
              edited_modules_spec >= 0.0 do
    if added_modules_spec + removed_modules_spec + edited_modules_spec > 1.0 do
      raise ArgumentError,
        message:
          "the sum of the arguments in case they are floats must be less than or equal to 1.0"
    end

    true
  end

  defp validate_args(added_modules_spec, removed_modules_spec, edited_modules_spec)
       when is_integer(added_modules_spec) and added_modules_spec >= 0 and
              is_integer(removed_modules_spec) and
              removed_modules_spec >= 0 and is_integer(edited_modules_spec) and
              edited_modules_spec >= 0 do
    true
  end

  defp validate_args(added_modules_spec, removed_modules_spec, edited_modules_spec) do
    raise ArgumentError,
      message:
        "invalid arguments: added_modules_spec = #{inspect(added_modules_spec)}, removed_modules_spec = #{inspect(removed_modules_spec)}, edited_modules_spec = #{inspect(edited_modules_spec)}"
  end
end
