export default class Calculator {
  constructor(initial) {
    this.value = initial;
  }

  add(n) {
    this.value += n;
    return this.value;
  }
}
