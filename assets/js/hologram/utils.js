export default class Utils {
  static keywordToMap(keyword) {
    return keyword.data.reduce((acc, elem) => {
      acc.data[`~atom[${elem.data[0].value}]`] = elem.data[1]
      return acc
    }, {type: "map", data: {}})
  }
}
