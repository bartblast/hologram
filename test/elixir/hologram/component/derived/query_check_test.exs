defmodule Hologram.Component.Derived.QueryCheckTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.Component.Derived.QueryCheck

  alias Hologram.Auth.RoleGrant
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1, as: Entity1
  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15
  alias Hologram.Test.Fixtures.Entity.Module16, as: Entity16
  alias Hologram.Test.Fixtures.Entity.Module25, as: Entity25
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  @server_only_tail " - the client never holds those values, so it could not evaluate the reference " <>
                      "locally. Drop the reference, or read the rows through the trusted backend API."

  defmodule QuantifiedDeadSource do
    use Hologram.Entity

    relationship :items, [Hologram.Test.Fixtures.Entity.Module1]

    allow :read
  end

  defmodule DeadSibling do
    use Hologram.Entity

    attribute :label, :string, optional: true
  end

  defmodule TwoDeadTargets do
    use Hologram.Entity

    relationship :first, Hologram.Test.Fixtures.Entity.Module1
    relationship :second, Hologram.Component.Derived.QueryCheckTest.DeadSibling

    allow :read
  end

  defmodule HeldSecret do
    use Hologram.Entity

    attribute :label, :string, optional: true
    attribute :token, :string, server_only: true

    relationship :holder, Hologram.Component.Derived.QueryCheckTest.SecretHolder

    allow :read
  end

  defmodule SecretHolder do
    use Hologram.Entity

    relationship :held, [Hologram.Component.Derived.QueryCheckTest.HeldSecret], inverse: holder

    derived :labelled, [Hologram.Component.Derived.QueryCheckTest.HeldSecret], fn held ->
      filter(held, label != nil)
    end

    allow :read
  end

  defmodule SecretOwner do
    use Hologram.Entity

    attribute :token, :string, server_only: true

    relationship :secret, Hologram.Test.Fixtures.Entity.Module15
    relationship :secrets, [Hologram.Test.Fixtures.Entity.Module15]

    allow :read
  end

  describe "refusal/1" do
    test "passes a query every part of which some rule reads" do
      term =
        Entity15
        |> filter(label == "shown")
        |> Stage.normalize()

      assert refusal(term) == nil
    end

    test "refuses a root type declaring no allow lines" do
      assert refusal(Stage.normalize(Entity1)) ==
               "reads Hologram.Test.Fixtures.Entity.Module1, which declares no allow lines - " <>
                 "default deny returns no rows to any session. Add allow lines, or drop the query."
    end

    test "takes the grant type, whose rules are the framework's own" do
      assert refusal(Stage.normalize(RoleGrant)) == nil
    end

    test "refuses an include target declaring no allow lines" do
      term =
        Entity3
        |> include(c)
        |> Stage.normalize()

      assert refusal(term) ==
               "includes Hologram.Test.Fixtures.Entity.Module1, which declares no allow lines - " <>
                 "default deny leaves the embed empty in every row. Add allow lines, or drop the include."
    end

    test "refuses a path through a type declaring no allow lines" do
      term =
        Entity3
        |> filter(c.id != nil)
        |> Stage.normalize()

      assert refusal(term) ==
               "filters through Hologram.Test.Fixtures.Entity.Module1, which declares no allow " <>
                 "lines - default deny reads every such row as missing. Add allow lines, or drop the path."
    end

    test "refuses a quantifier reading a type declaring no allow lines" do
      term =
        QuantifiedDeadSource
        |> filter(any(items))
        |> Stage.normalize()

      assert refusal(term) ==
               "filters through Hologram.Test.Fixtures.Entity.Module1, which declares no allow " <>
                 "lines - default deny reads every such row as missing. Add allow lines, or drop the path."
    end

    test "refuses a filter on a server-only attribute" do
      term =
        Entity15
        |> filter(token == "x")
        |> Stage.normalize()

      assert refusal(term) ==
               "filters or sorts on server_only attributes (Hologram.Test.Fixtures.Entity.Module15 :token)" <>
                 @server_only_tail
    end

    test "refuses a server-only attribute inside a disjunction" do
      term =
        Entity15
        |> filter(token == "x" or label == "shown")
        |> Stage.normalize()

      assert refusal(term) =~ "(Hologram.Test.Fixtures.Entity.Module15 :token)"
    end

    test "refuses a comparison with a server-only attribute" do
      term =
        Entity15
        |> filter(label == token)
        |> Stage.normalize()

      assert refusal(term) =~ "(Hologram.Test.Fixtures.Entity.Module15 :token)"
    end

    test "refuses a server-only attribute a path leads to" do
      term =
        Entity25
        |> filter(g.token == "x")
        |> Stage.normalize()

      assert refusal(term) =~ "(Hologram.Test.Fixtures.Entity.Module15 :token)"
    end

    test "follows a quantifier over an inverse" do
      term =
        SecretHolder
        |> filter(any(secret <- held, secret.token == "x"))
        |> Stage.normalize()

      assert refusal(term) =~ "(Hologram.Component.Derived.QueryCheckTest.HeldSecret :token)"
    end

    test "follows a quantifier over a derived field holding rows" do
      term =
        SecretHolder
        |> filter(any(secret <- labelled, secret.token == "x"))
        |> Stage.normalize()

      assert refusal(term) =~ "(Hologram.Component.Derived.QueryCheckTest.HeldSecret :token)"
    end

    test "refuses a server-only attribute a quantifier's condition reads" do
      term =
        Entity16
        |> filter(any(secret <- secrets, secret.token == "x"))
        |> Stage.normalize()

      assert refusal(term) =~ "(Hologram.Test.Fixtures.Entity.Module15 :token)"
    end

    test "refuses a sort on a server-only attribute, every name of a type listed once" do
      term =
        Entity15
        |> filter(token == "x")
        |> sort([secret_note, token])
        |> Stage.normalize()

      assert refusal(term) ==
               "filters or sorts on server_only attributes (Hologram.Test.Fixtures.Entity.Module15 " <>
                 ":secret_note, :token)" <> @server_only_tail
    end

    test "lists every dead include target, sorted, in the plural" do
      term =
        TwoDeadTargets
        |> include([second, first])
        |> Stage.normalize()

      assert refusal(term) ==
               "includes Hologram.Component.Derived.QueryCheckTest.DeadSibling, " <>
                 "Hologram.Test.Fixtures.Entity.Module1, which declare no allow lines - default " <>
                 "deny leaves the embed empty in every row. Add allow lines, or drop the include."
    end

    test "refuses a server-only attribute an outer name reads" do
      term =
        SecretOwner
        |> filter(any(secret <- secrets, secret.label == token))
        |> Stage.normalize()

      assert refusal(term) ==
               "filters or sorts on server_only attributes " <>
                 "(Hologram.Component.Derived.QueryCheckTest.SecretOwner :token)" <>
                 @server_only_tail
    end

    # An include holds no filter of its own, so the term is put together by hand to show where the
    # references of a term it includes go.
    test "lists the queried type first, then the types its paths lead to, then its includes" do
      term =
        SecretOwner
        |> filter(secret.token == "x" and token == "y")
        |> include(secrets)
        |> Stage.normalize()
        |> put_in([Access.key!(:include), :secrets, Access.key!(:filter)], [{:token, :==, "z"}])

      assert refusal(term) ==
               "filters or sorts on server_only attributes " <>
                 "(Hologram.Component.Derived.QueryCheckTest.SecretOwner :token, " <>
                 "Hologram.Test.Fixtures.Entity.Module15 :token, " <>
                 "Hologram.Test.Fixtures.Entity.Module15 :token)" <> @server_only_tail
    end

    test "refuses a claim of trust" do
      term =
        Entity15
        |> filter(label == "shown")
        |> trust()
        |> Stage.normalize()

      assert refusal(term) ==
               "claims the server's authority with trust() - a query in browser code is read for the " <>
                 "session user on both tiers, so it cannot claim another. Drop trust(), or read " <>
                 "through the backend API in a command."
    end
  end
end
