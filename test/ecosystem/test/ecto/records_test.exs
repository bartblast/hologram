defmodule HologramEcosystemTests.Ecto.RecordsTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ecto, as: EctoRules
  alias HologramEcosystemTests.Ecto.Comment
  alias HologramEcosystemTests.Ecto.Post
  alias HologramEcosystemTests.Ecto.Section
  alias HologramEcosystemTests.Ecto.Tag

  setup do
    [flow: DataFlow.start(PLT.start(), PLT.start())]
  end

  defp fields(schema, flow) do
    [{:struct, ^schema, fields}] = EctoRules.record_shapes(schema, flow)
    fields
  end

  defp not_loaded(schema) do
    {:struct, Ecto.Association.NotLoaded,
     %{__cardinality__: [:prim], __field__: [:prim], __owner__: [{:atom, schema}]}}
  end

  # The records a to-many association holds, from the list among its alternatives.
  defp listed(shapes) do
    [{:list, records}] = Enum.filter(shapes, &match?({:list, _records}, &1))
    records
  end

  test "a field holds its type or nil", %{flow: flow} do
    fields = fields(Post, flow)

    assert fields.title == [:prim]
    assert [:prim, {:struct, Date, _date}] = fields.published_on
    assert [:prim, {:struct, DateTime, _date_time}] = fields.inserted_at
  end

  test "a virtual field holds its type or nil", %{flow: flow} do
    assert fields(Post, flow).draft == [:prim]
  end

  test "an embed holds the embedded schema's record, a list of them for many, or nil", %{
    flow: flow
  } do
    tag = EctoRules.record_shapes(Tag, flow)
    fields = fields(Post, flow)

    assert fields.main_tag == Enum.sort([:prim | tag])
    assert fields.tags == [:prim, {:list, tag}]
  end

  test "an embedded schema that embeds itself ends", %{flow: flow} do
    assert listed(fields(Section, flow).sections) ==
             [{:bag, [{:reach, Section}, {:struct, Section, %{}}]}]
  end

  test "a to-one association holds the related record, nil or not loaded", %{flow: flow} do
    post = fields(Comment, flow).post

    assert :prim in post
    assert not_loaded(Comment) in post
    assert Enum.any?(post, &match?({:struct, Post, %{title: _title}}, &1))
  end

  test "a to-many association holds a list of the related records, nil or not loaded", %{
    flow: flow
  } do
    comments = fields(Post, flow).comments

    assert :prim in comments
    assert not_loaded(Post) in comments
    assert [{:struct, Comment, comment_fields}] = listed(comments)
    assert comment_fields.text == [:prim]
  end

  test "an association through others holds the records the last of them gives", %{flow: flow} do
    assert [{:struct, Post, _post_fields}] = listed(fields(Post, flow).comment_posts)
  end

  test "an association past the depth is a bag of the types every reachable record holds", %{
    flow: flow
  } do
    [{:struct, Comment, comment_fields}] = listed(fields(Post, flow).comments)

    assert [{:bag, leaves}] = Enum.filter(comment_fields.post, &match?({:bag, _leaves}, &1))
    assert {:struct, Post, %{}} in leaves
    assert {:struct, Comment, %{}} in leaves
    assert {:struct, Tag, %{}} in leaves
    assert {:struct, Decimal, %{}} in leaves
  end

  test "a schema with a source holds its metadata", %{flow: flow} do
    assert [{:struct, Ecto.Schema.Metadata, %{schema: [{:atom, Post}]}}] =
             fields(Post, flow).__meta__
  end

  test "an embedded schema holds no metadata", %{flow: flow} do
    fields = fields(Tag, flow)

    refute Map.has_key?(fields, :__meta__)
  end

  test "is remembered in the rule cache", %{flow: flow} do
    record = EctoRules.record_shapes(Post, flow)

    assert PLT.get(flow.rule_cache, {EctoRules, :record, Post, 0}) == {:ok, record}
  end
end
