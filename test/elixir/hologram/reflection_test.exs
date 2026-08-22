defmodule Hologram.ReflectionTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Reflection

  alias Hologram.Test.Fixtures.Entity
  alias Hologram.Test.Fixtures.Reflection.Module1
  alias Hologram.Test.Fixtures.Reflection.Module2
  alias Hologram.Test.Fixtures.Reflection.Module3
  alias Hologram.Test.Fixtures.Reflection.Module4
  alias Hologram.Test.Fixtures.Reflection.Module7
  alias Hologram.Test.Fixtures.Reflection.Module8
  alias Hologram.Test.Fixtures.Reflection.Module9
  alias Hologram.Test.Fixtures.Role

  # Reproduces the way some Erlang libraries (e.g. luerl) name their modules with an
  # "Elixir." prefix for interop. Such modules are compiled by the Erlang compiler, so
  # they lack the __info__/1 function that the Elixir compiler injects, and must not be
  # treated as Elixir modules.
  defp build_elixir_named_erlang_module do
    module = Hologram.Test.Fixtures.Reflection.ErlangModuleWithElixirName

    sources = [
      "-module('#{module}').",
      "-export([my_fun/0]).",
      "my_fun() -> my_value."
    ]

    forms =
      Enum.map(sources, fn source ->
        charlist = String.to_charlist(source)
        :merl.quote(charlist)
      end)

    {:ok, ^module, binary} = :compile.forms(forms, [:debug_info])
    {:module, ^module} = :code.load_binary(module, ~c"nofile", binary)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    module
  end

  defp load_app_depending_on_hologram(app) do
    spec =
      {:application, app,
       applications: [:hologram],
       description: ~c"fixture",
       modules: [],
       registered: [],
       vsn: ~c"0.0.0"}

    :ok = :application.load(spec)

    on_exit(fn -> :application.unload(app) end)
  end

  defp load_app_with_modules(app, modules) do
    spec =
      {:application, app,
       applications: [],
       description: ~c"fixture",
       modules: modules,
       registered: [],
       vsn: ~c"0.0.0"}

    :ok = :application.load(spec)

    on_exit(fn -> :application.unload(app) end)
  end

  defp put_env_with_cleanup(app, key, value) do
    Application.put_env(app, key, value)

    on_exit(fn -> Application.delete_env(app, key) end)
  end

  describe "alias?/1" do
    test "atom which is an alias" do
      assert alias?(Calendar.ISO)
    end

    test "atom which is not an alias" do
      refute alias?(:abc)
    end

    test "non-atom" do
      refute alias?(123)
    end
  end

  describe "beam_defs/1" do
    test "beam file path" do
      beam_path = :code.which(Module1)

      assert [
               {{:fun_2, 2}, :def, [{:line, 7} | _column_1],
                [
                  {[{:line, 7} | _column_2],
                   [
                     {:a, [{:version, 0}, {:line, 7} | _column_3], nil},
                     {:b, [{:version, 1}, {:line, 7} | _column_4], nil}
                   ], [],
                   {{:., [{:line, 8} | _column_5], [:erlang, :+]}, [{:line, 8} | _column_6],
                    [
                      {:a, [{:version, 0}, {:line, 8} | _column_7], nil},
                      {:b, [{:version, 1}, {:line, 8} | _column_8], nil}
                    ]}}
                ]},
               {{:fun_1, 0}, :def, [{:line, 3} | _column_9],
                [{[{:line, 3} | _column_10], [], [], :value_1}]}
             ] = beam_defs(beam_path)
    end

    # TODO: Remove when Hologram.Reflection.beam_source/1 goes (see the removal
    # note there), together with the beam_source/1 and umbrella?/0 describes.
    test "beam binary" do
      {Module1, bytecode, beam_path} = :code.get_object_code(Module1)

      assert beam_defs(bytecode) == beam_defs(beam_path)
    end
  end

  # TODO: Remove this describe when Hologram.Reflection.beam_source/1 goes (see
  # the removal note there).
  describe "beam_source/1" do
    test "module whose beam file exists" do
      assert beam_source(Hologram.Reflection) == :code.which(Hologram.Reflection)
    end

    # Reproduces the state Phoenix's code reloader leaves behind when it purges a
    # stale consolidated protocol beam: the module stays loaded from the removed
    # file, while its object code is still findable in the code path.
    test "loaded module whose consolidated beam was removed, with object code in the code path" do
      module = Hologram.Test.Fixtures.Reflection.OrphanedBeamModule
      code = "defmodule #{inspect(module)} do end"
      [{^module, bytecode}] = Code.compile_string(code)

      ebin_dir = Path.join([tmp_dir(), "tests", "reflection", "beam_source_1", "ebin"])
      ebin_dir_charlist = String.to_charlist(ebin_dir)
      beam_file_path = Path.join(ebin_dir, "#{module}.beam")

      File.mkdir_p!(ebin_dir)
      File.write!(beam_file_path, bytecode)
      true = :code.add_path(ebin_dir_charlist)

      {:module, ^module} =
        :code.load_binary(module, ~c"/removed/consolidated/#{module}.beam", bytecode)

      on_exit(fn ->
        :code.del_path(ebin_dir_charlist)
        :code.purge(module)
        :code.delete(module)
        File.rm_rf!(ebin_dir)
      end)

      assert beam_source(module) == bytecode
    end

    test "loaded module whose consolidated beam was removed, without object code in the code path" do
      module = Hologram.Test.Fixtures.Reflection.VanishedBeamModule
      code = "defmodule #{inspect(module)} do end"
      [{^module, bytecode}] = Code.compile_string(code)

      {:module, ^module} =
        :code.load_binary(module, ~c"/removed/consolidated/#{module}.beam", bytecode)

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
      end)

      assert beam_source(module) == nil
    end

    # Regular (non-consolidated) beam paths are returned without checking that the
    # file exists, so the hot compilation paths don't pay a stat per module.
    test "loaded module whose non-consolidated beam file was removed" do
      module = Hologram.Test.Fixtures.Reflection.MissingRegularBeamModule
      code = "defmodule #{inspect(module)} do end"
      [{^module, bytecode}] = Code.compile_string(code)

      beam_path = ~c"/removed/ebin/#{module}.beam"
      {:module, ^module} = :code.load_binary(module, beam_path, bytecode)

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
      end)

      assert beam_source(module) == beam_path
    end
  end

  test "build_dir/0" do
    assert build_dir() == "#{File.cwd!()}/_build/test/lib/hologram/priv"
  end

  test "call_graph_dump_file_name/0" do
    assert call_graph_dump_file_name() == "call_graph.bin"
  end

  test "compiler_lock_file_name/0" do
    assert String.length(compiler_lock_file_name()) > 0
  end

  describe "component?" do
    test "is a component module" do
      assert component?(Module3)
    end

    test "is not a module" do
      refute component?(123)
    end

    test "is not a component module" do
      refute component?(__MODULE__)
    end
  end

  describe "ecto_schema?/1" do
    test "module which is an Ecto schema" do
      assert ecto_schema?(Module8)
    end

    test "module which is not an Ecto schema" do
      refute ecto_schema?(Calendar.ISO)
    end

    test "non-module" do
      refute ecto_schema?(123)
    end
  end

  describe "exception?/1" do
    test "module which is an exception" do
      assert exception?(ArgumentError)
    end

    test "module which is not an exception" do
      refute exception?(Calendar.ISO)
    end

    test "non-module" do
      refute exception?(123)
    end
  end

  describe "elixir_module?/1" do
    test "existing Elixir module" do
      assert elixir_module?(Calendar.ISO)
    end

    test "atom that starts with an uppercase letter and is an alias of a non existing Elixir module" do
      refute elixir_module?(Aaa.Bbb)
    end

    test "atom that starts with an uppercase letter and is not an Elixir alias" do
      refute elixir_module?(:MyModule)
    end

    test "existing Erlang module" do
      refute elixir_module?(:maps)
    end

    test "Erlang module that uses Elixir-style naming" do
      refute elixir_module?(build_elixir_named_erlang_module())
    end

    test "atom that starts with a lowercase letter and is not an existing Erlang module" do
      refute elixir_module?(:my_module)
    end

    test "non-atom" do
      refute elixir_module?(123)
    end
  end

  describe "entity?" do
    test "is an entity type module" do
      assert entity?(Entity.Module1)
    end

    test "is not a module" do
      refute entity?(123)
    end

    test "is not an entity type module" do
      refute entity?(__MODULE__)
    end
  end

  describe "erlang_module?" do
    test "existing Elixir module" do
      refute erlang_module?(Calendar.ISO)
    end

    test "atom that starts with an uppercase letter and is an alias of a non existing Elixir module" do
      refute erlang_module?(Aaa.Bbb)
    end

    test "atom that starts with an uppercase letter and is not an Elixir alias" do
      refute erlang_module?(:MyModule)
    end

    test "existing Erlang module" do
      assert erlang_module?(:maps)
    end

    test "Erlang module that uses Elixir-style naming" do
      assert erlang_module?(build_elixir_named_erlang_module())
    end

    test "atom that starts with a lowercase letter and is not an existing Erlang module" do
      refute erlang_module?(:my_module)
    end

    test "non-atom" do
      refute erlang_module?(123)
    end
  end

  describe "has_function?/3" do
    test "returns true if the module has a function with the given name and arity" do
      assert has_function?(Module4, :test_fun, 2)
    end

    test "returns false if the module doesn't have a function with the given name and arity" do
      refute has_function?(Module4, :test_fun, 3)
    end
  end

  describe "has_struct?/1" do
    test "has a struct defined" do
      assert has_struct?(Module9)
    end

    test "doesn't have a struct defined" do
      refute has_struct?(__MODULE__)
    end
  end

  test "hologram_dep_dir/0" do
    assert hologram_dep_dir() == File.cwd!() <> "/deps/hologram"
  end

  test "ir_plt_dump_file_name/0" do
    assert ir_plt_dump_file_name() == "ir.plt"
  end

  test "list_all_otp_apps/0" do
    assert Enum.sort(list_all_otp_apps()) == Enum.sort(list_all_otp_apps())
  end

  test "list_components/0" do
    result = list_components()

    assert Hologram.Test.Fixtures.Compiler.CallGraph.Module3 in result
    assert Module3 in result

    refute Hologram.Compiler.Context in result
    refute Module2 in result
  end

  describe "list_ebin_modules/1" do
    test "OTP app has ebin dir" do
      result = list_ebin_modules(:websock_adapter)

      expected_modules = [
        WebSockAdapter,
        WebSockAdapter.UpgradeError,
        WebSockAdapter.UpgradeValidation
      ]

      assert Enum.sort(result) == expected_modules
    end

    test "OTP app is not on the code path" do
      assert list_ebin_modules(:nonexistent_otp_app) == []
    end
  end

  test "list_elixir_modules/0" do
    result = list_elixir_modules()

    assert Calendar.ISO in result
    assert Hologram.Template.Tokenizer in result
    assert Mix.Tasks.Holo.Check.TestFileNames in result
    assert Sobelow.CI in result
    assert Mix.Tasks.Sobelow in result

    refute :elixir_map in result
    refute :dialyzer in result

    refute Enumerable.Atom in result
    refute Kernel.SpecialForms in result
  end

  describe "list_elixir_modules/1" do
    test "returns all Elixir modules belonging to the given OTP apps" do
      result = list_elixir_modules([:elixir, :hologram])

      assert Calendar.ISO in result
      assert Hologram.Template.Tokenizer in result
      assert Mix.Tasks.Holo.Check.TestFileNames in result
      refute Sobelow.CI in result
      refute Mix.Tasks.Sobelow in result

      refute :elixir_map in result
      refute :dialyzer in result

      refute Enumerable.Atom in result
      refute Kernel.SpecialForms in result
    end

    # This test can't be async, because it manipulates global state
    # (compiles modules and modifies the file system)
    test "includes newly compiled module found in ebin but not in Application.spec" do
      module_name = random_module()

      module_source = """
      defmodule #{module_name} do
        def test_function do
          :test_value
        end
      end
      """

      hologram_ebin_path =
        :hologram
        |> :code.lib_dir()
        |> Path.join("ebin")

      beam_file_path = Path.join(hologram_ebin_path, "#{module_name}.beam")

      try do
        [{^module_name, beam_binary}] = Code.compile_string(module_source)

        # This simulates a newly compiled module that exists in ebin
        # but hasn't been added to Application.spec yet
        File.write!(beam_file_path, beam_binary)

        assert Code.ensure_loaded(module_name) == {:module, module_name}
        assert module_name.test_function() == :test_value

        current_spec_modules =
          :hologram
          |> Application.spec()
          |> Keyword.get(:modules, [])

        # Verify our module is NOT in Application.spec
        refute module_name in current_spec_modules

        ebin_modules = list_ebin_modules(:hologram)

        # Verify our module IS found by list_ebin_modules/1
        assert module_name in ebin_modules

        # Now test the actual list_elixir_modules/1 functionality...

        # Ensure we're actually in test environment
        assert Hologram.env() == :test

        result = list_elixir_modules([:hologram])

        assert module_name in result
      after
        # Clean up...

        if File.exists?(beam_file_path) do
          File.rm!(beam_file_path)
        end

        :code.purge(module_name)
        :code.delete(module_name)
      end
    end
  end

  describe "list_entities/0" do
    test "lists the entity types of the project" do
      result = list_entities()

      assert Entity.Module1 in result
      assert Entity.Module3 in result

      refute Hologram.Compiler.Context in result
      refute Module2 in result
    end

    test "includes the role grant store, since the project designates a user entity type" do
      assert Hologram.Auth.RoleGrant in list_entities()
    end
  end

  describe "list_entities/1" do
    test "includes the role grant store when an entity type is designated as the user entity" do
      app = :hologram_reflection_designated_user_fixture_app
      load_app_with_modules(app, [Entity.Module1, Entity.Module14, Hologram.Auth.RoleGrant])

      assert list_entities([app]) == [Entity.Module1, Entity.Module14, Hologram.Auth.RoleGrant]
    end

    test "excludes the role grant store when no entity type is designated as the user entity" do
      app = :hologram_reflection_undesignated_user_fixture_app
      load_app_with_modules(app, [Entity.Module1, Entity.Module3, Hologram.Auth.RoleGrant])

      assert list_entities([app]) == [Entity.Module1, Entity.Module3]
    end
  end

  test "list_loaded_otp_apps/0" do
    result = list_loaded_otp_apps()

    assert :crypto in result
    assert :elixir in result
    assert :file_system in result
    assert :hologram in result
  end

  test "list_pages/0" do
    result = list_pages()

    assert Hologram.Test.Fixtures.Compiler.CallGraph.Module11 in result
    assert Hologram.Test.Fixtures.Reflection.Module2 in result
    assert Hologram.Test.Fixtures.Reflection.Module6 in result
    assert Hologram.Test.Fixtures.Page.Module1 in result

    refute Hologram.Test.Fixtures.Compiler.Module6 in result
    refute Hologram.Test.Fixtures.Compiler.CallGraph.Module4 in result
    refute Hologram.Compiler.Context in result
  end

  test "list_protocol_implementations" do
    result = list_protocol_implementations(String.Chars)

    assert String.Chars.Atom in result
    assert String.Chars.Hologram.Test.Fixtures.Reflection.Module5 in result
  end

  test "list_roles/0" do
    result = list_roles()

    assert Role.Module1 in result
    assert Role.Module2 in result

    refute Entity.Module1 in result
    refute Hologram.Reflection in result
  end

  test "list_std_lib_elixir_modules/0" do
    result = list_std_lib_elixir_modules()

    assert Calendar.ISO in result
    assert DateTime in result
    assert Kernel in result

    refute :application in result
    refute :elixir in result
    refute :kernel in result

    refute BeamFile in result
    refute Hologram.Page in result

    refute Enumerable.Atom in result
    refute Kernel.SpecialForms in result
  end

  describe "module?/1" do
    test "existing Elixir module" do
      assert module?(Calendar.ISO)
    end

    test "atom that starts with an uppercase letter and is an alias of a non existing Elixir module" do
      refute module?(Aaa.Bbb)
    end

    test "atom that starts with an uppercase letter and is not an Elixir alias" do
      refute module?(:MyModule)
    end

    test "existing Erlang module" do
      assert module?(:maps)
    end

    test "atom that starts with a lowercase letter and is not an existing Erlang module" do
      refute module?(:my_module)
    end

    test "non-atom" do
      refute module?(123)
    end
  end

  test "module_digest_plt_dump_file_name/0" do
    assert module_digest_plt_dump_file_name() == "module_digest.plt"
  end

  test "module_name/1" do
    assert module_name(Aaa.Bbb) == "Aaa.Bbb"
  end

  describe "otp_app/0" do
    test "single-app project" do
      assert otp_app() == :hologram
    end

    # Mix.Project.in_project/4 injects its app atom as the :app config default when it
    # serves a cached project, but a real umbrella root project has no :app - the
    # [app: nil] post-config forces that value in every load path.
    test "umbrella project with a single app depending on Hologram" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      load_app_depending_on_hologram(:otp_app_fixture_a)

      result =
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
          otp_app()
        end)

      assert result == :otp_app_fixture_a
    end

    test "umbrella project with multiple apps depending on Hologram, one owning a Phoenix endpoint" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      load_app_depending_on_hologram(:otp_app_fixture_b)
      load_app_depending_on_hologram(:otp_app_fixture_c)
      put_env_with_cleanup(:otp_app_fixture_c, Module7, [])

      result =
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
          otp_app()
        end)

      assert result == :otp_app_fixture_c
    end

    test "umbrella project with multiple apps depending on Hologram, none owning a Phoenix endpoint" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      load_app_depending_on_hologram(:otp_app_fixture_d)
      load_app_depending_on_hologram(:otp_app_fixture_e)

      assert_raise RuntimeError, ~r/none of them has a configured Phoenix endpoint/, fn ->
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
          otp_app()
        end)
      end
    end

    test "umbrella project with multiple apps depending on Hologram, all owning Phoenix endpoints" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      load_app_depending_on_hologram(:otp_app_fixture_f)
      load_app_depending_on_hologram(:otp_app_fixture_g)
      put_env_with_cleanup(:otp_app_fixture_f, Module7, [])
      put_env_with_cleanup(:otp_app_fixture_g, Module7, [])

      assert_raise RuntimeError, ~r/one endpoint app per running BEAM instance/, fn ->
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
          otp_app()
        end)
      end
    end

    test "umbrella project with no apps depending on Hologram" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")

      assert_raise RuntimeError, ~r/no loaded application depends on :hologram/, fn ->
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
          otp_app()
        end)
      end
    end
  end

  describe "otp_app_dir/0" do
    test "single-app project" do
      assert otp_app_dir() == File.cwd!()
    end

    test "umbrella project root" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      load_app_depending_on_hologram(:app_a)

      result =
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
          otp_app_dir()
        end)

      assert result == Path.join(umbrella_dir, "apps/app_a")
    end

    test "umbrella project child app" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      app_a_dir = Path.join(umbrella_dir, "apps/app_a")

      result =
        Mix.Project.in_project(:app_a, app_a_dir, fn _module ->
          otp_app_dir()
        end)

      assert result == app_a_dir
    end
  end

  test "otp_app_priv_dir/0" do
    assert otp_app_priv_dir() == File.cwd!() <> "/_build/test/lib/hologram/priv"
  end

  test "otp_app_static_dir/0" do
    assert otp_app_static_dir() == File.cwd!() <> "/_build/test/lib/hologram/priv/static"
  end

  describe "page?" do
    test "is a page module" do
      assert page?(Module2)
    end

    test "is not a module" do
      refute page?(123)
    end

    test "is not a page module" do
      refute page?(__MODULE__)
    end
  end

  test "page_digest_plt_dump_file_name/0" do
    assert page_digest_plt_dump_file_name() == "page_digest.plt"
  end

  describe "phoenix_endpoint/0" do
    test "there is a config entry for the given Phoenix endpoint module" do
      put_env_with_cleanup(:hologram, Module7, [])

      assert phoenix_endpoint() == Module7
    end

    test "there is no config entry for the given Phoenix endpoint module" do
      assert phoenix_endpoint() == nil
    end

    test "ignores config entries whose keys are not Phoenix endpoint modules" do
      put_env_with_cleanup(:hologram, Module1, [])

      assert phoenix_endpoint() == nil
    end
  end

  describe "protocol?/1" do
    test "module which is a protocol" do
      assert protocol?(String.Chars)
    end

    test "module which is not a protocol" do
      refute protocol?(Calendar.ISO)
    end

    test "non-module" do
      refute protocol?(123)
    end
  end

  describe "protocol_implementation/1" do
    test "module that implements a protocol" do
      assert protocol_implementation(Enumerable.Function) == Enumerable
    end

    test "module that does not implement a protocol" do
      assert protocol_implementation(Calendar.ISO) == nil
    end
  end

  describe "protocol_implementation?/1" do
    test "module that implements a protocol" do
      assert protocol_implementation?(Enumerable.Function)
    end

    test "module that does not implement a protocol" do
      refute protocol_implementation?(Calendar.ISO)
    end
  end

  test "query_cache_plt_dump_file_name/0" do
    assert query_cache_plt_dump_file_name() == "query_cache.plt"
  end

  describe "relative_source_path/1" do
    test "project module" do
      assert relative_source_path(Hologram.Reflection) == "lib/hologram/reflection.ex"
    end

    test "dep module" do
      assert relative_source_path(BeamFile) == "lib/beam_file.ex"
    end

    test "Elixir standard library module" do
      assert relative_source_path(Enum) == "lib/enum.ex"
    end

    test "module with an unrecognized source root" do
      code = "defmodule Hologram.Test.Fixtures.Reflection.ForeignSourceModule do end"

      [{module, _bytecode}] =
        Code.compile_string(code, "/foreign/build/machine/lib/foreign_source.ex")

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
      end)

      assert relative_source_path(module) == "foreign_source.ex"
    end
  end

  describe "root_dir/0" do
    test "single-app project" do
      assert root_dir() == File.cwd!()
    end

    test "umbrella project child app" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")
      app_a_dir = Path.join(umbrella_dir, "apps/app_a")

      result =
        Mix.Project.in_project(:app_a, app_a_dir, fn _module ->
          root_dir()
        end)

      assert result == umbrella_dir
    end
  end

  describe "role?" do
    test "is a global role module" do
      assert role?(Role.Module1)
    end

    test "is not a module" do
      refute role?(123)
    end

    test "is not a global role module" do
      refute role?(Entity.Module1)
    end
  end

  test "source_path/1" do
    assert source_path(__MODULE__) == __ENV__.file
  end

  describe "templatable?" do
    test "is a component module" do
      assert templatable?(Module3)
    end

    test "is a page module" do
      assert templatable?(Module2)
    end

    test "is not a module" do
      refute templatable?(123)
    end

    test "is not a component or page module" do
      refute templatable?(__MODULE__)
    end
  end

  test "tmp_dir/0" do
    assert tmp_dir() == File.cwd!() <> "/tmp"
  end

  # TODO: Remove this describe when Hologram.Reflection.umbrella?/0 goes (see the
  # removal note there).
  describe "umbrella?/0" do
    test "single-app project" do
      refute umbrella?()
    end

    test "umbrella project root" do
      umbrella_dir = Path.join(@fixtures_dir, "umbrella")

      result =
        Mix.Project.in_project(:umbrella_fixture, umbrella_dir, [app: nil], fn _module ->
          umbrella?()
        end)

      assert result == true
    end
  end

  test "user_entity/0" do
    assert user_entity() == Entity.Module14
  end

  describe "user_entity?/1" do
    test "entity type designated as the user entity type" do
      assert user_entity?(Entity.Module14)
    end

    test "entity type not designated as the user entity type" do
      refute user_entity?(Entity.Module1)
    end

    test "module that is not an entity type" do
      refute user_entity?(Hologram.Reflection)
    end
  end
end
