export default class Utils {
  static keywordToMap(keyword) {
    return keyword.data.reduce((acc, elem) => {
      const key = Utils.serialize(elem.data[0])
      acc.data[key] = elem.data[1]
      return acc
    }, {type: "map", data: {}})
  }

  static serialize(arg) {
    switch (arg.type) {
      case 'atom':
        return `~atom[${arg.value}]`

      case 'string':
        return `~string[${arg.value}]`
        
      default:
        throw 'Not implemented, at Utils.serialize()'
    }
  }
}
