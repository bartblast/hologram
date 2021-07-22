const baseConfig = require("./webpack.config.base.js");

module.exports = (env, _options) => {
  const devConfig = {
    ...baseConfig,
    devtool: "cheap-module-source-map",
  };

  switch (env) {
    case "dev":
      return devConfig;
      
    default:
      return baseConfig;
  }
};