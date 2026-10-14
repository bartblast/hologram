defmodule Hologram.Compiler.DataModelInputs do
  @moduledoc """
  What a validation of the data model from the beams is decided by, recorded in the build dir when
  the validation passes: the Elixir compile manifest of every loaded application that has one,
  digested (see `Hologram.Compiler.CompileInputs.list_manifest_digests/1`). The Elixir compiler
  rewrites an application's manifest whenever it compiles or removes a module of it, so a record
  equal to the world now means the beams are the ones the model was valid for.
  """

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.CompileInputs

  # Bumped when the record's shape changes: a dump of another version is not loaded. An upgrade of
  # Hologram needs no bump, since it rewrites the :hologram application's manifest, which the record
  # holds.
  @dump_version 1

  @type t :: %{manifests: [{atom, non_neg_integer}]}

  @doc """
  Builds the record of the world now. Takes the compile task's options: `:build_lib_dir` for the
  manifests.
  """
  @spec build(keyword) :: t
  def build(opts) do
    %{manifests: CompileInputs.list_manifest_digests(opts[:build_lib_dir])}
  end

  @doc """
  Writes the record to the given path, atomically. The parent directory must exist.
  """
  @spec dump(t, String.t()) :: :ok
  def dump(record, path) do
    data = SerializationUtils.serialize({@dump_version, record})
    FileUtils.write_atomically!(path, data)
  end

  @doc """
  Reads the record at the given path, or returns nil when there is none or it is of another version.
  """
  @spec load(String.t()) :: t | nil
  def load(path) do
    with {:ok, data} <- File.read(path),
         {@dump_version, record} <- SerializationUtils.deserialize(data, true) do
      record
    else
      _no_record -> nil
    end
  end

  @doc """
  Whether the world is as the given record says: the manifests digested again equal the recorded
  ones.
  """
  @spec unchanged?(t, keyword) :: boolean
  def unchanged?(record, opts) do
    record == build(opts)
  end
end
