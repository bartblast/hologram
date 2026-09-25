defmodule Hologram.ReflectionTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Reflection

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Test.Fixtures.Reflection.Module1
  alias Hologram.Test.Fixtures.Reflection.Module2
  alias Hologram.Test.Fixtures.Reflection.Module3
  alias Hologram.Test.Fixtures.Reflection.Module4
  alias Hologram.Test.Fixtures.Reflection.Module7
  alias Hologram.Test.Fixtures.Reflection.Module8
  alias Hologram.Test.Fixtures.Reflection.Module9

  # Reproduces the way some Erlang libraries (e.g. luerl) name their modules with an
  # "Elixir." prefix for interop. Such modules are compiled by the Erlang compiler, so
  # they lack the __info__/1 function that the Elixir compiler injects, and must not be
  # treated as Elixir modules.
  defp build_elixir_named_erlang_module do
    {module, binary} = compile_elixir_named_erlang_module()
    {:module, ^module} = :code.load_binary(module, ~c"nofile", binary)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    module
  end

  defp compile_elixir_named_erlang_module do
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

    {module, binary}
  end

  defp compile_to_digest(code) do
    beam_info(compile_with_debug_info(code)).digest
  end

  # Code compiled inside the test run carries no debug info unless asked for, and a beam
  # without a Dbgi chunk has the same digest for any source and no literals to read.
  defp compile_with_debug_info(code) do
    debug_info? = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      [{module, bytecode}] = Code.compile_string(code)
      :code.purge(module)
      :code.delete(module)
      bytecode
    after
      Code.put_compiler_option(:debug_info, debug_info?)
    end
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

  # Puts the key back as it was before the test, set or not.
  defp put_env_with_cleanup(app, key, value) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      case previous do
        {:ok, previous_value} -> Application.put_env(app, key, previous_value)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  # Leaves the beam on a code path added for the test, so that the module exists on disk only.
  defp write_unloaded_beam(module, tmp_subdir, bytecode) do
    ebin_dir = Path.join([tmp_dir(), "tests", "reflection", tmp_subdir, "ebin"])
    ebin_dir_charlist = String.to_charlist(ebin_dir)
    beam_path = Path.join(ebin_dir, "#{module}.beam")
    File.mkdir_p!(ebin_dir)
    File.write!(beam_path, bytecode)
    true = :code.add_path(ebin_dir_charlist)

    on_exit(fn ->
      :code.del_path(ebin_dir_charlist)
      :code.purge(module)
      :code.delete(module)
    end)
  end

  # Compiles the module, unloads it, and leaves its beam on disk only.
  defp write_unloaded_module(module, tmp_subdir, body) do
    [{^module, bytecode}] = Code.compile_string("defmodule #{inspect(module)} do #{body} end")
    :code.purge(module)
    :code.delete(module)
    write_unloaded_beam(module, tmp_subdir, bytecode)
  end

  # Compiles the module, unloads it, and leaves its beam in the given application's ebin directory
  # only, so that a listing of that application's beams finds it while the VM does not hold it.
  defp write_unloaded_module_to_ebin(module, app, body) do
    [{^module, bytecode}] = Code.compile_string("defmodule #{inspect(module)} do #{body} end")
    :code.purge(module)
    :code.delete(module)

    beam_path = Path.join([:code.lib_dir(app), "ebin", "#{module}.beam"])
    File.write!(beam_path, bytecode)

    on_exit(fn ->
      File.rm!(beam_path)
      :code.purge(module)
      :code.delete(module)
    end)
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

  describe "beam_info/1" do
    test "beam file path of a plain module" do
      beam_path = :code.which(Module1)
      %File.Stat{mtime: mtime, size: size} = File.stat!(beam_path, time: :posix)

      assert %{
               digest: digest,
               mtime: ^mtime,
               size: ^size,
               page?: false,
               component?: false,
               protocol?: false,
               protocol_implementation?: false,
               struct?: false,
               exception?: false,
               ecto_schema?: false,
               js_imports?: false,
               broadcast_caller?: false,
               source_path: source_path,
               layout_module: nil,
               route: nil,
               protocol_functions: nil,
               implementation_for: nil,
               implemented_protocol: nil
             } = beam_info(beam_path)

      assert is_integer(digest)
      assert String.ends_with?(source_path, "test/elixir/support/fixtures/reflection/module_1.ex")
    end

    test "module with JS imports" do
      module = Hologram.Test.Fixtures.Compiler.Module12

      assert %{js_imports?: true} = beam_info(:code.which(module))
    end

    test "module calling a broadcast function" do
      module = Hologram.Test.Fixtures.Controller.Module6

      assert %{broadcast_caller?: true} = beam_info(:code.which(module))
    end

    test "source path is the one the loaded module reports" do
      assert beam_info(:code.which(Module1)).source_path == source_path(Module1)
      assert beam_info(:code.which(Enum)).source_path == source_path(Enum)
    end

    test "page module" do
      assert %{
               page?: true,
               component?: false,
               layout_module: Module4,
               route: "/hologram-test-fixtures-commons-reflection-module2"
             } = beam_info(:code.which(Module2))
    end

    test "page module without a layout" do
      bytecode =
        compile_with_debug_info(
          "defmodule PageWithoutLayout do def __is_hologram_page__, do: true end"
        )

      assert %{page?: true, layout_module: nil, route: nil} = beam_info(bytecode)
    end

    test "page module whose layout function computes its value" do
      bytecode =
        compile_with_debug_info(
          "defmodule PageWithComputedLayout do def __is_hologram_page__, do: true; def __layout_module__, do: Application.get_env(:hologram, :layout) end"
        )

      assert %{page?: true, layout_module: nil} = beam_info(bytecode)
    end

    test "page module whose route is not a string" do
      bytecode =
        compile_with_debug_info(
          "defmodule PageWithAtomRoute do def __is_hologram_page__, do: true; def __route__, do: :admin end"
        )

      assert %{page?: true, route: :admin} = beam_info(bytecode)
    end

    test "page module whose route is interpolated from a module attribute" do
      bytecode =
        compile_with_debug_info(
          ~S'defmodule PageWithInterpolatedRoute do def __is_hologram_page__, do: true; @prefix "admin"; def __route__, do: "/#{@prefix}/users" end'
        )

      assert %{page?: true, route: "/admin/users"} = beam_info(bytecode)
    end

    test "page module whose route comes from a module attribute" do
      bytecode =
        compile_with_debug_info(
          ~S'defmodule PageWithAttributeRoute do def __is_hologram_page__, do: true; @path "/from-attribute"; def __route__, do: @path end'
        )

      assert %{page?: true, route: "/from-attribute"} = beam_info(bytecode)
    end

    test "page module whose route function computes its value" do
      bytecode =
        compile_with_debug_info(
          "defmodule PageWithComputedRoute do def __is_hologram_page__, do: true; def __route__, do: Application.get_env(:hologram, :route) end"
        )

      assert %{page?: true, route: nil} = beam_info(bytecode)
    end

    test "component module" do
      assert %{page?: false, component?: true} = beam_info(:code.which(Module3))
    end

    test "protocol module" do
      assert %{
               protocol?: true,
               protocol_implementation?: false,
               protocol_functions: [to_string: 1]
             } =
               beam_info(:code.which(String.Chars))

      assert protocol?(String.Chars)
    end

    test "protocol implementation module" do
      assert %{
               protocol?: false,
               protocol_implementation?: true,
               implementation_for: Function,
               implemented_protocol: Enumerable
             } = beam_info(:code.which(Enumerable.Function))

      assert protocol_implementation?(Enumerable.Function)
    end

    test "struct module" do
      assert %{struct?: true} = beam_info(:code.which(Module9))
      assert has_struct?(Module9)
    end

    test "exception module" do
      assert %{exception?: true, struct?: true} = beam_info(:code.which(ArgumentError))
      assert exception?(ArgumentError)
    end

    test "Ecto schema module" do
      assert %{ecto_schema?: true, struct?: true} = beam_info(:code.which(Module8))
      assert ecto_schema?(Module8)
    end

    # TODO: Remove when Hologram.Reflection.beam_source/1 goes (see the removal
    # note there), together with the beam_source/1 and umbrella?/0 describes.
    test "beam binary gives the same digest and no mtime or size" do
      {Module1, bytecode, beam_path} = :code.get_object_code(Module1)

      assert %{digest: digest, mtime: nil, size: nil} = beam_info(bytecode)
      assert digest == beam_info(beam_path).digest
    end

    test "Erlang module that uses Elixir-style naming" do
      {_module, binary} = compile_elixir_named_erlang_module()

      assert beam_info(binary) == nil
    end

    test "the same source compiled twice gives the same digest" do
      code = "defmodule Hologram.Test.Fixtures.Reflection.BeamInfoModule1 do def fun, do: 1 end"

      assert compile_to_digest(code) == compile_to_digest(code)
    end

    test "a changed definition changes the digest" do
      code_1 = "defmodule Hologram.Test.Fixtures.Reflection.BeamInfoModule2 do def fun, do: 1 end"
      code_2 = "defmodule Hologram.Test.Fixtures.Reflection.BeamInfoModule2 do def fun, do: 2 end"

      assert compile_to_digest(code_1) != compile_to_digest(code_2)
    end
  end

  # TODO: Remove this describe when Hologram.Reflection.beam_source/1 goes (see
  # the removal note there).
  test "beam_info_keys/0" do
    keys =
      Module1
      |> :code.which()
      |> beam_info()
      |> Map.keys()

    assert Enum.sort(beam_info_keys()) == Enum.sort(keys)
  end

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

  test "broadcast_mfas/0" do
    result = broadcast_mfas()

    assert result == Enum.sort(result)
    assert {Hologram.Component, :put_broadcast, 3} in result
    assert {Hologram.Realtime, :broadcast_action, 2} in result
  end

  test "build_dir/0" do
    assert build_dir() == "#{File.cwd!()}/_build/test/lib/hologram/priv"
  end

  test "call_graph_dump_file_name/0" do
    assert call_graph_dump_file_name() == "call_graph.bin"
  end

  test "compile_inputs_dump_file_name/0" do
    assert compile_inputs_dump_file_name() == "compile_inputs.bin"
  end

  test "compile_state_dump_file_name/0" do
    assert compile_state_dump_file_name() == "compile_state.bin"
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

    test "does not load the module" do
      module = Hologram.Test.Fixtures.Reflection.NotLoadedElixirModule
      write_unloaded_module(module, "elixir_module_1", "")

      assert :code.is_loaded(module) == false
      assert elixir_module?(module)
      assert :code.is_loaded(module) == false
    end
  end

  describe "elixir_module?/2" do
    setup do
      [ir_plt: PLT.start()]
    end

    test "module the IR PLT holds, without consulting the code path", %{ir_plt: ir_plt} do
      PLT.put(ir_plt, Aaa.Bbb, :ir)

      assert elixir_module?(Aaa.Bbb, ir_plt)
    end

    test "existing Elixir module the IR PLT does not hold", %{ir_plt: ir_plt} do
      assert elixir_module?(Calendar.ISO, ir_plt)
    end

    test "non existing Elixir module the IR PLT does not hold", %{ir_plt: ir_plt} do
      refute elixir_module?(Aaa.Bbb, ir_plt)
    end

    test "existing Erlang module", %{ir_plt: ir_plt} do
      refute elixir_module?(:maps, ir_plt)
    end

    test "Erlang module that uses Elixir-style naming", %{ir_plt: ir_plt} do
      refute elixir_module?(build_elixir_named_erlang_module(), ir_plt)
    end

    test "non-atom", %{ir_plt: ir_plt} do
      refute elixir_module?(123, ir_plt)
    end

    test "nil IR PLT decides the elixir_module?/1 way" do
      assert elixir_module?(Calendar.ISO, nil)
      refute elixir_module?(Aaa.Bbb, nil)
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

    test "does not load the module" do
      {module, binary} = compile_elixir_named_erlang_module()
      write_unloaded_beam(module, "erlang_module_1", binary)

      assert :code.is_loaded(module) == false
      assert erlang_module?(module)
      assert :code.is_loaded(module) == false
    end
  end

  describe "erlang_module?/2" do
    setup do
      [ir_plt: PLT.start()]
    end

    test "module the IR PLT holds is not one, without consulting the code path", %{ir_plt: ir_plt} do
      module = build_elixir_named_erlang_module()
      PLT.put(ir_plt, module, :ir)

      refute erlang_module?(module, ir_plt)
    end

    test "existing Erlang module", %{ir_plt: ir_plt} do
      assert erlang_module?(:maps, ir_plt)
    end

    test "Erlang module that uses Elixir-style naming the IR PLT does not hold", %{ir_plt: ir_plt} do
      assert erlang_module?(build_elixir_named_erlang_module(), ir_plt)
    end

    test "existing Elixir module", %{ir_plt: ir_plt} do
      refute erlang_module?(Calendar.ISO, ir_plt)
    end

    test "atom that starts with a lowercase letter and is not an existing Erlang module", %{
      ir_plt: ir_plt
    } do
      refute erlang_module?(:my_module, ir_plt)
    end

    test "non-atom", %{ir_plt: ir_plt} do
      refute erlang_module?(123, ir_plt)
    end

    test "nil IR PLT decides the erlang_module?/1 way" do
      assert erlang_module?(:maps, nil)
      refute erlang_module?(Calendar.ISO, nil)
    end
  end

  describe "has_function?/3" do
    test "returns true if the module has a function with the given name and arity" do
      assert has_function?(Module4, :test_fun, 2)
    end

    test "returns false if the module doesn't have a function with the given name and arity" do
      refute has_function?(Module4, :test_fun, 3)
    end

    test "not loaded module that exports the function" do
      module = Hologram.Test.Fixtures.Reflection.NotLoadedModuleWithFun
      write_unloaded_module(module, "has_function_3", "def my_fun(_a), do: :ok")

      assert :code.is_loaded(module) == false
      assert has_function?(module, :my_fun, 1)
      assert :code.is_loaded(module) == false
    end

    test "not loaded module that does not export the function" do
      module = Hologram.Test.Fixtures.Reflection.NotLoadedModuleWithoutFun
      write_unloaded_module(module, "has_function_3", "def my_fun(_a), do: :ok")

      refute has_function?(module, :other_fun, 1)
      refute has_function?(module, :my_fun, 2)
    end

    test "not loaded module whose beam cannot be read" do
      module = Hologram.Test.Fixtures.Reflection.NotLoadedModuleWithUnreadableBeam
      write_unloaded_beam(module, "has_function_3_unreadable", "not a beam")

      assert is_list(:code.which(module))
      refute has_function?(module, :my_fun, 1)
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

  describe "js_imports?/1" do
    test "module that declares JS imports" do
      assert js_imports?(Hologram.Test.Fixtures.Compiler.Module12)
    end

    test "module that does not declare JS imports" do
      refute js_imports?(Hologram.Reflection)
    end

    test "non-existing module" do
      refute js_imports?(Aaa.Bbb)
    end
  end

  describe "js_imports?/2" do
    setup do
      [module_info_plt: PLT.start()]
    end

    test "module the PLT holds is answered from it, without consulting the code path", %{
      module_info_plt: module_info_plt
    } do
      PLT.put(module_info_plt, Aaa.Bbb, %{js_imports?: true})

      assert js_imports?(Aaa.Bbb, module_info_plt)
    end

    test "the PLT wins over the module", %{module_info_plt: module_info_plt} do
      PLT.put(module_info_plt, Hologram.Test.Fixtures.Compiler.Module12, %{js_imports?: false})

      refute js_imports?(Hologram.Test.Fixtures.Compiler.Module12, module_info_plt)
    end

    test "module the PLT does not hold is decided the js_imports?/1 way", %{
      module_info_plt: module_info_plt
    } do
      assert js_imports?(Hologram.Test.Fixtures.Compiler.Module12, module_info_plt)
      refute js_imports?(Hologram.Reflection, module_info_plt)
    end

    test "entry without the flag is decided the js_imports?/1 way", %{
      module_info_plt: module_info_plt
    } do
      PLT.put(module_info_plt, Hologram.Test.Fixtures.Compiler.Module12, %{digest: 1})

      assert js_imports?(Hologram.Test.Fixtures.Compiler.Module12, module_info_plt)
    end

    test "nil PLT decides the js_imports?/1 way" do
      assert js_imports?(Hologram.Test.Fixtures.Compiler.Module12, nil)
      refute js_imports?(Hologram.Reflection, nil)
    end
  end

  test "list_all_otp_apps/0" do
    assert Enum.sort(list_all_otp_apps()) == Enum.sort(list_all_otp_apps())
  end

  describe "list_candidate_modules/0" do
    test "includes the project's Elixir modules" do
      result = list_candidate_modules()

      assert Hologram.Reflection in result
      assert Module1 in result
      assert Calendar.ISO in result
    end

    test "excludes ignored modules" do
      refute Kernel.SpecialForms in list_candidate_modules()
    end
  end

  describe "list_candidate_modules/1" do
    test "includes the given apps' Elixir-named modules and no Erlang-named ones" do
      result = list_candidate_modules([:elixir, :stdlib])

      assert Kernel in result
      assert Calendar.ISO in result
      refute :maps in result
      refute :elixir_map in result
      refute Hologram.Reflection in result
    end

    test "excludes ignored modules" do
      refute Kernel.SpecialForms in list_candidate_modules([:elixir])
    end
  end

  describe "list_components/0" do
    test "lists the component modules of the loaded applications, sorted by name" do
      result = list_components()

      assert Hologram.Test.Fixtures.Compiler.CallGraph.Module3 in result
      assert Module3 in result

      refute Hologram.Compiler.Context in result
      refute Module2 in result

      assert result == Enum.sort(result)
    end

    test "lists a component whose beam is in an application's ebin directory without loading it" do
      module = Hologram.Test.Fixtures.Reflection.ComponentInEbinOnly

      write_unloaded_module_to_ebin(module, :hologram, """
      use Hologram.Component
      @impl Component
      def template, do: ~HOLO"ComponentInEbinOnly template"
      """)

      assert module in list_components()
      assert :code.is_loaded(module) == false
    end

    test "asks the code server about no module" do
      assert count_calls({:code, :which, 1}, &list_components/0) == 0
    end
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
      assert list_ebin_modules(:nonexistent_otp_app) == []
    end
  end

  describe "list_editable_apps/0" do
    test "lists the project's application, and only it, without umbrella apps or path dependencies" do
      assert list_editable_apps() == [:hologram]
    end

    test "adds the applications the Phoenix endpoint reloads" do
      put_env_with_cleanup(:hologram, Module7, reloadable_apps: [:file_system])

      assert list_editable_apps() == [:hologram, :file_system]
    end

    test "leaves out a reloadable application that is not loaded" do
      put_env_with_cleanup(:hologram, Module7, reloadable_apps: [:not_loaded_app])

      assert list_editable_apps() == [:hologram]
    end
  end

  describe "list_editable_beams/0" do
    test "lists the beams of the editable applications with their paths" do
      assert {Hologram.Reflection, :code.which(Hologram.Reflection)} in list_editable_beams()
    end

    test "lists a consolidated protocol from its consolidated beam" do
      beam_path = :code.which(Enumerable)

      # The test build consolidates protocols.
      assert :string.find(beam_path, ~c"/consolidated/") != :nomatch

      assert {Enumerable, beam_path} in list_editable_beams()
    end

    test "leaves out the modules of the other applications" do
      refute List.keymember?(list_editable_beams(), Enum, 0)
    end

    test "leaves out the beams of modules that are not Elixir-named" do
      # The listing reads only the file names, so the files need no content.
      dir = Path.join([tmp_dir(), "tests", "reflection", "list_editable_beams_0", "consolidated"])
      File.rm_rf!(dir)
      File.mkdir_p!(dir)

      elixir_beam_path =
        Path.join(dir, "Elixir.Hologram.Test.Fixtures.Reflection.EditableModule.beam")

      File.write!(elixir_beam_path, "")

      dir
      |> Path.join("erlang_named_module.beam")
      |> File.write!("")

      Code.prepend_path(dir)
      on_exit(fn -> Code.delete_path(dir) end)

      beam_paths = Map.new(list_editable_beams())

      assert beam_paths[Hologram.Test.Fixtures.Reflection.EditableModule] ==
               String.to_charlist(elixir_beam_path)

      refute Map.has_key?(beam_paths, :erlang_named_module)
    end

    test "lists every module once" do
      modules = Enum.map(list_editable_beams(), fn {module, _beam_path} -> module end)

      assert Enum.uniq(modules) == modules
    end
  end

  describe "list_elixir_modules/0" do
    test "lists the Elixir modules of the loaded applications" do
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

    test "asks the code server about no module" do
      assert count_calls({:code, :which, 1}, &list_elixir_modules/0) == 0
    end
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

    test "includes a module found in ebin but not in Application.spec, without loading it" do
      module = Hologram.Test.Fixtures.Reflection.ModuleInEbinOnly
      write_unloaded_module_to_ebin(module, :hologram, "def test_function, do: :test_value")

      refute module in Application.spec(:hologram, :modules)

      assert module in list_elixir_modules([:hologram])
      assert :code.is_loaded(module) == false
    end

    test "excludes an Erlang module with an Elixir-style name found in ebin" do
      {module, bytecode} = compile_elixir_named_erlang_module()
      beam_path = Path.join([:code.lib_dir(:hologram), "ebin", "#{module}.beam"])
      File.write!(beam_path, bytecode)

      on_exit(fn -> File.rm!(beam_path) end)

      refute module in list_elixir_modules([:hologram])
    end
  end

  test "list_loaded_otp_apps/0" do
    result = list_loaded_otp_apps()

    assert :crypto in result
    assert :elixir in result
    assert :file_system in result
    assert :hologram in result
  end

  describe "list_module_applications/0" do
    test "maps modules of the project, of Elixir and of Erlang/OTP to their applications" do
      result = list_module_applications()

      assert result[Hologram.Reflection] == :hologram
      assert result[Enum] == :elixir
      assert result[:lists] == :stdlib
    end

    test "has no entry for a module no loaded application lists" do
      refute Map.has_key?(list_module_applications(), Aaa.Bbb)
    end

    test "agrees with Application.get_application/1" do
      result = list_module_applications()

      result
      |> Map.keys()
      |> Enum.take_every(50)
      |> Enum.each(fn module ->
        assert Application.get_application(module) == result[module]
      end)
    end
  end

  describe "list_pages/0" do
    test "lists the page modules of the loaded applications, sorted by name" do
      result = list_pages()

      assert Hologram.Test.Fixtures.Compiler.CallGraph.Module11 in result
      assert Hologram.Test.Fixtures.Reflection.Module2 in result
      assert Hologram.Test.Fixtures.Reflection.Module6 in result
      assert Hologram.Test.Fixtures.Page.Module1 in result

      refute Hologram.Test.Fixtures.Compiler.Module6 in result
      refute Hologram.Test.Fixtures.Compiler.CallGraph.Module4 in result
      refute Hologram.Compiler.Context in result

      assert result == Enum.sort(result)
    end

    test "lists a page whose beam is in an application's ebin directory without loading it" do
      module = Hologram.Test.Fixtures.Reflection.PageInEbinOnly

      write_unloaded_module_to_ebin(module, :hologram, """
      use Hologram.Page
      route "/hologram-test-fixtures-reflection-page-in-ebin-only"
      layout Hologram.Test.Fixtures.LayoutFixture
      @impl Page
      def template, do: ~HOLO"PageInEbinOnly template"
      """)

      assert module in list_pages()
      assert :code.is_loaded(module) == false
    end

    test "asks the code server about no module" do
      assert count_calls({:code, :which, 1}, &list_pages/0) == 0
    end
  end

  describe "list_protocol_implementations/2" do
    setup do
      module_info_plt =
        PLT.start(
          items: [
            {String.Chars.Atom,
             %{protocol_implementation?: true, implemented_protocol: String.Chars}},
            {String.Chars.Integer,
             %{protocol_implementation?: true, implemented_protocol: String.Chars}},
            {Enumerable.List,
             %{protocol_implementation?: true, implemented_protocol: Enumerable}},
            {Calendar.ISO, %{protocol_implementation?: false, implemented_protocol: nil}},
            {String.Chars, %{protocol?: true}}
          ]
        )

      [module_info_plt: module_info_plt]
    end

    test "modules the PLT records as implementations of the protocol", %{
      module_info_plt: module_info_plt
    } do
      sorted_impls =
        String.Chars
        |> list_protocol_implementations(module_info_plt)
        |> Enum.sort()

      assert sorted_impls == [String.Chars.Atom, String.Chars.Integer]
    end

    test "protocol the PLT records no implementation of", %{module_info_plt: module_info_plt} do
      assert list_protocol_implementations(Inspect, module_info_plt) == []
    end

    test "the fixture app's PLT lists its implementation" do
      module_info_plt = Compiler.build_module_info_plt!(PLT.start(), nil)

      result = list_protocol_implementations(String.Chars, module_info_plt)

      assert String.Chars.Atom in result
      assert String.Chars.Hologram.Test.Fixtures.Reflection.Module5 in result
      refute Enumerable.List in result
    end
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

    test "does not load the module" do
      module = Hologram.Test.Fixtures.Reflection.NotLoadedModule
      write_unloaded_module(module, "module_1", "")

      assert :code.is_loaded(module) == false
      assert module?(module)
      assert :code.is_loaded(module) == false
    end

    test "non-atom" do
      refute module?(123)
    end
  end

  test "module_info_plt_dump_file_name/0" do
    assert module_info_plt_dump_file_name() == "module_info.plt"
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

  describe "protocol?/2" do
    setup do
      [module_info_plt: PLT.start()]
    end

    test "module the PLT holds is answered from it, without consulting the code path", %{
      module_info_plt: module_info_plt
    } do
      PLT.put(module_info_plt, Aaa.Bbb, %{protocol?: true})

      assert protocol?(Aaa.Bbb, module_info_plt)
    end

    test "the PLT wins over the module", %{module_info_plt: module_info_plt} do
      PLT.put(module_info_plt, String.Chars, %{protocol?: false})

      refute protocol?(String.Chars, module_info_plt)
    end

    test "term the PLT does not hold is decided the protocol?/1 way", %{
      module_info_plt: module_info_plt
    } do
      assert protocol?(String.Chars, module_info_plt)
      refute protocol?(Calendar.ISO, module_info_plt)
      refute protocol?(123, module_info_plt)
    end

    test "nil PLT decides the protocol?/1 way" do
      assert protocol?(String.Chars, nil)
      refute protocol?(Calendar.ISO, nil)
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

  describe "protocol_implementation/2" do
    setup do
      [module_info_plt: PLT.start()]
    end

    test "module the PLT holds is answered from it, without consulting the code path", %{
      module_info_plt: module_info_plt
    } do
      PLT.put(module_info_plt, Aaa.Bbb, %{implemented_protocol: String.Chars})

      assert protocol_implementation(Aaa.Bbb, module_info_plt) == String.Chars
    end

    test "the PLT wins over the module", %{module_info_plt: module_info_plt} do
      PLT.put(module_info_plt, Enumerable.Function, %{implemented_protocol: nil})

      assert protocol_implementation(Enumerable.Function, module_info_plt) == nil
    end

    test "module the PLT does not hold is decided the protocol_implementation/1 way", %{
      module_info_plt: module_info_plt
    } do
      assert protocol_implementation(Enumerable.Function, module_info_plt) == Enumerable
      assert protocol_implementation(Calendar.ISO, module_info_plt) == nil
    end

    test "nil PLT decides the protocol_implementation/1 way" do
      assert protocol_implementation(Enumerable.Function, nil) == Enumerable
      assert protocol_implementation(Calendar.ISO, nil) == nil
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

  test "put_env_with_cleanup/3 puts back the value the key had" do
    key = :put_env_with_cleanup_test_key
    Application.put_env(:hologram, key, :before)

    # Registered first, so it runs after the helper's cleanup: on_exit callbacks run in reverse order.
    on_exit(fn ->
      assert Application.fetch_env(:hologram, key) == {:ok, :before}
      Application.delete_env(:hologram, key)
    end)

    put_env_with_cleanup(:hologram, key, :during)

    assert Application.fetch_env!(:hologram, key) == :during
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

  describe "relative_source_path/2" do
    test "dep module" do
      assert relative_source_path("/proj/deps/my_dep/lib/my_dep/a.ex", "/proj") ==
               "lib/my_dep/a.ex"
    end

    test "project module" do
      assert relative_source_path("/proj/lib/my_app/a.ex", "/proj") == "lib/my_app/a.ex"
    end

    test "Elixir standard library module" do
      path = "/home/runner/work/elixir/elixir/lib/elixir/lib/enum.ex"

      assert relative_source_path(path, "/proj") == "lib/enum.ex"
    end

    test "unrecognized source root" do
      assert relative_source_path("/foreign/build/machine/lib/a.ex", "/proj") == "a.ex"
    end

    test "a sibling directory whose name starts with the root's name is not the root" do
      assert relative_source_path("/proj_other/lib/a.ex", "/proj") == "a.ex"
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
end
