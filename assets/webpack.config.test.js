const nodeExternals = require("webpack-node-externals");

module.exports = {
  target: "node", // Webpack should emit Node.js compatible code
  externals: [nodeExternals()], // in order to ignore all modules in node_modules folder from bundling
};