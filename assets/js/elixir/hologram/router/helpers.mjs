"use strict";

import AssetPathRegistry from "../../../asset_path_registry.mjs";
import Bitstring from "../../../bitstring.mjs";
import Interpreter from "../../../interpreter.mjs";
import Type from "../../../type.mjs";

const Elixir_Hologram_Router_Helpers = {
  "asset_path/1": (staticPath) => {
    const assetPath = AssetPathRegistry.lookup(staticPath);

    if (Type.isNil(assetPath)) {
      const message = `there is no such asset: "${Bitstring.toText(
        staticPath,
      )}"`;

      return Interpreter.raiseError("Hologram.AssetNotFoundError", message);
    }

    return assetPath;
  },

  // Deps: [String.Chars.to_string/1, :lists.keyfind/3, :lists.keymember/3]
  "page_path/2": (pageModule, params) => {
    const context = Interpreter.buildContext();

    const requiredParams = Interpreter.callNamedFunction(
      pageModule,
      "__props__",
      0,
      [],
      context,
    );

    const route = Interpreter.callNamedFunction(
      pageModule,
      "__route__",
      0,
      [],
      context,
    );

    const [remainingParams, path] = requiredParams.data.reduce(
      (acc, requiredParam) => {
        const key = requiredParam.data[0];
        const paramsAcc = acc[0];
        const pathAcc = acc[1];

        if (
          Type.isFalse(
            Erlang_Lists["keymember/3"](key, Type.integer(1), paramsAcc),
          )
        ) {
          const msg = `page "${Interpreter.inspect(pageModule)}" expects "${key.value}" param`;
          Interpreter.raiseArgumentError(msg);
        }

        const newParamsAcc = Type.list(
          paramsAcc.data.filter((param) => param.data[0].value !== key.value),
        );

        const paramValue = Erlang_Lists["keyfind/3"](
          key,
          Type.integer(1),
          paramsAcc,
        ).data[1];

        const paramValueText = Bitstring.toText(
          Elixir_String_Chars["to_string/1"](paramValue),
        );

        const newPathAcc = Type.bitstring(
          Bitstring.toText(pathAcc).replaceAll(`:${key.value}`, paramValueText),
        );

        return [newParamsAcc, newPathAcc];
      },
      [params, route],
    );

    if (remainingParams.data.length > 0) {
      const key = remainingParams.data[0].data[0];

      const msg = `page "${Interpreter.inspect(pageModule)}" doesn't expect "${key.value}" param`;
      Interpreter.raiseArgumentError(msg);
    }

    return path;
  },
};

export default Elixir_Hologram_Router_Helpers;
