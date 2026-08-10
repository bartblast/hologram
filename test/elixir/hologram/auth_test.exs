defmodule Hologram.AuthTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Auth

  alias Hologram.Auth.Context
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1

  describe "can?/3" do
    test "grants an action through a rule whose predicates hold" do
      assert can?(nil, :read, %Module1{public: true})
    end

    test "denies an action when no rule matches" do
      refute can?("user_id_1", :read, %Module1{public: false})
    end

    test "denies an action the entity type declares no rule for" do
      refute can?("user_id_1", :transfer, %Module1{public: true})
    end

    test "matches a rule referencing the acting user" do
      entity = %Module1{author_id: "user_id_2"}

      assert can?("user_id_2", :archive, entity)
      refute can?("user_id_3", :archive, entity)
    end

    test "takes the user entity" do
      user = Entity.new(Module14, email: "user_1@example.com")

      assert can?(user, :archive, %Module1{author_id: user.id})
    end

    test "skips rules referencing the acting user for an anonymous session" do
      refute can?(nil, :archive, %Module1{author_id: nil})
    end
  end

  describe "user_id/0" do
    test "returns the actor of the calling process" do
      assert Context.with_actor("user_id_1", fn -> user_id() end) == "user_id_1"
    end

    test "returns nil for an anonymous session" do
      assert user_id() == nil
    end
  end
end
