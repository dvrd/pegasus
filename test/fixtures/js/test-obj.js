f(obj.prototype, {
  p0: mk(k0),
  p1: mk(k1),
  p2: mk(k2),
  p3: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k3) !== 0 ? this[kVal3] : null;
    },
    set(value) {
      if (value) {
        this[kVal3] = value;
        this[kState] |= k3;
      } else {
        this[kState] &= ~k3;
      }
    },
  },
  p4: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k4) !== 0 ? this[kVal4] : null;
    },
    set(value) {
      if (value) {
        this[kVal4] = value;
        this[kState] |= k4;
      } else {
        this[kState] &= ~k4;
      }
    },
  }
});