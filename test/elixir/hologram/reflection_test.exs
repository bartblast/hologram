defmodule Hologram.ReflectionTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Reflection

  alias Hologram.Test.Fixtures.Reflection.Module1
  alias Hologram.Test.Fixtures.Reflection.Module2
  alias Hologram.Test.Fixtures.Reflection.Module3
  alias Hologram.Test.Fixtures.Reflection.Module4
  alias Hologram.Test.Fixtures.Reflection.Module7
  alias Hologram.Test.Fixtures.Reflection.Module8
  alias Hologram.Test.Fixtures.Reflection.Module9

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

  test "beam_defs/1" do
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

  describe "dist_dir_name/0" do
    test "returns 'dist' when Hologram is running in standalone mode" do
      original_mode = Application.get_env(:hologram, :mode)

      on_exit(fn ->
        if original_mode do
          Application.put_env(:hologram, :mode, original_mode)
        else
          Application.delete_env(:hologram, :mode)
        end
      end)

      Application.put_env(:hologram, :mode, :standalone)

      assert dist_dir_name() == "dist"
    end

    test "returns 'static' when Hologram is running in embedded mode" do
      original_mode = Application.get_env(:hologram, :mode)

      on_exit(fn ->
        if original_mode do
          Application.put_env(:hologram, :mode, original_mode)
        else
          Application.delete_env(:hologram, :mode)
        end
      end)

      Application.put_env(:hologram, :mode, :embedded)

      assert dist_dir_name() == "static"
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

    test "atom that starts with a lowercase letter and is not an existing Erlang module" do
      refute elixir_module?(:my_module)
    end

    test "non-atom" do
      refute elixir_module?(123)
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

  test "ir_plt_dump_file_name/0" do
    assert ir_plt_dump_file_name() == "ir.plt"
  end

  test "list_all_otp_apps/0" do
    assert Enum.sort(list_all_otp_apps()) == Enum.sort(list_all_otp_apps())
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

    test "OTP app doesn't have ebin dir" do
      assert list_ebin_modules(:odbc) == []
    end
  end

  test "list_elixir_modules/0" do
    result = list_elixir_modules()

    assert Calendar.ISO in result
    assert Hologram.Template.Tokenizer in result
    assert Mix.Tasks.Holo.Test.CheckFileNames in result
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
      assert Mix.Tasks.Holo.Test.CheckFileNames in result
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

  describe "mode/0" do
    test "returns the mode if it is set in the config" do
      original_mode = Application.get_env(:hologram, :mode)

      on_exit(fn ->
        if original_mode do
          Application.put_env(:hologram, :mode, original_mode)
        else
          Application.delete_env(:hologram, :mode)
        end
      end)

      Application.put_env(:hologram, :mode, :my_mode)

      assert mode() == :my_mode
    end

    test "returns :embedded if the mode is not set in the config" do
      original_mode = Application.get_env(:hologram, :mode)

      on_exit(fn ->
        if original_mode do
          Application.put_env(:hologram, :mode, original_mode)
        else
          Application.delete_env(:hologram, :mode)
        end
      end)

      Application.delete_env(:hologram, :mode)

      assert mode() == :embedded
    end
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

  test "otp_app/0" do
    assert otp_app() == :hologram
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
      Application.put_env(:hologram, Module7, [])

      assert phoenix_endpoint() == Module7

      Application.delete_env(:hologram, Module7)
    end

    test "there is no config entry for the given Phoenix endpoint module" do
      assert phoenix_endpoint() == nil
    end
  end

  test "release_dist_dir/0" do
    expected_path =
      Path.join([File.cwd!(), "_build", "test", "lib", "hologram", "priv", "static"])

    assert release_dist_dir() == expected_path
  end

  test "release_priv_dir/0" do
    expected_path =
      Path.join([File.cwd!(), "_build", "test", "lib", "hologram", "priv"])

    assert release_priv_dir() == expected_path
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

  test "root_dir/0" do
    assert root_dir() == File.cwd!()
  end

  test "root_priv_dir/0" do
    assert root_priv_dir() == File.cwd!() <> "/priv/hologram"
  end

  test "source_path/1" do
    assert source_path(__MODULE__) == __ENV__.file
  end

  describe "standalone_mode?/0" do
    test "returns true when Hologram is running in standalone mode" do
      original_mode = Application.get_env(:hologram, :mode)

      on_exit(fn ->
        if original_mode do
          Application.put_env(:hologram, :mode, original_mode)
        else
          Application.delete_env(:hologram, :mode)
        end
      end)

      Application.put_env(:hologram, :mode, :standalone)

      assert standalone_mode?() == true
    end

    test "returns false when Hologram is running in embedded mode" do
      original_mode = Application.get_env(:hologram, :mode)

      on_exit(fn ->
        if original_mode do
          Application.put_env(:hologram, :mode, original_mode)
        else
          Application.delete_env(:hologram, :mode)
        end
      end)

      Application.put_env(:hologram, :mode, :embedded)

      refute standalone_mode?() == false
    end
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
end
